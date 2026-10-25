import 'dart:async';
import 'dart:ui';

/// Loads compiled fragment programs and caches them by asset key.
class ShaderLibrary {
  ShaderLibrary._();

  static final Map<String, Future<FragmentProgram>> _cache =
      <String, Future<FragmentProgram>>{};

  /// Loads the program at [assetKey], for example
  /// `packages/cocoverse_ui/shaders/starfield_sphere.frag`.
  ///
  /// The result is cached, so each program is only loaded once. A failed load
  /// is not cached, so a later call can try again.
  static Future<FragmentProgram> load(String assetKey) {
    return _cache.putIfAbsent(assetKey, () {
      final future = FragmentProgram.fromAsset(assetKey);
      unawaited(
        future.then<void>(
          (_) {},
          onError: (Object _) {
            _cache.remove(assetKey);
          },
        ),
      );
      return future;
    });
  }
}