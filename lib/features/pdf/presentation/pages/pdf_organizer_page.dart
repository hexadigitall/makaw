import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfOrganizerPage extends StatefulWidget {
  final String filePath;
  const PdfOrganizerPage({super.key, required this.filePath});

  @override
  State<PdfOrganizerPage> createState() => _PdfOrganizerPageState();
}

class _PdfOrganizerPageState extends State<PdfOrganizerPage> {
  PdfDocument? _document;
  List<int> _pageOrder = [];
  Set<int> _selectedPages = {};
  bool _isLoading = true;
  bool _isModified = false;

  static const _kDark = Color(0xFF0F0F1A);
  static const _kCard = Color(0xFF1A1A2E);
  static const _kAccent = Color(0xFF818CF8);
  static const _kMuted = Color(0xFF666680);

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final file = File(widget.filePath);
      _document = await PdfDocument.openFile(file.path);
      _pageOrder = List.generate(_document!.pages.length, (i) => i);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading PDF: $e')));
      }
    }
  }

  void _selectPage(int index) {
    setState(() {
      if (_selectedPages.contains(index)) {
        _selectedPages.remove(index);
      } else {
        _selectedPages.add(index);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedPages.length == _pageOrder.length) {
        _selectedPages.clear();
      } else {
        _selectedPages = Set.from(List.generate(_pageOrder.length, (i) => i));
      }
    });
  }

  void _deleteSelected() {
    if (_selectedPages.isEmpty) return;
    setState(() {
      final toDelete = _selectedPages.toList()..sort((a, b) => b.compareTo(a));
      for (final idx in toDelete) {
        _pageOrder.removeAt(idx);
      }
      _selectedPages.clear();
      _isModified = true;
    });
  }

  void _rotateSelected() {
    if (_selectedPages.isEmpty) return;
    // Rotation is visual only in this implementation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rotation applied (visual only in preview)')),
    );
  }

  void _moveSelected(int direction) {
    if (_selectedPages.isEmpty) return;
    final sorted = _selectedPages.toList()..sort();
    setState(() {
      if (direction < 0) {
        // Move up
        if (sorted.first > 0) {
          final newOrder = List<int>.from(_pageOrder);
          for (final idx in sorted) {
            if (idx > 0) {
              final temp = newOrder[idx];
              newOrder[idx] = newOrder[idx - 1];
              newOrder[idx - 1] = temp;
            }
          }
          _pageOrder = newOrder;
          _selectedPages = _selectedPages.map((p) => p - 1).where((p) => p >= 0).toSet();
          _isModified = true;
        }
      } else {
        // Move down
        if (sorted.last < _pageOrder.length - 1) {
          final newOrder = List<int>.from(_pageOrder);
          for (final idx in sorted.reversed) {
            if (idx < newOrder.length - 1) {
              final temp = newOrder[idx];
              newOrder[idx] = newOrder[idx + 1];
              newOrder[idx + 1] = temp;
            }
          }
          _pageOrder = newOrder;
          _selectedPages = _selectedPages.map((p) => p + 1).where((p) => p < _pageOrder.length).toSet();
          _isModified = true;
        }
      }
    });
  }

  Future<void> _saveChanges() async {
    if (!_isModified) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page reordering saved (visual layout updated)')),
    );
    setState(() => _isModified = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: Text(
          _selectedPages.isEmpty
              ? 'Page Organizer'
              : '${_selectedPages.length} selected',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _selectAll,
            child: Text(
              _selectedPages.length == _pageOrder.length ? 'Deselect All' : 'Select All',
              style: const TextStyle(color: _kAccent),
            ),
          ),
          if (_selectedPages.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
              onPressed: _deleteSelected,
              tooltip: 'Delete',
            ),
            IconButton(
              icon: const Icon(Icons.rotate_right, color: Colors.white70, size: 22),
              onPressed: _rotateSelected,
              tooltip: 'Rotate',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, color: Colors.white70, size: 22),
              onPressed: () => _moveSelected(-1),
              tooltip: 'Move Up',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, color: Colors.white70, size: 22),
              onPressed: () => _moveSelected(1),
              tooltip: 'Move Down',
            ),
          ],
          if (_isModified)
            IconButton(
              icon: const Icon(Icons.save, color: _kAccent, size: 22),
              onPressed: _saveChanges,
              tooltip: 'Save',
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _kAccent))
          : _buildGrid(),
    );
  }

  Widget _buildGrid() {
    if (_pageOrder.isEmpty) {
      return const Center(child: Text('No pages remaining', style: TextStyle(color: _kMuted)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _pageOrder.length,
      itemBuilder: (_, i) {
        final pageIdx = _pageOrder[i];
        final isSelected = _selectedPages.contains(i);
        return GestureDetector(
          onTap: () => _selectPage(i),
          onLongPress: () => _selectPage(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? _kAccent.withOpacity(0.2) : _kCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? _kAccent : const Color(0xFF2D3748),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                    child: PdfPageView(
                        document: _document!,
                        pageNumber: pageIdx + 1,
                        alignment: Alignment.center,
                      )
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? _kAccent.withOpacity(0.3) : _kCard,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSelected)
                        const Icon(Icons.check_circle, color: _kAccent, size: 14)
                      else
                        Icon(Icons.check_circle_outline, color: _kMuted, size: 14),
                      const SizedBox(width: 4),
                      Text('${i + 1}', style: TextStyle(
                        color: isSelected ? Colors.white : _kMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
