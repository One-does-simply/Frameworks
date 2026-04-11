import 'package:flutter/material.dart';

import '../engine/framework_auth_service.dart';

/// Framework-level admin account creation screen.
/// Shown when multi-user mode is first enabled.
class FrameworkAdminSetupScreen extends StatefulWidget {
  final FrameworkAuthService authService;
  final VoidCallback onSetupComplete;
  final VoidCallback? onCancel;

  const FrameworkAdminSetupScreen({
    super.key,
    required this.authService,
    required this.onSetupComplete,
    this.onCancel,
  });

  @override
  State<FrameworkAdminSetupScreen> createState() => _FrameworkAdminSetupScreenState();
}

class _FrameworkAdminSetupScreenState extends State<FrameworkAdminSetupScreen> {
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSetup() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final displayName = _displayNameController.text.trim();

    if (email.isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() { _error = null; _loading = true; });
    final success = await widget.authService.setupAdmin(
      email: email,
      password: password,
      displayName: displayName.isNotEmpty ? displayName : null,
    );
    if (!mounted) return;

    if (success) {
      widget.onSetupComplete();
    } else {
      setState(() { _error = 'Failed to create admin account'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'One Does Simply',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Create Admin Account',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Set up the administrator account. You\'ll use this to manage apps and users.',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_error!, style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13)),
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          enabled: !_loading,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(labelText: 'Display Name (optional)'),
                          textInputAction: TextInputAction.next,
                          enabled: !_loading,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(labelText: 'Password', hintText: 'Minimum 8 characters'),
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                          enabled: !_loading,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmController,
                          decoration: const InputDecoration(labelText: 'Confirm Password'),
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          enabled: !_loading,
                          onSubmitted: (_) => _handleSetup(),
                        ),
                        const SizedBox(height: 20),

                        FilledButton(
                          onPressed: _loading ? null : _handleSetup,
                          child: _loading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Create Admin & Continue'),
                        ),

                        if (widget.onCancel != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loading ? null : widget.onCancel,
                            child: const Text('Cancel'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
