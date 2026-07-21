class Url {
  final String value;
  final Uri _uri;

  Url._(this.value) : _uri = Uri.parse(value);

  static Url? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }
    return Url._(trimmed);
  }

  factory Url(String input) {
    final result = tryParse(input);
    if (result == null) {
      throw ArgumentError('Invalid URL: "$input". Must be a valid http or https URL.');
    }
    return result;
  }

  String get scheme => _uri.scheme;
  String get host => _uri.host;
  String get path => _uri.path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Url && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Url($value)';
}
