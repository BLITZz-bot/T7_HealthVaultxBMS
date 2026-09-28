import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/language_service.dart';
import '../services/blockchain_service.dart';

class QrScreen extends StatelessWidget {
  final Map<String, dynamic> member;
  final String familySalt;

  const QrScreen({Key? key, required this.member, required this.familySalt}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String memberId = member['id'].toString();
    final String commitment = BlockchainService.beneficiaryCommitment(memberId, familySalt);
    
    // The data to encode in QR.
    // e.g. healthvault://verify?patient=commitment
    final String qrData = "healthvault://verify?patient=$commitment";

    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF32104E)),
        title: Text(
          LanguageService.tr('patient_qr') ?? 'Patient QR',
          style: const TextStyle(color: Color(0xFF32104E), fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              member['full_name']?.toString() ?? 'Patient',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF32104E)),
            ),
            const SizedBox(height: 10),
            Text(
              "ABHA: ${member['abha_id'] ?? 'N/A'}",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 250.0,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF32104E),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF32104E),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Show this QR code to the Hospital Verifier or Admin to authorize access to your health records.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
