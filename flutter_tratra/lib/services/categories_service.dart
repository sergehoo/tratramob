// lib/services/category_service.dart
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/category.dart';

class CategoryService extends BaseApi {
  CategoryService({super.client});

  Future<List<Category>> list({int page = 1}) async {
    final uri = Uri.parse('$baseUrl/categories/').replace(queryParameters: {
      'page': page.toString(),
    });
    final r = await client.get(uri, headers: await headers);
    if (r.statusCode != 200) handleError(r);
    final decoded = decodeBody(r);
    final list = extractResults(decoded);
    return list.map((e) => Category.fromJson(e)).toList();
  }
}
