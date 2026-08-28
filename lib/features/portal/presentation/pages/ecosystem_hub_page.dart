import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive.dart';
import '../../domain/ecosystem.dart';

/// A generic ecosystem hub screen.
///
/// Shows the ecosystem's tools as a launcher grid. It carries a HOME /
/// "Back to Makaw Home" action (no main menu) and is used across desktop and
/// mobile. Each tool tap opens the tool page (with "Back to {Ecosystem} Hub").
class EcosystemHubPage extends StatelessWidget {
  final Ecosystem ecosystem;
  final void Function(EcosystemTool tool) onOpenTool;
  final void Function() onGoHome;
  final bool isDesktopShell;

  const EcosystemHubPage({
    super.key,
    required this.ecosystem,
    required this.onOpenTool,
    required this.onGoHome,
    this.isDesktopShell = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = isDesktopShell || Responsive.isDesktop(context);
    final columns = isDesktop ? (Responsive.gridColumns(context).clamp(3, 5)) : 2;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1120),
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
        ),
        title: Row(
          children: [
            Icon(ecosystem.icon, color: ecosystem.accent, size: 22),
            const SizedBox(width: 8),
            Text(ecosystem.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: onGoHome,
            icon: const Icon(Icons.home_rounded, color: Color(0xFF38BDF8), size: 20),
            label: const Text('Makaw Home', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? Responsive.desktopMax : double.infinity),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ecosystem.name} Hub',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Everything in ${ecosystem.name}',
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ecosystem.tools.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: isDesktop ? 1.35 : 1.1,
                    ),
                    itemBuilder: (context, i) {
                      final tool = ecosystem.tools[i];
                      return _buildToolCard(context, tool, isDesktop);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolCard(BuildContext context, EcosystemTool tool, bool isDesktop) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => onOpenTool(tool),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isDesktop ? 56 : 48,
                height: isDesktop ? 56 : 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(tool.icon, color: tool.accent, size: isDesktop ? 26 : 24),
              ),
              const SizedBox(height: 12),
              Text(
                tool.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
