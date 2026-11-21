/// Why a relay URL was rejected.
enum RelayUrlProblem {
  /// Nothing was entered.
  empty,

  /// Not an origin URL (bad scheme/host/port, userinfo, path, query, fragment).
  invalid,

  /// Plain HTTP to a non-loopback host.
  insecure,
}

/// Transport and identity policy for the Push Relay.
///
/// One relay is supported per **origin**: `scheme://host[:port]` with no path,
/// query, fragment or userinfo. HTTPS is mandatory except for loopback labs.
/// A trailing `/` is accepted and normalized away, so `https://r.example.com`
/// and `https://r.example.com/` are the same relay (and the same Keychain
/// reference). Explicit default ports are normalized away too.
class RelayUrlPolicy {
  const RelayUrlPolicy._();

  static final _octet = RegExp(r'^(0|[1-9]\d{0,2})$');
  static final _origin =
      RegExp(r'^(https?)://([^/?#@\s]+)/?$', caseSensitive: false);

  static bool isLoopbackHost(String host) =>
      host == 'localhost' || host == '::1' || _isIpv4Loopback(host);

  /// Strict 127.0.0.0/8: exactly four decimal octets, each 0-255 without
  /// leading zeros (so `127.999.999.999`, `127.0.0`, `127.0.0.1.2` and
  /// `127.00.0.1` are not loopback), first octet 127.
  static bool _isIpv4Loopback(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      if (!_octet.hasMatch(part)) return false;
      final value = int.parse(part);
      if (value > 255) return false;
      octets.add(value);
    }
    return octets.first == 127;
  }

  /// Returns the reason [raw] is unacceptable, or null when it is a valid origin.
  static RelayUrlProblem? problem(String raw) {
    final analysis = _analyze(raw);
    return analysis.$2;
  }

  /// Normalized origin string (`https://host[:port]`), or null if unacceptable.
  static String? normalize(String raw) => _analyze(raw).$1;

  /// Normalized origin as a [Uri] (empty path), or null if unacceptable.
  static Uri? parse(String raw) {
    final origin = normalize(raw);
    return origin == null ? null : Uri.parse(origin);
  }

  static bool isAllowed(String raw) => normalize(raw) != null;

  /// Builds an endpoint under the relay origin, or null if the URL is not allowed.
  static Uri? endpoint(String relayUrl, String path) {
    final origin = normalize(relayUrl);
    return origin == null ? null : Uri.parse('$origin$path');
  }

  static (String?, RelayUrlProblem?) _analyze(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return (null, RelayUrlProblem.empty);
    final match = _origin.firstMatch(text);
    if (match == null) return (null, RelayUrlProblem.invalid);
    final authority = match.group(2)!;
    // `host:` with an empty port, or a bare `:port`.
    if (authority.endsWith(':') || authority.startsWith(':')) {
      return (null, RelayUrlProblem.invalid);
    }
    final Uri uri;
    try {
      uri = Uri.parse('${match.group(1)!.toLowerCase()}://$authority');
    } on FormatException {
      return (null, RelayUrlProblem.invalid);
    }
    if (uri.host.isEmpty) return (null, RelayUrlProblem.invalid);
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return (null, RelayUrlProblem.invalid);
    }
    final https = uri.scheme == 'https';
    if (!https && !isLoopbackHost(uri.host)) {
      return (null, RelayUrlProblem.insecure);
    }
    final defaultPort = https ? 443 : 80;
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
    return ('${uri.scheme}://$host$port', null);
  }
}
