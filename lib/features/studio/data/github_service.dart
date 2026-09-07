import 'dart:convert';

import 'package:http/http.dart' as http;

/// A repository search hit returned by the GitHub REST API.
class GitHubRepo {
  final String owner;
  final String name;
  final String? description;
  final String cloneUrl;
  final int stars;

  const GitHubRepo({
    required this.owner,
    required this.name,
    this.description,
    required this.cloneUrl,
    required this.stars,
  });
}

/// Minimal GitHub REST integration for the Code Studio IDE.
///
/// Uses a personal access token (in [IdeSettings]) for authenticated
/// requests: verify the token, search repositories and resolve clones.
/// Clone itself is performed through the `git` CLI (see [cloneUrl]).
class GitHubService {
  final String? token;

  GitHubService([this.token]);

  Map<String, String> _headers() => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

  /// Verifies the token against the authenticated user endpoint.
  /// Returns the GitHub login name on success, or null on failure.
  Future<String?> verifyToken() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: _headers(),
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['login'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Searches public repositories. With a valid [token] private repos the
  /// user can access are also included.
  Future<List<GitHubRepo>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final res = await http.get(
        Uri.parse(
            'https://api.github.com/search/repositories?q=${Uri.encodeQueryComponent(query.trim())}&per_page=12'),
        headers: _headers(),
      );
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = body['items'] as List? ?? const [];
      return items
          .map((e) => GitHubRepo(
                owner: ((e as Map<String, dynamic>)['owner']
                        as Map<String, dynamic>?)?['login']
                        as String? ??
                    '',
                name: e['name'] as String? ?? '',
                description: e['description'] as String?,
                cloneUrl: e['clone_url'] as String? ?? '',
                stars: e['stargazers_count'] as int? ?? 0,
              ))
          .where((r) => r.owner.isNotEmpty && r.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// A `git clone`-ready URL. When a token is present it is embedded so
  /// private repos can be cloned without the credential manager.
  String cloneUrl(GitHubRepo repo) {
    final base = repo.cloneUrl;
    if (token == null || token!.isEmpty) return base;
    try {
      final uri = Uri.parse(base);
      return uri.replace(
        userInfo: 'x-access-token:${token!.trim()}',
      ).toString();
    } catch (_) {
      return base;
    }
  }
}