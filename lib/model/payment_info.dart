class PaymentInfo {
  final String paymentStatus;
  final String payslipNumber;
  final String paymentType;
  final DateTime requestDate;
  final DateTime dueDate;
  final double totalAmount;
  final int semesterSessionId;

  PaymentInfo({
    required this.paymentStatus,
    required this.payslipNumber,
    required this.paymentType,
    required this.requestDate,
    required this.dueDate,
    required this.totalAmount,
    required this.semesterSessionId,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      paymentStatus: json['paymentStatus'],
      payslipNumber: json['payslipNumber'],
      paymentType: json['paymentType'],
      requestDate: DateTime.parse(json['requestDate']),
      dueDate: DateTime.parse(json['dueDate']),
      totalAmount: json['totalAmount'].toDouble(),
      semesterSessionId: json['semesterSessionId'],
    );
  }
}
