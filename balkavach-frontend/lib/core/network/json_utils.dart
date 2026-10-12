/// Parses a JSON array of objects returned by a list endpoint.
List<T> parseJsonList<T>(
  List<dynamic>? data,
  T Function(Map<String, dynamic>) parse,
) => (data ?? const []).cast<Map<String, dynamic>>().map(parse).toList();
