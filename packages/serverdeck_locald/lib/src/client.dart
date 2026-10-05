import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

final class LocalApiClient {
  LocalApiClient({
    required this.port,
    required this.proof,
    this.timeout = const Duration(seconds: 5),
  }) {
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = timeout;
  }
  final int port;
  final String proof;
  final Duration timeout;
  final HttpClient _http = HttpClient();
  void close() => _http.close(force: true);
  Future<dynamic> call(String operation, [JsonMap body = const {}]) async {
    try {
      return await (() async {
        final request = await _http.postUrl(
          Uri(
            scheme: 'http',
            host: '127.0.0.1',
            port: port,
            path: '/v1/$operation',
          ),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $proof');
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const LocalApiException('ResponseTooLarge');
          }
        }
        final result = jsonDecode(utf8.decode(bytes)) as JsonMap;
        if (response.statusCode != 200) {
          throw LocalApiException(
            result['error'] as String? ?? 'ServiceFailure',
          );
        }
        return result['data'];
      })().timeout(timeout);
    } on LocalApiException {
      rethrow;
    } catch (_) {
      throw const LocalApiException('ServiceUnavailable');
    }
  }

  Future<void> health() async {
    final data = await call('health') as JsonMap;
    if (data['apiVersion'] != localApiVersion ||
        data['service'] != 'serverdeck') {
      throw const LocalApiException('IncompatibleService');
    }
  }

  Future<List<JsonMap>> profiles() async =>
      (await call('profiles/list') as List).cast<JsonMap>();
  Future<void> initializeProfiles(List<JsonMap> seeds) async {
    await call('profiles/initialize', {'profiles': seeds});
  }

  Future<void> saveProfile(JsonMap profile) async {
    await call('profiles/save', {'profile': profile});
  }

  Future<void> removeProfile(String id) async {
    await call('profiles/remove', {'id': id});
  }
}
