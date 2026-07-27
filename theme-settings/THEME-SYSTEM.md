# Sumika Theme Settings Extension

## 1. Overview

`theme-settings` is an external shared extension installed at:

```text
~/.local/share/sumika-shell/extensions/theme-settings/
```

It is not a Quickshell UI module. The extension contributes a launcher, a
Python curses interface, shell backends, theme packs, and wallpaper helpers.
The extension relies on Sumika Core services and runtime paths, but it does
not add QML components to the core shell.

The current active theme is recorded in:

```text
~/.local/state/sumika-shell/theme/current-name
```

## 2. Registration And Launch Flow

`module.json` registers the launcher `sumika-theme-settings`:

```text
module.json
  -> omd-launch-settings-theme-tui
  -> terminal application
  -> omd-settings-theme-tui
  -> omd-settings-theme apply <theme>
```

The launcher uses a terminal cascade. It prefers `uwsm-app` and
`xdg-terminal-exec`, then falls back to foot, Kitty, Alacritty,
GNOME Terminal, and Konsole. The dedicated application ID is:

```text
org.omd.themetui
```

The runtime module registry identifies this extension as an external shared
module. It has no QML entry point and no actions provider.

## 3. File Responsibilities

| File | Responsibility |
| --- | --- |
| `module.json` | Extension metadata and launcher registration. |
| `bin/omd-launch-settings-theme-tui` | Finds a terminal and launches the theme TUI. |
| `bin/omd-settings-theme-tui` | Python curses frontend for browsing and applying themes. |
| `bin/omd-settings-theme` | Backend for listing, applying, repairing, and querying themes. |
| `bin/omd-launch-settings-wallpaper-tui` | Launches the wallpaper TUI. |
| `bin/omd-settings-wallpaper-tui` | Controls file, folder, color, interval, next, and stop actions. |
| `bin/omd-wallpaper` | Sets wallpaper with `swaybg` and manages rotation. |
| `bin/omd-theme-bg-set` | Imports a selected image into managed Sumika wallpaper state. |
| `themes/<id>/colors.toml` | Required source colors for a theme. |
| `themes/<id>/neovim.lua` | Neovim theme payload. |
| `config/` | Reserved extension configuration area; currently no active configuration. |
| `wallpaper/` | Reserved extension wallpaper area; runtime state is stored elsewhere. |

## 4. Applying A Theme

When the user selects a theme:

1. The TUI calls `omd-settings-theme apply <id>`.
2. The backend copies the selected theme into:

   ```text
   ~/.local/state/sumika-shell/theme/current/
   ```

3. It writes the selected ID to `current-name`.
4. It generates missing runtime adapters from `colors.toml`:

   ```text
   quickshell.json
   hyprland.lua
   foot.ini
   alacritty.toml
   kitty.conf
   ghostty.conf
   ```

5. Existing files are preserved. A theme-provided adapter therefore acts as
   an override and is not replaced by the generated fallback.
6. The backend requests refreshes from Quickshell, Hyprland, terminals,
   wallpaper, and supported Neovim instances.

Theme application and wallpaper selection are intentionally independent.
Changing a theme does not change the user's wallpaper.

## 5. Theme Source And Supported Themes

The runtime source of truth is:

```text
~/.local/share/sumika-shell/extensions/theme-settings/themes/
```

The extension currently contains 22 selectable themes:

```text
catppuccin
catppuccin-latte
ethereal
everforest
flexoki-light
gruvbox
hackerman
kanagawa
last-horizon
lumon
matte-black
miasma
nord
oceanblack
osaka-jade
retro-82
ristretto
rose-pine
solitude
tokyo-night
vantablack
white
```

All 22 themes currently contain `colors.toml` and `neovim.lua`, so all can
provide the core Sumika color theme and a Neovim payload.

Optional theme files are unevenly distributed:

```text
btop.theme
vscode.json
waybar.css
swayosd.css
icons.theme
chromium.theme
light.mode
keyboard.rgb
preview.png
preview-unlock.png
unlock.png
```

The presence of an optional file means that the theme provides a resource;
it does not by itself guarantee that the corresponding application is
installed, configured, or refreshed automatically.

`oceanblack` is a minimal theme pack. It contains the core color definition
and Neovim payload but does not contain most optional adapters or preview
images. It remains a valid and selectable theme because `colors.toml` is
present.

## 6. Runtime Adapter Coverage

### Always generated from `colors.toml`

The backend can generate these adapters for every valid theme:

- Sumika / Quickshell colors via `quickshell.json`
- Hyprland colors via `hyprland.lua`
- foot via `foot.ini`
- Alacritty via `alacritty.toml`
- Kitty via `kitty.conf`
- Ghostty via `ghostty.conf`

### Resource-based or partially wired adapters

The following are optional and require separate consumer integration:

- Neovim: payload exists for all themes, but live reload depends on the
  user's Neovim configuration and `OmarchyThemeReload` support.
- VS Code: `vscode.json` describes a theme resource; the backend does not
  install or select a VS Code extension.
- btop, Waybar, SwayOSD, Chromium, and icon themes: resources may be copied
  into the current theme directory, but automatic application is not
  universal.
- Ghostty: the generated adapter exists, but the local Ghostty configuration
  must include it for live theme changes to take effect.

## 7. Wallpaper Architecture

Wallpaper state is stored independently from theme state:

```text
~/.local/state/sumika-shell/wallpaper/
```

Important state includes:

```text
source
mode
interval
background
renderer log
```

`omd-wallpaper` uses `swaybg`. For folder mode it uses a user systemd
service/timer to select a random image at the configured interval. The
managed `background` path is used so previews and desktop rendering continue
to work even if the original source file is moved.

Supported wallpaper operations include:

```text
status
pick-file
pick-folder
set-file
set-folder
set-color
random
next
stop
restore
restart
refresh-outputs
render-image
render-color
```

## 8. TUI Interaction

The theme TUI is a frontend only. The backend remains authoritative.

Supported navigation includes:

```text
Arrow keys / hjkl   Navigate
PageUp / PageDown   Page navigation
Home / End          Jump to bounds
Enter / a           Apply selected theme
r                   Refresh
q / Escape          Quit
Mouse wheel         Scroll
```

The current TUI displays color swatches derived from `colors.toml`. It does
not currently render the optional preview PNG files as image previews.

## 9. Known Inconsistencies And Follow-up Work

1. Some older documentation and `AGENTS.md` refer to
   `~/development/OMD/share/themes/`. The actual runtime source is the
   extension directory documented above.
2. Optional adapters are copied as resources but are not all automatically
   applied to their target applications.
3. Ghostty inclusion must be verified and made explicit if Ghostty theme
   switching is required.
4. Neovim live reload depends on external user configuration.
5. The empty `config/` and `wallpaper/` directories should either receive a
   documented purpose or be removed.
6. The extension currently calls core-facing commands such as `hyprctl`,
   `omd-wallpaper`, Quickshell IPC, and terminal reload helpers. This is an
   integration dependency and should remain explicit rather than being
   treated as a standalone extension guarantee.
7. Theme apply currently generates only missing adapters. A future version
   should define whether stale files from a previous theme are removed or
   retained, because this affects reproducibility.

## 10. Intended Long-Term Model

The extension should remain responsible for:

- theme discovery;
- theme selection UI;
- theme pack data;
- theme-to-application adapters;
- wallpaper selection and rotation.

Sumika Core should remain responsible for:

- extension discovery and lifecycle;
- stable runtime paths and APIs;
- Quickshell and Hyprland integration points;
- shared style and service interfaces.

The extension must not require its own QML objects in Core, and disabling or
removing it should only remove theme and wallpaper settings, not prevent the
base desktop from starting.
