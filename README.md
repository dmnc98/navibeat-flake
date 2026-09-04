# navibeat-flake

A Nix flake packaging [NaviBeat](https://navibeat.app/linux) — a native
(Kotlin/Compose) [Navidrome](https://www.navidrome.org/) and OpenSubsonic
client — from upstream's Linux AppImage.

NaviBeat is closed source, so it is not in nixpkgs and cannot be. This wraps
the published AppImage with `appimageTools` instead of building from source.

The packaged version tracks upstream automatically: a scheduled workflow polls
[`nenadjokic/navibeat-linux`](https://github.com/nenadjokic/navibeat-linux)
every six hours, and every new upstream release becomes a verified build,
a commit on `main`, and a matching `vX.Y.Z` release here.

## Usage

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    navibeat = {
      url = "github:dmnc98/navibeat-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Then add the package to a NixOS `environment.systemPackages` or a Home Manager
`home.packages`:

```nix
home.packages = [ inputs.navibeat.packages.${pkgs.system}.default ];
```

NaviBeat is unfree, so `nixpkgs.config.allowUnfree` (or an
`allowUnfreePredicate` covering it) has to be set in the consuming config.

There is also an overlay, if you would rather reach it as `pkgs.navibeat`:

```nix
nixpkgs.overlays = [ inputs.navibeat.overlays.default ];
```

Or run it without installing:

```sh
nix run github:dmnc98/navibeat-flake
```

Pass `--tui` to get the terminal client instead of the window.

## What this flake handles

Two things the plain AppImage gets wrong under Nix, both documented at the
relevant code in [`navibeat.nix`](navibeat.nix):

- **The bundled `libdbus-1.so.3` is removed.** AppRun prepends the bundle's own
  `vlc/` to `LD_LIBRARY_PATH`, which puts a second copy of libdbus in the
  process alongside the FHS environment's. Skia's theme detection then dlopens
  libdbus and locks a process-global mutex living in the *other* copy, and the
  JVM dies with a SIGSEGV in `pthread_mutex_lock`. That path only runs with
  Appearance set to "System" — and since the setting is persisted, the app
  crashes the moment you pick it and never starts again.
- **The `.desktop` entry and icon are rewritten.** Upstream ships
  `Exec=NaviBeat`/`Icon=NaviBeat`, but the wrapper installs the binary as
  `navibeat`. The icon is a single 1024x1024 PNG, which is not a size hicolor
  indexes, so it goes in `share/pixmaps` rather than a hicolor bucket nothing
  would look in.

This packages the full AppImage, not `-slim`: the full build carries its own JRE
*and* its own VLC, which AppRun points at via `LD_LIBRARY_PATH` and
`VLC_PLUGIN_PATH`, so there is no system libvlc to line up against. The only
libraries the bundle leaves out are libXi/libXrender/libXtst, wanted by the
JDK's `libawt_xawt`, and those are already in `appimageTools`' default FHS
environment.

Only `x86_64-linux` is packaged. Upstream also publishes aarch64 AppImages, but
those are neither packaged nor build-verified in CI here.

## Automation

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [`bump-navibeat.yml`](.github/workflows/bump-navibeat.yml) | every 6h, or manually | Compares upstream's latest non-prerelease against `navibeat.nix`. If it is newer: prefetches the AppImage, rewrites `version` and `hash`, runs a full `nix build` with output checks, pushes to `main`, and dispatches the release workflow. |
| [`tag-on-version-bump.yml`](.github/workflows/tag-on-version-bump.yml) | push to `main` touching `navibeat.nix`, or manually | Creates a `vX.Y.Z` release matching the version in `navibeat.nix`, if one does not already exist. |

The bump job only pushes once `nix build` has succeeded *and* the binary,
`.desktop` entry, and icon are all present in the result — so an upstream
layout change fails the run rather than landing a broken flake. That build also
doubles as a nixpkgs-drift check, since it runs every six hours regardless of
whether there is anything to bump.

The release workflow is dispatched explicitly rather than left to fire on
`push`: pushes made with `GITHUB_TOKEN` do not trigger `on: push` workflows,
and `workflow_dispatch` is one of the two events GitHub exempts from that
anti-recursion rule.

## Bumping by hand

Set `version` in [`navibeat.nix`](navibeat.nix), then read back the new hash:

```sh
nix store prefetch-file \
  https://github.com/nenadjokic/navibeat-linux/releases/download/v<VER>/NaviBeat-linux-x86_64.AppImage
```

It prints `... (hash 'sha256-...')`; paste that whole string into `hash`. Do not
hand-edit the old hash into "looks right" shape — a wrong hash fails the build
loudly, but a *stale* one silently keeps the old build.

## Licence

The packaging in this repository is MIT. NaviBeat itself is proprietary and
redistributed under upstream's terms; see <https://navibeat.app>.
