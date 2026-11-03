import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';



enum _Demo { glossy, starfield, glass, cube, cluster, clayBot,
 jelly, 
urchin, foil, geo, blossom, cubeSphere, capsule, linkChain  }
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
    <Color> [Color.fromARGB(255, 250, 155, 196), Color.fromARGB(255, 240, 204, 232), Color.fromARGB(255, 179, 168, 226)],
    <Color>[Color(0xFF1E8E6A), Color(0xFF34D1BF), Color(0xFF63B7F0)],
  ];

  _Demo _demo = _Demo.glass;
int _palette = 0;
final CharacterController _sprite = CharacterController();
final ClayBotController _bot = ClayBotController();

    static const List<List<_Demo>> _pages = <List<_Demo>>[
    <_Demo>[_Demo.glossy, _Demo.starfield, _Demo.glass],
    <_Demo>[_Demo.cube, _Demo.cluster, _Demo.jelly],
    <_Demo>[ _Demo.urchin, _Demo.foil],
    <_Demo>[_Demo.cubeSphere, _Demo.blossom, _Demo.geo],
    <_Demo>[_Demo.capsule, _Demo.clayBot, _Demo.linkChain],
  ];

  static const Map<_Demo, String> _labels = <_Demo, String>{
    _Demo.glossy: 'Glossy',
    _Demo.starfield: 'Starfield',
    _Demo.glass: 'Glass ring',
    _Demo.cube: 'Cube',
    _Demo.cluster: 'Cluster',
    _Demo.jelly: 'Jelly',
    _Demo.urchin: 'Urchin',
    _Demo.foil: 'Foil ring',
    _Demo.geo:'GeoMorph',
    _Demo.blossom: 'Blossom',
   _Demo.cubeSphere: 'Cube sphere',
   _Demo.capsule: 'Capsule sprite',
   _Demo.clayBot: 'Clay bot',
   _Demo.linkChain: 'Link chain',
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
      _Demo.cluster =>
        ShardSphere(colors: colors, semanticLabel: 'Shard sphere'),
        _Demo.linkChain => LinkChain(colors: colors, semanticLabel: 'Link chain'),
      _Demo.jelly =>
        JellySphere(colors: colors, semanticLabel: 'Jelly sphere'),
      _Demo.clayBot => ClayBot(controller: _bot, walkSpeed: 2.5, colors: [
        Color.lerp(colors[0], const Color.fromARGB(255, 199, 23, 23), 0.5)!,
        Color.lerp(colors[1], const Color.fromARGB(255, 6, 30, 168), 0.5)!,
        Color.lerp(colors[2], const Color(0xFFFFFFFF), 0.5)!,
      ],
      entrance: ClayBotEntrance.dropIn, semanticLabel: 'Clay bot'),
      _Demo.capsule => CapsuleSprite(controller: _sprite, semanticLabel: 'Capsule sprite'),
        _Demo.urchin => Urchin(colors: colors, quality: EffectQuality.high, semanticLabel: 'Urchin'),
        // _Demo.urchin => Urchin(colors: colors, semanticLabel: 'Urchin'),
            _Demo.foil => FoilRing(colors: colors, semanticLabel: 'Foil ring'),
      _Demo.geo => GeoMorph(
          color: colors[0],
          shapeColors: {
            GeoShape.sphere: colors[1],
            GeoShape.octahedron: colors[2],
            GeoShape.torus: colors[1],
          },
          semanticLabel: 'GeoMorph',
        ),
      _Demo.blossom => Blossom(spin: 0, float: 0, tilt: 0, semanticLabel: 'Blossom'),
        _Demo.cubeSphere => CubeSphere(semanticLabel: 'Cube sphere'),
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
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _demoFor(colors)),
              if (_demo == _Demo.clayBot)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      OutlinedButton(onPressed: _bot.blink, child: const Text('Blink')),
                      OutlinedButton(onPressed: _bot.shake, child: const Text('Shake')),
                      OutlinedButton(onPressed: _bot.nod, child: const Text('Nod')),
                      OutlinedButton(onPressed: _bot.bounce, child: const Text('Hop')),
                      OutlinedButton(onPressed: _bot.wave, child: const Text('Wave')),
                      OutlinedButton(onPressed: () => _bot.walkOff(ClayBotSide.right), child: const Text('Walk off')),
                      OutlinedButton(onPressed: () => _bot.walkIn(ClayBotSide.left), child: const Text('Walk in')),
                    ],
                  ),
                ),
              if (_demo == _Demo.capsule)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        OutlinedButton(onPressed: _sprite.blink, child: const Text('Blink')),
                        OutlinedButton(onPressed: _sprite.shake, child: const Text('Shake')),
                        OutlinedButton(onPressed: _sprite.nod, child: const Text('Nod')),
                        OutlinedButton(onPressed: _sprite.bounce, child: const Text('Bounce')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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
