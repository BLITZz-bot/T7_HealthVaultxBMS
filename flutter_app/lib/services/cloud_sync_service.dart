import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_db_service.dart';

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

  static Future<bool> syncAll() async {
    final db = await LocalDbService.database;

    // 1. Get logged in ASHA user
    final users = await db.query('users', where: 'role = ?', whereArgs: ['asha'], limit: 1);
    if (users.isEmpty) return false;
    final asha = users.first;
    final String? ashaCloudId = asha['cloud_id']?.toString();
    final String? phcId = asha['phc_id']?.toString();
    
    if (ashaCloudId == null || phcId == null || ashaCloudId.isEmpty || phcId.isEmpty) {
      print("No cloud_id or phc_id found for ASHA. Cannot sync.");
      return false;
    }

    final headers = {
      'apikey': _supabaseAnonKey,
      'Authorization': 'Bearer $_supabaseAnonKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    };

    // 2. Sync Families -> Households
    final unsyncedFamilies = await db.query('families', where: 'is_synced = 0 OR cloud_id IS NULL');
    for (var family in unsyncedFamilies) {
      // Find area name
      final areaRes = await db.query('areas', where: 'id = ?', whereArgs: [family['area_id']]);
      String areaName = areaRes.isNotEmpty ? areaRes.first['village_or_ward'].toString() : 'Unknown';

      // Find village UUID in supabase
      String? villageUuid;
      try {
        final vRes = await http.get(Uri.parse('$_supabaseUrl/rest/v1/villages?name=eq.$areaName&phc_id=eq.$phcId&select=id'), headers: headers);
        if (vRes.statusCode == 200) {
          final List vList = jsonDecode(vRes.body);
          if (vList.isNotEmpty) villageUuid = vList.first['id'];
        }
      } catch (e) {}

      try {
        final res = await http.post(
          Uri.parse('$_supabaseUrl/rest/v1/households'),
          headers: headers,
          body: jsonEncode({
            'phc_id': phcId,
            'asha_id': ashaCloudId,
            'village_id': villageUuid,
            'head_name': family['family_head_name'],
            'house_number': family['house_number'],
            'contact_number': family['contact_number'],
          }),
        );
        if (res.statusCode == 201 || res.statusCode == 200) {
          final List data = jsonDecode(res.body);
          if (data.isNotEmpty) {
            await db.update('families', {'cloud_id': data.first['id'], 'is_synced': 1}, where: 'id = ?', whereArgs: [family['id']]);
          }
        }
      } catch (e) {
        print("Error syncing family: $e");
      }
    }

    // 3. Sync Members -> members
    final unsyncedMembers = await db.query('members', where: 'is_synced = 0 OR cloud_id IS NULL');
    for (var member in unsyncedMembers) {
      final fRes = await db.query('families', where: 'id = ?', whereArgs: [member['family_id']]);
      if (fRes.isEmpty || fRes.first['cloud_id'] == null) continue; // Skip if family not synced
      
      try {
        final res = await http.post(
          Uri.parse('$_supabaseUrl/rest/v1/members'),
          headers: headers,
          body: jsonEncode({
            'household_id': fRes.first['cloud_id'],
            'phc_id': phcId,
            'asha_id': ashaCloudId,
            'full_name': member['full_name'],
            'age': member['age'],
            'gender': member['gender'],
            'relation_to_head': member['relationship_to_head'],
            'abha_id': member['abha_id'],
            'mobile_number': member['mobile_number'],
            'is_pregnant': member['is_pregnant'] == 1,
            'lmp_date': member['lmp_date'],
            'edd_date': member['edd_date'],
            'is_high_risk_pregnancy': member['is_high_risk_pregnancy'] == 1,
            'is_lactating': member['is_lactating'] == 1,
            'birth_weight': member['birth_weight'],
            'delivery_type': member['delivery_type'],
            'muac_cm': member['muac_cm'],
            'has_chronic_condition': member['has_chronic_condition'] == 1,
            'chronic_notes': member['chronic_notes'],
          }),
        );
        if (res.statusCode == 201 || res.statusCode == 200) {
          final List data = jsonDecode(res.body);
          if (data.isNotEmpty) {
            await db.update('members', {'cloud_id': data.first['id'], 'is_synced': 1}, where: 'id = ?', whereArgs: [member['id']]);
          }
        }
      } catch (e) {
        print("Error syncing member: $e");
      }
    }

    // 4. Sync Medical Records -> vitals
    final unsyncedVitals = await db.query('medical_records', where: 'is_synced = 0 OR cloud_id IS NULL');
    for (var vital in unsyncedVitals) {
      final mRes = await db.query('members', where: 'id = ?', whereArgs: [vital['member_id']]);
      if (mRes.isEmpty || mRes.first['cloud_id'] == null) continue;
      
      try {
        final res = await http.post(
          Uri.parse('$_supabaseUrl/rest/v1/vitals'),
          headers: headers,
          body: jsonEncode({
            'member_id': mRes.first['cloud_id'],
            'phc_id': phcId,
            'asha_id': ashaCloudId,
            'bp_systolic': vital['blood_pressure_systolic'],
            'bp_diastolic': vital['blood_pressure_diastolic'],
            'temperature_c': vital['temperature'],
            'pulse_rate': vital['pulse_rate'],
            'spo2': vital['spo2'],
            'respiratory_rate': vital['respiratory_rate'],
            'blood_sugar_fasting': vital['blood_sugar_fasting'],
            'blood_sugar_postprandial': vital['blood_sugar_postprandial'],
            'notes': vital['notes'],
            'device_id': vital['device_id'],
            'recorded_at': vital['recorded_at'],
          }),
        );
        if (res.statusCode == 201 || res.statusCode == 200) {
          final List data = jsonDecode(res.body);
          if (data.isNotEmpty) {
            await db.update('medical_records', {'cloud_id': data.first['id'], 'is_synced': 1}, where: 'id = ?', whereArgs: [vital['id']]);
          }
        }
      } catch (e) {
        print("Error syncing vital: $e");
      }
    }

    // 5. Update last_sync_at
    try {
      await http.patch(
        Uri.parse('$_supabaseUrl/rest/v1/profiles?user_id=eq.$ashaCloudId'),
        headers: headers,
        body: jsonEncode({
          'last_sync_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch(e) {}

    return true;
  }
}
