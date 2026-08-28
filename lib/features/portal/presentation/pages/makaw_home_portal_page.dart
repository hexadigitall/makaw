import 'package:flutter/material.dart';
import '../../domain/launcher_item.dart';

class MakawHomePortalPage extends StatelessWidget {
  final Function(String route) onNavigate;
  final VoidCallback onOpenQrScanner;
  final VoidCallback onToggleIncognito;
  final VoidCallback onOpenAiAssistant;

  const MakawHomePortalPage({
    Key? key,
    required this.onNavigate,
    required this.onOpenQrScanner,
    required this.onToggleIncognito,
    required this.onOpenAiAssistant,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),

              // 1. Center Wordmark
              const Text(
                'Makaw',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // 2. Universal Search & Command Palette
              _buildUniversalSearchBar(),
              const SizedBox(height: 20),

              // 3. Launcher Hub Card
              _buildLauncherHub(context),
              const SizedBox(height: 16),

              // 4. AI Assistant Banner (Gradient Action Pill)
              _buildAiAssistantBanner(),
              const SizedBox(height: 16),

              // 5. Recent Activity Card
              _buildRecentActivitySection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUniversalSearchBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.white38, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search Tools, Files, and Web...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner_rounded, color: Colors.white.withOpacity(0.6), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onOpenQrScanner,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.shield_outlined, color: Colors.white.withOpacity(0.6), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onToggleIncognito,
          ),
        ],
      ),
    );
  }

  Widget _buildLauncherHub(BuildContext context) {
    final launcherItems = _launcherItems(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('🚀', style: TextStyle(fontSize: 14)),
              SizedBox(width: 8),
              Text(
                'Launcher Hub',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2x3 Grid of Shortcuts
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: launcherItems.map((item) => _buildGridTile(item)).toList(),
          ),
        ],
      ),
    );
  }

  List<LauncherItem> _launcherItems(BuildContext context) {
    return [
      LauncherItem(
        title: 'Code Studio',
        icon: Icons.code_rounded,
        accentColor: const Color(0xFF818CF8),
        onTap: () => onNavigate('studio'),
      ),
      LauncherItem(
        title: 'Terminal',
        icon: Icons.terminal_rounded,
        accentColor: const Color(0xFF22D3EE),
        onTap: () => onNavigate('terminal'),
      ),
      LauncherItem(
        title: 'Documents',
        icon: Icons.edit_document,
        accentColor: const Color(0xFFFBBF24),
        onTap: () => onNavigate('documents'),
      ),
      LauncherItem(
        title: 'Media Hub',
        icon: Icons.video_collection_outlined,
        accentColor: const Color(0xFFF87171),
        onTap: () => onNavigate('media'),
      ),
      LauncherItem(
        title: 'Web Browser',
        icon: Icons.language_rounded,
        accentColor: const Color(0xFF00A7C2),
        onTap: () => onNavigate('browser'),
      ),
      LauncherItem(
        title: 'File Explorer',
        icon: Icons.folder_outlined,
        accentColor: const Color(0xFF34D399),
        onTap: () => onNavigate('files'),
      ),
    ];
  }

  Widget _buildGridTile(LauncherItem item) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, color: item.accentColor, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAssistantBanner() {
    return InkWell(
      onTap: onOpenAiAssistant,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Assistant',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Powered by Gemini',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivitySection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Activity',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(Icons.settings_outlined, color: Colors.white.withOpacity(0.4), size: 18),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'No recent activity',
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
