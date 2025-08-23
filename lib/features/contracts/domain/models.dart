import 'package:flutter/material.dart';

enum BillingCycle { monthly, quarterly, yearly, oneTime }
extension BillingCycleLabel on BillingCycle {
  String get label => switch (this) {
        BillingCycle.monthly => 'Monthly',
        BillingCycle.quarterly => 'Quarterly',
        BillingCycle.yearly => 'Yearly',
        BillingCycle.oneTime => 'One-time',
      };
}

enum PaymentMethod { sepa, paypal, creditCard, bankTransfer, other }
extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.sepa => 'SEPA Direct Debit',
        PaymentMethod.paypal => 'PayPal',
        PaymentMethod.creditCard => 'Credit Card (Visa/Mastercard)',
        PaymentMethod.bankTransfer => 'Bank Transfer',
        PaymentMethod.other => 'Other',
      };
  IconData get icon => switch (this) {
        PaymentMethod.sepa => Icons.account_balance_outlined,
        PaymentMethod.paypal => Icons.account_balance_wallet_outlined,
        PaymentMethod.creditCard => Icons.credit_card_outlined,
        PaymentMethod.bankTransfer => Icons.swap_horiz_outlined,
        PaymentMethod.other => Icons.payments_outlined,
      };
}

class ContractGroup {
  final String id;
  final String name;
  final bool builtIn;

  const ContractGroup({required this.id, required this.name, this.builtIn = false});

  IconData get icon {
    final n = name.toLowerCase();
    if (n.contains('home')) return Icons.home_outlined;
    if (n.contains('sub')) return Icons.movie_outlined;
    return Icons.category_outlined;
  }
}

class Contract {
  final String id;
  final String title;
  final String provider;
  final String categoryId;

  final double? costAmount;
  final String costCurrency;
  final BillingCycle? billingCycle;

  final PaymentMethod? paymentMethod;
  final String? paymentNote;

  final DateTime? startDate;
  final DateTime? endDate;
  final bool isOpenEnded;

  const Contract({
    required this.id,
    required this.title,
    required this.provider,
    required this.categoryId,
    this.costAmount,
    this.costCurrency = '€',
    this.billingCycle,
    this.paymentMethod,
    this.paymentNote,
    this.startDate,
    this.endDate,
    this.isOpenEnded = false,
  });

  bool get isExpired =>
      !isOpenEnded && endDate != null && endDate!.isBefore(DateTime.now());

  Contract copyWith({
    String? title,
    String? provider,
    String? categoryId,
    double? costAmount,
    String? costCurrency,
    BillingCycle? billingCycle,
    PaymentMethod? paymentMethod,
    String? paymentNote,
    DateTime? startDate,
    DateTime? endDate,
    bool? isOpenEnded,
  }) {
    return Contract(
      id: id,
      title: title ?? this.title,
      provider: provider ?? this.provider,
      categoryId: categoryId ?? this.categoryId,
      costAmount: costAmount ?? this.costAmount,
      costCurrency: costCurrency ?? this.costCurrency,
      billingCycle: billingCycle ?? this.billingCycle,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentNote: paymentNote ?? this.paymentNote,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isOpenEnded: isOpenEnded ?? this.isOpenEnded,
    );
  }
}
