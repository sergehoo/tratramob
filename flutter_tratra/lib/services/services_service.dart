import 'package:http/http.dart' as http;
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/service.dart';

class ServiceService {
  final BaseApi api;

  ServiceService(this.api);

  Future<List<Service>> getServices({
    String? search,
    int? categoryId,
    int page = 1,
  }) async {
    final headers = await api.headers;
    final params = <String, String>{'page': '$page'};

    if (search != null && search.isNotEmpty) params['search'] = search;
    if (categoryId != null) params['category'] = categoryId.toString();

    final uri =
        Uri.parse('${api.baseUrl}/services/').replace(queryParameters: params);
    final r = await api.client.get(uri, headers: headers);

    if (r.statusCode != 200) api.handleError(r);

    final decoded = api.decodeBody(r);
    final list = api.extractResults(decoded);
    return list.map((e) => Service.fromJson(e)).toList();
  }

  Future<List<Service>> getNearbyServices({
    required double lat,
    required double lng,
    double radiusKm = 15,
    int? categoryId,
  }) async {
    final headers = await api.headers;
    final params = <String, String>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius_km': radiusKm.toString(),
    };

    if (categoryId != null) params['category_id'] = categoryId.toString();

    final uri = Uri.parse('${api.baseUrl}/services/nearby/')
        .replace(queryParameters: params);
    final r = await api.client.get(uri, headers: headers);

    if (r.statusCode != 200) api.handleError(r);

    final decoded = api.decodeBody(r);
    final list = api.extractResults(decoded);
    return list.map((e) => Service.fromJson(e)).toList();
  }

  Future<Service> getServiceDetail(String id) async {
    final headers = await api.headers;
    final r = await api.client.get(
      Uri.parse('${api.baseUrl}/services/$id/'),
      headers: headers,
    );
    if (r.statusCode != 200) api.handleError(r);
    return Service.fromJson(api.decodeBody(r));
  }
}
