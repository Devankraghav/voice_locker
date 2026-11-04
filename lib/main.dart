import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_intent_plus/android_intent.dart'; // New import

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'voice_locker_channel',
    'Voice Locker Service',
    description: 'Listens for your lock command in the background',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'voice_locker_channel',
      initialNotificationTitle: 'Voice Locker',
      initialNotificationContent: 'Listening for command...',
      foregroundServiceTypes: [AndroidForegroundType.microphone],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

// --- The Background Isolate Entry Point ---
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final stt.SpeechToText speech = stt.SpeechToText();
  Timer? speechTimer; // We now store the timer so we can kill it

  final prefs = await SharedPreferences.getInstance();
  String targetCommand = prefs.getString('lock_command') ?? "lock my phone";

  // 1. Properly handle the stop command from the UI
  service.on('stopService').listen((event) {
    speechTimer?.cancel(); // Kill the loop
    speech.stop();         // Stop the mic
    service.stopSelf();    // Terminate the background service completely
  });

  // 2. Listen for password updates
  service.on('update_command').listen((event) {
    if (event != null && event['command'] != null) {
      targetCommand = event['command'];
    }
  });

  // 3. The safe background listening loop
  // 3. The safe background listening loop (UPDATED)
  speechTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
    if (!speech.isListening) {
      bool available = await speech.initialize(
        onError: (e) => debugPrint("Speech error: $e"),
      );

      if (available) {
        speech.listen(
          onResult: (val) async {
            String words = val.recognizedWords.toLowerCase();

            // ---> NEW: Live Notification Debugger <---
            // This will update the notification to show exactly what the app is hearing.
            final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
            notifications.show(
                id: 888,
                title: 'Voice Locker',
                body: 'Heard: $words',
                notificationDetails: const NotificationDetails(
                    android: AndroidNotificationDetails('voice_locker_channel', 'Voice Locker', importance: Importance.low)
                )
            );

            if (words.contains(targetCommand)) {
              // ---> NEW: Explicit Intent Fix <---
              // Android 8+ requires the exact package name for background broadcasts.
              // NOTE: If you changed your package name when creating the project,
              // replace 'com.example.voice_locker' with your actual package name.
              final intent = const AndroidIntent(
                action: 'com.voice_locker.LOCK_SCREEN',
                package: 'com.example.voice_locker',
              );
              await intent.sendBroadcast();

              speech.stop();
            }
          },
          listenOptions: stt.SpeechListenOptions(listenMode: stt.ListenMode.dictation),
        );
      }
    }
  });
}

// --- Flutter UI ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const VoiceLockerApp());
}

class VoiceLockerApp extends StatelessWidget {
  const VoiceLockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Locker',
      theme: ThemeData(primarySwatch: Colors.red),
      home: const LockerHome(),
    );
  }
}

class LockerHome extends StatefulWidget {
  const LockerHome({super.key});

  @override
  State<LockerHome> createState() => _LockerHomeState();
}

class _LockerHomeState extends State<LockerHome> {
  static const platformAdmin = MethodChannel('com.voice_locker/admin');
  final TextEditingController _commandController = TextEditingController();
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.microphone, Permission.notification].request();
    try {
      await platformAdmin.invokeMethod('requestAdmin');
    } catch (e) {
      debugPrint("Admin request failed: $e");
    }
  }

  Future<void> _checkServiceStatus() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isRunning = isRunning;
      _commandController.text = prefs.getString('lock_command') ?? "lock my phone";
    });
  }

  Future<void> _saveCommand() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lock_command', _commandController.text.toLowerCase());

    FlutterBackgroundService().invoke('update_command', {'command': _commandController.text.toLowerCase()});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Voice command updated!")),
    );
  }

  Future<void> _toggleService() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();

    if (isRunning) {
      service.invoke("stopService"); // This now correctly triggers the kill switch
      setState(() => _isRunning = false);
    } else {
      await service.startService();
      setState(() => _isRunning = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Locker - Background Mode')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _commandController,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Lock Command'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _saveCommand, child: const Text("Save Command")),
            const Spacer(),
            Text(
              _isRunning ? "Listening in background..." : "Service Stopped",
              style: TextStyle(color: _isRunning ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 20),
            FloatingActionButton.extended(
              onPressed: _toggleService,
              backgroundColor: _isRunning ? Colors.red : Colors.green,
              label: Text(_isRunning ? "Stop Background Protection" : "Start Background Protection"),
              icon: Icon(_isRunning ? Icons.stop : Icons.shield),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}