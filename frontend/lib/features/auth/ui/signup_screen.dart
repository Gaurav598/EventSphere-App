import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/features/auth/providers/auth_provider.dart';
import 'package:frontend/core/validators.dart';
import 'package:frontend/shared/widgets/animated_dialog.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _organizerCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isAdmin = false;
  bool _isPasswordVisible = false;

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text.trim(),
      _isAdmin,
      organizerCode: _isAdmin ? _organizerCodeController.text.trim() : null,
    );

    if (!mounted) return;

    if (success) {
      await AnimatedDialog.show(context, title: 'Welcome!', message: 'User successfully created. Please log in.', icon: Icons.check_circle_outline, color: Colors.green);
      if (mounted) context.go('/login');
    } else {
      AnimatedDialog.show(context, title: 'Signup Failed', message: authProvider.error ?? 'Signup failed', icon: Icons.error_outline, color: Colors.red);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _organizerCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/auth_bg.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Join EventSphere',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create your account to continue',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                        ),
                        const SizedBox(height: 40),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name', 
                            prefixIcon: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary),
                          ),
                          validator: Validators.requiredField,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'Email Address', 
                            prefixIcon: Icon(Icons.email_outlined, color: Theme.of(context).colorScheme.primary),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: Validators.email,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password', 
                            prefixIcon: Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.primary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                          ),
                          obscureText: !_isPasswordVisible,
                          validator: Validators.password,
                        ),
                        const SizedBox(height: 20),
                        Material(
                          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: SwitchListTile(
                            title: const Text('Register as Admin', style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text('Create and manage events', style: TextStyle(fontSize: 12)),
                            value: _isAdmin,
                            onChanged: (val) => setState(() => _isAdmin = val),
                            activeColor: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (_isAdmin) ...[
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _organizerCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Organizer invitation code',
                              prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                            ),
                            obscureText: true,
                            validator: _isAdmin ? Validators.requiredField : null,
                          ),
                        ],
                        const SizedBox(height: 40),
                        ElevatedButton(
                          onPressed: authProvider.isLoading ? null : _signup,
                          child: authProvider.isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('CREATE ACCOUNT'),
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: RichText(
                            text: TextSpan(
                              text: 'Already have an account? ',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                              children: [
                                TextSpan(
                                  text: 'Sign In',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
