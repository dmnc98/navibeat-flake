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
  version = "1.0.7";
  hash = "sha256-p35mqRzkXYeAhigZdeQG02ARRvy1eP6DsiubdG2aGzE=";

  # The full build, not `-slim`: it carries its own JRE *and* its own VLC, which
  # AppRun points at via LD_LIBRARY_PATH/VLC_PLUGIN_PATH, so there is no system
  # libvlc to line up against. Beyond the C runtime the bundle leaves out only
  # libXi/libXtst (wanted by the JDK's libawt_xawt) and, since 1.0.1,
  # libdbus-1/libsystemd — all of them already in appimageTools' default FHS
  # environment.
  src = fetchurl {
    url = "https://github.com/nenadjokic/navibeat-linux/releases/download/v${version}/NaviBeat-linux-x86_64.AppImage";
    inherit hash;
  };

  # Unpacked rather than run straight from the .AppImage so the .desktop entry
  # and icon can be lifted out below.
  #
  # Up to 1.0.0 the bundle shipped its own libdbus-1.so.3 in vlc/, which AppRun
  # prepends to LD_LIBRARY_PATH, so the process mapped that copy *and* the FHS
  # environment's under the same soname. Skia's Linux theme detection (skiko's
  # SystemThemeHelper.getCurrentSystemTheme) dlopens libdbus and calls
  # dbus_bus_get, which locks a process-global mutex living in the other copy
  # and never initialised there — null deref, SIGSEGV in pthread_mutex_lock
  # under internal_bus_get. That path runs only with Appearance set to "System"
  # (Compose's isSystemInDarkTheme), and the choice persists in
  # ~/.config/navibeat/settings.json, so the app died on selection and would
  # not start again. This package removed the bundled copy to work around it.
  #
  # 1.0.1 stopped shipping it (upstream's own fix: "It was carrying its own
  # copy of two system libraries ... They are gone; your system's are used"),
  # which is what broke that `rm`, so it is gone from here too. If a future
  # release bundles libdbus again the crash comes back — the build will not
  # catch it, so check vlc/ if theme selection starts segfaulting.
  contents = appimageTools.extract {
    inherit pname version src;
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
