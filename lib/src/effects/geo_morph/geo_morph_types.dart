/// The solids [GeoMorph] can show.
enum GeoShape {
  /// A cube.
  box,

  /// A ball.
  sphere,

  /// Two pyramids joined at their bases.
  octahedron,

  /// A ring, like a doughnut.
  torus,
}

/// One condition for [GeoMorph.rules]: show [shape] while [when] returns true.
///
/// The rules are checked in order and the first one that returns true decides
/// the shape. A rule that throws counts as false.
class GeoMorphRule {
  /// Creates a rule.
  const GeoMorphRule({required this.shape, required this.when});

  /// The shape to show while this rule matches.
  final GeoShape shape;

  /// The condition. It should be quick, because it is called about once a
  /// second.
  final bool Function() when;
}