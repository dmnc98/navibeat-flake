{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "navibeat";

  # `version` and `hash` are rewritten in place by
  # .github/workflows/bump-navibeat.yml. Keep both on their own line, in this
  # exact `name = "value";` shape — the workflow's sed patterns anchor on it.
  version = "1.0.0";
  hash = "sha256-7JyZhbeJ/kdimxHK49oNw8f3kL1lRUBe9cE33qyFHLg=";

  # The full build, not `-slim`: it carries its own JRE *and* its own VLC, which
  # AppRun points at via LD_LIBRARY_PATH/VLC_PLUGIN_PATH, so there is no system
  # libvlc to line up against. The only libraries the bundle leaves out are
  # libXi/libXrender/libXtst, wanted by the JDK's libawt_xawt, and those are
  # already in appimageTools' default FHS environment.
  src = fetchurl {
    url = "https://github.com/nenadjokic/navibeat-linux/releases/download/v${version}/NaviBeat-linux-x86_64.AppImage";
    inherit hash;
  };

  # Unpacked rather than run straight from the .AppImage: the .desktop entry
  # and icon are lifted out below, and one bundled library has to go first.
  #
  # AppRun prepends the bundle's own vlc/ to LD_LIBRARY_PATH, and that
  # directory ships a libdbus-1.so.3 alongside VLC's other dependencies. The
  # FHS environment supplies a libdbus of its own, so the process ends up
  # with *two* copies of the same soname mapped at once. Skia's Linux theme
  # detection (skiko's SystemThemeHelper.getCurrentSystemTheme) then dlopens
  # libdbus and calls dbus_bus_get, which locks a process-global mutex that
  # lives in the other copy and was never initialised there — so it
  # dereferences null and the JVM dies with SIGSEGV in pthread_mutex_lock,
  # under internal_bus_get. That path runs only when Appearance is set to
  # "System" (Compose's isSystemInDarkTheme), which is why the app crashes
  # the moment you pick it and then will not start again: the choice is
  # already persisted in ~/.config/navibeat/settings.json, so every
  # subsequent launch walks straight back into it.
  #
  # Dropping the bundle's copy leaves exactly one libdbus in the process.
  # Both VLC and skiko bind to the FHS one; the soname is identical and
  # libdbus-1 has been ABI-stable across the 1.x series, so VLC is unaffected.
  #
  # Re-check this `rm` on every bump — if upstream stops shipping its own
  # libdbus, the rm fails loudly and can just be dropped.
  contents = appimageTools.extract {
    inherit pname version src;
    postExtract = ''
      rm "$out/vlc/libdbus-1.so.3"
    '';
  };
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = contents;

  # The shipped entry says Exec=NaviBeat/Icon=NaviBeat; the wrapper installs
  # the binary as `navibeat`. The icon is a single 1024x1024 PNG, which is
  # not a size hicolor indexes, so it goes in share/pixmaps — always searched
  # as a fallback — rather than a hicolor bucket that nothing would look in.
  extraInstallCommands = ''
    install -Dm444 ${contents}/NaviBeat.desktop $out/share/applications/${pname}.desktop
    install -Dm444 ${contents}/NaviBeat.png $out/share/pixmaps/${pname}.png
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=NaviBeat' 'Exec=${pname}' \
      --replace-fail 'Icon=NaviBeat' 'Icon=${pname}'
  '';

  meta = {
    description = "Navidrome and OpenSubsonic music client";
    longDescription = ''
      NaviBeat is a native (Kotlin/Compose) Navidrome and OpenSubsonic client.
      It is closed source, so this packages upstream's AppImage release rather
      than building from source. Pass `--tui` to get the terminal client
      instead of the window.
    '';
    homepage = "https://navibeat.app/linux";
    downloadPage = "https://github.com/nenadjokic/navibeat-linux/releases";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
