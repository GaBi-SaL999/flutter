import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // Mantener la pantalla encendida
import 'package:connectivity_plus/connectivity_plus.dart'; // Detectar estado de red
import 'package:flutter/services.dart'; // Manejar la orientación y el modo UI

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camara WIFI',
      theme: ThemeData(
        // Tema sutil y minimalista
        brightness: Brightness.light,
        primaryColor: const Color(0xFFE0E0E0),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: const AppBarTheme(
          color: Color(0xFFE0E0E0),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String wsUrl = 'ws://192.168.4.1:81'; // Dirección del ESP32-CAM
  late WebSocketChannel channel;
  Uint8List? imageBytes;
  String connectionStatus = "Conexión no iniciada";
  bool isFullscreen = false; // Controla el estado de pantalla completa

  // Flag para evitar múltiples intentos de reconexión
  bool _isReconnecting = false;

  // Suscripción al stream de conectividad para actuar cuando se restablece la conexión Wi-Fi
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();

    // Mantiene la pantalla encendida
    WakelockPlus.enable();

    // Conectarse al WebSocket
    connectToWebSocket();

    // Escuchar cambios en la conectividad y reconectar si es necesario
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.wifi && _isReconnecting) {
        connectToWebSocket();
      }
    });
  }

  @override
  void dispose() {
    // Desactiva el wakelock cuando se cierra la app
    WakelockPlus.disable();
    _connectivitySubscription?.cancel();
    channel.sink.close();

    // Restaurar la orientación y el modo UI por defecto
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Intenta conectar al canal WebSocket y configura los callbacks.
  Future<void> connectToWebSocket() async {
    setState(() {
      connectionStatus = "Conectando a la Camara...";
    });

    try {
      // Reiniciamos el flag de reconexión al iniciar una conexión
      _isReconnecting = false;
      channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      setState(() {
        connectionStatus = "Conectado con la Camara";
      });

      channel.stream.listen(
        (data) {
          // Si los datos recibidos son un Uint8List se actualiza la imagen.
          if (data is Uint8List) {
            setState(() {
              imageBytes = data;
            });
          }
        },
        onError: (error) {
          setState(() {
            connectionStatus = "Error: $error";
          });
          scheduleReconnect();
        },
        onDone: () {
          setState(() {
            connectionStatus = "Conexión cerrada. Intentando reconectar...";
          });
          scheduleReconnect();
        },
      );
    } catch (e) {
      setState(() {
        connectionStatus = "Error al conectar: $e";
      });
      scheduleReconnect();
    }
  }

  /// Programa una reconexión después de unos segundos, validando que haya conexión Wi-Fi.
  void scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    Timer(Duration(seconds: 3), () {
      Connectivity().checkConnectivity().then((result) {
        if (result == ConnectivityResult.wifi) {
          connectToWebSocket();
        } else {
          setState(() {
            connectionStatus = "Sin conexión Wi-Fi. Esperando reconexión...";
          });
          scheduleReconnect();
        }
      });
    });
  }

  /// Alterna entre modo pantalla completa y modo normal, ajustando la orientación y la UI.
  void toggleFullscreen() {
    setState(() {
      isFullscreen = !isFullscreen;
      if (isFullscreen) {
        // En modo pantalla completa, se cambia a orientación horizontal y se oculta la UI
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      } else {
        // Se vuelve a la orientación vertical y se muestra la UI normal
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  /// Devuelve un widget que muestra un pequeño círculo de color junto al texto del estado.
  Widget buildConnectionIndicator() {
    Color statusColor;
    if (connectionStatus.contains("Conectado")) {
      statusColor = Colors.green;
    } else if (connectionStatus.contains("Conectando")) {
      statusColor = Colors.orange;
    } else if (connectionStatus.contains("Error")) {
      statusColor = Colors.red;
    } else if (connectionStatus.contains("Sin conexión") || connectionStatus.contains("cerrada")) {
      statusColor = Colors.yellow;
    } else {
      statusColor = Colors.grey;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          connectionStatus,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Se utiliza AnimatedSwitcher para una transición suave entre modos
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isFullscreen ? _buildFullscreenView() : _buildVerticalView(),
    );
  }

  Widget _buildFullscreenView() {
    return Scaffold(
      key: const ValueKey("fullscreen"),
      body: GestureDetector(
        onTap: toggleFullscreen,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            // Gradiente sutil de tonos claros
            gradient: const LinearGradient(
              colors: [Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return imageBytes != null
                  ? Image.memory(
                      imageBytes!,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    )
                  : const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalView() {
    return Scaffold(
      key: const ValueKey("vertical"),
      appBar: AppBar(
        title: const Text("Camara WIFI"),
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          // Gradiente sutil minimalista
          gradient: LinearGradient(
            colors: [Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: buildConnectionIndicator(),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GestureDetector(
                onTap: toggleFullscreen,
                child: imageBytes != null
                    ? Image.memory(
                        imageBytes!,
                        gaplessPlayback: true,
                        fit: BoxFit.fitWidth,
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}