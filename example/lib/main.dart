import 'package:flutter/material.dart';

import 'gallery.dart';

void main() => runApp(const ExampleApp());

/// Root of the Cocoverse UI example app.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cocoverse UI example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color.fromARGB(255, 168, 167, 167),
      ),
      home: const Gallery(),
    );
  }
}