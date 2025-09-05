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
  final int? orderIndex; // 0-based ordering across visible categories
  final String? iconKey; // material icon key from a curated set

  const ContractGroup({
    required this.id,
    required this.name,
    this.builtIn = false,
    this.orderIndex,
    this.iconKey,
  });

  IconData get icon {
    final icon = _iconForKey(iconKey);
    if (icon != null) return icon;
    // Fallback heuristic if no explicit icon selected
    final n = name.toLowerCase();
    if (n.contains('home')) return Icons.home_outlined;
    if (n.contains('sub')) return Icons.movie_outlined;
    return Icons.category_outlined;
  }
}

// Minimal curated icon map; UI picker references these keys
const Map<String, IconData> kCategoryIconMap = {
  'home': Icons.home_outlined,
  'house': Icons.house_outlined,
  'utilities': Icons.lightbulb_outline,
  'internet': Icons.wifi_outlined,
  'phone': Icons.phone_iphone,
  'tv': Icons.tv_outlined,
  'streaming': Icons.movie_outlined,
  'music': Icons.music_note_outlined,
  'gaming': Icons.sports_esports_outlined,
  'insurance': Icons.health_and_safety_outlined,
  'medical': Icons.medical_services_outlined,
  'fitness': Icons.fitness_center_outlined,
  'education': Icons.school_outlined,
  'car': Icons.directions_car_outlined,
  'travel': Icons.flight_takeoff_outlined,
  'hotel': Icons.hotel_outlined,
  'food': Icons.restaurant_outlined,
  'groceries': Icons.local_grocery_store_outlined,
  'pets': Icons.pets_outlined,
  'kids': Icons.child_friendly_outlined,
  'gift': Icons.card_giftcard_outlined,
  'bank': Icons.account_balance_outlined,
  'loan': Icons.account_balance_wallet_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'tools': Icons.build_outlined,
  'subscription': Icons.subscriptions_outlined,
  'security': Icons.vpn_key_outlined,
  'cloud': Icons.cloud_outlined,
  'other': Icons.category_outlined,
};

IconData? _iconForKey(String? key) => key == null ? null : kCategoryIconMap[key];

class Contract {
  final String id;
  final String title;
  final String provider;
  final String? customerNumber;
  final String categoryId;

  final double? costAmount;
  final String costCurrency;
  final BillingCycle? billingCycle;

  final PaymentMethod? paymentMethod;
  final String? paymentNote;

  final DateTime? startDate;
  final DateTime? endDate;
  final bool isOpenEnded;
  final bool isActive;
  final bool isDeleted;
  final String? notes;
  final DateTime? deletedAt;

  const Contract({
    required this.id,
    required this.title,
    required this.provider,
    this.customerNumber,
    required this.categoryId,
    this.costAmount,
    this.costCurrency = '€',
    this.billingCycle,
    this.paymentMethod,
    this.paymentNote,
    this.startDate,
    this.endDate,
    this.isOpenEnded = false,
    this.isActive = true,
    this.isDeleted = false,
    this.notes,
    this.deletedAt,
  });

  bool get isExpired =>
      !isOpenEnded && endDate != null && endDate!.isBefore(DateTime.now());

  Contract copyWith({
    String? title,
    String? provider,
    String? customerNumber,
    String? categoryId,
    double? costAmount,
    String? costCurrency,
    BillingCycle? billingCycle,
    PaymentMethod? paymentMethod,
    String? paymentNote,
    DateTime? startDate,
    DateTime? endDate,
    bool? isOpenEnded,
    bool? isActive,
    bool? isDeleted,
    String? notes,
    DateTime? deletedAt,
  }) {
    return Contract(
      id: id,
      title: title ?? this.title,
      provider: provider ?? this.provider,
      customerNumber: customerNumber ?? this.customerNumber,
      categoryId: categoryId ?? this.categoryId,
      costAmount: costAmount ?? this.costAmount,
      costCurrency: costCurrency ?? this.costCurrency,
      billingCycle: billingCycle ?? this.billingCycle,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentNote: paymentNote ?? this.paymentNote,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isOpenEnded: isOpenEnded ?? this.isOpenEnded,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
      notes: notes ?? this.notes,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
