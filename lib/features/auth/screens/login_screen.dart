import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../main/screens/main_shell_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final List<String> _pin = List.filled(4, '');
  int _currentIndex = 0;

  void _onNumberPress(String number) {
    if (_currentIndex < 4) {
      setState(() {
        _pin[_currentIndex] = number;
        _currentIndex++;
      });

      // Auto-attempt login when 4 digits are entered
      if (_currentIndex == 4) {
        _attemptLogin();
      }
    }
  }

  void _onBackspace() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _pin[_currentIndex] = '';
      });
    }
  }

  Future<void> _attemptLogin() async {
    final enteredPin = _pin.join();

    // Call login from auth provider
    await ref.read(currentUserProvider.notifier).login(enteredPin);

    // Check if login was successful
    final user = ref.read(currentUserProvider);

    if (user != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
      );
    } else if (mounted) {
      // Wrong PIN - reset and show error
      setState(() {
        _pin.fillRange(0, 4, '');
        _currentIndex = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect PIN. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    // If already logged in, redirect immediately
    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainShellScreen()),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo / Icon
              const Icon(Icons.storefront, size: 90, color: Colors.green),
              const SizedBox(height: 32),

              const Text(
                'ShopPOS',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Welcome Back!',
                style: TextStyle(fontSize: 20, color: Colors.grey),
              ),

              const SizedBox(height: 60),

              // PIN Display
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 55,
                    height: 65,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _pin[index].isEmpty ? Colors.grey : Colors.green,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        _pin[index].isEmpty ? '•' : _pin[index],
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 80),

              // Numeric Keypad
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  if (index == 9) return const SizedBox.shrink(); // Empty space
                  if (index == 11) {
                    return ElevatedButton(
                      onPressed: _onBackspace,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(20),
                      ),
                      child: const Icon(Icons.backspace, size: 28),
                    );
                  }

                  final number = index == 10 ? '0' : (index + 1).toString();

                  return ElevatedButton(
                    onPressed: () => _onNumberPress(number),
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                      backgroundColor: Colors.grey[100],
                      foregroundColor: Colors.black87,
                    ),
                    child: Text(
                      number,
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w500),
                    ),
                  );
                },
              ),

              const SizedBox(height: 30),
              const Text(
                'Default test PIN: 1234',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
