import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/local_db_service.dart';
import '../services/image_utils.dart';
import '../services/language_service.dart';
import '../widgets/language_switcher_widget.dart';
import '../widgets/qwen_ai_chat_modal.dart';
import 'member_detail_screen.dart';

class FamilyDetailScreen extends StatefulWidget {
  final Map<String, dynamic> family;
  final String token;

  const FamilyDetailScreen({super.key, required this.family, required this.token});

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  late Future<List<dynamic>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _refreshMembers();
  }

  void _refreshMembers() {
    setState(() {
      _membersFuture = LocalDbService.getMembers(widget.token).then((allMembers) {
        // Filter locally by family id
        return allMembers.where((m) => m['family'].toString() == widget.family['id'].toString()).toList();
      });
    });
  }

  void _showAddMemberDialog() {
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final relCtrl = TextEditingController();
    String gender = 'female';
    String? pickedImageBase64;
    final abhaCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final aadhaarCtrl = TextEditingController();
    DateTime? dobDate;
    bool hasHereditary = false;
    final hereditaryNotesCtrl = TextEditingController();

    final houseNo = widget.family['house_number']?.toString() ?? widget.family['id']?.toString() ?? '105';
    final headName = widget.family['head_of_family_name']?.toString() ?? 'Family Head';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: const Color(0xFFFBF8F5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header Bar ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Color(0xFF32104E)),
                              onPressed: () => Navigator.pop(ctx),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Add member',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF32104E),
                              ),
                            ),
                          ],
                        ),
                        // Small Photo Attachment
                        GestureDetector(
                          onTap: () async {
                            final compressedBase64 = await ImageUtils.pickAndCompressImage(context);
                            if (compressedBase64 != null) {
                              setModalState(() => pickedImageBase64 = compressedBase64);
                            }
                          },
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.purple.shade50,
                            backgroundImage: ImageUtils.safeBase64Image(pickedImageBase64),
                            child: pickedImageBase64 == null
                                ? const Icon(Icons.add_a_photo_outlined, size: 16, color: Color(0xFF5B2C82))
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── House Banner ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F1FC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.home_outlined, color: Color(0xFF1976D2), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'House number $houseNo · $headName',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Name Input ──
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

                    // ── Gender Segmented Selection ──
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

                    // ── Age & Date of Birth Row ──
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Age (years)',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                            ),
                            onChanged: (val) {
                              final y = int.tryParse(val);
                              if (y != null && y > 0 && dobDate == null) {
                                // approximate dob year
                                setModalState(() {});
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
                                initialDate: dobDate ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
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

                    // ── Relationship to Head Dropdown ──
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

                    // ── Mobile Number ──
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Mobile number (optional)',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Aadhaar Input with Secure Caption ──
                    TextField(
                      controller: aadhaarCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Aadhaar (optional)',
                        prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF5B2C82), size: 20),
                        helperText: 'Only a secure hash and the last 4 digits are stored.',
                        helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── ABHA Health ID ──
                    TextField(
                      controller: abhaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'ABHA health ID (optional)',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF5B2C82), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Hereditary / Genetic Condition Toggle ──
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
                        title: const Text('Hereditary / genetic condition', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Sickle cell, thalassemia, haemophilia...', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        value: hasHereditary,
                        onChanged: (val) => setModalState(() => hasHereditary = val),
                      ),
                    ),
                    if (hasHereditary) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: hereditaryNotesCtrl,
                        decoration: InputDecoration(
                          hintText: 'Specify condition / details',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),

                    // ── Save Button ──
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
                        label: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter member name')),
                            );
                            return;
                          }
                          if (relCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select relationship to head')),
                            );
                            return;
                          }

                          final age = int.tryParse(ageCtrl.text) ?? (dobDate != null ? (DateTime.now().difference(dobDate!).inDays ~/ 365) : 0);

                          final ok = await LocalDbService.addMember(
                            widget.token,
                            widget.family['id'].toString(),
                            nameCtrl.text.trim(),
                            age,
                            gender,
                            relCtrl.text.trim(),
                            profileImage: pickedImageBase64,
                            abhaId: abhaCtrl.text.trim().isNotEmpty ? abhaCtrl.text.trim() : null,
                            mobileNumber: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                            isPregnant: false,
                            hasChronicCondition: hasHereditary,
                            chronicNotes: hereditaryNotesCtrl.text.trim().isNotEmpty ? hereditaryNotesCtrl.text.trim() : (hasHereditary ? 'Hereditary / Genetic condition flagged' : null),
                          );

                          if (!mounted || !context.mounted) return;
                          Navigator.pop(ctx);
                          if (ok && context.mounted) {
                            _refreshMembers();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Member added successfully'), backgroundColor: Color(0xFF5B2C82)),
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

  Color _flagColor(String? flag) {
    switch (flag) {
      case 'critical': return Colors.red;
      case 'warning': return Colors.orange;
      default: return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final headName = widget.family['family_head_name'] ?? 'Household';
    final houseNo = widget.family['house_number'] ?? 'N/A';
    final contact = widget.family['contact_number'] ?? 'N/A';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: Text(
          '${LanguageService.tr('family_details')} • $headName',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF004D40),
        foregroundColor: Colors.white,
        actions: const [
          LanguageSwitcherWidget(),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Household Hero Card ──
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF004D40), const Color(0xFF00796B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.teal.shade300.withAlpha(60),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.home_work_rounded, color: Colors.tealAccent, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${LanguageService.tr('house_number')}: $houseNo',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.phone_rounded, size: 12, color: Colors.tealAccent.shade100),
                          const SizedBox(width: 3),
                          Text(
                            contact,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Members Section Title ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_alt_rounded, size: 18, color: Color(0xFF00796B)),
                    const SizedBox(width: 6),
                    Text(
                      LanguageService.tr('members'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _showAddMemberDialog,
                  icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF00796B)),
                  label: Text(
                    LanguageService.tr('add_member'),
                    style: const TextStyle(color: Color(0xFF00796B), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          // ── Members List ──
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _membersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final members = snapshot.data ?? [];
                if (members.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_add_disabled_rounded, size: 54, color: Colors.teal.shade200),
                          const SizedBox(height: 12),
                          Text(
                            LanguageService.tr('no_members'),
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00796B),
                              minimumSize: const Size(160, 42),
                            ),
                            onPressed: _showAddMemberDialog,
                            icon: const Icon(Icons.add),
                            label: Text(LanguageService.tr('add_member')),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final flag = member['current_flag'] as String?;
                    final lastRecorded = member['last_recorded_at'] as String?;
                    final flagC = _flagColor(flag);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: flag == 'critical'
                              ? Colors.red.shade300
                              : (flag == 'warning' ? Colors.orange.shade300 : Colors.teal.shade50.withAlpha(200)),
                          width: flag == 'critical' || flag == 'warning' ? 1.6 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: flag == 'critical'
                                ? Colors.red.shade100.withAlpha(60)
                                : Colors.black.withAlpha(5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MemberDetailScreen(
                                member: member,
                                token: widget.token,
                              ),
                            ),
                          );
                          _refreshMembers();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Row(
                            children: [
                              // Avatar with Triage Color Border Ring
                              Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: flagC, width: 2),
                                ),
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.teal.shade50,
                                  backgroundImage: ImageUtils.safeBase64Image(member['profile_image']?.toString()),
                                  child: ImageUtils.safeBase64Image(member['profile_image']?.toString()) != null
                                      ? null
                                      : Icon(
                                          member['gender'] == 'male' ? Icons.male : (member['gender'] == 'female' ? Icons.female : Icons.person),
                                          color: Colors.teal.shade800,
                                          size: 24,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Info Column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            member['full_name'] ?? 'Member',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                                          ),
                                        ),
                                        if (flag != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: flagC.withAlpha(25),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: flagC.withAlpha(120)),
                                            ),
                                            child: Text(
                                              flag.toUpperCase(),
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: flagC),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${LanguageService.tr('age')}: ${member['age']} ${LanguageService.tr('years')} • ${member['gender']} • ${member['relationship_to_head']}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                    ),
                                    if (lastRecorded != null) ...[
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Icon(Icons.history_rounded, size: 12, color: Colors.grey.shade400),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${LanguageService.tr('recorded_at')}: ${_formatDate(lastRecorded)}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: const QwenChatFloatingButton(heroTag: 'family_qwen_chat_fab'),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
