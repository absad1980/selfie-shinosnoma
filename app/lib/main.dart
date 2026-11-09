import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'theme.dart';
import 'screens/splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // credit for the bundled face and person models (Apache License 2.0)
  LicenseRegistry.addLicense(() => Stream.value(const LicenseEntryWithLineBreaks(['MediaPipe models (face detection, face mesh, selfie segmentation)'],
      'Copyright Google LLC.\n\nLicensed under the Apache License, Version 2.0. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0\n\nUnless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.')));
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));
  final st = AppState();
  st.housekeeping();
  runApp(AppScope(notifier: st, child: const SelfieApp()));
}

/// Makes the single app state available to every screen.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required super.notifier, required super.child});
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class SelfieApp extends StatelessWidget {
  const SelfieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'СЭЛФИ ШИНОСНОМА',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}
