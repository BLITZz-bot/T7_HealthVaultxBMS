import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';
import 'blockchain_service.dart';

class CloudSyncService {
  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hjllsydtufkatfqczssx.supabase.co',
  );
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhqbGxzeWR0dWZrYXRmcWN6c3N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2MTE5NTcsImV4cCI6MjEwNjE4Nzk1N30.MLXtdVN_1KRH5Q60pJxoCGO9jdIdTvXrprAUKomXHaQ',
  );

  static Future<int> getPendingSyncCount() async {
    final db = await LocalDbService.database;
    int count = 0;
    try {
      final families = await db.query('families', where: 'is_synced = 0 OR cloud_id IS NULL');
      final members = await db.query('members', where: 'is_synced = 0 OR cloud_id IS NULL');
      final vitals = await db.query('medical_records', where: 'is_synced = 0 OR cloud_id IS NULL');
      count = families.length + members.length + vitals.length;
    } catch (_) {}
    return count;
  }

  static Future<bool> syncMasterJurisdictions() async {
    final headers = {
      'apikey': _supabaseAnonKey,
      'Authorization': 'Bearer $_supabaseAnonKey',
      'Content-Type': 'application/json',
    };

    try {
      final db = await LocalDbService.database;
      
      // 1. Sync States
      final statesRes = await http.get(Uri.parse('$_supabaseUrl/rest/v1/states'), headers: headers);
      if (statesRes.statusCode == 200) {
        final List states = jsonDecode(statesRes.body);
        for (var s in states) {
          final existing = await db.query('states', where: 'name = ?', whereArgs: [s['name']]);
          if (existing.isEmpty) {
            await db.insert('states', {'name': s['name']});
          }
        }
      }

      // 2. Sync Districts
      final districtsRes = await http.get(Uri.parse('$_supabaseUrl/rest/v1/districts?select=name,states(name)'), headers: headers);
      if (districtsRes.statusCode == 200) {
        final List districts = jsonDecode(districtsRes.body);
        for (var d in districts) {
          final stateName = d['states']?['name'];
          if (stateName == null) continue;
          
          final localState = await db.query('states', where: 'name = ?', whereArgs: [stateName]);
          if (localState.isEmpty) continue;
          
          final existing = await db.query('districts', where: 'name = ? AND state_id = ?', whereArgs: [d['name'], localState.first['id']]);
          if (existing.isEmpty) {
            await db.insert('districts', {'state_id': localState.first['id'], 'name': d['name']});
          }
        }
      }

      // 3. Sync Areas (Villages)
      final areasRes = await http.get(Uri.parse('$_supabaseUrl/rest/v1/villages?select=name,block,districts(name,states(name))'), headers: headers);
      if (areasRes.statusCode == 200) {
        final List areas = jsonDecode(areasRes.body);
        for (var a in areas) {
          final distName = a['districts']?['name'];
          if (distName == null) continue;
          
          final localDist = await db.query('districts', where: 'name = ?', whereArgs: [distName]);
          if (localDist.isEmpty) continue;

          final existing = await db.query('areas', where: 'village_or_ward = ? AND district_id = ?', whereArgs: [a['name'], localDist.first['id']]);
          if (existing.isEmpty) {
            await db.insert('areas', {
              'district_id': localDist.first['id'],
              'block': a['block'] ?? 'General',
              'village_or_ward': a['name']
            });
          }
        }
      }

      return true;
    } catch (e) {
      print('Error syncing master jurisdictions: $e');
      return false;
    }
  }

  static Future<bool> syncWorkersFromCloud() async {
    final db = await LocalDbService.database;

    final headers = {
      'apikey': _supabaseAnonKey,
      'Authorization': 'Bearer $_supabaseAnonKey',
      'Content-Type': 'application/json',
    };

    try {
      // Fetch ASHA workers from Supabase profiles with their PHC info
      final res = await http.get(
        Uri.parse('$_supabaseUrl/rest/v1/profiles?role=eq.asha&select=user_id,phc_id,full_name,phone,username,last_sync_at,is_active,phc:phcs(*)'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final List profiles = jsonDecode(res.body);
        int synced = 0;

        for (var profile in profiles) {
          final cloudId = profile['user_id']?.toString();
          if (cloudId == null) continue;

          String? localStateId;
          final phc = profile['phc'];
          if (phc != null && phc['state'] != null) {
            final stateMaps = await db.query('states', where: 'name = ?', whereArgs: [phc['state'].toString()]);
            if (stateMaps.isNotEmpty) {
              localStateId = stateMaps.first['id'].toString();
            }
          }

          final existing = await db.query('users', where: 'cloud_id = ?', whereArgs: [cloudId]);
          final fullName = profile['full_name'] ?? '';
          final nameParts = fullName.split(' ');
          final firstName = nameParts.isNotEmpty ? nameParts.first : '';
          final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

          if (existing.isEmpty) {
            await db.insert('users', {
              'username': profile['username'] ?? '',
              'password': 'password123',
              'first_name': firstName,
              'last_name': lastName,
              'phone_number': profile['phone'] ?? '',
              'aadhaar_number': '',
              'state': localStateId ?? '',
              'role': 'asha',
              'profile_image': null,
              'cloud_id': cloudId,
              'phc_id': profile['phc_id']?.toString() ?? '',
            });
            synced++;
          } else {
            await db.update(
              'users',
              {
                'username': profile['username'] ?? '',
                'first_name': firstName,
                'last_name': lastName,
                'phone_number': profile['phone'] ?? '',
                'state': localStateId ?? '',
                'cloud_id': cloudId,
                'phc_id': profile['phc_id']?.toString() ?? '',
              },
              where: 'cloud_id = ?',
              whereArgs: [cloudId],
            );
          }
        }
        print('Synced $synced workers from cloud (out of ${profiles.length} total)');
        return true;
      } else {
        print('Failed to sync workers: HTTP ${res.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error syncing workers from cloud: $e');
      return false;
    }
  }

  static Future<bool> syncAll({String? workerAddress}) async {
    final db = await LocalDbService.database;

    final users = await db.query('users', where: 'role = ?', whereArgs: ['asha'], limit: 1);
    if (users.isEmpty) return false;
    final asha = users.first;
    final String? ashaCloudId = asha['cloud_id']?.toString();
    final String? phcId = asha['phc_id']?.toString();

    if (ashaCloudId == null || phcId == null || ashaCloudId.isEmpty || phcId.isEmpty) {
      print("No cloud_id or phc_id found for ASHA. Cannot sync.");
      return false;
    }

    final anonHeaders = {
      'apikey': _supabaseAnonKey,
      'Authorization': 'Bearer $_supabaseAnonKey',
      'Content-Type': 'application/json',
    };

    // ── Collect unsynced data from local DB ──

    // 1. Families → Households (resolve village UUIDs via anon key — best effort)
    final unsyncedFamilies = await db.query('families', where: 'is_synced = 0 OR cloud_id IS NULL');
    final pushHouseholds = <Map<String, dynamic>>[];
    for (var family in unsyncedFamilies) {
      final areaRes = await db.query('areas', where: 'id = ?', whereArgs: [family['area_id']]);
      final areaName = areaRes.isNotEmpty ? areaRes.first['village_or_ward'].toString() : 'Unknown';
      String? villageUuid;
      try {
        final vRes = await http.get(
          Uri.parse('$_supabaseUrl/rest/v1/villages?name=eq.$areaName&phc_id=eq.$phcId&select=id'),
          headers: anonHeaders,
        );
        if (vRes.statusCode == 200) {
          final List vList = jsonDecode(vRes.body);
          if (vList.isNotEmpty) villageUuid = vList.first['id'];
        }
      } catch (e) {}

      pushHouseholds.add({
        'cloud_id': family['cloud_id']?.toString(),
        'family_head_name': family['family_head_name'],
        'house_number': family['house_number'],
        'contact_number': family['contact_number'],
        'village_id': villageUuid,
      });
    }

    // 2. Members → need family cloud_id for household_id mapping
    final unsyncedMembers = await db.query('members', where: 'is_synced = 0 OR cloud_id IS NULL');
    final pushMembers = <Map<String, dynamic>>[];
    for (var member in unsyncedMembers) {
      final fRes = await db.query('families', where: 'id = ?', whereArgs: [member['family_id']]);
      final householdCloudId = fRes.isNotEmpty ? fRes.first['cloud_id']?.toString() : null;
      if (householdCloudId == null) continue;

      pushMembers.add({
        'cloud_id': member['cloud_id']?.toString(),
        'household_cloud_id': householdCloudId,
        'full_name': member['full_name'],
        'age': member['age'],
        'gender': member['gender'],
        'relationship_to_head': member['relationship_to_head'],
        'abha_id': member['abha_id'],
        'mobile_number': member['mobile_number'],
        'is_pregnant': member['is_pregnant'] == 1,
        'lmp_date': member['lmp_date'],
        'edd_date': member['edd_date'],
        'is_high_risk_pregnancy': member['is_high_risk_pregnancy'] == 1,
        'is_lactating': member['is_lactating'] == 1,
        'td1_vaccine': member['td1_vaccine'] == 1,
        'td2_vaccine': member['td2_vaccine'] == 1,
        'td_booster': member['td_booster'] == 1,
        'ifa_tablets_given': member['ifa_tablets_given'] ?? 0,
        'calcium_tablets_given': member['calcium_tablets_given'] ?? 0,
        'birth_weight': member['birth_weight'],
        'delivery_type': member['delivery_type'],
        'muac_cm': member['muac_cm'],
        'has_chronic_condition': member['has_chronic_condition'] == 1,
        'chronic_notes': member['chronic_notes'],
      });
    }

    // 3. Medical Records → need member cloud_id
    final unsyncedVitals = await db.query('medical_records', where: 'is_synced = 0 OR cloud_id IS NULL');
    final pushVitals = <Map<String, dynamic>>[];
    for (var vital in unsyncedVitals) {
      final mRes = await db.query('members', where: 'id = ?', whereArgs: [vital['member_id']]);
      final memberCloudId = mRes.isNotEmpty ? mRes.first['cloud_id']?.toString() : null;
      if (memberCloudId == null) continue;

      pushVitals.add({
        'cloud_id': vital['cloud_id']?.toString(),
        'member_cloud_id': memberCloudId,
        'blood_pressure_systolic': vital['blood_pressure_systolic'],
        'blood_pressure_diastolic': vital['blood_pressure_diastolic'],
        'temperature': vital['temperature'],
        'pulse_rate': vital['pulse_rate'],
        'spo2': vital['spo2'],
        'respiratory_rate': vital['respiratory_rate'],
        'blood_sugar_fasting': vital['blood_sugar_fasting'],
        'blood_sugar_postprandial': vital['blood_sugar_postprandial'],
        'notes': vital['notes'],
        'device_id': vital['device_id'],
        'recorded_at': vital['recorded_at'],
      });
    }

    var allSucceeded = true;

    // 4. Send all data to fetch-worker-data Edge Function (bypasses RLS via service role)
    try {
      final response = await http.post(
        Uri.parse('$_supabaseUrl/functions/v1/fetch-worker-data'),
        headers: anonHeaders,
        body: jsonEncode({
          'cloud_id': ashaCloudId,
          'phc_id': phcId,
          'households': pushHouseholds,
          'members': pushMembers,
          'vitals': pushVitals,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> result = jsonDecode(response.body);
        final List cloudHouseholds = result['households'] ?? [];
        final List cloudMembers = result['members'] ?? [];
        final List cloudVitals = result['vitals'] ?? [];

        // Update local families with cloud_id
        for (var hh in cloudHouseholds) {
          final cloudHHId = hh['id']?.toString();
          if (cloudHHId == null) continue;
          final headName = hh['head_name']?.toString() ?? '';
          final contact = hh['contact_number']?.toString() ?? '';
          await db.update(
            'families',
            {'cloud_id': cloudHHId, 'is_synced': 1},
            where: 'family_head_name = ? AND contact_number = ? AND (cloud_id IS NULL OR cloud_id = ?)',
            whereArgs: [headName, contact, cloudHHId],
          );
        }

        // Update local members with cloud_id
        for (var m in cloudMembers) {
          final cloudMId = m['id']?.toString();
          if (cloudMId == null) continue;
          final fullName = m['full_name']?.toString() ?? '';
          await db.update(
            'members',
            {'cloud_id': cloudMId, 'is_synced': 1},
            where: 'full_name = ? AND (cloud_id IS NULL OR cloud_id = ?)',
            whereArgs: [fullName, cloudMId],
          );
        }

        // Update local medical_records with cloud_id
        for (var v in cloudVitals) {
          final cloudVId = v['id']?.toString();
          if (cloudVId == null) continue;
          await db.update(
            'medical_records',
            {'cloud_id': cloudVId, 'is_synced': 1},
            where: 'recorded_at = ? AND (cloud_id IS NULL OR cloud_id = ?)',
            whereArgs: [v['recorded_at']?.toString() ?? '', cloudVId],
          );
        }
      } else {
        allSucceeded = false;
        print('fetch-worker-data returned HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      allSucceeded = false;
      print('Error calling fetch-worker-data: $e');
    }

    if (workerAddress != null) {
      try {
        await BlockchainService.syncOutbox(workerAddress: workerAddress);
      } catch (e) {
        allSucceeded = false;
        print('Error syncing blockchain outbox: $e');
      }
    }

    return allSucceeded;
  }

  static Future<bool> syncFromCloud() async {
    final db = await LocalDbService.database;

    final users = await db.query('users', where: 'role = ?', whereArgs: ['asha'], limit: 1);
    if (users.isEmpty) return false;
    final asha = users.first;
    final String? ashaCloudId = asha['cloud_id']?.toString();
    if (ashaCloudId == null || ashaCloudId.isEmpty) {
      print("No cloud_id found for ASHA. Cannot pull from cloud.");
      return false;
    }

    final headers = {
      'apikey': _supabaseAnonKey,
      'Authorization': 'Bearer $_supabaseAnonKey',
      'Content-Type': 'application/json',
    };

    try {
      final response = await http.post(
        Uri.parse('$_supabaseUrl/functions/v1/fetch-worker-data'),
        headers: headers,
        body: jsonEncode({'cloud_id': ashaCloudId}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('fetch-worker-data returned HTTP ${response.statusCode}');
        return false;
      }

      final Map<String, dynamic> result = jsonDecode(response.body);
      final List cloudHouseholds = result['households'] ?? [];
      final List cloudMembers = result['members'] ?? [];
      final List cloudVitals = result['vitals'] ?? [];

      int inserted = 0;

      // ── Pull Households → Families ──
      for (var hh in cloudHouseholds) {
        final cloudHHId = hh['id']?.toString();
        if (cloudHHId == null) continue;

        final existing = await db.query('families', where: 'cloud_id = ?', whereArgs: [cloudHHId]);
        if (existing.isEmpty) {
          final villageName = hh['village']?['name']?.toString() ?? 'Unknown';
          final areaRes = await db.query('areas', where: 'village_or_ward = ?', whereArgs: [villageName]);
          int areaId = 0;
          if (areaRes.isNotEmpty) {
            areaId = areaRes.first['id'] as int;
          } else {
            areaId = await db.insert('areas', {
              'village_or_ward': villageName,
              'block': 'Remote',
              'district_id': 0,
            });
          }

          await db.insert('families', {
            'family_head_name': hh['head_name'] ?? '',
            'house_number': hh['house_number'] ?? '',
            'contact_number': hh['contact_number'] ?? '',
            'area_id': areaId,
            'cloud_id': cloudHHId,
            'is_synced': 1,
          });
          inserted++;
        }
      }

      // ── Pull Members → local members ──
      for (var m in cloudMembers) {
        final cloudMId = m['id']?.toString();
        if (cloudMId == null) continue;

        final existing = await db.query('members', where: 'cloud_id = ?', whereArgs: [cloudMId]);
        final cloudHouseholdId = m['household_id']?.toString();
        int? localFamilyId;
        if (cloudHouseholdId != null) {
          final fRes = await db.query('families', where: 'cloud_id = ?', whereArgs: [cloudHouseholdId]);
          if (fRes.isNotEmpty) localFamilyId = fRes.first['id'] as int;
        }

        final memberData = {
          'family_id': localFamilyId ?? 0,
          'full_name': m['full_name'] ?? '',
          'age': m['age'] ?? 0,
          'gender': m['gender'] ?? '',
          'relationship_to_head': m['relation_to_head'] ?? '',
          'abha_id': m['abha_id'] ?? '',
          'mobile_number': m['mobile_number'] ?? '',
          'is_pregnant': m['is_pregnant'] == true ? 1 : 0,
          'lmp_date': m['lmp_date']?.toString() ?? '',
          'edd_date': m['edd_date']?.toString() ?? '',
          'is_high_risk_pregnancy': m['is_high_risk_pregnancy'] == true ? 1 : 0,
          'is_lactating': m['is_lactating'] == true ? 1 : 0,
          'td1_vaccine': m['td1_vaccine'] == true ? 1 : 0,
          'td2_vaccine': m['td2_vaccine'] == true ? 1 : 0,
          'td_booster': m['td_booster'] == true ? 1 : 0,
          'ifa_tablets_given': m['ifa_tablets_given'] ?? 0,
          'calcium_tablets_given': m['calcium_tablets_given'] ?? 0,
          'birth_weight': m['birth_weight'] != null ? double.tryParse(m['birth_weight'].toString()) : null,
          'delivery_type': m['delivery_type'] ?? '',
          'muac_cm': m['muac_cm'] != null ? double.tryParse(m['muac_cm'].toString()) : null,
          'has_chronic_condition': m['has_chronic_condition'] == true ? 1 : 0,
          'chronic_notes': m['chronic_notes'] ?? '',
          'cloud_id': cloudMId,
          'is_synced': 1,
        };

        if (existing.isEmpty) {
          await db.insert('members', memberData);
          inserted++;
        } else {
          await db.update('members', memberData, where: 'cloud_id = ?', whereArgs: [cloudMId]);
        }
      }

      // ── Pull Vitals → medical_records ──
      for (var v in cloudVitals) {
        final cloudVId = v['id']?.toString();
        if (cloudVId == null) continue;

        final existing = await db.query('medical_records', where: 'cloud_id = ?', whereArgs: [cloudVId]);
        final cloudMemberId = v['member_id']?.toString();
        int? localMemberId;
        if (cloudMemberId != null) {
          final mRes = await db.query('members', where: 'cloud_id = ?', whereArgs: [cloudMemberId]);
          if (mRes.isNotEmpty) localMemberId = mRes.first['id'] as int;
        }

        final recordData = {
          'member_id': localMemberId ?? 0,
          'blood_sugar_fasting': v['blood_sugar_fasting'] != null ? double.tryParse(v['blood_sugar_fasting'].toString()) : null,
          'blood_sugar_postprandial': v['blood_sugar_postprandial'] != null ? double.tryParse(v['blood_sugar_postprandial'].toString()) : null,
          'blood_pressure_systolic': v['bp_systolic'] ?? 0,
          'blood_pressure_diastolic': v['bp_diastolic'] ?? 0,
          'temperature': v['temperature_c'] != null ? double.tryParse(v['temperature_c'].toString()) : null,
          'pulse_rate': v['pulse_rate'] ?? 0,
          'spo2': v['spo2'] ?? 0,
          'respiratory_rate': v['respiratory_rate'] ?? 0,
          'notes': v['notes'] ?? '',
          'entry_source': 'cloud_sync',
          'device_id': v['device_id'] ?? '',
          'recorded_at': v['recorded_at']?.toString() ?? DateTime.now().toIso8601String(),
          'cloud_id': cloudVId,
          'is_synced': 1,
        };

        if (existing.isEmpty) {
          await db.insert('medical_records', recordData);
          inserted++;
        } else {
          await db.update('medical_records', recordData, where: 'cloud_id = ?', whereArgs: [cloudVId]);
        }
      }

      print('Sync from cloud: inserted/updated $inserted records');
      return true;
    } catch (e) {
      print('Error syncing from cloud: $e');
      return false;
    }
  }

}
