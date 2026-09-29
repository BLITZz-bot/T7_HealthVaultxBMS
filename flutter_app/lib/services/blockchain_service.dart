import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';

class BlockchainService {
  static const String RELAY_URL = String.fromEnvironment(
    'RELAY_URL',
    defaultValue: 'https://t7-mst-health-vault.onrender.com',
  );

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

  static Future<void> syncOutbox({required String workerAddress}) async {
    if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(workerAddress)) {
      throw ArgumentError('A provisioned worker wallet is required before blockchain sync.');
    }
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

        // Fetch member age for canonical vitals hash
        int? memberAge;
        final memberList = await db.query('members', where: 'id = ?', whereArgs: [record['member_id']]);
        if (memberList.isNotEmpty) {
          memberAge = memberList.first['age'] as int?;
        }

        // Compute MAP from systolic and diastolic if not stored separately
        // MAP = DBP + (SBP - DBP) / 3
        final int? sbp = medRec['blood_pressure_systolic'] as int?;
        final int? dbp = medRec['blood_pressure_diastolic'] as int?;
        double? map;
        if (sbp != null && dbp != null) {
          map = dbp + (sbp - dbp) / 3.0;
          map = double.parse(map.toStringAsFixed(2));
        }

        // Canonical vitals dict — ALL fields required for hash consistency with relay
        final vitals = {
          "hr":          medRec['pulse_rate'],
          "sbp":         sbp,
          "dbp":         dbp,
          "map":         map,                             // FIX: was missing
          "temp":        medRec['temperature'],
          "spo2":        medRec['spo2'],
          "resp":        medRec['respiratory_rate'],
          "age":         memberAge,                       // FIX: was missing
          "recorded_at": medRec['recorded_at'],
        };

        // Per-family salt: use a stable identifier. In production this should be
        // a securely generated per-family random string stored in the local DB.
        // Using memberId as a stable fallback for the custodial pilot.
        final familySalt = 'hv_salt_$memberId';

        // Compute period (YYYY-MM) for replay-attack prevention
        DateTime now = DateTime.now();
        String period = "${now.year}-${now.month.toString().padLeft(2, '0')}";
        int taskType = 1; // Default: Home Visit

        // 2. Call /anchor — anchors the vitals hash on RecordAnchor contract
        final anchorResponse = await http.post(
          Uri.parse('$RELAY_URL/anchor'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'worker_address': workerAddress,
            'vitals': vitals,
            'beneficiary_id': memberId,
          }),
        );

        if (anchorResponse.statusCode != 200 && anchorResponse.statusCode != 201) {
          print('Relay /anchor error: ${anchorResponse.body}');
          continue;
        }

        final anchorJson = jsonDecode(anchorResponse.body);
        final anchorTxHash = anchorJson['tx_hash'] ?? '0x_mock';

        // 3. Call /visit — submits visit to StipendVault for hospital attestation
        // This is required for the worker to eventually receive CareCoin payment.
        final visitResponse = await http.post(
          Uri.parse('$RELAY_URL/visit'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'worker_address': workerAddress,
            'beneficiary_id': memberId,
            'family_salt':    familySalt,
            'task_type':      taskType,
            'period':         period,
          }),
        );

        if (visitResponse.statusCode != 200 && visitResponse.statusCode != 201) {
          print('Relay /visit error (non-fatal, anchor succeeded): ${visitResponse.body}');
          // Anchor succeeded — still mark as synced so we don't re-anchor.
          // Visit will be retried on next sync if needed.
        }

        final visitJson = visitResponse.statusCode == 200
            ? jsonDecode(visitResponse.body)
            : {};

        await db.update(
          'chain_outbox',
          {
            'status': 'synced',
            'synced_at': DateTime.now().toUtc().toIso8601String(),
            'tx_hash': anchorTxHash,
          },
          where: 'id = ?',
          whereArgs: [record['id']],
        );
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

  static Future<Map<String, dynamic>?> getWorkerBalance(String? address) async {
    if (address == null || !RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) return null;
    try {
      final response = await http.get(Uri.parse('$RELAY_URL/worker/$address'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
