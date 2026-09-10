import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter_flip_card/flutter_flip_card.dart';
import 'package:preconnect/pages/shared_widgets/bracu_logo.dart';
import 'package:preconnect/tools/cached_image.dart';

class LibraryCard extends StatelessWidget {
  const LibraryCard({super.key, required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureFlipCard(
        animationDuration: const Duration(milliseconds: 300),
        axis: FlipAxis.vertical,
        frontWidget: _LibraryCardFront(
          profile: profile,
          photoWidth: constraints.maxWidth < 450
              ? constraints.maxWidth * 0.20
              : 90,
        ),
        backWidget: _LibraryCardBack(profile: profile),
      ),
    );
  }
}

class _LibraryCardFront extends StatelessWidget {
  const _LibraryCardFront({required this.profile, required this.photoWidth});
  final Map<String, dynamic> profile;
  final double photoWidth;

  @override
  Widget build(BuildContext context) {
    final displayName = (profile['fullname'] ?? '').toString();
    final displayProgram = (profile['department'] ?? '').toString();
    final displayStudentId = (profile['student_id'] ?? '').toString();
    final photoUrl = (profile['profile_image'] ?? '').toString();
    final expireDate = (profile['expire_date'] ?? '').toString();

    return Center(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(14, 75, 117, 0.08),
              offset: Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  const BracuLogo(width: 34, height: 34),
                  const Gap(8),
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Ayesha Abed Library',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 17,
                          color: Color(0xFF0E4B75),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              color: Color(0xFFE2E8F0),
              thickness: 1.0,
              height: 0,
              indent: 0,
            ),
            IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0xFF0E4B75)),
                    child: const RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'LIBSYNC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Opacity(
                            opacity: 0.03,
                            child: BracuLogo(width: 136, height: 136),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Gap(5),
                                    Text(
                                      displayProgram,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Gap(8),
                                    Table(
                                      columnWidths: const {
                                        0: FixedColumnWidth(74),
                                        1: IntrinsicColumnWidth(),
                                        2: FlexColumnWidth(),
                                      },
                                      defaultVerticalAlignment:
                                          TableCellVerticalAlignment.top,
                                      children: [
                                        for (final detail in [
                                          ('Student ID', displayStudentId),
                                          ('Validity', expireDate),
                                        ])
                                          TableRow(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 5,
                                                ),
                                                child: Text(
                                                  detail.$1,
                                                  style: const TextStyle(
                                                    color: Color(0xFF64748B),
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: Text(
                                                  ':',
                                                  style: TextStyle(
                                                    color: Color(0xFF64748B),
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                detail.$2,
                                                style: const TextStyle(
                                                  color: Color(0xFF1E293B),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(12),
                              SizedBox(
                                width: photoWidth,
                                height: photoWidth * 106 / 90,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: photoUrl.isEmpty
                                      ? const SizedBox.expand()
                                      : CachedImage(
                                          url: photoUrl,
                                          width: photoWidth,
                                          height: photoWidth * 106 / 90,
                                          fit: BoxFit.cover,
                                          alignment: Alignment.center,
                                          placeholder: const ColoredBox(
                                            color: Colors.white,
                                          ),
                                          error: const SizedBox.expand(),
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
      ),
    );
  }
}

class _LibraryCardBack extends StatelessWidget {
  const _LibraryCardBack({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final displayStudentId = (profile['student_id'] ?? '').toString();

    return Center(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black),
          color: const Color(0xFF0E4B75),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(14, 75, 117, 0.12),
              offset: Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Opacity(
              opacity: 0.08,
              child: BracuLogo(width: 150, height: 130),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ayesha Abed Library Unauthorized Virtual Card.\nFor Library Libsync booking verification & access.',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Gap(6),
                  const Text(
                    'BRAC University Library\n'
                    'Kha 224 Bir Uttam Rafiqul Islam Ave,\n'
                    'Merul Badda, Dhaka 1212, Bangladesh',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 7,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(5),
                  const Text(
                    'Tel : +8809638464646 ext. 1653',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: displayStudentId,
                          width: 100,
                          height: 10,
                          drawText: false,
                          color: Colors.black,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Row(
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          displayStudentId,
                          style: const TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  Container(width: 80, height: 1, color: Colors.white30),
                  const Gap(2),
                  const Text(
                    'Authorized Signature',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
