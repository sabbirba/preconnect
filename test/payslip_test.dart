import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:preconnect/api/profile.dart';
import 'package:preconnect/tools/time_utils.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/payslips.json').readAsStringSync())
          as Map<String, dynamic>;
  final banks = (fixture['banks'] as List)
      .cast<Map<String, dynamic>>()
      .map(BankConfig.fromJson)
      .toList();
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  for (final (index, sample) in cases.indexed) {
    test('payslip ${index + 1} prints exactly what Connect prints', () {
      final detail = PayslipDetail.fromJson(
        sample['detail'] as Map<String, dynamic>,
      );
      expect(
        jsonDecode(jsonEncode(detail.printData(banks))),
        sample['connectPrintData'],
      );
    });
  }

  test('deadlines at Bangladesh midnight keep their own day', () {
    expect(
      AppTime.formatCampusTime('2026-10-14T00:00+0600', 'd MMMM y'),
      '14 October 2026',
    );
    expect(
      AppTime.formatCampusTime('2026-10-13T18:00:00.000Z', 'd MMMM, y'),
      '14 October, 2026',
    );
  });

  test('payment cards read installment details', () {
    final payment = PaymentInfo.fromJson({
      'paymentStatus': 'PAID',
      'payslipNumber': '900000001',
      'paymentType': 'REGISTRATION_FEE',
      'dueDate': '2026-10-13T18:00:00.000Z',
      'installmentEnabled': true,
      'installmentNumber': 2,
    });
    expect(payment.installmentEnabled, isTrue);
    expect(payment.installmentNumber, 2);
    expect(PaymentInfo.fromJson(payment.toJson()).installmentNumber, 2);
  });
}
