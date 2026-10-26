import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';


enum _Demo { glossy, starfield, glass, cube, cluster, jelly }




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


    static const List<List<_Demo>> _pages = <List<_Demo>>[
    <_Demo>[_Demo.glossy, _Demo.starfield, _Demo.glass],
    <_Demo>[_Demo.cube, _Demo.cluster, _Demo.jelly],
  ];

  static const Map<_Demo, String> _labels = <_Demo, String>{
    _Demo.glossy: 'Glossy',
    _Demo.starfield: 'Starfield',
    _Demo.glass: 'Glass ring',
    _Demo.cube: 'Cube',
    _Demo.cluster: 'Cluster',
    _Demo.jelly: 'Jelly',
  };

  int _page = 0;

  void _goToPage(int page) {
    setState(() {
      _page = page;
      _demo = _pages[page].first;
    });
  }


  Widget _demoFor(List<Color> colors) {
    return switch (_demo) {
         _Demo.cube =>
        ParticleCube(colors: colors, semanticLabel: 'Particle cube'),
      _Demo.cluster => const _ComingSoon('Cluster'),
      _Demo.jelly => const _ComingSoon('Jelly sphere'),
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
              segments: [
                for (final demo in _pages[_page])
                  ButtonSegment(value: demo, label: Text(_labels[demo]!)),
              ],
              selected: {_demo},
              onSelectionChanged: (selection) =>
                  setState(() => _demo = selection.first),
            ),
          ),
                    Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_page + 1} / ${_pages.length}'),
              IconButton(
                onPressed: _page < _pages.length - 1
                    ? () => _goToPage(_page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
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


class _ComingSoon extends StatelessWidget {
  const _ComingSoon(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$name is coming next'));
  }
}