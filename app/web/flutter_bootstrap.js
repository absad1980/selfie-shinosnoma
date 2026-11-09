{{flutter_js}}
{{flutter_build_config}}

// Run the app inside the phone frame (#phone) instead of the whole browser window.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.querySelector('#phone'),
    });
    await appRunner.runApp();
  },
});
