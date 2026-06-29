import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';

const String _bracuLogoUrl =
    'https://www.bracu.ac.bd/sites/default/files/resources/media/bracu_logo_12-0-2022.png';

class CardSection extends StatelessWidget {
  const CardSection({super.key, required this.profile, required this.photoUrl});

  final Map<String, String?>? profile;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile ?? {};
    final fullName = (profile['fullName'] ?? '').trim();
    final degreeName = (profile['program'] ?? '').trim();
    final studentId = (profile['studentId'] ?? '').trim();
    final enrolledSession = int.tryParse(
      (profile['enrolledSessionSemesterId'] ?? '').trim(),
    );
    final validation = enrolledSession == null
        ? ''
        : '31-12-${(enrolledSession ~/ 10) + 5}';
    final bloodGroup = (profile['bloodGroup'] ?? '').trim();
    final photoUrl = this.photoUrl;
    final displayName = fullName.isNotEmpty ? fullName : 'BRACU Student';
    final displayProgram = degreeName.isNotEmpty ? degreeName : '';
    final displayStudentId = studentId.isNotEmpty ? studentId : '';
    final displayBloodGroup = bloodGroup.isNotEmpty ? bloodGroup : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _FlipCard(
          front: _CardFront(
            displayName: displayName,
            displayProgram: displayProgram,
            displayStudentId: displayStudentId,
            displayBloodGroup: displayBloodGroup,
            validation: validation,
            photoUrl: photoUrl,
          ),
          back: _CardBack(displayStudentId: displayStudentId),
        ),
      ],
    );
  }
}

class _FlipCard extends StatefulWidget {
  const _FlipCard({required this.front, required this.back});

  final Widget front;
  final Widget back;

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  bool _showFront = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.isAnimating) return;
    setState(() => _showFront = !_showFront);
    if (_showFront) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _turn,
        builder: (context, child) {
          final angle = _turn.value * math.pi;
          final showingBack = angle > math.pi / 2;
          final visibleAngle = showingBack ? angle - math.pi : angle;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(visibleAngle),
            child: showingBack ? widget.back : widget.front,
          );
        },
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.displayName,
    required this.displayProgram,
    required this.displayStudentId,
    required this.displayBloodGroup,
    required this.validation,
    required this.photoUrl,
  });

  final String displayName;
  final String displayProgram;
  final String displayStudentId;
  final String displayBloodGroup;
  final String validation;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
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
                  const _BracuLogo(width: 34, height: 34),
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
                      color: Colors.transparent,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                    child: const RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'STUDENT',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          letterSpacing: 1.4,
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
                          const Opacity(
                            opacity: 0.06,
                            child: _BracuLogo(width: 136, height: 136),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      displayProgram,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _InfoRow(
                                      label: 'Student ID',
                                      value: displayStudentId,
                                      enableCopy: false,
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
                                  child: photoUrl == null || photoUrl!.isEmpty
                                      ? const SizedBox.expand()
                                      : CachedImage(
                                          url: photoUrl!,
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

class _CardBack extends StatelessWidget {
  const _CardBack({required this.displayStudentId});

  final String displayStudentId;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          const Opacity(
            opacity: 0.1,
            child: _BracuLogo(width: 150, height: 130),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(48, 24, 2, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unauthorized Virtual ID card of BRACU.\nDo not accept this card as a valid ID card.',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Contact:',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'BRAC University\n'
                  'Kha 224 Bir Uttam Rafiqul Islam Ave,\n'
                  'Merul Badda, Dhaka 1212, Bangladesh',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Tel : +8809638464646 ext. 1653',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                InkWell(
                  onTap: () => openMailComposer(context, 'idcard@bracu.ac.bd'),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Email : idcard@bracu.ac.bd',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(flex: 4, child: Text('')),
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
                Container(width: 80, height: 1, color: const Color(0xFF1E1E1E)),
                const Text(
                  'Authorized Signature',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.enableCopy = false,
  });

  final String label;
  final String value;
  final bool enableCopy;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 9,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        SizedBox(width: 74, child: Text(label, style: textStyle)),
        const Text(':', style: textStyle),
        const SizedBox(width: 8),
        Expanded(
          child: enableCopy
              ? GestureDetector(
                  onTap: () => copyToClipboard(context, value),
                  child: Text(value, style: textStyle),
                )
              : Text(value, style: textStyle),
        ),
      ],
    );
  }
}

class _BracuLogo extends StatelessWidget {
  const _BracuLogo({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CachedImage(
      url: _bracuLogoUrl,
      width: width,
      height: height,
      fit: BoxFit.contain,
      error: const SizedBox.shrink(),
      placeholder: const SizedBox.shrink(),
    );
  }
}
