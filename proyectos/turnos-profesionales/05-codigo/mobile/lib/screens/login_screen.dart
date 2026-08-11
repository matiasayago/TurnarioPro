import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/sesion.dart';

/// HU-01: login de cliente o profesional. El registro de negocio/administrador (HU-00a) y el
/// registro de cliente (HU-01) se resuelven con pantallas propias no incluidas en este slice
/// inicial — este login alcanza para probar el flujo con datos creados vía el backend/API.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final email = _emailCtrl.text.trim();
      final resp = await sesion.api.post('/auth/login', {
        'email': email,
        'password': _passCtrl.text,
      });
      sesion.iniciarSesion(resp['token'] as String, email: email);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turnos Profesionales')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            FilledButton(
              onPressed: _cargando ? null : _login,
              child: _cargando ? const CircularProgressIndicator() : const Text('Ingresar'),
            ),
          ],
        ),
      ),
    );
  }
}
