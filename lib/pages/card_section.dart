import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter_flip_card/flutter_flip_card.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CardSection extends StatefulWidget {
  const CardSection({super.key, required this.profile, required this.photoUrl});

  final Map<String, String?>? profile;
  final String? photoUrl;

  @override
  CardSectionState createState() => CardSectionState();
}

class CardSectionState extends State<CardSection> {
  final cong = GestureFlipCardController();

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile ?? {};
    final fullName = (profile['fullName'] ?? '').trim();
    final degreeName = (profile['program'] ?? '').trim();
    final studentId = (profile['studentId'] ?? '').trim();
    final enrolledSession =
        int.tryParse((profile['enrolledSessionSemesterId'] ?? '').trim());
    final validation = enrolledSession == null
        ? 'N/A'
        : '31-12-${(enrolledSession ~/ 10) + 5}';
    final bloodGroup = (profile['bloodGroup'] ?? '').trim();
    final photoUrl = widget.photoUrl;
    final displayName = fullName.isNotEmpty ? fullName : 'BRACU Student';
    final displayProgram = degreeName.isNotEmpty ? degreeName : 'N/A';
    final displayStudentId = studentId.isNotEmpty ? studentId : 'N/A';
    final displayBloodGroup = bloodGroup.isNotEmpty ? bloodGroup : '--';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        GestureFlipCard(
          enableController: true,
          controller: cong,
          animationDuration: const Duration(milliseconds: 300),
          axis: FlipAxis.vertical,
          frontWidget: Center(
              child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.18),
                  offset: Offset(0, 4),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/bracu.svg',
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'BRAC University',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 21,
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  color: Colors.black,
                  thickness: 0.9,
                  height: 0,
                  indent: 0,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 138),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF2F4),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                            ),
                          ),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            "STUDENT",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              letterSpacing: 1.4,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: const BoxDecoration(
                            color: Color(0xFF7BB3D3),
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(16),
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 0.06,
                                child: SvgPicture.asset(
                                  "assets/bracu.svg",
                                  height: 120,
                                  width: 120,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          displayName,
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 14,
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          displayProgram,
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 9,
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _InfoRow(
                                          label: 'Student ID',
                                          value: displayStudentId,
                                        ),
                                        const SizedBox(height: 5),
                                        _InfoRow(
                                          label: 'Blood Group',
                                          value: displayBloodGroup,
                                        ),
                                        const SizedBox(height: 5),
                                        _InfoRow(
                                          label: 'Validity',
                                          value: validation,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 90,
                                    height: 106,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: photoUrl == null || photoUrl.isEmpty
                                          ? const SizedBox.expand()
                                          : Image.network(
                                              photoUrl,
                                              fit: BoxFit.cover,
                                              alignment: Alignment.center,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                return const SizedBox.expand();
                                              },
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )),
          backWidget: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black),
              color: const Color(0xFF67ADD8),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.25),
                  offset: Offset(0, 4),
                  blurRadius: 4,
                ),
              ],
            ),
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0.1,
                  child: SvgPicture.asset(
                    "assets/bracu.svg",
                    height: 120,
                    width: 140,
                    fit: BoxFit.contain,
                  ),
                ),

                Container(
                  padding: const EdgeInsets.fromLTRB(
                      48, 24, 2, 12),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Unauthorized ID card of BRACU. Generated by PreConnect App.',
                        style: TextStyle(
                          fontSize: 8,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Do not accept this card as a valid ID without the original physical card.',
                        style: TextStyle(
                          fontSize: 8,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Contact:',
                        style: TextStyle(
                          fontSize: 8,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'BRAC University\n'
                        'Kha 224 Bir Uttam Rafiqul Islam Ave,\n'
                        'Merul Badda, Dhaka 1212, Bangladesh',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 7,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Tel : +8809638464646 ext. 1653\n'
                        'Email : idcard@bracu.ac.bd',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(flex: 4, child: Text('')),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: BarcodeWidget(
                              barcode: Barcode.code128(),
                              data: displayStudentId,
                              width: 100,
                              height: 10,
                              drawText: false,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 80,
                        height: 1,
                        color: const Color(0xFF1E1E1E),
                      ),
                      const Text(
                        'Authorized Signature',
                        style: TextStyle(
                          fontSize: 7,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 9,
      fontFamily: 'Poppins',
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: textStyle,
          ),
        ),
        const Text(':', style: textStyle),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
