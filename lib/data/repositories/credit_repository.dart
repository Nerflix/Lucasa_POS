import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer.dart';

class CreditRepository {
  final SupabaseClient _client;

  CreditRepository(this._client);

  Future<List<Credit>> getCreditsByLocation(
    String locationId,
    String category,
  ) async {
    final response = await _client
        .from('credits')
        .select('*, customers(*)')
        .eq('location_id', locationId)
        .eq('category', category)
        .order('created_at', ascending: false);

    return (response as List).map((json) => Credit.fromJson(json)).toList();
  }

  Future<List<Credit>> getCreditsByCustomer(String customerId) async {
    final response = await _client
        .from('credits')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);

    return (response as List).map((json) => Credit.fromJson(json)).toList();
  }

  Future<Credit?> getCredit(String id) async {
    final response = await _client
        .from('credits')
        .select('*, customers(*)')
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return Credit.fromJson(response);
  }

  Future<void> insertCredit(Credit credit) async {
    await _client.from('credits').insert(credit.toJson());
  }

  Future<void> updateCredit(Credit credit) async {
    await _client.from('credits').update(credit.toJson()).eq('id', credit.id);
  }

  Future<List<Credit>> getCreditsByCustomerAndCategory(
    String customerId,
    String category,
  ) async {
    final response = await _client
        .from('credits')
        .select()
        .eq('customer_id', customerId)
        .eq('category', category)
        .order('created_at', ascending: false);

    return (response as List).map((json) => Credit.fromJson(json)).toList();
  }

  Future<List<CreditPayment>> getPaymentsByCreditIds(
    List<String> creditIds,
  ) async {
    if (creditIds.isEmpty) return [];

    final response = await _client
        .from('credit_payments')
        .select()
        .filter('credit_id', 'in', creditIds)
        .order('paid_at', ascending: false);

    return (response as List)
        .map((json) => CreditPayment.fromJson(json))
        .toList();
  }

  Future<void> insertPayment(CreditPayment payment) async {
    await _client.from('credit_payments').insert(payment.toJson());
  }

  Future<void> applyPayment({
    required String customerId,
    required String category,
    required double amount,
  }) async {
    // 1. Get all outstanding credits for this customer and category
    final response = await _client
        .from('credits')
        .select()
        .eq('customer_id', customerId)
        .eq('category', category)
        .gt('balance', 0)
        .order('created_at', ascending: true);

    final credits = (response as List)
        .map((json) => Credit.fromJson(json))
        .toList();
    if (credits.isEmpty) return;

    double remaining = amount;
    final now = DateTime.now();

    for (final credit in credits) {
      if (remaining <= 0) break;

      final applied = remaining >= credit.balance ? credit.balance : remaining;

      // 2. Update the credit record
      await _client
          .from('credits')
          .update({
            'amount_paid': credit.amountPaid + applied,
            'balance': credit.balance - applied,
            'last_payment_at': now.toIso8601String(),
          })
          .eq('id', credit.id);

      // 3. Create a payment record
      await _client.from('credit_payments').insert({
        'id':
            'pay_${DateTime.now().millisecondsSinceEpoch}_${credit.id.substring(0, 4)}',
        'credit_id': credit.id,
        'amount': applied,
        'paid_at': now.toIso8601String(),
      });

      remaining -= applied;
    }
  }
}
