import 'package:flutter/material.dart';
import 'package:cocoverse_ui/cocoverse_ui.dart';

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
      home: Scaffold(
        appBar: AppBar(title: const Text('Cocoverse UI example')),
        body: const Column(
          children: [
            Expanded(
              child: GlossySphere(semanticLabel: 'Glossy sphere'),
            ),
            Expanded(
              child: StarfieldSphere(semanticLabel: 'Starfield sphere'),
            ),
          ],
        ),
      ),
    );
  }
}