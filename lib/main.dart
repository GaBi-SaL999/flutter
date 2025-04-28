// main.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math; // Para usar math.pi
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Importa la pantalla de configuración
import 'config_network_page.dart';

void main() => runApp(
      ShowCaseWidget(
        builder: (context) => MyApp(),
      ),
    );

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkTheme = true;

  void _toggleTheme() {
    setState(() {
      _isDarkTheme = !_isDarkTheme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cámara WIFI',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[200],
        appBarTheme: AppBarTheme(
          color: Colors.blue,
          elevation: 0,
          titleTextStyle: const TextStyle(
              color: Colors.black87, fontSize: 20, fontWeight: FontWeight.w500),
          iconTheme: const IconThemeData(color: Colors.black87),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1F1F1F),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          color: Color(0xFF1F1F1F),
          elevation: 0,
          titleTextStyle: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      themeMode: _isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      home: MyHomePage(
        toggleTheme: _toggleTheme,
        isDarkTheme: _isDarkTheme,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkTheme;
  const MyHomePage(
      {Key? key, required this.toggleTheme, required this.isDarkTheme})
      : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  // Dirección del WebSocket
  final String wsUrl = 'ws://192.168.4.1:81';
  late WebSocketChannel channel;
  Uint8List? imageBytes;
  String connectionStatus = "Conexión no iniciada";
  bool isFullscreen = false;

  // Para el efecto rotacional 180° de la cámara.
  bool rotateCamera = false;

  bool _isReconnecting = false;
  Timer? _checkTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Llaves globales para el tutorial
  final GlobalKey _keyHelpButton = GlobalKey();
  final GlobalKey _keyConnectionIndicator = GlobalKey();
  final GlobalKey _keyImageScreen = GlobalKey();

  int batteryPercentage = 100;
  bool isSensorEnabled = true;
  bool isCharging = false;

  final List<String> tutorialDescriptions = [
    "Introducción:\n\nBienvenido a Cámara WIFI.\n• Visualiza la transmisión en vivo de tu cámara.\n• Conéctate a la red 'CAMARA'.\n• Asegúrate de que la cámara esté encendida.",
    "Conexión:\n\n• La barra superior te indica si la conexión es estable:\n   - Verde: Conexión estable.\n   - Otros colores: Revisa tu WiFi o reinicia la app.",
    "Transmisión:\n\n• La vista central muestra la transmisión en vivo.\n• Toca dos veces la imagen para activar el modo pantalla completa y disfrutar en detalle.",
    "Consejo:\n\n• Utiliza la app en un entorno con buena señal WiFi.\n• Si hay interrupciones, verifica la cámara y la red.",
    "Batería:\n\nEl icono indica el nivel de carga:\n• Verde: Alta\n• Amarillo: Media\n• Rojo: Baja",
    "Sensor de iluminación:\n\nActiva el sensor con el switch.\n• Encendido: Los LEDs se activan en la oscuridad.\n• Apagado: Los LEDs permanecen apagados."
  ];
  int currentStep = 0;
  bool isTutorialActive = false;

  @override
  void initState() {
    super.initState();

    WakelockPlus.enable();
    checkNetworkAndCamera();

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.wifi) {
        checkNetworkAndCamera();
      } else {
        if (!mounted) return;
        setState(() {
          connectionStatus =
              "No conectado a WiFi. Conéctate a la red CAMARA";
          imageBytes = null;
        });
      }
    });

    _checkTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!connectionStatus.contains("Conectado")) {
        checkNetworkAndCamera();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      bool tutorialShown = prefs.getBool('tutorialShown') ?? false;
      if (!tutorialShown) {
        _startTutorial();
        prefs.setBool('tutorialShown', true);
      }
    });

    // Inicializamos el canal WebSocket y nos conectamos
    channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    connectToWebSocket();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _checkTimer?.cancel();
    _connectivitySubscription?.cancel();
    channel.sink.close();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startTutorial() {
    setState(() {
      currentStep = 0;
      isTutorialActive = true;
    });
  }

  void _nextStep() {
    if (currentStep < tutorialDescriptions.length - 1) {
      setState(() {
        currentStep++;
      });
    } else {
      setState(() {
        isTutorialActive = false;
      });
    }
  }

  void _prevStep() {
    if (currentStep > 0) {
      setState(() {
        currentStep--;
      });
    }
  }

  Future<void> checkNetworkAndCamera() async {
    ConnectivityResult connectivityResult =
        await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.wifi) {
      if (!mounted) return;
      setState(() {
        connectionStatus =
            "No conectado a WiFi. Conéctate a la red CAMARA";
        imageBytes = null;
      });
      return;
    }

    try {
      Socket socket = await Socket.connect("192.168.4.1", 81,
          timeout: const Duration(seconds: 2));
      socket.destroy();
      if (!mounted) return;
      connectToWebSocket();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        connectionStatus =
            "No se puede acceder a la cámara. Conéctate a la red CAMARA";
        imageBytes = null;
      });
    }
  }

  Future<void> connectToWebSocket() async {
    if (!mounted) return;
    setState(() {
      connectionStatus = "Conectando a la Cámara...";
    });

    try {
      _isReconnecting = false;
      channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      if (!mounted) return;
      setState(() {
        connectionStatus = "Conectado con la Cámara";
      });

      channel.stream.listen(
        (data) {
          if (data is Uint8List) {
            if (!mounted) return;
            setState(() {
              imageBytes = data;
            });
          } else if (data is String) {
            debugPrint('Mensaje recibido: $data');
            try {
              final Map<String, dynamic> message = jsonDecode(data);
              if (message.containsKey('percentage')) {
                setState(() {
                  batteryPercentage = (message['percentage'] as num).toInt();
                });
              } else if (message.containsKey('bateria')) {
                setState(() {
                  batteryPercentage = (message['bateria'] as num).toInt();
                });
              }
            if (message.containsKey('charging')) {
              setState(() {
                isCharging = message['charging'] as bool;
              });
            }

            } catch (e) {
              debugPrint("Error al decodificar JSON: $e");
            }
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            connectionStatus = "Error: $error";
            imageBytes = null;
          });
          scheduleReconnect();
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            connectionStatus =
                "Conexión cerrada. Intentando reconectar...";
            imageBytes = null;
          });
          scheduleReconnect();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        connectionStatus = "Error al conectar: $e";
        imageBytes = null;
      });
      scheduleReconnect();
    }
  }

  void scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    Timer(const Duration(seconds: 3), () {
      Connectivity().checkConnectivity().then((result) {
        if (result == ConnectivityResult.wifi) {
          checkNetworkAndCamera();
        } else {
          if (!mounted) return;
          setState(() {
            connectionStatus =
                "Sin conexión WiFi. Espera: Conéctate a la red CAMARA";
            imageBytes = null;
          });
          scheduleReconnect();
        }
      });
    });
  }

  void toggleFullscreen() {
    setState(() {
      isFullscreen = !isFullscreen;
      if (isFullscreen) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  // Retorna la transformación para rotar la imagen en 180° si rotateCamera es true
  Matrix4 _buildImageTransform() {
    Matrix4 transform = Matrix4.identity();
    if (rotateCamera) {
      transform.rotateX(math.pi);
      transform.rotateY(math.pi);
    }
    return transform;
  }

  Widget buildConnectionIndicator() {
    String displayText;
    Color statusColor;
    if (connectionStatus.contains("Conectado")) {
      statusColor = Colors.green;
      displayText = "Conectado";
    } else if (connectionStatus.contains("Conectando")) {
      statusColor = Colors.orange;
      displayText = "Conectando…";
    } else if (connectionStatus.contains("Error")) {
      statusColor = Colors.red;
      displayText = "Error";
    } else if (connectionStatus.contains("No conectado") ||
        connectionStatus.contains("Sin conexión")) {
      statusColor = Colors.yellow;
      displayText = "No Conectado";
    } else {
      statusColor = Colors.grey;
      displayText = "Conéctate a la red CAMARA";
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:
            Theme.of(context).appBarTheme.backgroundColor ?? Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: statusColor, size: 12),
          const SizedBox(width: 6),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color:
                  Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.signal_wifi_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Transmisión interrumpida',
            style: TextStyle(fontSize: 20, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialDialog() {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildTutorialAnimation(),
          const SizedBox(height: 10),
          Text(
            "Paso ${currentStep + 1} de ${tutorialDescriptions.length}",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tutorialDescriptions[currentStep],
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (currentStep > 0)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                  ),
                  onPressed: _prevStep,
                  child: const Text("Anterior"),
                )
              else
                const SizedBox(width: 80),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: _nextStep,
                child: Text(
                  currentStep == tutorialDescriptions.length - 1
                      ? "Finalizar"
                      : "Siguiente",
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () {
              setState(() {
                isTutorialActive = false;
              });
            },
            child: const Text("Omitir tutorial",
                style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget buildTutorialAnimation() {
    IconData icon;
    switch (currentStep) {
      case 0:
        icon = Icons.info_outline;
        break;
      case 1:
        icon = Icons.wifi;
        break;
      case 2:
        icon = Icons.camera_alt;
        break;
      case 3:
        icon = Icons.lightbulb_outline;
        break;
      case 4:
        icon = Icons.battery_charging_full;
        break;
      case 5:
        icon = Icons.toggle_on;
        break;
      default:
        icon = Icons.info;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 2 * math.pi),
      duration: const Duration(seconds: 2),
      builder: (context, angle, child) {
        return Transform.rotate(
          angle: angle,
          child: Icon(icon, size: 100, color: Colors.blueAccent),
        );
      },
    );
  }

  Widget buildBatteryIndicator() {
    IconData batteryIcon;
    Color batteryColor;

    // Si está cargando, mostramos el icono de carga (por ejemplo, con color azul)
    if (isCharging) {
      batteryIcon = Icons.battery_charging_full;
      batteryColor = Colors.purpleAccent;
    } else if (batteryPercentage >= 75) {
      batteryIcon = Icons.battery_full;
      batteryColor = Colors.green;
    } else if (batteryPercentage >= 50) {
      batteryIcon = Icons.battery_3_bar;
      batteryColor = Colors.yellow;
    } else if (batteryPercentage >= 25) {
      batteryIcon = Icons.battery_2_bar;
      batteryColor = Colors.orange;
    } else {
      batteryIcon = Icons.battery_alert;
      batteryColor = Colors.red;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(batteryIcon, color: batteryColor, size: 30),
        const SizedBox(width: 8),
        Text(
          "$batteryPercentage%",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: batteryColor,
          ),
        ),
      ],
    );
  }


  Widget _buildFullscreenView() {
    return Scaffold(
      key: const ValueKey("fullscreen"),
      body: GestureDetector(
        onTap: toggleFullscreen,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF121212), Color(0xFF1F1F1F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return imageBytes != null
                      ? Transform(
                          alignment: Alignment.center,
                          transform: _buildImageTransform(),
                          child: Image.memory(
                            imageBytes!,
                            gaplessPlayback: true,
                            fit: BoxFit.contain,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          ),
                        )
                      : _buildPlaceholder();
                },
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Rot:",
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                    Switch(
                      value: rotateCamera,
                      onChanged: (value) {
                        setState(() {
                          rotateCamera = value;
                        });
                      },
                      activeColor: Colors.blue,
                      inactiveThumbColor: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Sensor:",
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                    Switch(
                      value: isSensorEnabled,
                      onChanged: (value) {
                        setState(() {
                          isSensorEnabled = value;
                        });
                        if (isSensorEnabled) {
                          channel.sink
                              .add(jsonEncode({"ledControl": "enable"}));
                          print("Sensor habilitado: Los LEDs se encenderán en la oscuridad.");
                        } else {
                          channel.sink
                              .add(jsonEncode({"ledControl": "disable"}));
                          print("Sensor deshabilitado: Los LEDs estarán siempre apagados.");
                        }
                      },
                      activeColor: Colors.blue,
                      inactiveThumbColor: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 80,
              left: 20,
              child: buildBatteryIndicator(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isFullscreen ? _buildFullscreenView() : _buildVerticalView(),
    );
  }

  Widget _buildVerticalView() {
    return Scaffold(
      key: const ValueKey("vertical"),
      appBar: AppBar(
        title: const Text("Cámara WIFI"),
        actions: [
          // Botón para ver el tutorial
          Showcase(
            key: _keyHelpButton,
            description:
                "Pulsa este botón para acceder a la guía de la aplicación. Puedes volver a verla cuando lo necesites.",
            child: IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: "Ver la guía",
              onPressed: _startTutorial,
            ),
          ),
          // Modo de tema: claro/oscuro
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Switch(
              value: widget.isDarkTheme,
              onChanged: (value) => widget.toggleTheme(),
              activeColor: Colors.white,
              inactiveThumbColor: Colors.black,
            ),
          ),
        ],
      ),
      // Drawer para configuraciones adicionales
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: const Text(
                'Configuración',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('Configurar Red'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ConfigNetworkPage(channel: channel),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).scaffoldBackgroundColor,
                    Theme.of(context).primaryColorDark,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card del indicador de conexión, envuelto en Showcase
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Showcase(
                          key: _keyConnectionIndicator,
                          description:
                              "Esta barra muestra el estado de tu conexión. La luz verde indica que la transmisión se recibe correctamente.",
                          child: buildConnectionIndicator(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Tarjeta principal para la vista de la cámara
                    Expanded(
                      child: Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Showcase(
                          key: _keyImageScreen,
                          description:
                              "Esta es la vista en vivo de la cámara. Toca dos veces la imagen para cambiar a modo pantalla completa y disfrutar de una experiencia más inmersiva.",
                          child: GestureDetector(
                            onDoubleTap: toggleFullscreen,
                            child: imageBytes != null
                                ? Transform(
                                    alignment: Alignment.center,
                                    transform: _buildImageTransform(),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Image.memory(
                                        imageBytes!,
                                        gaplessPlayback: true,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  )
                                : _buildPlaceholder(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Indicador de batería y switch para la rotación de la cámara
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        connectionStatus.contains("Conectado")
                                ? buildBatteryIndicator()
                                : Container(),
                        Row(
                          children: [
                            const Text(
                              "Rotación de cámara",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Switch(
                              value: rotateCamera,
                              onChanged: (value) {
                                setState(() {
                                  rotateCamera = value;
                                });
                              },
                              activeColor: Colors.blue,
                              inactiveThumbColor: Colors.grey,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Card para controlar el sensor de iluminación
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Column(
                          children: [
                            const Text(
                              "Sensor de Iluminación",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Switch(
                              value: isSensorEnabled,
                              onChanged: (value) {
                                setState(() {
                                  isSensorEnabled = value;
                                });
                                if (isSensorEnabled) {
                                  channel.sink.add(
                                      jsonEncode({"ledControl": "enable"}));
                                  print(
                                      "Sensor habilitado: Los LEDs se encenderán en la oscuridad.");
                                } else {
                                  channel.sink.add(
                                      jsonEncode({"ledControl": "disable"}));
                                  print(
                                      "Sensor deshabilitado: Los LEDs estarán siempre apagados.");
                                }
                              },
                              activeColor: Colors.blue,
                              inactiveThumbColor: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            // Muestra el diálogo tutorial si está activo
            if (isTutorialActive)
              Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildTutorialDialog(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}