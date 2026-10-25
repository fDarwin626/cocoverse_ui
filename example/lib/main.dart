import 'package:flutter/material.dart';

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
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('Cocoverse UI example')),
      ),
    );
  }
}