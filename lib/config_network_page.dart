// config_network_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:showcaseview/showcaseview.dart'; // Asegúrate de tener este paquete importado

class ConfigNetworkPage extends StatefulWidget {
  final WebSocketChannel channel;
  const ConfigNetworkPage({Key? key, required this.channel}) : super(key: key);

  @override
  _ConfigNetworkPageState createState() => _ConfigNetworkPageState();
}

class _ConfigNetworkPageState extends State<ConfigNetworkPage> {
  final _formKey = GlobalKey<FormState>();
  // GlobalKey para la ayuda
  final GlobalKey _keyConfigHelp = GlobalKey();

  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // Variable para habilitar o deshabilitar el botón de envío en tiempo real.
  bool _isFormValid = false;

  // Variable para controlar la visibilidad de la contraseña.
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    _ssidController.addListener(_checkFormValidity);
    _passwordController.addListener(_checkFormValidity);
    _confirmPasswordController.addListener(_checkFormValidity);
    _passwordVisible = false;
  }

  void _checkFormValidity() {
    // El formulario es válido si:
    // - Existe un SSID no vacío.
    // - La contraseña y la confirmación están ingresadas.
    // - Ambas contraseñas coinciden.
    final isValid = _ssidController.text.trim().isNotEmpty &&
        _passwordController.text.trim().isNotEmpty &&
        _confirmPasswordController.text.trim().isNotEmpty &&
        (_passwordController.text.trim() == _confirmPasswordController.text.trim());
    if (isValid != _isFormValid) {
      setState(() {
        _isFormValid = isValid;
      });
    }
  }

  void _submitConfig() {
    if (_formKey.currentState!.validate()) {
      final config = {
        "networkConfig": {
          "ssid": _ssidController.text.trim(),
          "password": _passwordController.text.trim(),
        }
      };

      widget.channel.sink.add(jsonEncode(config));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración enviada')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _confirmAndSubmit() async {
    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmar configuración"),
          content: const Text(
              "¿Estás seguro de que deseas cambiar el SSID y la contraseña?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Confirmar"),
            ),
          ],
        );
      },
    );
    if (shouldSubmit == true) {
      _submitConfig();
    }
  }

  // Función para mostrar la guía de configuración en un diálogo.
  // Se ha agregado una sección que explica que, si se olvida la contraseña, se debe
  // presionar el botón de reset de la cámara Wi‑Fi durante 5 segundos para restaurar
  // los valores de fábrica.
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Ayuda - Configuración de Red"),
          content: const Text(
            "En esta pantalla puedes cambiar el SSID y la contraseña de la red de tu cámara.\n\n"
            "1. Ingresa un nuevo SSID y una contraseña, confirmando esta última.\n"
            "2. Pulsa el botón 'Guardar' y confirma la acción para aplicar los cambios.\n\n"
            "Si olvidas la contraseña, presiona el botón de reset de la cámara wifi durante 5 segundos, "
            "lo que restablecerá la configuración a los valores de fábrica:\n • SSID: CAMARA\n • Contraseña: 12345678",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Entendido"),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Red'),
        actions: [
          // Ícono de ayuda con Showcase
          Showcase(
            key: _keyConfigHelp,
            description:
                "Pulsa este ícono para ver la guía de cómo configurar la red.\n"
                "Si olvidas la contraseña, presiona el botón de reset de la cámara wifi durante 5 segundos "
                "para restaurar los valores de fábrica.",
            child: IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: "Ayuda",
              onPressed: _showHelpDialog,
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _ssidController,
                  decoration: const InputDecoration(labelText: 'Nuevo SSID'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, ingresa el nombre de la red';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Nueva Contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _passwordVisible = !_passwordVisible;
                        });
                      },
                    ),
                  ),
                  obscureText: !_passwordVisible,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa la contraseña';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirmar Contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _passwordVisible = !_passwordVisible;
                        });
                      },
                    ),
                  ),
                  obscureText: !_passwordVisible,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Confirma la contraseña';
                    }
                    if (value.trim() != _passwordController.text.trim()) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _isFormValid ? _confirmAndSubmit : null,
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
