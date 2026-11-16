# Changelog

All notable changes to `cocoverse_ui` are written here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows [Semantic Versioning](https://semver.org/).

## 0.0.2 - 2026-11-15

The first release of CocoVerse UI: a free collection of animated 3D and particle effects for Flutter. Each effect is a single widget that you place in your app, with no setup beyond the install. They are drawn with Dart painters and fragment shaders and tuned to stay smooth on phones.

### Added

**Spheres and solids**

- `GlossySphere`: a glossy sphere with flowing bands of colour and a bright rim.
- `StarfieldSphere`: a clear glass sphere with small stars drifting inside it.
- `JellySphere`: a glossy sphere that squashes like jelly when you press it.
- `ShardSphere`: a sphere of prism-shaped shards that grow and light up near your finger.
- `CubeSphere`: thousands of small glossy cubes on a sphere that tumble and breathe in a wave.
- `ParticleCube`: a cube built from particles.
- `GeoMorph`: a solid that morphs between a box, a sphere, an octahedron and a torus.
- `Urchin`: a glass-bright sea urchin with spikes that slowly morph.

**Rings and chains**

- `GlassRing`: a turning ring of clear glass that bends the text behind it.
- `FoilRing`: a twisting ring covered in wavy foil brush strokes.
- `LinkChain`: interlocked links hanging on rope physics that you can tilt, shake and grab, in metallic or cartoon finish.

**Characters and creatures**

- `CapsuleSprite`: a sprite with pill eyes sealed in a glass capsule, watching your finger.
- `ClayBot`: a small clay robot with a screen for a face that follows your pointer, hops and waves.
- `Mito`: a hovering robot on three rings of light that glides to follow your pointer.
- `Pisces`: a goldfish that swims on its own and follows your finger.
- `Gaze`: a wet, glossy eyeball that follows your finger or cursor anywhere on the screen. A `GazeController` can make it look at a point or a widget, for example a password field.

**Loaders and progress**

- `Crossfold`: three bars that fold out of a stack into a cross, in polished metal or matte plastic, with one colour. It has no text of its own, so you put your own text wherever you want.
- `Halo`: rings turning inside each other like a gyroscope, as a loader or progress ring.
- `Infiloop`: glowing fibres twisting round an infinity loop, in three colours. It can also be a loader.
- `Plush`: a plush, furry effect with a progress mode and an optional widget in the middle.

**Scenes and backdrops**

- `Blossom`: a lotus cast in pink resin and lit from inside, that opens from a bud.
- `Fireworks`: a firework show with an optional animated title and subtitle.
- `Hourglass`: an hourglass of glowing gradient rings, made to sit behind your app.
- `Meteor`: a cracked meteor with glowing seams, hanging in a swarm of shapes and rock chips.
- `Moonbloom`: a night scene of a blossoming tree with petals drifting down.
- `Timeline`: photos that flip over tile by tile, like a split-flap board.

**Shared across the package**

- Every effect fills the space its parent gives it, so you size it with a `SizedBox` or any other layout widget.
- Most effects take a `quality` setting (`EffectQuality.low`, `medium` or `high`) so you can trade detail for speed on slower phones.
- Most effects take a `paused` flag and a `speed` setting, and many take colours so that they fit your brand.
- `EffectController` lets your code replay an effect from the start with `reset`.
- Character effects take a `CharacterController` (blink, shake, nod, bounce) and a `mood`. `ClayBot`, `Mito` and `Pisces` also have their own controllers for actions such as walking, flying and swimming.
- Every effect takes a `semanticLabel`. Leave it null and the effect is treated as decoration by screen readers.
- Effects that follow touch listen to the whole screen, so they keep looking at your finger even when it is outside the widget.

### Notes

- This is an early `0.0.x` release. The names and options of the effects can still change before `1.0.0`, and every change will be listed here.
- Effects drawn by fragment shaders (the glass, metal and eye effects) are bundled with the package. You do not need to list them in your own `pubspec.yaml`.
- The effects are made to be decoration and feedback, not to carry meaning on their own. Keep your own text or labels next to them.

### Licence

Released under the MIT licence. The code is open source and free to copy, clone, fork and modify. See `LICENSE` for the full text.