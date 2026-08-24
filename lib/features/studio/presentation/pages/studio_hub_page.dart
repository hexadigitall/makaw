import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/code_studio_service.dart';
import 'code_studio_workspace.dart';

class MakawStudioHubPage extends StatefulWidget {
  const MakawStudioHubPage({super.key});

  @override
  State<MakawStudioHubPage> createState() => _MakawStudioHubPageState();
}

class _MakawStudioHubPageState extends State<MakawStudioHubPage> {
  List<StudioProject> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final res = await CodeStudioService.getProjects();
    setState(() { _projects = res; _isLoading = false; });
  }

  void _showCreateDialog() {
    String template = 'dart';
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('New Project', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController, autofocus: true,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: const InputDecoration(labelText: 'Project Name', hintText: 'my_flutter_app'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: template,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: const InputDecoration(labelText: 'Template'),
                items: const [
                  DropdownMenuItem(value: 'dart', child: Text('Dart Console')),
                  DropdownMenuItem(value: 'python', child: Text('Python Script')),
                  DropdownMenuItem(value: 'javascript', child: Text('Node.js / JavaScript')),
                  DropdownMenuItem(value: 'web', child: Text('HTML5 / CSS / JS Web')),
                ],
                onChanged: (val) => setDialogState(() => template = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(ctx);
                  final project = await CodeStudioService.createProject(name, template);
                  _loadProjects();
                  _openWorkspace(project);
                }
              },
              child: Text('Create', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  void _openWorkspace(StudioProject project) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MakawStudioWorkspacePage(project: project),
    )).then((_) => _loadProjects());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cs.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Code Studio', style: TextStyle(color: cs.onSurface, fontSize: 16)),
        actions: [IconButton(icon: Icon(Icons.refresh, color: cs.onSurface.withOpacity(0.6)), onPressed: _loadProjects)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.code_outlined, size: 64, color: cs.onSurface.withOpacity(0.15)),
                    const SizedBox(height: 12),
                    Text('No local projects found.', style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: cs.primary),
                      onPressed: _showCreateDialog,
                      icon: Icon(Icons.add, color: cs.onPrimary),
                      label: Text('Create New Project', style: TextStyle(color: cs.onPrimary)),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _projects.length,
                  itemBuilder: (context, index) {
                    final p = _projects[index];
                    return Card(
                      color: cs.surface,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(Icons.folder_special, color: cs.primary),
                        title: Text(p.name, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'Modified: ${p.lastModified.toString().split('.').first}',
                          style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: cs.onSurface.withOpacity(0.3)),
                          onPressed: () async { await CodeStudioService.deleteProject(p.directory); _loadProjects(); },
                        ),
                        onTap: () => _openWorkspace(p),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: cs.primary,
        onPressed: _showCreateDialog,
        child: Icon(Icons.add, color: cs.onPrimary),
      ),
    );
  }
}
