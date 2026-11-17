import 'package:supabase_flutter/supabase_flutter.dart';

class ReportsRepository {
  final SupabaseClient _client;

  ReportsRepository(this._client);

  /// Fetch sales statistics for a given period
  Future<Map<String, dynamic>> getSalesStats({
    required List<String> locationIds,
    required String category,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _client
        .from('sales')
        .select('total_amount, profit, payment_method')
        .inFilter('location_id', locationIds)
        .eq('category', category)
        .gte('timestamp', startDate.toIso8601String())
        .lte('timestamp', endDate.toIso8601String());

    final sales = response as List;
    double totalSales = 0;
    double totalProfit = 0;
    Map<String, double> paymentMethods = {};

    for (final sale in sales) {
      final amount = (sale['total_amount'] as num).toDouble();
      final profit = (sale['profit'] as num).toDouble();
      final method = sale['payment_method'] as String;

      totalSales += amount;
      totalProfit += profit;
      paymentMethods[method] = (paymentMethods[method] ?? 0) + amount;
    }

    return {
      'totalSales': totalSales,
      'totalProfit': totalProfit,
      'paymentMethods': paymentMethods,
      'count': sales.length,
    };
  }

  /// Get daily sales for chart
  Future<List<Map<String, dynamic>>> getDailySales({
    required List<String> locationIds,
    required String category,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // This is better done with a Group By in SQL/RPC
    // For now, simple client-side grouping
    final response = await _client
        .from('sales')
        .select('total_amount, timestamp')
        .inFilter('location_id', locationIds)
        .eq('category', category)
        .gte('timestamp', startDate.toIso8601String())
        .lte('timestamp', endDate.toIso8601String());

    final sales = response as List;
    Map<String, double> dailyData = {};

    for (final sale in sales) {
      final date = (sale['timestamp'] as String).substring(0, 10);
      final amount = (sale['total_amount'] as num).toDouble();
      dailyData[date] = (dailyData[date] ?? 0) + amount;
    }

    return dailyData.entries
        .map((e) => {'date': e.key, 'amount': e.value})
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }
}
