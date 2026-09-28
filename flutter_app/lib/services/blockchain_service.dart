import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';

class BlockchainService {
  static const String RELAY_URL = 'https://t7-mst-health-vault.onrender.com';
  static const String DEMO_WORKER_ADDRESS = '0xB7a280Cd618dB5a0E82D84306DB423728034A089';

  static final List<String> VITALS_FIELDS = [
    "hr",
    "sbp",
    "dbp",
    "map",
    "temp",
    "spo2",
    "resp",
    "age",
    "recorded_at",
  ];

  static String canonicalVitalsJson(Map<String, dynamic> record) {
    Map<String, dynamic> ordered = {};
    for (String field in VITALS_FIELDS) {
      var val = record[field];
      if (val == null) {
        ordered[field] = "";
      } else if (val is double) {
        double rounded = double.parse(val.toStringAsFixed(2));
        ordered[field] = (rounded == rounded.toInt()) ? rounded.toInt() : rounded;
      } else {
        ordered[field] = val;
      }
    }
    return jsonEncode(ordered);
  }

  static String keccak256OfVitals(Map<String, dynamic> record) {
    String canonical = canonicalVitalsJson(record);
    return "0x" + hex.encode(KeccakDigest(256).process(Uint8List.fromList(utf8.encode(canonical))));
  }

  static String beneficiaryCommitment(String beneficiaryId, String familySalt) {
    String raw = beneficiaryId + familySalt;
    return hex.encode(KeccakDigest(256).process(Uint8List.fromList(utf8.encode(raw))));
  }

  static String visitKey(String bCommitmentHex, int taskType, String period) {
    // backend hasher does: b_commitment.hex() + str(task_type) + period
    String raw = bCommitmentHex + taskType.toString() + period;
    return hex.encode(KeccakDigest(256).process(Uint8List.fromList(utf8.encode(raw))));
  }

  static Future<void> queueVitals({
    required int memberId,
    required int medicalRecordId,
    required Map<String, dynamic> vitalsRecord,
    required String familySalt,
  }) async {
    final db = await LocalDbService.database;

    String payloadHash = keccak256OfVitals(vitalsRecord);
    String bCommitment = beneficiaryCommitment(memberId.toString(), familySalt);
    
    DateTime now = DateTime.now();
    String period = "${now.year}-${now.month.toString().padLeft(2, '0')}";
    String vKey = visitKey(bCommitment, 1, period); // 1 = ASHA Survey

    await db.insert('chain_outbox', {
      'member_id': memberId,
      'medical_record_id': medicalRecordId,
      'visit_key': vKey,
      'payload_hash': payloadHash,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> syncOutbox(String ashaToken) async {
    final db = await LocalDbService.database;
    final List<Map<String, dynamic>> pending = await db.query(
      'chain_outbox',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    for (var record in pending) {
      try {
        // 1. Fetch raw vitals for this record
        final medRecList = await db.query(
          'medical_records',
          where: 'id = ?',
          whereArgs: [record['medical_record_id']]
        );
        if (medRecList.isEmpty) continue;
        final medRec = medRecList.first;
        final memberId = record['member_id'].toString();

        final vitals = {
          "hr": medRec['pulse_rate'],
          "sbp": medRec['blood_pressure_systolic'],
          "dbp": medRec['blood_pressure_diastolic'],
          "temp": medRec['temperature'],
          "spo2": medRec['spo2'],
          "resp": medRec['respiratory_rate'],
          "recorded_at": medRec['recorded_at'],
        };

        // 2. Call the new /anchor endpoint on Render
        final response = await http.post(
          Uri.parse('$RELAY_URL/anchor'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'worker_address': DEMO_WORKER_ADDRESS,
            'vitals': vitals,
            'beneficiary_id': memberId,
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final resJson = jsonDecode(response.body);
          await db.update(
            'chain_outbox',
            {
              'status': 'synced',
              'synced_at': DateTime.now().toUtc().toIso8601String(),
              'tx_hash': resJson['tx_hash'] ?? '0x_mock',
            },
            where: 'id = ?',
            whereArgs: [record['id']],
          );
        } else {
          print('Relay error: ${response.body}');
        }
      } catch (e) {
        print("Sync failed for record ${record['id']}: $e");
      }
    }
  }

  static Future<Map<String, dynamic>?> getChainStatus(int medicalRecordId) async {
    final db = await LocalDbService.database;
    final List<Map<String, dynamic>> results = await db.query(
      'chain_outbox',
      where: 'medical_record_id = ?',
      whereArgs: [medicalRecordId],
      limit: 1,
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }
}
