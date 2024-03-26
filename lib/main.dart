
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:object_detection_app/ui/home_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter is initialized
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Live Object Detection TFLite',
    theme: ThemeData(
      primarySwatch: Colors.blue,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    ),
    home: const HomeView(),
  );
}


//0-90 Degrees x pos y po , top right quadrant
//90-180 Degrees x pos y po , top left quadrant
//180-270 Degrees x pos y po , bottom left quadrant
//270-360 Degrees x pos y po , bottom right quadrant