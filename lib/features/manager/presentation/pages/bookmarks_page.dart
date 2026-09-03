import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/storage/bookmark_service.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<BookmarkFolder> _folders = [];
  List<Bookmark> _bookmarks = [];
  List<Bookmark>? _allBookmarks;
  int? _selectedFolderId;
  bool _isLoading = true;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final folders = await BookmarkService.getFolders();
    final all = await BookmarkService.getAll();
    final query = _query.trim();
    final bookmarks = query.isNotEmpty
        ? await BookmarkService.search(query)
        : (_selectedFolderId == null
            ? all
            : await BookmarkService.getAll(folderId: _selectedFolderId));
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _allBookmarks = all;
      _bookmarks = bookmarks;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search bookmarks',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Colors.white38, size: 22),
            prefixIconConstraints: BoxConstraints(minWidth: 40),
          ),
          onChanged: (v) {
            _query = v.trim();
            _load();
          },
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _query = '';
                _load();
              },
            ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: Color(0xFFFBBF24)),
            tooltip: 'New folder',
            onPressed: _showNewFolderDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFFBBF24)),
            tooltip: 'Add bookmark',
            onPressed: _showAddBookmarkDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFBBF24)))
          : Column(
              children: [
                if (_folders.isNotEmpty && _query.isEmpty) _buildFolderChips(),
                Expanded(
                  child: _bookmarks.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _bookmarks.length,
                          itemBuilder: (_, i) => _buildBookmarkTile(_bookmarks[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFolderChips() {
    final selectedTitle = _folders.firstWhere(
      (f) => f.id == _selectedFolderId,
      orElse: () => BookmarkFolder(id: null, name: '', createdAt: DateTime.now()),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _folderChip('All', _selectedFolderId == null, Icon(Icons.collections_bookmark), () {
            setState(() => _selectedFolderId = null);
            _load();
          }, onLongPress: null),
          ..._folders.map((f) => _folderChip(
            f.name,
            f.id == _selectedFolderId,
            Icon(Icons.folder, color: const Color(0xFFFBBF24)),
            () {
              setState(() => _selectedFolderId = f.id);
              _load();
            },
            onLongPress: () => _showFolderEditSheet(f),
          )),
          if (_selectedFolderId != null)
            TextButton.icon(
              onPressed: () {
                setState(() => _selectedFolderId = null);
                _load();
              },
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Clear filter'),
            ),
          SizedBox(width: 4),
          if (selectedTitle.id != null) _bookmarkCount(selectedTitle.id!),
        ],
      ),
    );
  }

  Widget _bookmarkCount(int folderId) {
    final count = _allBookmarks?.where((b) => b.folderId == folderId).length ?? 0;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text('$count', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
    );
  }

  Widget _folderChip(String label, bool selected, Widget icon, VoidCallback onTap,
      {VoidCallback? onLongPress}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? const Color(0xFFFBBF24) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(data: const IconThemeData(size: 16), child: icon),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkTile(Bookmark b) {
    final folder = _folders.firstWhere(
      (f) => f.id == b.folderId,
      orElse: () => BookmarkFolder(id: null, name: '', createdAt: DateTime.now()),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final url = b.url.startsWith('http') ? b.url : 'https://${b.url}';
          try {
            if (await canLaunchUrl(Uri.parse(url))) {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          } catch (_) {}
        },
        onLongPress: () => _showBookmarkSheet(b),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _favicon(b),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.title,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_host(b.url)}${b.folderId != null ? ' \u2022 ${folder.name}' : ''}',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (b.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: b.tags
                              .take(4)
                              .map((t) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text('#$t',
                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
                onPressed: () => _showBookmarkSheet(b),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _favicon(Bookmark b) {
    if (b.faviconUrl != null && b.faviconUrl!.isNotEmpty) {
      return Image.network(
        b.faviconUrl!,
        width: 40,
        height: 40,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.bookmark, color: Color(0xFFFBBF24), size: 22),
      );
    }
    return const Icon(Icons.bookmark, color: Color(0xFFFBBF24), size: 22);
  }

  String _host(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmarks_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            _query.isNotEmpty ? 'No results found' : 'No bookmarks yet',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          if (_query.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Save sites you visit often to see them here',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showNewFolderDialog() async {
    final ctl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('New folder', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          TextButton(
            onPressed: () async {
              final name = ctl.text.trim();
              if (name.isNotEmpty) {
                await BookmarkService.createFolder(name, parentId: _selectedFolderId);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _load();
            },
            child: const Text('Create', style: TextStyle(color: Color(0xFFFBBF24))),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddBookmarkDialog() async {
    final titleCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final tagCtl = TextEditingController();
    int? folderId = _selectedFolderId;
    final tags = <String>[];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Add bookmark', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'URL', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: folderId,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Folder',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No folder')),
                    ..._folders.map((f) => DropdownMenuItem<int?>(
                      value: f.id,
                      child: Text(f.name),
                    )),
                  ],
                  onChanged: (v) => setDlg(() => folderId = v),
                ),
                const SizedBox(height: 12),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags.map((t) => Chip(
                        label: Text('#$t', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        backgroundColor: const Color(0xFF334155),
                        deleteIconColor: const Color(0xFFF87171),
                        onDeleted: () => setDlg(() => tags.remove(t)),
                      )).toList(),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tagCtl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(hintText: 'Add tag', hintStyle: TextStyle(color: Colors.white38)),
                        onSubmitted: (_) {
                          final t = tagCtl.text.trim().replaceAll('#', '');
                          if (t.isNotEmpty && !tags.contains(t)) setDlg(() { tags.add(t); tagCtl.clear(); });
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: Color(0xFFFBBF24)),
                      onPressed: () {
                        final t = tagCtl.text.trim().replaceAll('#', '');
                        if (t.isNotEmpty && !tags.contains(t)) setDlg(() { tags.add(t); tagCtl.clear(); });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            TextButton(
              onPressed: () async {
                final title = titleCtl.text.trim();
                final url = urlCtl.text.trim();
                if (url.isNotEmpty) {
                  await BookmarkService.upsert(Bookmark(
                    title: title.isEmpty ? _host(url) : title,
                    url: url,
                    folderId: folderId,
                    tags: List.from(tags),
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ));
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _load();
              },
              child: const Text('Save', style: TextStyle(color: Color(0xFFFBBF24))),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookmarkSheet(Bookmark b) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  b.title,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _actionTile(Icons.content_copy, 'Copy URL', () {
                Clipboard.setData(ClipboardData(text: b.url));
                Navigator.of(ctx).pop();
              }),
              _actionTile(Icons.folder_outlined, 'Move to folder', () {
                Navigator.of(ctx).pop();
                _showMoveFolderDialog(b);
              }),
              _actionTile(Icons.label_outline, 'Edit tags', () {
                Navigator.of(ctx).pop();
                _showEditTagsSheet(b);
              }),
              _actionTile(Icons.edit_outlined, 'Edit', () {
                Navigator.of(ctx).pop();
                _showEditBookmarkDialog(b);
              }),
              _actionTile(Icons.delete_outline, 'Delete', () async {
                Navigator.of(ctx).pop();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    title: const Text('Delete bookmark?', style: TextStyle(color: Colors.white, fontSize: 18)),
                    content: Text('Delete "${b.title}"?', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dCtx).pop(false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
                      TextButton(onPressed: () => Navigator.of(dCtx).pop(true), child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171)))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await BookmarkService.deleteBookmark(b.id!);
                  await _load();
                }
              }, color: const Color(0xFFF87171)),
            ],
          ),
        );
      },
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white70, size: 22),
      title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 14)),
      onTap: onTap,
      dense: true,
    );
  }

  Future<void> _showEditBookmarkDialog(Bookmark b) async {
    final titleCtl = TextEditingController(text: b.title);
    final urlCtl = TextEditingController(text: b.url);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Edit bookmark', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'URL', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          TextButton(
            onPressed: () async {
              final title = titleCtl.text.trim();
              final url = urlCtl.text.trim();
              if (url.isNotEmpty) {
                await BookmarkService.updateBookmark(Bookmark(
                  id: b.id,
                  title: title.isEmpty ? b.title : title,
                  url: url,
                  folderId: b.folderId,
                  faviconUrl: b.faviconUrl,
                  tags: b.tags,
                  notes: b.notes,
                  createdAt: b.createdAt,
                  updatedAt: DateTime.now(),
                ));
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _load();
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFFFBBF24))),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveFolderDialog(Bookmark b) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Move to folder', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.inbox, color: Color(0xFF94A3B8)),
                title: const Text('No folder', style: TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () async {
                  await BookmarkService.moveToFolder(b.id!, null);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _load();
                },
              ),
              ..._folders.map((f) => ListTile(
                    leading: const Icon(Icons.folder_outlined, color: Color(0xFFFBBF24)),
                    title: Text(f.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    onTap: () async {
                      await BookmarkService.moveToFolder(b.id!, f.id);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      await _load();
                    },
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close', style: TextStyle(color: Color(0xFF94A3B8)))),
        ],
      ),
    );
  }

  Future<void> _showEditTagsSheet(Bookmark b) async {
    final tagCtl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tags', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: b.tags.map((t) => Chip(
                    label: Text('#$t', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: const Color(0xFF334155),
                    deleteIconColor: const Color(0xFFF87171),
                    onDeleted: () async {
                      await BookmarkService.removeTag(b.id!, t);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      await _load();
                    },
                  )).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: tagCtl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'Add tag', hintStyle: TextStyle(color: Colors.white38)),
                    onSubmitted: (_) => _addTagCommit(ctx, b, tagCtl),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Color(0xFFFBBF24)),
                  onPressed: () => _addTagCommit(ctx, b, tagCtl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTagCommit(BuildContext ctx, Bookmark b, TextEditingController tagCtl) async {
    final tag = tagCtl.text.trim().replaceAll('#', '');
    if (tag.isNotEmpty) {
      await BookmarkService.addTag(b.id!, tag);
      tagCtl.clear();
      await _load();
    }
  }

  void _showFolderEditSheet(BookmarkFolder f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(f.name,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            _actionTile(Icons.edit_outlined, 'Rename folder', () {
              Navigator.of(ctx).pop();
              _showRenameFolderDialog(f);
            }),
            _actionTile(Icons.delete_outline, 'Delete folder', () async {
              Navigator.of(ctx).pop();
              final count = _allBookmarks?.where((b) => b.folderId == f.id).length ?? 0;
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Delete folder?', style: TextStyle(color: Colors.white, fontSize: 18)),
                  content: Text(
                    count > 0
                        ? 'Delete "${f.name}" and its $count bookmark${count == 1 ? '' : 's'}?'
                        : 'Delete empty folder "${f.name}"?',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(dCtx).pop(false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
                    TextButton(onPressed: () => Navigator.of(dCtx).pop(true), child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171)))),
                  ],
                ),
              );
              if (confirm == true) {
                await BookmarkService.deleteFolder(f.id!, cascade: true);
                if (_selectedFolderId == f.id) _selectedFolderId = null;
                await _load();
              }
            }, color: const Color(0xFFF87171)),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameFolderDialog(BookmarkFolder f) async {
    final ctl = TextEditingController(text: f.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Rename folder', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Folder name', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          TextButton(
            onPressed: () async {
              final name = ctl.text.trim();
              if (name.isNotEmpty) await BookmarkService.renameFolder(f.id!, name);
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _load();
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFFFBBF24))),
          ),
        ],
      ),
    );
  }
}
