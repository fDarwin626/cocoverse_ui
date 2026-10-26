import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';

enum _Demo { glossy, starfield, glass }

/// Shows one effect at a time, with a few colour choices.
class Gallery extends StatefulWidget {
  /// Creates the gallery.
  const Gallery({super.key});

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF7B5CFF), Color(0xFF46D9E8), Color(0xFFFF6FAE)],
    <Color>[Color(0xFFFF8A1F), Color(0xFFFF3D6E), Color(0xFFFFD45E)],
    <Color>[Color(0xFF1E8E6A), Color(0xFF34D1BF), Color(0xFF63B7F0)],
  ];

  _Demo _demo = _Demo.glass;
  int _palette = 0;

  Widget _demoFor(List<Color> colors) {
    return switch (_demo) {
      _Demo.glossy =>
        GlossySphere(colors: colors, semanticLabel: 'Glossy sphere'),
      _Demo.starfield =>
        StarfieldSphere(colors: colors, semanticLabel: 'Starfield sphere'),
      _Demo.glass => GlassRing(
          tint: Color.lerp(colors[1], const Color(0xFFFFFFFF), 0.5)!,
          backdropText: 'GLASS\nRING',
          semanticLabel: 'Glass ring',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[_palette];
    return Scaffold(
      appBar: AppBar(title: const Text('Cocoverse UI example')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<_Demo>(
              segments: const [
                ButtonSegment(value: _Demo.glossy, label: Text('Glossy')),
                ButtonSegment(value: _Demo.starfield, label: Text('Starfield')),
                ButtonSegment(value: _Demo.glass, label: Text('Glass ring')),
              ],
              selected: {_demo},
              onSelectionChanged: (selection) =>
                  setState(() => _demo = selection.first),
            ),
          ),
          Expanded(child: _demoFor(colors)),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _palettes.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _palette = i),
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: _palettes[i]),
                        border: Border.all(
                          color: i == _palette
                              ? const Color(0xFFFFFFFF)
                              : const Color.fromARGB(0, 71, 0, 252),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}