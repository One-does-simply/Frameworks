import 'package:flutter/material.dart';

import '../engine/framework_auth_service.dart';

/// Inline user list with add/edit/reset-password/delete. Backed by
/// [FrameworkAuthService] so every caller (Framework Settings, per-app
/// Settings in multi-user mode, etc.) shares the same list of users.
class FrameworkUserList extends StatefulWidget {
  final FrameworkAuthService authService;
  const FrameworkUserList({super.key, required this.authService});

  @override
  State<FrameworkUserList> createState() => _FrameworkUserListState();
}

class _FrameworkUserListState extends State<FrameworkUserList> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final users = await widget.authService.listUsers();
    if (mounted) setState(() { _users = users; _isLoading = false; });
  }

  Future<void> _addUser() async {
    final emailCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String selectedRole = 'user';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add User'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: displayNameCtrl,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'Min. 8 characters',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                items: ['admin', 'user']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedRole = v ?? 'user'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (result == true && emailCtrl.text.trim().isNotEmpty && passwordCtrl.text.isNotEmpty) {
      if (passwordCtrl.text.length < 8) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password must be at least 8 characters.')),
          );
        }
      } else {
        await widget.authService.registerUser(
          email: emailCtrl.text.trim(),
          password: passwordCtrl.text,
          role: selectedRole,
          displayName: displayNameCtrl.text.trim().isNotEmpty ? displayNameCtrl.text.trim() : null,
        );
        _loadUsers();
      }
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final displayNameCtrl = TextEditingController(text: user['display_name'] as String? ?? '');
    final roles = (user['roles'] as List<dynamic>?)?.cast<String>() ?? [];
    String selectedRole = roles.contains('admin') ? 'admin' : 'user';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit ${user['email'] ?? user['username']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: displayNameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                items: ['admin', 'user']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedRole = v ?? 'user'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (result == true) {
      final newRoles = selectedRole == 'admin' ? ['admin', 'user'] : ['user'];
      await widget.authService.updateUser(
        user['_id'] as String,
        displayName: displayNameCtrl.text.trim().isNotEmpty ? displayNameCtrl.text.trim() : null,
        roles: newRoles,
      );
      _loadUsers();
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset Password — ${user['email'] ?? user['username']}'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New Password',
            helperText: 'Must be at least 8 characters',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Reset')),
        ],
      ),
    );
    if (newPassword != null && newPassword.isNotEmpty) {
      if (newPassword.length < 8) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password must be at least 8 characters.')),
          );
        }
      } else {
        await widget.authService.changePassword(user['_id'] as String, newPassword);
      }
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (user['_id'] == widget.authService.currentUserId) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete "${user['email'] ?? user['username']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.authService.deleteUser(user['_id'] as String);
      _loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.person_add_outlined),
          title: const Text('Add User'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          onTap: _addUser,
        ),
        ..._users.map((user) {
          final email = user['email'] as String? ?? '';
          final fallback = email.isNotEmpty ? email : (user['username'] as String? ?? '?');
          final displayName = (user['display_name'] as String?)?.trim();
          final label = (displayName != null && displayName.isNotEmpty) ? displayName : fallback;
          final roles = (user['roles'] as List<dynamic>?)?.cast<String>() ?? [];
          final isAdmin = roles.contains('admin');
          final isSelf = user['_id'] == widget.authService.currentUserId;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: isAdmin ? colorScheme.primary : colorScheme.surfaceContainerHighest,
              child: Text(
                label[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isAdmin ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            title: Row(
              children: [
                Flexible(child: Text(label, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
                if (isSelf) ...[
                  const SizedBox(width: 6),
                  Text('(you)', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
            subtitle: Text(
              email.isNotEmpty ? '$email · ${roles.join(', ')}' : roles.join(', '),
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit',
                  onPressed: () => _editUser(user),
                ),
                IconButton(
                  icon: const Icon(Icons.key, size: 18),
                  tooltip: 'Reset Password',
                  onPressed: () => _resetPassword(user),
                ),
                if (!isSelf)
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                    tooltip: 'Delete',
                    onPressed: () => _deleteUser(user),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
