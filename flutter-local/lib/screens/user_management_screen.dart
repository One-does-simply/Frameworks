import 'package:flutter/material.dart';

import '../engine/auth_service.dart';

/// Admin-only user management screen for creating, editing, and deleting users.
///
/// ODS Ethos: The framework provides a complete user management UI out of the
/// box. Builders never need to create admin panels — the framework handles it.
class UserManagementScreen extends StatefulWidget {
  final AuthService authService;
  final List<String> availableRoles;

  const UserManagementScreen({
    super.key,
    required this.authService,
    required this.availableRoles,
  });

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
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
    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'user';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add User'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: widget.availableRoles
                    .where((r) => r != 'guest')
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedRole = v ?? 'user'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final username = usernameController.text.trim();
      final password = passwordController.text;
      if (username.isNotEmpty && password.isNotEmpty) {
        final userId = await widget.authService.registerUser(
          username: username,
          password: password,
          role: selectedRole,
        );
        if (userId != null) {
          await _loadUsers();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create user. Username may be taken.')),
          );
        }
      }
    }

    usernameController.dispose();
    passwordController.dispose();
  }

  Future<void> _confirmDeleteUser(Map<String, dynamic> user) async {
    final userId = user['_id'] as int;
    final username = user['username'] as String;

    // Can't delete yourself.
    if (userId == widget.authService.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot delete your own account.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete "$username"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.authService.deleteUser(userId);
      await _loadUsers();
    }
  }

  Future<void> _showChangePasswordDialog(Map<String, dynamic> user) async {
    final userId = user['_id'] as int;
    final username = user['username'] as String;
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Password for $username'),
        content: TextField(
          controller: passwordController,
          decoration: const InputDecoration(labelText: 'New Password'),
          obscureText: true,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final password = passwordController.text;
      if (password.isNotEmpty) {
        await widget.authService.changePassword(userId, password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Password reset for $username')),
          );
        }
      }
    }

    passwordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Text(
                    'No users found',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final username = user['username'] as String;
                    final displayName = user['display_name'] as String? ?? username;
                    final roles = (user['roles'] as List<String>?) ?? [];
                    final isCurrentUser = user['_id'] == widget.authService.currentUserId;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: roles.contains('admin')
                              ? colorScheme.primary
                              : colorScheme.secondaryContainer,
                          foregroundColor: roles.contains('admin')
                              ? colorScheme.onPrimary
                              : colorScheme.onSecondaryContainer,
                          child: Text(username[0].toUpperCase()),
                        ),
                        title: Row(
                          children: [
                            Text(displayName),
                            if (isCurrentUser) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'you',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Wrap(
                          spacing: 4,
                          children: roles.map((role) {
                            return Chip(
                              label: Text(role),
                              labelStyle: const TextStyle(fontSize: 11),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            switch (action) {
                              case 'password':
                                _showChangePasswordDialog(user);
                              case 'delete':
                                _confirmDeleteUser(user);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'password',
                              child: ListTile(
                                leading: Icon(Icons.lock_reset),
                                title: Text('Reset Password'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            if (!isCurrentUser)
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline,
                                      color: colorScheme.error),
                                  title: Text('Delete',
                                      style: TextStyle(color: colorScheme.error)),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add User'),
      ),
    );
  }
}
