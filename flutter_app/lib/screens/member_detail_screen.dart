import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/local_db_service.dart';
import '../services/image_utils.dart';
import '../services/news2_delta_service.dart';
import '../services/sepsis_inference_service.dart';
import '../services/language_service.dart';
import '../services/on_device_llm_service.dart';
import '../widgets/language_switcher_widget.dart';
import '../widgets/qwen_ai_chat_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helper: compute a flag color from a record map
// ─────────────────────────────────────────────────────────────────────────────
Color flagColor(String? flag) {
  switch (flag) {
    case 'critical': return Colors.red;
    case 'warning': return Colors.orange;
    default: return Colors.green;
  }
}

IconData flagIcon(String? flag) {
  switch (flag) {
    case 'critical': return Icons.warning_amber_rounded;
    case 'warning': return Icons.info_outline;
    default: return Icons.check_circle_outline;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MemberDetailScreen
// ─────────────────────────────────────────────────────────────────────────────
class MemberDetailScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  final String token;

  const MemberDetailScreen({super.key, required this.member, required this.token});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<dynamic>> _historyFuture;
  late Future<Map<String, dynamic>> _analyticsFuture;
  late Map<String, dynamic> _currentMember;
  String _selectedTimeRange = 'all'; // Default time range for analytics

  @override
  void initState() {
    super.initState();
    _currentMember = Map<String, dynamic>.from(widget.member);
    _tabController = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    final id = widget.member['id'].toString();
    setState(() {
      _historyFuture = LocalDbService.getMemberHistory(widget.token, id).then((records) {
        if (records.isNotEmpty) {
          final latest = records.first;
          setState(() {
            _currentMember['current_flag'] = latest['flag'];
          });
        }
        return records;
      });
      _analyticsFuture = LocalDbService.getMemberAnalytics(widget.token, id);
    });
  }

  DateTime? _getCutoffDate() {
    final now = DateTime.now();
    switch (_selectedTimeRange) {
      case '7d': return now.subtract(const Duration(days: 7));
      case '14d': return now.subtract(const Duration(days: 14));
      case '1m': return now.subtract(const Duration(days: 30));
      case '2m': return now.subtract(const Duration(days: 60));
      case '3m': return now.subtract(const Duration(days: 90));
      case '6m': return now.subtract(const Duration(days: 180));
      case '9m': return now.subtract(const Duration(days: 270));
      case '1y': return now.subtract(const Duration(days: 365));
      case 'all':
      default:
        return null;
    }
  }

  void _showEditMemberDialog() {
    final nameCtrl = TextEditingController(text: _currentMember['full_name']?.toString() ?? '');
    final ageCtrl = TextEditingController(text: _currentMember['age']?.toString() ?? '');
    final relCtrl = TextEditingController(text: _currentMember['relationship_to_head']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: _currentMember['mobile_number']?.toString() ?? '');
    final abhaCtrl = TextEditingController(text: _currentMember['abha_id']?.toString() ?? '');
    final chronicNotesCtrl = TextEditingController(text: _currentMember['chronic_notes']?.toString() ?? '');

    String gender = _currentMember['gender']?.toString().toLowerCase() ?? 'male';
    if (gender != 'male' && gender != 'female' && gender != 'other') gender = 'male';
    String? pickedImageBase64 = _currentMember['profile_image']?.toString();

    DateTime? dobDate;
    final int initialAge = int.tryParse(ageCtrl.text) ?? 0;
    if (initialAge > 0) {
      dobDate = DateTime(DateTime.now().year - initialAge, DateTime.now().month, DateTime.now().day);
    }

    bool hasChronic = (_currentMember['has_chronic_condition'] == 1 || _currentMember['has_chronic_condition'] == true);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final int parsedAge = int.tryParse(ageCtrl.text) ?? 0;

          return Dialog(
            backgroundColor: const Color(0xFFFBF8F5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with back arrow & title
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF32104E)),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Edit Member Profile',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF32104E)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Soft Blue Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F1FC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.badge_outlined, size: 16, color: Color(0xFF1565C0)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Member Profile · ${_currentMember['full_name'] ?? 'Member'}',
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1565C0), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Avatar Picker with Camera Badge
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          final compressedBase64 = await ImageUtils.pickAndCompressImage(context);
                          if (compressedBase64 != null) {
                            setModalState(() => pickedImageBase64 = compressedBase64);
                          }
                        },
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: Colors.purple.shade50,
                              backgroundImage: ImageUtils.safeBase64Image(pickedImageBase64),
                              child: pickedImageBase64 == null
                                  ? const Icon(Icons.person, color: Color(0xFF5B2C82), size: 36)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5B2C82),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Name Input
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: 'Name *',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Gender Segmented Selection
                    const Text('Gender', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          _buildGenderSegment('Female', 'female', gender, (val) => setModalState(() => gender = val)),
                          _buildGenderSegment('Male', 'male', gender, (val) => setModalState(() => gender = val)),
                          _buildGenderSegment('Other', 'other', gender, (val) => setModalState(() => gender = val)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Age & Date of Birth Row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Age (years) *',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                            ),
                            onChanged: (val) {
                              final a = int.tryParse(val);
                              if (a != null && a > 0 && a <= 120) {
                                setModalState(() {
                                  dobDate = DateTime(DateTime.now().year - a, DateTime.now().month, DateTime.now().day);
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dobDate ?? DateTime.now().subtract(Duration(days: 365 * (parsedAge > 0 ? parsedAge : 25))),
                                firstDate: DateTime.now().subtract(const Duration(days: 365 * 105)),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  dobDate = picked;
                                  final years = DateTime.now().difference(picked).inDays ~/ 365;
                                  ageCtrl.text = years.toString();
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Date of birth', style: TextStyle(fontSize: 10, color: Color(0xFF5B2C82), fontWeight: FontWeight.bold)),
                                      Text(
                                        dobDate == null ? '—' : DateFormat('dd MMM yyyy').format(dobDate!),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const Icon(Icons.cake_outlined, size: 20, color: Colors.black87),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Relationship to Head Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: relCtrl.text.isNotEmpty ? relCtrl.text : null,
                      decoration: InputDecoration(
                        hintText: 'Relationship to head *',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Head of Family', child: Text('Head of Family')),
                        DropdownMenuItem(value: 'Spouse', child: Text('Spouse')),
                        DropdownMenuItem(value: 'Son', child: Text('Son')),
                        DropdownMenuItem(value: 'Daughter', child: Text('Daughter')),
                        DropdownMenuItem(value: 'Mother', child: Text('Mother')),
                        DropdownMenuItem(value: 'Father', child: Text('Father')),
                        DropdownMenuItem(value: 'Brother', child: Text('Brother')),
                        DropdownMenuItem(value: 'Sister', child: Text('Sister')),
                        DropdownMenuItem(value: 'Grandmother', child: Text('Grandmother')),
                        DropdownMenuItem(value: 'Grandfather', child: Text('Grandfather')),
                        DropdownMenuItem(value: 'Daughter-in-law', child: Text('Daughter-in-law')),
                        DropdownMenuItem(value: 'Son-in-law', child: Text('Son-in-law')),
                        DropdownMenuItem(value: 'Other Relative', child: Text('Other Relative')),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => relCtrl.text = val);
                      },
                    ),
                    const SizedBox(height: 14),

                    // Mobile Number
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Mobile number (optional)',
                        prefixIcon: const Icon(Icons.phone, size: 18, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ABHA Health ID
                    TextField(
                      controller: abhaCtrl,
                      decoration: InputDecoration(
                        hintText: 'ABHA health ID (optional)',
                        prefixIcon: const Icon(Icons.badge_outlined, size: 18, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Hereditary / Chronic Condition Toggle
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        activeThumbColor: const Color(0xFF5B2C82),
                        activeTrackColor: Colors.purple.shade100,
                        title: const Text('Hereditary / chronic health condition', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Sickle cell, diabetes, hypertension, asthma...', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        value: hasChronic,
                        onChanged: (val) => setModalState(() => hasChronic = val),
                      ),
                    ),
                    if (hasChronic) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: chronicNotesCtrl,
                        decoration: InputDecoration(
                          hintText: 'Specify condition / medications / details',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),

                    // Full-width Purple Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B2C82),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          if (nameCtrl.text.isNotEmpty && ageCtrl.text.isNotEmpty && relCtrl.text.isNotEmpty) {
                            final age = int.tryParse(ageCtrl.text) ?? 0;
                            final ok = await LocalDbService.updateMember(
                              token: widget.token,
                              memberId: _currentMember['id'].toString(),
                              fullName: nameCtrl.text,
                              age: age,
                              gender: gender,
                              relationship: relCtrl.text,
                              profileImage: pickedImageBase64,
                              abhaId: abhaCtrl.text.isNotEmpty ? abhaCtrl.text : null,
                              mobileNumber: phoneCtrl.text.isNotEmpty ? phoneCtrl.text : null,
                              isPregnant: _currentMember['is_pregnant'] == 1 || _currentMember['is_pregnant'] == true,
                              lmpDate: _currentMember['lmp_date']?.toString(),
                              eddDate: _currentMember['edd_date']?.toString(),
                              isHighRiskPregnancy: _currentMember['is_high_risk_pregnancy'] == 1 || _currentMember['is_high_risk_pregnancy'] == true,
                              isLactating: _currentMember['is_lactating'] == 1 || _currentMember['is_lactating'] == true,
                              td1Vaccine: _currentMember['td1_vaccine'] == 1 || _currentMember['td1_vaccine'] == true,
                              td2Vaccine: _currentMember['td2_vaccine'] == 1 || _currentMember['td2_vaccine'] == true,
                              tdBooster: _currentMember['td_booster'] == 1 || _currentMember['td_booster'] == true,
                              ifaTabletsGiven: _currentMember['ifa_tablets_given'] as int? ?? 0,
                              calciumTabletsGiven: _currentMember['calcium_tablets_given'] as int? ?? 0,
                              birthWeight: _currentMember['birth_weight'] != null ? double.tryParse(_currentMember['birth_weight'].toString()) : null,
                              deliveryType: _currentMember['delivery_type']?.toString(),
                              muacCm: _currentMember['muac_cm'] != null ? double.tryParse(_currentMember['muac_cm'].toString()) : null,
                              hasChronicCondition: hasChronic,
                              chronicNotes: chronicNotesCtrl.text.isNotEmpty ? chronicNotesCtrl.text : null,
                            );
                            if (!mounted || !context.mounted) return;
                            Navigator.pop(ctx);
                            if (ok) {
                              setState(() {
                                _currentMember['full_name'] = nameCtrl.text;
                                _currentMember['age'] = age;
                                _currentMember['gender'] = gender;
                                _currentMember['relationship_to_head'] = relCtrl.text;
                                if (pickedImageBase64 != null) _currentMember['profile_image'] = pickedImageBase64;
                                _currentMember['abha_id'] = abhaCtrl.text;
                                _currentMember['mobile_number'] = phoneCtrl.text;
                                _currentMember['has_chronic_condition'] = hasChronic ? 1 : 0;
                                _currentMember['chronic_notes'] = chronicNotesCtrl.text;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Member profile updated!'), backgroundColor: Color(0xFF5B2C82)),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGenderSegment(String label, String value, String current, Function(String) onSelect) {
    final isSelected = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF3E5F5) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: const Color(0xFF5B2C82), width: 1.5) : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF5B2C82) : Colors.grey.shade800,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Add Medical Record Dialog
  // ─────────────────────────────────────────────────────────────────────
  void _showAddRecordDialog() {
    String entrySource = 'manual'; // 'manual' or 'device'
    final systolicCtrl = TextEditingController();
    final diastolicCtrl = TextEditingController();
    final bsfCtrl = TextEditingController();
    final bsppCtrl = TextEditingController();
    final tempCtrl = TextEditingController();
    final pulseCtrl = TextEditingController();
    final spo2Ctrl = TextEditingController();
    final rrCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.monitor_heart, color: Color(0xFF00796B)),
            const SizedBox(width: 8),
            Text(LanguageService.tr('record_vital_signs')),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Entry Source Toggle ──
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setModalState(() => entrySource = 'manual'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: entrySource == 'manual' ? const Color(0xFF00796B) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.edit_note,
                                    size: 18,
                                    color: entrySource == 'manual' ? Colors.white : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text('Manual Entry',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: entrySource == 'manual' ? Colors.white : Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setModalState(() => entrySource = 'device'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: entrySource == 'device' ? const Color(0xFF00796B) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.usb,
                                    size: 18,
                                    color: entrySource == 'device' ? Colors.white : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text('Device (USB)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: entrySource == 'device' ? Colors.white : Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Manual Entry Fields ──
                  if (entrySource == 'manual') ...[
                    _vitalField(systolicCtrl, LanguageService.tr('bp_systolic'), Icons.favorite),
                    _vitalField(diastolicCtrl, LanguageService.tr('bp_diastolic'), Icons.favorite_border),
                    _vitalField(pulseCtrl, LanguageService.tr('pulse_rate'), Icons.monitor_heart_outlined),
                    _vitalField(spo2Ctrl, LanguageService.tr('spo2'), Icons.air),
                    _vitalField(rrCtrl, LanguageService.tr('respiratory_rate'), Icons.waves),
                    _vitalField(tempCtrl, LanguageService.tr('temperature'), Icons.thermostat),
                    _vitalField(bsfCtrl, LanguageService.tr('blood_sugar_fasting'), Icons.water_drop),
                    _vitalField(bsppCtrl, LanguageService.tr('blood_sugar_pp'), Icons.water_drop_outlined),
                    const SizedBox(height: 4),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: LanguageService.tr('clinical_notes'),
                        prefixIcon: const Icon(Icons.notes),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],

                  // ── Device Stub ──
                  if (entrySource == 'device') ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.usb, size: 40, color: Colors.orange.shade700),
                          const SizedBox(height: 12),
                          Text(
                            'Device Connection',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800, fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connect the health monitoring device via USB OTG to begin reading vitals automatically.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Device connection not yet implemented. Use Manual Entry for now.')),
                              );
                            },
                            icon: const Icon(Icons.cable),
                            label: const Text('Connect Device'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.tr('cancel'))),
            if (entrySource == 'manual')
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00796B),
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving ? null : () async {
                  setModalState(() => isSaving = true);
                  final ok = await LocalDbService.addMedicalRecord(
                    token: widget.token,
                    memberId: widget.member['id'].toString(),
                    bloodPressureSystolic: int.tryParse(systolicCtrl.text),
                    bloodPressureDiastolic: int.tryParse(diastolicCtrl.text),
                    pulseRate: int.tryParse(pulseCtrl.text),
                    spo2: int.tryParse(spo2Ctrl.text),
                    respiratoryRate: int.tryParse(rrCtrl.text),
                    temperature: double.tryParse(tempCtrl.text),
                    bloodSugarFasting: double.tryParse(bsfCtrl.text),
                    bloodSugarPostprandial: double.tryParse(bsppCtrl.text),
                    notes: notesCtrl.text,
                    entrySource: 'manual',
                  );
                  if (!mounted || !context.mounted) return;
                  Navigator.pop(ctx);
                  if (ok && context.mounted) {
                    _refresh();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(LanguageService.tr('save_record')), backgroundColor: Colors.green),
                    );
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to save record.'), backgroundColor: Colors.red),
                    );
                  }
                },
                child: isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(LanguageService.tr('save_record')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _vitalField(TextEditingController ctrl, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguageNotifier,
      builder: (context, currentLang, _) {
        final name = _currentMember['full_name'] ?? 'Member';
        final currentFlag = (_currentMember['current_flag'] ?? widget.member['current_flag']) as String?;

        return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004D40),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: _showEditMemberDialog,
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.teal.shade200,
                backgroundImage: ImageUtils.safeBase64Image(_currentMember['profile_image']?.toString()),
                child: ImageUtils.safeBase64Image(_currentMember['profile_image']?.toString()) != null
                    ? null
                    : Icon(
                        _currentMember['gender'] == 'male'
                            ? Icons.male
                            : (_currentMember['gender'] == 'female' ? Icons.female : Icons.person),
                        color: Colors.teal.shade900,
                        size: 18,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${LanguageService.tr('age')}: ${_currentMember['age']} ${LanguageService.tr('years')} • ${_currentMember['gender']}',
                    style: const TextStyle(fontSize: 10.5, color: Colors.tealAccent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          const LanguageSwitcherWidget(),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white, size: 19),
            tooltip: 'Edit Member / Photo',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            onPressed: _showEditMemberDialog,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined, size: 20),
            tooltip: 'Print PHC Referral Slip',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            onPressed: () async {
              final records = await _historyFuture;
              _showPHCReferralSlipDialog(records);
            },
          ),
          if (currentFlag != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: flagColor(currentFlag).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: flagColor(currentFlag), width: 1),
                ),
                child: Text(
                  currentFlag.toUpperCase(),
                  style: TextStyle(color: flagColor(currentFlag), fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00BFA5),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: [
            Tab(
              icon: const Icon(Icons.history, size: 19),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(LanguageService.tr('vitals_history')),
              ),
            ),
            Tab(
              icon: const Icon(Icons.show_chart, size: 19),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(LanguageService.tr('vital_changes')),
              ),
            ),
            Tab(
              icon: const Icon(Icons.psychology_outlined, size: 19),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(LanguageService.tr('ai_insights')),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(),
          _buildAnalyticsTab(),
          _buildAIInsightsTab(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          T7ChatFloatingButton(
            member: _currentMember,
            heroTag: 'member_qwen_chat_fab',
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'member_add_record_fab',
            onPressed: _showAddRecordDialog,
            backgroundColor: const Color(0xFF00796B),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_chart),
            label: Text(LanguageService.tr('add_record')),
          ),
        ],
      ),
    );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Tab 1: Health History
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    return FutureBuilder<List<dynamic>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final records = snapshot.data ?? [];
        final maternalCard = _buildMaternalANCCard();
        final pediatricCard = _buildPediatricChildCard();
        final hasMaternal = maternalCard is! SizedBox;
        final hasPediatric = pediatricCard is! SizedBox;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            if (hasMaternal) ...[
              maternalCard,
              const SizedBox(height: 12),
            ],
            if (hasPediatric) ...[
              pediatricCard,
              const SizedBox(height: 12),
            ],
            if (records.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monitor_heart_outlined, size: 54, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No health records yet.', style: TextStyle(color: Colors.grey, fontSize: 15)),
                      SizedBox(height: 6),
                      Text('Tap "+ Add Record" to log the first reading.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ] else ...[
              for (final r in records) _buildRecordCard(r),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRecordCard(dynamic r) {
    final flag = r['flag'] as String? ?? 'normal';
    final isDevice = r['entry_source'] == 'device';
    final dateStr = _formatDate(r['recorded_at']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isDevice ? Icons.usb : Icons.edit_note,
                  size: 16,
                  color: isDevice ? Colors.blueAccent : Colors.teal,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$dateStr • ${r['recorded_by_name'] ?? 'Unknown'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: flagColor(flag).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: flagColor(flag).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(flagIcon(flag), size: 13, color: flagColor(flag)),
                      const SizedBox(width: 4),
                      Text(
                        flag.toUpperCase(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: flagColor(flag)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Chip(
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  label: Text(
                    isDevice ? 'Device' : 'Manual',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDevice ? Colors.blueAccent : Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: isDevice ? Colors.blue.shade50 : Colors.teal.shade50,
                  side: BorderSide(color: isDevice ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.teal.withValues(alpha: 0.4)),
                ),
              ],
            ),
            const Divider(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (r['blood_pressure_systolic'] != null || r['blood_pressure_diastolic'] != null)
                  _vitalChip('BP', '${r['blood_pressure_systolic'] ?? '?'}/${r['blood_pressure_diastolic'] ?? '?'} mmHg', Icons.favorite, Colors.red),
                if (r['pulse_rate'] != null)
                  _vitalChip('Pulse', '${r['pulse_rate']} bpm', Icons.monitor_heart, Colors.teal),
                if (r['spo2'] != null)
                  _vitalChip('SpO2', '${r['spo2']}%', Icons.air, Colors.blue),
                if (r['respiratory_rate'] != null)
                  _vitalChip('RR', '${r['respiratory_rate']} /min', Icons.waves, Colors.indigo),
                if (r['temperature'] != null)
                  _vitalChip('Temp', '${r['temperature']}°F', Icons.thermostat, Colors.orange),
                if (r['blood_sugar_fasting'] != null)
                  _vitalChip('BSF', '${r['blood_sugar_fasting']} mg/dL', Icons.water_drop, Colors.purple),
                if (r['blood_sugar_postprandial'] != null)
                  _vitalChip('BSPP', '${r['blood_sugar_postprandial']} mg/dL', Icons.water_drop_outlined, Colors.deepPurple),
              ],
            ),
            if (r['notes'] != null && (r['notes'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('📝 ${r['notes']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vitalChip(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Tab 2: Vital Variations (Delta)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildAnalyticsTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _analyticsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final data = snapshot.data ?? {};

        final cutoff = _getCutoffDate();
        List<dynamic> filterData(List<dynamic>? list) {
          if (list == null) return [];
          if (cutoff == null) return list;
          return list.where((item) {
            try {
              return DateTime.parse(item['date'].toString()).toLocal().isAfter(cutoff);
            } catch (_) {
              return true;
            }
          }).toList();
        }

        final systolicDataList = filterData(data['blood_pressure_systolic'] as List?);
        final diastolicDataList = filterData(data['blood_pressure_diastolic'] as List?);
        final bsfDataList = filterData(data['blood_sugar_fasting'] as List?);
        final hrDataList = filterData(data['pulse_rate'] as List?);
        final spo2DataList = filterData(data['spo2'] as List?);
        final tempDataList = filterData(data['temperature'] as List?);
        final rrDataList = filterData(data['respiratory_rate'] as List?);

        final systolicData = _toSpots(systolicDataList);
        final diastolicData = _toSpots(diastolicDataList);
        final bsfData = _toSpots(bsfDataList);
        final hrData = _toSpots(hrDataList);
        final spo2Data = _toSpots(spo2DataList);
        final tempData = _toSpots(tempDataList);
        final rrData = _toSpots(rrDataList);

        final bpDates = systolicDataList.isNotEmpty
            ? systolicDataList.map((e) => e['date']?.toString() ?? '').toList()
            : diastolicDataList.map((e) => e['date']?.toString() ?? '').toList();
        final bsfDates = bsfDataList.map((e) => e['date']?.toString() ?? '').toList();
        final hrDates = hrDataList.map((e) => e['date']?.toString() ?? '').toList();
        final spo2Dates = spo2DataList.map((e) => e['date']?.toString() ?? '').toList();
        final tempDates = tempDataList.map((e) => e['date']?.toString() ?? '').toList();
        final rrDates = rrDataList.map((e) => e['date']?.toString() ?? '').toList();

        final hasAnyData = systolicData.isNotEmpty ||
            diastolicData.isNotEmpty ||
            bsfData.isNotEmpty ||
            hrData.isNotEmpty ||
            spo2Data.isNotEmpty ||
            tempData.isNotEmpty ||
            rrData.isNotEmpty;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Time Range: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedTimeRange,
                    isDense: true,
                    underline: Container(height: 1, color: Colors.teal),
                    items: const [
                      DropdownMenuItem(value: '7d', child: Text('Last 7 Days')),
                      DropdownMenuItem(value: '14d', child: Text('Last 14 Days')),
                      DropdownMenuItem(value: '1m', child: Text('Last 1 Month')),
                      DropdownMenuItem(value: '2m', child: Text('Last 2 Months')),
                      DropdownMenuItem(value: '3m', child: Text('Last 3 Months')),
                      DropdownMenuItem(value: '6m', child: Text('Last 6 Months')),
                      DropdownMenuItem(value: '9m', child: Text('Last 9 Months')),
                      DropdownMenuItem(value: '1y', child: Text('Last 1 Year')),
                      DropdownMenuItem(value: 'all', child: Text('All Time')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedTimeRange = val);
                      }
                    },
                  ),
                ],
              ),
            ),
            if (!hasAnyData)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.show_chart, size: 54, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No vital variations recorded in this time range.', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16).copyWith(top: 0),
                  children: [
                    _chartCard(
                      title: 'Blood Pressure',
                      subtitle: '— Systolic   ┄ Diastolic',
                      dates: bpDates,
                      lines: [
                        LineChartBarData(
                          spots: systolicData,
                          isCurved: false,
                          color: const Color(0xFFE53935),
                          barWidth: 2.5,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 4.5,
                              color: const Color(0xFFE53935),
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                        ),
                        LineChartBarData(
                          spots: diastolicData,
                          isCurved: false,
                          color: const Color(0xFFFFA000),
                          barWidth: 2.5,
                          dashArray: [5, 4],
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 4.5,
                              color: const Color(0xFFFFA000),
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                      yLabel: 'mmHg',
                      emptyMessage: 'No BP data yet',
                      hasData: systolicData.isNotEmpty || diastolicData.isNotEmpty,
                    ),
                    const SizedBox(height: 16),
                    _chartCard(
                      title: 'Blood Sugar (Fasting)',
                      subtitle: '— Fasting glucose',
                      dates: bsfDates,
                      lines: [
                        LineChartBarData(
                          spots: bsfData,
                          isCurved: false,
                          color: const Color(0xFF8E24AA),
                          barWidth: 2.5,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 4.5,
                              color: const Color(0xFF8E24AA),
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF8E24AA).withAlpha(20),
                          ),
                        ),
                      ],
                      yLabel: 'mg/dL',
                      emptyMessage: 'No blood sugar data yet',
                      hasData: bsfData.isNotEmpty,
                    ),
                    if (hrData.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _chartCard(
                        title: 'Heart Rate / Pulse',
                        subtitle: '— Pulse rate',
                        dates: hrDates,
                        lines: [
                          LineChartBarData(
                            spots: hrData,
                            isCurved: false,
                            color: const Color(0xFF00897B),
                            barWidth: 2.5,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                radius: 4.5,
                                color: const Color(0xFF00897B),
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: const Color(0xFF00897B).withAlpha(20),
                            ),
                          ),
                        ],
                        yLabel: 'bpm',
                        emptyMessage: 'No pulse data yet',
                        hasData: hrData.isNotEmpty,
                      ),
                    ],
                    if (spo2Data.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _chartCard(
                        title: 'SpO2 Oxygen Saturation',
                        subtitle: '— SpO2 level',
                        dates: spo2Dates,
                        lines: [
                          LineChartBarData(
                            spots: spo2Data,
                            isCurved: false,
                            color: const Color(0xFF1E88E5),
                            barWidth: 2.5,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                radius: 4.5,
                                color: const Color(0xFF1E88E5),
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: const Color(0xFF1E88E5).withAlpha(20),
                            ),
                          ),
                        ],
                        yLabel: '%',
                        emptyMessage: 'No SpO2 data yet',
                        hasData: spo2Data.isNotEmpty,
                      ),
                    ],
                    if (tempData.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _chartCard(
                        title: 'Body Temperature',
                        subtitle: '— Temperature in °F',
                        dates: tempDates,
                        lines: [
                          LineChartBarData(
                            spots: tempData,
                            isCurved: false,
                            color: const Color(0xFFFB8C00),
                            barWidth: 2.5,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                radius: 4.5,
                                color: const Color(0xFFFB8C00),
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: const Color(0xFFFB8C00).withAlpha(20),
                            ),
                          ),
                        ],
                        yLabel: '°F',
                        emptyMessage: 'No temperature data yet',
                        hasData: tempData.isNotEmpty,
                      ),
                    ],
                    if (rrData.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _chartCard(
                        title: 'Respiratory Rate',
                        subtitle: '— Breaths per minute',
                        dates: rrDates,
                        lines: [
                          LineChartBarData(
                            spots: rrData,
                            isCurved: false,
                            color: const Color(0xFF5E35B1),
                            barWidth: 2.5,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                radius: 4.5,
                                color: const Color(0xFF5E35B1),
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: const Color(0xFF5E35B1).withAlpha(20),
                            ),
                          ),
                        ],
                        yLabel: '/min',
                        emptyMessage: 'No respiratory data yet',
                        hasData: rrData.isNotEmpty,
                      ),
                    ],
                    if (_buildMaternalANCCard() is! SizedBox) ...[
                      const SizedBox(height: 16),
                      _buildMaternalANCCard(),
                    ],
                    if (_buildPediatricChildCard() is! SizedBox) ...[
                      const SizedBox(height: 16),
                      _buildPediatricChildCard(),
                    ],
                    const SizedBox(height: 100),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  List<FlSpot> _toSpots(List? dataPoints) {
    if (dataPoints == null || dataPoints.isEmpty) return [];
    return dataPoints.asMap().entries.map((entry) {
      final val = entry.value['value'];
      final numVal = (val is num) ? val.toDouble() : double.tryParse(val?.toString() ?? '') ?? 0.0;
      return FlSpot(entry.key.toDouble(), numVal);
    }).toList();
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required List<String> dates,
    required List<LineChartBarData> lines,
    required String yLabel,
    required String emptyMessage,
    required bool hasData,
  }) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            if (!hasData)
              SizedBox(
                height: 120,
                child: Center(child: Text(emptyMessage, style: const TextStyle(color: Colors.grey, fontSize: 13))),
              )
            else
              SizedBox(
                height: 185,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (dates.length - 1).toDouble() > 0 ? (dates.length - 1).toDouble() : 1.0,
                    lineBarsData: lines,
                    gridData: FlGridData(
                      show: true,
                      drawHorizontalLine: true,
                      drawVerticalLine: true,
                      getDrawingHorizontalLine: (_) =>
                        const FlLine(color: Color(0xFFEEEEEE), strokeWidth: 1),
                      getDrawingVerticalLine: (_) =>
                        const FlLine(color: Color(0xFFEEEEEE), strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        axisNameWidget: Text(yLabel, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          reservedSize: 22,
                          getTitlesWidget: (value, meta) {
                            if (value % 1 != 0) return const SizedBox.shrink();
                            int index = value.toInt();
                            if (index < 0 || index >= dates.length) return const SizedBox.shrink();

                            String dtStr = dates[index];
                            String formatted = '';
                            try {
                              final dt = DateTime.parse(dtStr).toLocal();
                              formatted = DateFormat('dd MMM').format(dt);
                            } catch (_) {
                              formatted = dtStr.length >= 5 ? dtStr.substring(0, 5) : dtStr;
                            }

                            return Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                formatted,
                                style: const TextStyle(fontSize: 9, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: dates.isNotEmpty,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => const Color(0xFF263238),
                        getTooltipItems: (spots) => spots.map((spot) => LineTooltipItem(
                          '${spot.y.toStringAsFixed(1)} $yLabel',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        )).toList(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }


  // ── 4. One-Tap PHC Clinical Summary & Referral Slip Dialog ──
  void _showPHCReferralSlipDialog(List<dynamic> records) {
    if (records.isEmpty) return;
    final latest = Map<String, dynamic>.from(records.first);
    final name = _currentMember['full_name'] ?? _currentMember['name'] ?? 'Patient';
    final age = _currentMember['age'] ?? 'Unknown';
    final gender = _currentMember['gender'] ?? 'Unknown';
    final abha = _currentMember['abha_id'] ?? 'Not Linked';
    final nowStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.local_hospital, color: Color(0xFF00796B)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'PHC / Emergency Referral Slip',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patient: $name ($gender, $age yrs)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('ABHA ID: $abha', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                    Text('Generated: $nowStr', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Latest Bedside Physiological Readings:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _slipRow('Blood Pressure', '${latest['blood_pressure_systolic'] ?? '?'}/${latest['blood_pressure_diastolic'] ?? '?'} mmHg'),
              _slipRow('Pulse / HR', '${latest['pulse_rate'] ?? '?'} bpm'),
              _slipRow('SpO2 Oxygen', '${latest['spo2'] ?? '?'} %'),
              _slipRow('Core Temp', '${latest['temperature'] ?? '?'} °F'),
              _slipRow('Resp Rate', '${latest['respiratory_rate'] ?? '?'} rpm'),
              _slipRow('Blood Sugar', '${latest['blood_sugar_fasting'] ?? latest['blood_sugar_postprandial'] ?? '?'} mg/dL'),
              if (latest['notes'] != null && (latest['notes'] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('ASHA Field Notes: "${latest['notes']}"', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
              ],
              const Divider(height: 20),
              const Text('Doctor Clinical Impression & Action:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 35),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('_____________________________\nPHC Medical Officer Signature', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('📄 PHC Clinical Referral Slip generated successfully!')),
              );
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirm & Print'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00796B), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _slipRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── ANC Pregnancy Registration Dialog ──
  void _showRegisterANCDialog() {
    final husbandCtrl = TextEditingController();
    final thayiCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final bpSysCtrl = TextEditingController(text: '120');
    final bpDiaCtrl = TextEditingController(text: '80');
    final hbCtrl = TextEditingController(text: '11.5');
    final sugarCtrl = TextEditingController();
    final riskNotesCtrl = TextEditingController();

    DateTime? lmpDate = _currentMember['lmp_date'] != null ? DateTime.tryParse(_currentMember['lmp_date'].toString()) : null;
    DateTime? eddDate;
    String? eddDateStr = _currentMember['edd_date']?.toString();
    DateTime regDate = DateTime.now();

    final gravidaCtrl = TextEditingController(text: '1');
    final paraCtrl = TextEditingController(text: '0');
    final abortionCtrl = TextEditingController(text: '0');
    final livingCtrl = TextEditingController(text: '0');

    String? bloodGroup;
    String urineAlbumin = 'Nil';

    bool td1 = (_currentMember['td1_vaccine'] == 1 || _currentMember['td1_vaccine'] == true);
    bool td2 = (_currentMember['td2_vaccine'] == 1 || _currentMember['td2_vaccine'] == true);
    bool tdBooster = (_currentMember['td_booster'] == 1 || _currentMember['td_booster'] == true);
    bool ifaProvided = true;
    bool calciumProvided = true;

    final Set<String> selectedRisks = {};
    if (_currentMember['is_high_risk_pregnancy'] == 1 || _currentMember['is_high_risk_pregnancy'] == true) {
      selectedRisks.add('High-Risk Flagged');
    }

    if (lmpDate != null) {
      eddDate = lmpDate.add(const Duration(days: 280));
      eddDateStr = DateFormat('dd MMM yyyy').format(eddDate);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          int weeks = 0;
          String stageText = '';
          if (lmpDate != null) {
            final days = DateTime.now().difference(lmpDate!).inDays;
            weeks = (days / 7).floor();
            final tri = weeks >= 28 ? '3rd Trimester' : (weeks >= 13 ? '2nd Trimester' : '1st Trimester');
            stageText = 'Week $weeks • $tri';
          }

          return Dialog(
            backgroundColor: const Color(0xFFFBF8F5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: 540,
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF32104E)),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            LanguageService.tr('anc_pregnancy_registration'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF32104E)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Pregnant Woman Name
                    Text('${LanguageService.tr('pregnant_woman_name')} *', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                      child: Text(_currentMember['full_name']?.toString() ?? 'Mother', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(height: 12),

                    // Husband Name
                    Text('${LanguageService.tr('husband_name')} *', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: husbandCtrl,
                      decoration: InputDecoration(
                        hintText: LanguageService.tr('enter_husband_name'),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Thayi Card Number
                    Text(LanguageService.tr('thayi_card_number'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: thayiCtrl,
                      decoration: InputDecoration(
                        hintText: LanguageService.tr('from_thayi_card'),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Age
                    Text('${LanguageService.tr('age')} (${LanguageService.tr('years')}) *', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                      child: Text('${_currentMember['age'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(height: 12),

                    // LMP Date Picker
                    Text('${LanguageService.tr('lmp_date')} *', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.pink)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: lmpDate ?? DateTime.now().subtract(const Duration(days: 60)),
                          firstDate: DateTime.now().subtract(const Duration(days: 300)),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setModalState(() {
                            lmpDate = picked;
                            eddDate = picked.add(const Duration(days: 280));
                            eddDateStr = DateFormat('dd MMM yyyy').format(eddDate!);
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: lmpDate == null ? Colors.pink.shade300 : Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              lmpDate == null ? LanguageService.tr('pick_a_date') : DateFormat('dd MMM yyyy').format(lmpDate!),
                              style: TextStyle(fontSize: 14, color: lmpDate == null ? Colors.grey : Colors.black87, fontWeight: FontWeight.w600),
                            ),
                            const Icon(Icons.calendar_month, color: Colors.pink, size: 20),
                          ],
                        ),
                      ),
                    ),
                    if (stageText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('🌸 $stageText', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple)),
                    ],
                    const SizedBox(height: 12),

                    // Expected Delivery Date
                    Text(LanguageService.tr('edd_date'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: eddDate ?? DateTime.now().add(const Duration(days: 200)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 320)),
                        );
                        if (picked != null) {
                          setModalState(() {
                            eddDate = picked;
                            eddDateStr = DateFormat('dd MMM yyyy').format(picked);
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(eddDateStr ?? LanguageService.tr('edd_auto_calculated'), style: TextStyle(fontSize: 14, color: eddDateStr == null ? Colors.grey : Colors.black87, fontWeight: FontWeight.w600)),
                            const Icon(Icons.calendar_month_outlined, color: Colors.grey, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Registration Date
                    Text('${LanguageService.tr('registration_date')} *', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: regDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 120)),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setModalState(() => regDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('dd MMM yyyy').format(regDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const Icon(Icons.calendar_month, color: Colors.grey, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── GPAL Obstetric History ──
                    Text(LanguageService.tr('obstetric_history_gpal'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5B2C82))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: gravidaCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: LanguageService.tr('gravida'),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: paraCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: LanguageService.tr('para'),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: abortionCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: LanguageService.tr('abortions'),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: livingCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: LanguageService.tr('living_children'),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Clinical Baseline Tests ──
                    const Text('Clinical Screening & Vitals', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5B2C82))),
                    const SizedBox(height: 8),

                    // Blood Group
                    DropdownButtonFormField<String>(
                      initialValue: bloodGroup,
                      decoration: InputDecoration(
                        labelText: 'Blood group',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'A+', child: Text('A+')),
                        DropdownMenuItem(value: 'A-', child: Text('A- (Rh Negative) ⚠️')),
                        DropdownMenuItem(value: 'B+', child: Text('B+')),
                        DropdownMenuItem(value: 'B-', child: Text('B- (Rh Negative) ⚠️')),
                        DropdownMenuItem(value: 'O+', child: Text('O+')),
                        DropdownMenuItem(value: 'O-', child: Text('O- (Rh Negative) ⚠️')),
                        DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                        DropdownMenuItem(value: 'AB-', child: Text('AB- (Rh Negative) ⚠️')),
                      ],
                      onChanged: (v) => setModalState(() => bloodGroup = v),
                    ),
                    const SizedBox(height: 10),

                    // Weight & Hemoglobin
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: weightCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Weight (kg)',
                              hintText: 'e.g. 55',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: hbCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Hemoglobin (g/dL)',
                              hintText: 'e.g. 11.5',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // BP Systolic & Diastolic
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bpSysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'BP systolic',
                              hintText: 'e.g. 120',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: bpDiaCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'BP diastolic',
                              hintText: 'e.g. 80',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Blood Sugar & Urine Albumin
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: sugarCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Blood sugar (mg/dL)',
                              hintText: 'e.g. 95',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: urineAlbumin,
                            decoration: InputDecoration(
                              labelText: 'Urine Albumin',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Nil', child: Text('Nil (Normal)')),
                              DropdownMenuItem(value: 'Trace', child: Text('Trace')),
                              DropdownMenuItem(value: 'Present (+)', child: Text('Present (+) ⚠️')),
                              DropdownMenuItem(value: 'High (++)', child: Text('High (++) 🚨')),
                            ],
                            onChanged: (v) => setModalState(() => urineAlbumin = v ?? 'Nil'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Tetanus Vaccines ──
                    const Text('Tetanus (Td) Immunization', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF5B2C82))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Td-1 Dose', style: TextStyle(fontSize: 12)),
                            value: td1,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => td1 = v ?? false),
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Td-2 Dose', style: TextStyle(fontSize: 12)),
                            value: td2,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => td2 = v ?? false),
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Td Booster', style: TextStyle(fontSize: 12)),
                            value: tdBooster,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => tdBooster = v ?? false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── High-Risk Pregnancy Chips ──
                    const Text('High-risk factors (if any)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        'Previous C-Section',
                        'Severe Anemia (Hb < 7)',
                        'Hypertension / High BP',
                        'Gestational Diabetes',
                        'Age < 18 or > 35',
                        'Twins / Multiple',
                      ].map((risk) {
                        final isSel = selectedRisks.contains(risk);
                        return FilterChip(
                          label: Text(risk, style: TextStyle(fontSize: 11, color: isSel ? Colors.red.shade900 : Colors.black87, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                          selected: isSel,
                          selectedColor: Colors.red.shade100,
                          checkmarkColor: Colors.red.shade900,
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selectedRisks.add(risk);
                              } else {
                                selectedRisks.remove(risk);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: riskNotesCtrl,
                      decoration: InputDecoration(
                        hintText: 'Additional clinical notes or risk factors...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Nutrition Checkboxes ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('IFA tablets provided (Iron & Folic Acid)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text('180 target protocol', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            value: ifaProvided,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => ifaProvided = v ?? false),
                          ),
                          const Divider(height: 1),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Calcium tablets provided (500mg)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text('360 target protocol', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            value: calciumProvided,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => calciumProvided = v ?? false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Purple Save Button ──
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B2C82),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('Save ANC Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          if (lmpDate == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select LMP Date to register ANC')),
                            );
                            return;
                          }

                          final isHrp = selectedRisks.isNotEmpty ||
                              (double.tryParse(hbCtrl.text) ?? 12) < 7 ||
                              (int.tryParse(bpSysCtrl.text) ?? 120) >= 140;

                          final ok = await LocalDbService.updateMember(
                            token: widget.token,
                            memberId: _currentMember['id'].toString(),
                            fullName: _currentMember['full_name'],
                            age: _currentMember['age'],
                            gender: _currentMember['gender'],
                            relationship: _currentMember['relationship_to_head'],
                            profileImage: _currentMember['profile_image']?.toString(),
                            abhaId: _currentMember['abha_id']?.toString(),
                            mobileNumber: _currentMember['mobile_number']?.toString(),
                            isPregnant: true,
                            lmpDate: lmpDate?.toIso8601String(),
                            eddDate: eddDateStr,
                            isHighRiskPregnancy: isHrp,
                            isLactating: false,
                            td1Vaccine: td1,
                            td2Vaccine: td2,
                            tdBooster: tdBooster,
                            ifaTabletsGiven: ifaProvided ? ((_currentMember['ifa_tablets_given'] as int? ?? 0) + 30) : (_currentMember['ifa_tablets_given'] as int? ?? 0),
                            calciumTabletsGiven: calciumProvided ? ((_currentMember['calcium_tablets_given'] as int? ?? 0) + 60) : (_currentMember['calcium_tablets_given'] as int? ?? 0),
                            hasChronicCondition: _currentMember['has_chronic_condition'] == 1,
                            chronicNotes: selectedRisks.isNotEmpty ? selectedRisks.join(', ') : _currentMember['chronic_notes'],
                          );

                          // Record Baseline Vitals in Medical Records
                          if (bpSysCtrl.text.isNotEmpty || sugarCtrl.text.isNotEmpty || weightCtrl.text.isNotEmpty) {
                            await LocalDbService.addMedicalRecord(
                              token: widget.token,
                              memberId: _currentMember['id'].toString(),
                              bloodPressureSystolic: int.tryParse(bpSysCtrl.text),
                              bloodPressureDiastolic: int.tryParse(bpDiaCtrl.text),
                              bloodSugarFasting: double.tryParse(sugarCtrl.text),
                              notes: 'ANC Checkup • Hb: ${hbCtrl.text} g/dL, Wt: ${weightCtrl.text} kg, Urine: $urineAlbumin, Blood Group: ${bloodGroup ?? "—"}, GPAL: G${gravidaCtrl.text}P${paraCtrl.text}A${abortionCtrl.text}L${livingCtrl.text}${selectedRisks.isNotEmpty ? " • HRP: ${selectedRisks.join(', ')}" : ""}',
                              entrySource: 'manual',
                            );
                          }

                          if (!mounted || !context.mounted) return;
                          Navigator.pop(ctx);
                          if (ok) {
                            setState(() {
                              _currentMember['is_pregnant'] = 1;
                              _currentMember['lmp_date'] = lmpDate?.toIso8601String();
                              _currentMember['edd_date'] = eddDateStr;
                              _currentMember['is_high_risk_pregnancy'] = isHrp ? 1 : 0;
                              _currentMember['is_lactating'] = 0;
                              _currentMember['td1_vaccine'] = td1 ? 1 : 0;
                              _currentMember['td2_vaccine'] = td2 ? 1 : 0;
                              _currentMember['td_booster'] = tdBooster ? 1 : 0;
                            });
                            _refresh();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('🌸 ANC Registration saved successfully!'), backgroundColor: Color(0xFF5B2C82)),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Record Childbirth & Delivery Outcome Dialog ──
  void _showRecordDeliveryDialog() {
    DateTime deliveryDate = DateTime.now();
    String deliveryType = 'Institutional (Normal Delivery - NVD)';
    String babyGender = 'female';
    final babyNameCtrl = TextEditingController(text: 'Baby of ${_currentMember['full_name']}');
    final weightCtrl = TextEditingController(text: '2.8');
    bool bcgGiven = true;
    bool opv0Given = true;
    bool hepBGiven = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: const Color(0xFFFBF8F5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF32104E)),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 10),
                        Text(LanguageService.tr('birth_record'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF32104E))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Delivery Date
                    const Text('Delivery Date & Time *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: deliveryDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 60)),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setModalState(() => deliveryDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('dd MMM yyyy').format(deliveryDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const Icon(Icons.calendar_month, color: Colors.purple, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Delivery Type
                    const Text('Delivery Type & Place *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: deliveryType,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Institutional (Normal Delivery - NVD)', child: Text('Hospital / PHC (Normal - NVD)')),
                        DropdownMenuItem(value: 'Institutional (Caesarean - C-Section)', child: Text('Hospital (Caesarean - C-Section)')),
                        DropdownMenuItem(value: 'Home Delivery', child: Text('Home Delivery')),
                      ],
                      onChanged: (v) => setModalState(() => deliveryType = v ?? deliveryType),
                    ),
                    const SizedBox(height: 12),

                    // Baby Gender
                    const Text('Baby Gender', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => babyGender = 'female'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: babyGender == 'female' ? Colors.pink.shade50 : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: babyGender == 'female' ? Border.all(color: Colors.pink, width: 1.5) : null,
                                ),
                                child: Text('Girl 👧', textAlign: TextAlign.center, style: TextStyle(fontWeight: babyGender == 'female' ? FontWeight.bold : FontWeight.normal, color: babyGender == 'female' ? Colors.pink.shade800 : Colors.black87)),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => babyGender = 'male'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: babyGender == 'male' ? Colors.blue.shade50 : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: babyGender == 'male' ? Border.all(color: Colors.blue, width: 1.5) : null,
                                ),
                                child: Text('Boy 👦', textAlign: TextAlign.center, style: TextStyle(fontWeight: babyGender == 'male' ? FontWeight.bold : FontWeight.normal, color: babyGender == 'male' ? Colors.blue.shade800 : Colors.black87)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Baby Name & Birth Weight
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: babyNameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Baby Name',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: weightCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Weight (kg)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Birth Vaccines
                    const Text('Zero-Day Birth Vaccines Given', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('BCG', style: TextStyle(fontSize: 11)),
                            value: bcgGiven,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => bcgGiven = v ?? false),
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('OPV-0', style: TextStyle(fontSize: 11)),
                            value: opv0Given,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => opv0Given = v ?? false),
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Hep-B', style: TextStyle(fontSize: 11)),
                            value: hepBGiven,
                            activeColor: const Color(0xFF5B2C82),
                            onChanged: (v) => setModalState(() => hepBGiven = v ?? false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B2C82),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('Confirm Delivery & Transition to PNC', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final double? bWeight = double.tryParse(weightCtrl.text);

                          // 1. Transition mother from Pregnant to Lactating
                          final ok = await LocalDbService.updateMember(
                            token: widget.token,
                            memberId: _currentMember['id'].toString(),
                            fullName: _currentMember['full_name'],
                            age: _currentMember['age'],
                            gender: _currentMember['gender'],
                            relationship: _currentMember['relationship_to_head'],
                            profileImage: _currentMember['profile_image']?.toString(),
                            abhaId: _currentMember['abha_id']?.toString(),
                            mobileNumber: _currentMember['mobile_number']?.toString(),
                            isPregnant: false,
                            isLactating: true,
                            deliveryType: deliveryType,
                            birthWeight: bWeight,
                            hasChronicCondition: _currentMember['has_chronic_condition'] == 1,
                            chronicNotes: _currentMember['chronic_notes'],
                          );

                          // 2. Add newborn into the family
                          if (_currentMember['family'] != null) {
                            await LocalDbService.addMember(
                              widget.token,
                              _currentMember['family'].toString(),
                              babyNameCtrl.text.trim().isNotEmpty ? babyNameCtrl.text.trim() : 'Baby of ${_currentMember['full_name']}',
                              0,
                              babyGender,
                              babyGender == 'male' ? 'Son' : 'Daughter',
                              birthWeight: bWeight,
                              deliveryType: deliveryType,
                            );
                          }

                          if (!mounted || !context.mounted) return;
                          Navigator.pop(ctx);
                          if (ok) {
                            setState(() {
                              _currentMember['is_pregnant'] = 0;
                              _currentMember['is_lactating'] = 1;
                              _currentMember['delivery_type'] = deliveryType;
                            });
                            _refresh();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('👶 Childbirth recorded! Mother transitioned to PNC and newborn added to family.'),
                                backgroundColor: Color(0xFF5B2C82),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 1. Maternal ANC & PNC Clinical Healthcare Card ──
  Widget _buildMaternalANCCard() {
    final isPregnant = (_currentMember['is_pregnant'] == 1 || _currentMember['is_pregnant'] == true);
    final isLactating = (_currentMember['is_lactating'] == 1 || _currentMember['is_lactating'] == true);
    final gender = _currentMember['gender']?.toString().toLowerCase() ?? '';
    final age = int.tryParse(_currentMember['age']?.toString() ?? '0') ?? 0;

    // Show dedicated card for eligible reproductive women or active pregnancy/lactation
    if (!isPregnant && !isLactating) {
      if (gender != 'female' || age < 12 || age > 50) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2D9EC)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.pregnant_woman_rounded, color: Color(0xFF5B2C82), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LanguageService.tr('maternal_care'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2E1A47)),
                      ),
                      Text(
                        '${LanguageService.tr('eligible_reproductive_female')} ($age ${LanguageService.tr('years')}) • ${LanguageService.tr('not_currently_pregnant')}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(LanguageService.tr('eligible'), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF8FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade50),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFF5B2C82)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LanguageService.tr('maternal_care_guidance'),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showRegisterANCDialog,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text(LanguageService.tr('register_pregnancy_btn'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B2C82),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 1,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final lmpStr = _currentMember['lmp_date']?.toString();
    final eddStr = _currentMember['edd_date']?.toString();
    final isHighRisk = (_currentMember['is_high_risk_pregnancy'] == 1 || _currentMember['is_high_risk_pregnancy'] == true);
    final td1 = (_currentMember['td1_vaccine'] == 1 || _currentMember['td1_vaccine'] == true);
    final td2 = (_currentMember['td2_vaccine'] == 1 || _currentMember['td2_vaccine'] == true);
    final tdBooster = (_currentMember['td_booster'] == 1 || _currentMember['td_booster'] == true);
    final ifa = (_currentMember['ifa_tablets_given'] as int?) ?? 0;
    final calcium = (_currentMember['calcium_tablets_given'] as int?) ?? 0;

    int weeks = 0;
    String stageText = 'ANC Registered';
    String daysLeftText = '';
    if (lmpStr != null) {
      final lmp = DateTime.tryParse(lmpStr);
      if (lmp != null) {
        final days = DateTime.now().difference(lmp).inDays;
        weeks = (days / 7).floor();
        if (weeks >= 28) {
          stageText = 'Week $weeks • 3rd Trimester (Pre-Delivery)';
        } else if (weeks >= 13) {
          stageText = 'Week $weeks • 2nd Trimester (Growth)';
        } else {
          stageText = 'Week $weeks • 1st Trimester (Organogenesis)';
        }
        final edd = lmp.add(const Duration(days: 280));
        final diffDays = edd.difference(DateTime.now()).inDays;
        if (diffDays > 0) {
          daysLeftText = '👶 Due in ~$diffDays days (${DateFormat('dd MMM yyyy').format(edd)})';
        } else {
          daysLeftText = '👶 Due date reached (${DateFormat('dd MMM yyyy').format(edd)})';
        }
      }
    } else if (eddStr != null) {
      daysLeftText = '👶 Expected Delivery: $eddStr';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.pink.shade50, Colors.purple.shade50.withAlpha(100)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.pink.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.shade100.withAlpha(80),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.pink.shade100, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.pregnant_woman, color: Colors.pink, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Maternal Health & Reproductive Care', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.pink)),
                    Text(isPregnant ? 'Active ANC Protocol • 4 Mandatory Checkups' : 'Postnatal & Lactation Care', style: TextStyle(fontSize: 11, color: Colors.purple.shade700)),
                  ],
                ),
              ),
              if (isHighRisk)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 12),
                      SizedBox(width: 4),
                      Text('HRP HIGH RISK', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Gestational Progress Banner
          if (isPregnant) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.pink.shade100)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('🌸 $stageText', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple)),
                      Text('${(weeks / 40 * 100).clamp(0, 100).toStringAsFixed(0)}% Term', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.pink.shade700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (weeks / 40).clamp(0.0, 1.0),
                      backgroundColor: Colors.pink.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.pink),
                      minHeight: 6,
                    ),
                  ),
                  if (daysLeftText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(daysLeftText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal.shade800)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ANC 4-Checkup Protocol Grid
          const Text('Mandatory ANC Visit Milestones (GoI Guidelines):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            children: [
              _ancStagePill('ANC 1', '≤12 Wks', weeks >= 1, Colors.teal),
              const SizedBox(width: 6),
              _ancStagePill('ANC 2', '14-26 Wks', weeks >= 14, Colors.blue),
              const SizedBox(width: 6),
              _ancStagePill('ANC 3', '28-34 Wks', weeks >= 28, Colors.amber.shade800),
              const SizedBox(width: 6),
              _ancStagePill('ANC 4', '36+ Wks', weeks >= 36, Colors.purple),
            ],
          ),
          const SizedBox(height: 12),

          // Td Vaccine & Nutrition Tablets Grid
          Row(
            children: [
              // Vaccines
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.vaccines, size: 14, color: Colors.teal),
                          SizedBox(width: 4),
                          Text('Td Injections', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('• Td-1: ${td1 ? "✅ Given" : "⏳ Pending"}', style: TextStyle(fontSize: 10, color: td1 ? Colors.green.shade800 : Colors.black87)),
                      Text('• Td-2: ${td2 ? "✅ Given" : "⏳ Pending"}', style: TextStyle(fontSize: 10, color: td2 ? Colors.green.shade800 : Colors.black87)),
                      Text('• Booster: ${tdBooster ? "✅ Given" : "—"}', style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Nutrition Tablets
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.medication, size: 14, color: Colors.pink),
                          SizedBox(width: 4),
                          Text('Supplementation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('• IFA Tablets: $ifa / 180', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                      Text('• Calcium: $calcium / 360', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                      Text('• Deworming: ${weeks >= 14 ? "✅ Done" : "⏳ 2nd Tri"}', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 7-Stage Postnatal Care (PNC) Timeline
          if (isLactating || !isPregnant) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.purple.shade100)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.child_friendly, size: 14, color: Colors.purple),
                          SizedBox(width: 4),
                          Text('HBNC / PNC Home Visits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.purple)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(6)),
                        child: const Text('🍼 100% EBF Active', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.teal)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _pncDayBadge('Day 1'),
                        _pncDayBadge('Day 3'),
                        _pncDayBadge('Day 7'),
                        _pncDayBadge('Day 14'),
                        _pncDayBadge('Day 21'),
                        _pncDayBadge('Day 28'),
                        _pncDayBadge('Day 42'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Red-Flag Danger Signs Checklist
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50.withAlpha(100),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Maternal Red Flags: Severe headache, vision blur, facial edema, epigastric pain, bleeding, or reduced baby kicks ➔ Call 108 Emergency Ambulance!',
                    style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons: Update ANC / Record Delivery
          const SizedBox(height: 14),
          if (isPregnant) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showRegisterANCDialog,
                    icon: const Icon(Icons.edit_calendar, size: 16),
                    label: const Text('Update ANC / Vitals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF5B2C82),
                      side: const BorderSide(color: Color(0xFF5B2C82)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showRecordDeliveryDialog,
                    icon: const Icon(Icons.child_care, size: 16),
                    label: Text(LanguageService.tr('record_delivery'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B2C82),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (isLactating) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showRegisterANCDialog,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: Text(LanguageService.tr('register_new_pregnancy_btn'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF5B2C82),
                  side: const BorderSide(color: Color(0xFF5B2C82)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ancStagePill(String title, String timing, bool active, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(30) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? color : Colors.grey)),
            Text(timing, style: TextStyle(fontSize: 8, color: active ? color.withAlpha(200) : Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _pncDayBadge(String day) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Text(day, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple)),
    );
  }

  // ── 2. Pediatric Child Growth & Immunization Card (< 5 Years) ──
  Widget _buildPediatricChildCard() {
    final age = int.tryParse(_currentMember['age']?.toString() ?? '0') ?? 0;
    if (age >= 5) return const SizedBox.shrink();

    final birthWeight = (_currentMember['birth_weight'] as num?)?.toDouble();
    final deliveryType = _currentMember['delivery_type']?.toString() ?? 'Institutional (Hospital/PHC)';
    final muac = (_currentMember['muac_cm'] as num?)?.toDouble();

    String muacStatus = 'Normal Nutritional State';
    Color muacColor = Colors.green;
    if (muac != null) {
      if (muac < 11.5) {
        muacStatus = '🔴 SAM (Severe Acute Malnutrition - NRC Urgent)';
        muacColor = Colors.red;
      } else if (muac < 12.5) {
        muacStatus = '🟡 MAM (Moderate Malnutrition - Supplementary Food)';
        muacColor = Colors.orange;
      } else {
        muacStatus = '🟢 Green Zone (Healthy Nutritional Growth)';
        muacColor = Colors.green;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.teal.shade50.withAlpha(100)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withAlpha(80),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.child_care, color: Colors.blue, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pediatric Health & Immunization ($age Yrs)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
                    const Text('Universal Immunization Program (UIP) • Growth Tracking', style: TextStyle(fontSize: 11, color: Colors.teal)),
                  ],
                ),
              ),
              if (birthWeight != null && birthWeight < 2.5)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.favorite, color: Colors.orange, size: 12),
                      SizedBox(width: 4),
                      Text('LBW / KMC Care', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Birth Weight & Delivery Type
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Birth Weight', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text(birthWeight != null ? '$birthWeight kg' : 'Not Recorded', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text(birthWeight != null && birthWeight < 2.5 ? '⚠️ Low Birth Weight' : '🟢 Normal Weight', style: TextStyle(fontSize: 9, color: birthWeight != null && birthWeight < 2.5 ? Colors.orange : Colors.green)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Delivery Place', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text(deliveryType.contains('Inst') ? '🏥 Institutional' : '🏡 Home Delivery', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const Text('Safe Birth Protocol', style: TextStyle(fontSize: 9, color: Colors.teal)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Interactive MUAC Malnutrition Color Tape Gauge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.straighten, size: 14, color: Colors.teal),
                        const SizedBox(width: 4),
                        const Text('MUAC Arm Tape Screening', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                    Text(muac != null ? '$muac cm' : 'Tap to Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: muacColor)),
                  ],
                ),
                const SizedBox(height: 6),
                // Visual Color Scale Bar
                Row(
                  children: [
                    Expanded(flex: 2, child: Container(height: 6, decoration: BoxDecoration(color: Colors.red, borderRadius: const BorderRadius.horizontal(left: Radius.circular(4))))),
                    Expanded(flex: 2, child: Container(height: 6, color: Colors.orange)),
                    Expanded(flex: 6, child: Container(height: 6, decoration: BoxDecoration(color: Colors.green, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(muacStatus, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muacColor)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // National Immunization Schedule (NIS)
          const Text('National Immunization Schedule (NIS):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
            child: Column(
              children: [
                _vaccineRow('At Birth', 'BCG, OPV-0, Hepatitis-B', true),
                const Divider(height: 10),
                _vaccineRow('6, 10, 14 Wks', 'Pentavalent 1-2-3, Rotavirus, IPV, PCV', age >= 1),
                const Divider(height: 10),
                _vaccineRow('9–12 Months', 'Measles-Rubella (MR-1), Vitamin A', age >= 1),
                const Divider(height: 10),
                _vaccineRow('16–24 Months', 'MR-2, DPT Booster-1, OPV Booster', age >= 2),
                const Divider(height: 10),
                _vaccineRow('5–6 Years', 'DPT Booster-2', age >= 5),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // IMNCI Infant Danger Signs
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50.withAlpha(100),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.emergency, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Infant Danger Signs (IMNCI): Unable to suck milk, persistent vomiting, fast breathing (>50 bpm = Pneumonia), chest indrawing, or cold limbs ➔ Immediate Referral to Pediatric PHC/SNCU!',
                    style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vaccineRow(String stage, String vaccines, bool completed) {
    return Row(
      children: [
        Icon(completed ? Icons.check_circle : Icons.radio_button_unchecked, size: 14, color: completed ? Colors.green : Colors.grey),
        const SizedBox(width: 8),
        SizedBox(width: 85, child: Text(stage, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
        Expanded(child: Text(vaccines, style: TextStyle(fontSize: 10, color: completed ? Colors.black87 : Colors.grey.shade700))),
      ],
    );
  }



  // ─────────────────────────────────────────────────────────────────────
  // Tab 3: AI Health Intelligence (NEWS2 + DELTA + PhysioNet 2019 Sepsis)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildAIInsightsTab() {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguageNotifier,
      builder: (context, currentLang, _) {
        return FutureBuilder<List<dynamic>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error loading AI insights: ${snapshot.error}'));
            }

            final records = (snapshot.data ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

            if (records.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.psychology_outlined, size: 64, color: Colors.teal.shade300),
                      const SizedBox(height: 16),
                      Text(
                        LanguageService.tr('ai_insights', defaultText: 'AI Health Intelligence'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No vital records recorded yet. Log the first health record to generate on-device NEWS2 Early Warning score, DELTA variations, and PhysioNet Sepsis risk prediction.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showAddRecordDialog,
                        icon: const Icon(Icons.add_chart),
                        label: const Text('Add First Record'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00796B),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final latestRecord = records.first;
            final previousRecord = records.length > 1 ? records[1] : null;

            // 1. Evaluate NEWS2
            final news2Result = NEWS2DeltaService.evaluateNEWS2(latestRecord);

            // 2. Evaluate DELTA
            final deltaResult = NEWS2DeltaService.computeDelta(latestRecord, previousRecord);

            return FutureBuilder<Map<String, dynamic>>(
              future: SepsisInferenceService.predictSepsisRisk(
                records: records,
                member: _currentMember,
              ),
              builder: (context, sepsisSnapshot) {
                final sepsisResult = sepsisSnapshot.data ?? {
                  'risk_score': 0.05,
                  'risk_percent': '5%',
                  'risk_level': 'Low Risk',
                  'risk_color': '#4CAF50',
                  'confidence': 0.88,
                  'hours_to_onset': null,
                  'is_onnx': false,
                };

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 110.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card 1: Master Triage Risk Banner
                      _buildTriageRiskBanner(news2Result, sepsisResult),
                      const SizedBox(height: 14),

                      // Card 2: Hospital ICU Multiparameter Monitor & Telemetry
                      _buildHospitalMultiparameterTelemetry(latestRecord),
                      const SizedBox(height: 14),

                      // Card 3: Hospital Emergency Clinical Indices (Shock Index, MAP, qSOFA)
                      _buildEmergencyClinicalIndicesCard(latestRecord),
                      const SizedBox(height: 14),

                      // Card 4: PhysioNet 2019 Sepsis Model Card
                      _buildPhysioNetSepsisCard(sepsisResult, records.length),
                      const SizedBox(height: 14),

                      // Card 5: NEWS2 Early Warning Card
                      _buildNEWS2Card(news2Result, latestRecord),
                      const SizedBox(height: 14),

                      // Card 6: Longitudinal Trajectory Diagnostic ("What Happened Over Time")
                      _buildLongitudinalTrajectoryDiagnostic(records, deltaResult),
                      const SizedBox(height: 14),

                      // Card 7: DELTA Variations vs Last Visit
                      _buildDeltaCard(deltaResult, previousRecord != null),
                      const SizedBox(height: 14),

                      // Card 8: Multilingual AI Clinical Explanation
                      _buildAIExplanationCard(news2Result, sepsisResult, deltaResult, currentLang),
                      const SizedBox(height: 14),

                      // Card 9: Clinical Recommendation / Action
                      _buildClinicalActionCard(news2Result, sepsisResult),
                      const SizedBox(height: 40),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Master Triage Banner ──
  Widget _buildTriageRiskBanner(Map<String, dynamic> news2, Map<String, dynamic> sepsis) {
    final news2Score = news2['score'] as int? ?? 0;
    final sepsisLevel = sepsis['risk_level'] as String? ?? 'Low Risk';
    final isCritical = news2Score >= 7 || sepsisLevel == 'High Risk';
    final isWarning = news2Score >= 5 || sepsisLevel == 'Moderate Risk';

    final Color bannerColor = isCritical
        ? const Color(0xFFD32F2F)
        : (isWarning ? const Color(0xFFE65100) : const Color(0xFF2E7D32));

    final String statusTitle = isCritical
        ? 'HIGH CLINICAL CONCERN'
        : (isWarning ? 'MODERATE OBSERVATION' : 'STABLE / LOW RISK');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withAlpha(80),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isCritical ? Icons.warning_amber_rounded : (isWarning ? Icons.info_outline : Icons.check_circle_outline),
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '⚡ On-Device AI',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NEWS2 Score', style: TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$news2Score pts (${news2['risk_level']})',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sepsis Risk (PhysioNet)', style: TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${sepsis['risk_percent']} ($sepsisLevel)',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Hospital Multiparameter Telemetry Grid ──
  Widget _buildHospitalMultiparameterTelemetry(Map<String, dynamic> latest) {
    final sbp = latest['blood_pressure_systolic'] as int?;
    final dbp = latest['blood_pressure_diastolic'] as int?;
    final hr = latest['pulse_rate'] as int?;
    final spo2 = latest['spo2'] as int?;
    final rr = latest['respiratory_rate'] as int?;
    final temp = latest['temperature'] as num?;
    final bsf = latest['blood_sugar_fasting'] as num?;
    final bspp = (latest['blood_sugar_postprandial'] ?? latest['blood_sugar_pp']) as num?;

    Color hrColor = (hr != null && (hr > 100 || hr < 50)) ? Colors.redAccent : Colors.greenAccent.shade400;
    Color bpColor = (sbp != null && (sbp >= 140 || sbp < 90)) ? Colors.redAccent : Colors.cyanAccent.shade400;
    Color spo2Color = (spo2 != null && spo2 < 92) ? Colors.redAccent : (spo2 != null && spo2 < 95 ? Colors.amberAccent : Colors.greenAccent.shade400);
    Color rrColor = (rr != null && (rr > 22 || rr < 10)) ? Colors.redAccent : Colors.lightBlueAccent.shade200;
    Color tempColor = (temp != null && (temp > 101 || temp < 96)) ? Colors.redAccent : Colors.orangeAccent.shade200;
    Color sugarColor = ((bsf != null && (bsf > 140 || bsf < 70)) || (bspp != null && bspp > 180)) ? Colors.redAccent : Colors.tealAccent.shade400;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: const Color(0xFF0D1B2A), // Dark Hospital ICU Monitor Theme
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'ICU MULTIPARAMETER MONITOR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                            letterSpacing: 0.6,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'BEDSIDE TELEMETRY',
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent.shade100),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _telemetryTile(
                    label: 'ECG / PULSE',
                    value: hr != null ? '$hr' : '--',
                    unit: 'bpm',
                    normalRange: '60 - 100',
                    color: hrColor,
                    status: (hr == null) ? 'No Signal' : (hr > 100 ? 'Tachycardia' : (hr < 60 ? 'Bradycardia' : 'Normal Sinus')),
                    icon: Icons.monitor_heart,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _telemetryTile(
                    label: 'NIBP (BP)',
                    value: (sbp != null && dbp != null) ? '$sbp/$dbp' : '--/--',
                    unit: 'mmHg',
                    normalRange: '120/80',
                    color: bpColor,
                    status: (sbp == null) ? 'No Signal' : (sbp >= 140 ? 'Hypertension' : (sbp < 90 ? 'Hypotension' : 'Normotensive')),
                    icon: Icons.favorite,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _telemetryTile(
                    label: 'PLETH / SpO2',
                    value: spo2 != null ? '$spo2' : '--',
                    unit: '%',
                    normalRange: '95 - 100',
                    color: spo2Color,
                    status: (spo2 == null) ? 'No Signal' : (spo2 < 90 ? 'Hypoxemia' : (spo2 < 95 ? 'Borderline' : 'Optimal')),
                    icon: Icons.air,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _telemetryTile(
                    label: 'RESP RATE',
                    value: rr != null ? '$rr' : '--',
                    unit: 'rpm',
                    normalRange: '12 - 20',
                    color: rrColor,
                    status: (rr == null) ? 'No Signal' : (rr > 22 ? 'Tachypnea' : (rr < 10 ? 'Bradypnea' : 'Eupnea')),
                    icon: Icons.waves,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _telemetryTile(
                    label: 'TEMP (CORE)',
                    value: temp != null ? temp.toStringAsFixed(1) : '--',
                    unit: '°F',
                    normalRange: '97.8 - 99.1',
                    color: tempColor,
                    status: (temp == null) ? 'No Signal' : (temp > 100.4 ? 'Febrile / Fever' : (temp < 96 ? 'Hypothermia' : 'Normothermia')),
                    icon: Icons.thermostat,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _telemetryTile(
                    label: 'GLUCOSE',
                    value: bsf != null ? '$bsf' : (bspp != null ? '$bspp' : '--'),
                    unit: 'mg/dL',
                    normalRange: '70 - 140',
                    color: sugarColor,
                    status: (bsf == null && bspp == null) ? 'Not Tested' : ((bsf != null && bsf < 70) ? 'Hypoglycemia' : ((bsf != null && bsf > 130) ? 'Hyperglycemia' : 'Euglycemic')),
                    icon: Icons.water_drop,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _telemetryTile({
    required String label,
    required String value,
    required String unit,
    required String normalRange,
    required Color color,
    required String status,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A4A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 8.5, fontWeight: FontWeight.bold),
                ),
              ),
              Icon(icon, size: 11, color: color),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                ),
                const SizedBox(width: 2.5),
                Text(unit, style: const TextStyle(color: Colors.white38, fontSize: 8.5)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w600),
          ),
          Text(
            'Ref: $normalRange',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white24, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  // ── ICU Emergency Clinical Indices Card ──
  Widget _buildEmergencyClinicalIndicesCard(Map<String, dynamic> latest) {
    final sbp = latest['blood_pressure_systolic'] as int?;
    final dbp = latest['blood_pressure_diastolic'] as int?;
    final hr = latest['pulse_rate'] as int?;
    final rr = latest['respiratory_rate'] as int?;

    double? shockIndex;
    if (hr != null && sbp != null && sbp > 0) {
      shockIndex = hr / sbp;
    }

    double? map;
    if (sbp != null && dbp != null) {
      map = dbp + ((sbp - dbp) / 3.0);
    }

    int? pulsePressure;
    if (sbp != null && dbp != null) {
      pulsePressure = sbp - dbp;
    }

    int qsofa = 0;
    if (sbp != null && sbp <= 100) qsofa++;
    if (rr != null && rr >= 22) qsofa++;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.biotech, color: Color(0xFF00796B), size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hospital ICU Emergency Indices & Perfusion',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Real-time hemodynamic calculations utilized in emergency & critical care units.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _indexBox(
                    title: 'Shock Index (SI)',
                    value: shockIndex != null ? shockIndex.toStringAsFixed(2) : 'N/A',
                    subtitle: 'HR / SBP',
                    interpretation: shockIndex == null
                        ? 'Need HR & BP'
                        : (shockIndex > 0.9 ? '⚠️ Impending Shock' : (shockIndex >= 0.7 ? 'Mild Stress' : '✅ Normal (< 0.7)')),
                    isAlert: shockIndex != null && shockIndex > 0.9,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _indexBox(
                    title: 'Mean Arterial Press.',
                    value: map != null ? '${map.round()} mmHg' : 'N/A',
                    subtitle: 'Organ Perfusion',
                    interpretation: map == null
                        ? 'Need SBP/DBP'
                        : (map < 65 ? '⚠️ Hypoperfusion (<65)' : '✅ Adequate (≥ 65)'),
                    isAlert: map != null && map < 65,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _indexBox(
                    title: 'Pulse Pressure (PP)',
                    value: pulsePressure != null ? '$pulsePressure mmHg' : 'N/A',
                    subtitle: 'SBP - DBP',
                    interpretation: pulsePressure == null
                        ? 'Need SBP/DBP'
                        : (pulsePressure < 25 ? '⚠️ Narrow (Shock)' : (pulsePressure > 60 ? 'Wide (Stiff artery)' : '✅ Normal (30-50)')),
                    isAlert: pulsePressure != null && pulsePressure < 25,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _indexBox(
                    title: 'Bedside qSOFA',
                    value: '$qsofa / 2 pts',
                    subtitle: 'Quick Sepsis Score',
                    interpretation: qsofa >= 2 ? '⚠️ High Sepsis Risk' : (qsofa == 1 ? 'Moderate Risk' : '✅ Low Risk'),
                    isAlert: qsofa >= 2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _indexBox({
    required String title,
    required String value,
    required String subtitle,
    required String interpretation,
    required bool isAlert,
  }) {
    final Color bgColor = isAlert ? Colors.red.shade50 : Colors.grey.shade50;
    final Color borderColor = isAlert ? Colors.red.shade300 : Colors.grey.shade200;
    final Color valColor = isAlert ? Colors.red.shade800 : const Color(0xFF00796B);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.grey)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valColor)),
          ),
          const SizedBox(height: 4),
          Text(
            interpretation,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isAlert ? Colors.red.shade900 : Colors.black54),
          ),
        ],
      ),
    );
  }

  // ── Longitudinal Trajectory Diagnostic ("What Happened Over Time") ──
  Widget _buildLongitudinalTrajectoryDiagnostic(List<dynamic> records, Map<String, Map<String, dynamic>> delta) {
    if (records.isEmpty) return const SizedBox.shrink();

    final count = records.length;
    String trajectoryHeadline;
    String clinicalExplanation;
    IconData icon;
    Color color;

    if (count == 1) {
      trajectoryHeadline = 'Initial Baseline Encounter Established';
      clinicalExplanation = 'This is the patient\'s first recorded clinical assessment. Baseline physiological values have been benchmarked. Future visits will compare dynamic velocity and trajectory slopes.';
      icon = Icons.flag_outlined;
      color = const Color(0xFF00796B);
    } else {
      final latest = records.first;
      final prev = records[1];
      final sbpDiff = (latest['blood_pressure_systolic'] as int? ?? 120) - (prev['blood_pressure_systolic'] as int? ?? 120);
      final hrDiff = (latest['pulse_rate'] as int? ?? 75) - (prev['pulse_rate'] as int? ?? 75);
      final spo2Diff = (latest['spo2'] as int? ?? 98) - (prev['spo2'] as int? ?? 98);

      if (sbpDiff < -15 && hrDiff > 15) {
        trajectoryHeadline = '⚠️ Compensatory Circulatory Shift Detected';
        clinicalExplanation = 'Longitudinal analysis shows a notable drop in Systolic Blood Pressure ($sbpDiff mmHg) coupled with compensatory tachycardia (+$hrDiff bpm). This pattern is consistent with developing systemic hypoperfusion or fluid depletion.';
        icon = Icons.warning_amber_rounded;
        color = Colors.red.shade700;
      } else if (spo2Diff < -4) {
        trajectoryHeadline = '⚠️ Acute Respiratory Decline Pattern';
        clinicalExplanation = 'Oxygen saturation dropped by ${spo2Diff.abs()}% from the previous encounter. Recommend immediate auscultation, airway assessment, and Primary Health Centre referral.';
        icon = Icons.air;
        color = Colors.orange.shade800;
      } else {
        trajectoryHeadline = '✅ Stable Physiological Trajectory';
        clinicalExplanation = 'Hemodynamic and metabolic parameters demonstrate stable equilibrium across $count recorded encounters with no critical velocity deviations.';
        icon = Icons.verified_user_outlined;
        color = Colors.green.shade700;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(60), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trajectoryHeadline,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '$count Encounters',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              clinicalExplanation,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ── PhysioNet 2019 Sepsis Challenge Card ──
  Widget _buildPhysioNetSepsisCard(Map<String, dynamic> sepsis, int recordCount) {
    final riskScore = (sepsis['risk_score'] as num?)?.toDouble() ?? 0.0;
    final riskPercent = sepsis['risk_percent'] ?? '0%';
    final riskLevel = sepsis['risk_level'] ?? 'Low Risk';
    final hours = sepsis['hours_to_onset'];
    final confidence = ((sepsis['confidence'] as num?)?.toDouble() ?? 0.88) * 100;
    final isONNX = sepsis['is_onnx'] ?? false;

    Color progressColor = Colors.green;
    if (riskScore >= 0.60) {
      progressColor = Colors.red;
    } else if (riskScore >= 0.30) {
      progressColor = Colors.orange;
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.biotech, color: Color(0xFF00796B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'PhysioNet 2019 Sepsis Predictor',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isONNX ? Colors.teal.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isONNX ? Colors.teal.shade300 : Colors.blue.shade300),
                  ),
                  child: Text(
                    isONNX ? 'ONNX Runtime' : 'Clinical Model',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isONNX ? Colors.teal.shade900 : Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sepsis Probability: $riskPercent',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: progressColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  riskLevel.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: progressColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: riskScore,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Confidence', style: TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        FittedBox(fit: BoxFit.scaleDown, child: Text('${confidence.round()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                  ),
                  Container(height: 24, width: 1, color: Colors.grey.shade300),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Est. Onset Window', style: TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        FittedBox(fit: BoxFit.scaleDown, child: Text(hours != null ? '~$hours hrs' : 'N/A (Stable)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                  ),
                  Container(height: 24, width: 1, color: Colors.grey.shade300),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('History Points', style: TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        FittedBox(fit: BoxFit.scaleDown, child: Text('$recordCount visits', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Trained on PhysioNet/CinC 2019 Challenge 40,336 ICU patient dataset (Reyna et al., CC BY 4.0).',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  // ── NEWS2 Score Breakdown Card ──
  Widget _buildNEWS2Card(Map<String, dynamic> news2, Map<String, dynamic> latest) {
    final score = news2['score'] as int? ?? 0;
    final breakdown = (news2['breakdown'] as Map<String, dynamic>?) ?? {};
    final riskLevel = news2['risk_level'] ?? 'Low Risk';
    final hasExtreme = news2['has_extreme_vital'] ?? false;

    Color badgeColor = Colors.green;
    if (score >= 7) {
      badgeColor = Colors.red;
    } else if (score >= 5 || hasExtreme) {
      badgeColor = Colors.orange;
    } else if (score >= 1) {
      badgeColor = Colors.amber.shade700;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.health_and_safety, color: Color(0xFF00796B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'NEWS2 Clinical Early Warning',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    '$score Points ($riskLevel)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: badgeColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Royal College of Physicians (UK) standard clinical score for early deterioration detection.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Divider(height: 20),
            ...breakdown.entries.map((e) {
              final pts = e.value as int;
              Color ptColor = Colors.green;
              if (pts == 3) {
                ptColor = Colors.red;
              } else if (pts == 2) {
                ptColor = Colors.orange;
              } else if (pts == 1) {
                ptColor = Colors.amber.shade700;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        e.key,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pts / 3.0,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(ptColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ptColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$pts ${pts == 1 ? 'pt' : 'pts'}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ptColor),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (hasExtreme) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Single parameter scored 3 points (Extreme trigger detected — immediate clinical alert).',
                        style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── DELTA Variations Card ──
  Widget _buildDeltaCard(Map<String, Map<String, dynamic>> delta, bool hasPrevious) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up, color: Color(0xFF00796B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'DELTA Vitals Variation',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                    ),
                  ],
                ),
                Text(
                  hasPrevious ? 'vs. Last Visit' : 'Baseline Record',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasPrevious)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Color(0xFF00796B)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This is the member\'s baseline visit. Future visits will automatically calculate DELTA rate of change.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF004D40)),
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: delta.entries.map((e) {
                  final name = e.key;
                  final data = e.value;
                  final diff = data['diff'] as num?;
                  final pct = data['percent_change'] as num?;
                  final unit = data['unit'] as String? ?? '';
                  final direction = data['direction'] as String? ?? 'neutral';

                  if (diff == null) return const SizedBox.shrink();

                  Color chipColor = Colors.grey.shade700;
                  IconData dirIcon = Icons.remove;
                  Color bgColor = Colors.grey.shade100;

                  if (direction == 'up') {
                    dirIcon = Icons.arrow_upward;
                    chipColor = (name == 'SpO2') ? Colors.green : Colors.redAccent.shade700;
                    bgColor = (name == 'SpO2') ? Colors.green.shade50 : Colors.red.shade50;
                  } else if (direction == 'down') {
                    dirIcon = Icons.arrow_downward;
                    chipColor = (name == 'SpO2') ? Colors.redAccent.shade700 : Colors.blue.shade700;
                    bgColor = (name == 'SpO2') ? Colors.red.shade50 : Colors.blue.shade50;
                  }

                  final sign = diff > 0 ? '+' : '';
                  final diffStr = '$sign${diff.toStringAsFixed(diff is double && diff % 1 != 0 ? 1 : 0)} $unit';
                  final pctStr = pct != null ? ' (${pct > 0 ? '+' : ''}${pct.toStringAsFixed(0)}%)' : '';

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: chipColor.withAlpha(50)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(dirIcon, size: 14, color: chipColor),
                            const SizedBox(width: 4),
                            Text(
                              '$diffStr$pctStr',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: chipColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ── AI Explanation Card ──
  Widget _buildAIExplanationCard(
    Map<String, dynamic> news2,
    Map<String, dynamic> sepsis,
    Map<String, Map<String, dynamic>> delta,
    String currentLang,
  ) {
    final summary = LanguageService.generateClinicalExplanation(
      member: _currentMember,
      news2Result: news2,
      sepsisResult: sepsis,
      delta: delta,
      languageCode: currentLang,
    );

    final langInfo = LanguageService.getLanguageInfo(currentLang);
    final TextEditingController qwenQueryCtrl = TextEditingController();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF00796B), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'AI Clinical Intelligence (T7 Clinical AI)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Text(
                    '${langInfo['native']}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            // GGUF Download Status Banner (Disappears completely once model is downloaded!)
            ValueListenableBuilder<bool>(
              valueListenable: OnDeviceLLMService.isModelDownloadedNotifier,
              builder: (context, isDownloaded, _) {
                if (isDownloaded) {
                  return const SizedBox.shrink(); // Download header is gone once downloaded!
                }
                return ValueListenableBuilder<bool>(
                  valueListenable: OnDeviceLLMService.isDownloadingNotifier,
                  builder: (context, isDownloading, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: OnDeviceLLMService.isPausedNotifier,
                      builder: (context, isPaused, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isPaused ? Colors.orange.shade50 : (isDownloading ? Colors.blue.shade50 : Colors.amber.shade50),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isPaused
                                  ? Colors.orange.shade300
                                  : (isDownloading ? Colors.blue.shade300 : Colors.amber.shade300),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDownloading
                                    ? Icons.downloading_rounded
                                    : (isPaused ? Icons.pause_circle_filled : Icons.download_for_offline_outlined),
                                size: 18,
                                color: isPaused
                                    ? Colors.orange.shade900
                                    : (isDownloading ? Colors.blue.shade900 : Colors.amber.shade900),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isDownloading
                                      ? 'Downloading Offline Model... Tap to manage.'
                                      : (isPaused
                                          ? 'Download Paused • Tap Resume to continue.'
                                          : 'Optional: Download Offline GGUF Neural Model (~1.05 GB)'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isPaused
                                        ? Colors.orange.shade900
                                        : (isDownloading ? Colors.blue.shade900 : Colors.amber.shade900),
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: isDownloading
                                      ? Colors.orange.shade600
                                      : (isPaused ? const Color(0xFF00796B) : const Color(0xFF00796B)),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                onPressed: () {
                                  _showGgufDownloadDialog(context);
                                },
                                child: Text(
                                  isDownloading ? 'Pause' : (isPaused ? 'Resume' : 'Download'),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),

            // AI Explanation Output Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.teal.shade50.withAlpha(120),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade100),
              ),
              child: Text(
                summary,
                style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 12),

            // Custom Interactive Question Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qwenQueryCtrl,
                    decoration: InputDecoration(
                      hintText: 'Ask T7 Clinical AI Doctor a question in ${langInfo['name']}...',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF00796B)),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  onPressed: () async {
                    if (qwenQueryCtrl.text.trim().isEmpty) return;
                    final question = qwenQueryCtrl.text.trim();
                    qwenQueryCtrl.clear();
                    
                    final answer = await OnDeviceLLMService.generateGenerativeClinicalExplanation(
                      member: _currentMember,
                      news2Result: news2,
                      sepsisResult: sepsis,
                      delta: delta,
                      languageCode: currentLang,
                      customQuestion: question,
                    );

                    if (context.mounted) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Row(
                            children: [
                              const Icon(Icons.auto_awesome, color: Color(0xFF00796B)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('T7 Clinical AI Answer (${langInfo['native']})', style: const TextStyle(fontSize: 16)),
                              ),
                            ],
                          ),
                          content: SingleChildScrollView(
                            child: Text(answer, style: const TextStyle(fontSize: 13, height: 1.5)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00796B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(
                  '💬 Open Full T7 Clinical AI AI Health Chat (${langInfo['native']})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  _showT7ClinicalAIFullChatModal(context, news2, sepsis, delta, currentLang);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '100% Offline • On-Device Generative AI',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00796B),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.translate, size: 14),
                  label: const Text('Switch Language', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    LanguageSwitcherWidget.showLanguageModal(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showGgufDownloadDialog(BuildContext context) {
    OnDeviceLLMService.showModelManagementDialog(context);
  }

  // ── Clinical Action Card ──
  Widget _buildClinicalActionCard(Map<String, dynamic> news2, Map<String, dynamic> sepsis) {
    final news2Score = news2['score'] as int? ?? 0;
    final sepsisLevel = sepsis['risk_level'] as String? ?? 'Low Risk';
    final isCritical = news2Score >= 7 || sepsisLevel == 'High Risk';
    final isWarning = news2Score >= 5 || sepsisLevel == 'Moderate Risk';

    final Color cardBg = isCritical ? Colors.red.shade50 : (isWarning ? Colors.orange.shade50 : Colors.green.shade50);
    final Color borderColor = isCritical ? Colors.red.shade300 : (isWarning ? Colors.orange.shade300 : Colors.green.shade300);
    final Color textColor = isCritical ? Colors.red.shade900 : (isWarning ? Colors.orange.shade900 : Colors.green.shade900);
    final IconData icon = isCritical ? Icons.emergency : (isWarning ? Icons.warning_amber : Icons.verified_user_outlined);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(width: 8),
              Text(
                'RECOMMENDED CLINICAL ACTION',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            news2['action'] as String? ?? 'Routine monitoring per community schedule.',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
          ),
        ],
      ),
    );
  }

  void _showT7ClinicalAIFullChatModal(
    BuildContext context,
    Map<String, dynamic> news2,
    Map<String, dynamic> sepsis,
    Map<String, Map<String, dynamic>> delta,
    String currentLang,
  ) {
    QwenAIChatModal.show(
      context,
      member: _currentMember,
      news2Result: news2,
      sepsisResult: sepsis,
      delta: delta,
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return 'Unknown date';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

