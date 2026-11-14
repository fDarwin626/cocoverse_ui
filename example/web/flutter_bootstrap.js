{{flutter_js}}
{{flutter_build_config}}

// The website runs one Flutter engine and gives every phone its own view.
_flutter.loader.load({
  config: {
    entrypointBaseUrl: "/flutter/",
    assetBase: "/flutter/",
    canvasKitBaseUrl: "/flutter/canvaskit/",
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const engine = await engineInitializer.initializeEngine({
      multiViewEnabled: true,
      assetBase: "/flutter/",
      canvasKitBaseUrl: "/flutter/canvaskit/",
    });
    const app = await engine.runApp();
    window.__cocoverseFlutter = app;
    window.dispatchEvent(new Event("cocoverse-flutter-ready"));
  },
});



// --- STANDARD DEFAULT LOADER FOR LOCAL PREVIEW ---
_flutter.loader.load({});