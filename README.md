# zmk-config — Sweep Bling LP

ZMK config for a Sweep Bling LP (`cradio` shield) on nRF52840 SuperMini controllers
(`nice_nano_v2`). Colemak-DH with Cmd/Opt/Ctrl home row mods, for macOS with the
"British – PC" input source. Ported from the Corne keymap in `../qmk`.

![Keymap](keymap-drawer/cradio.svg)

The diagram is redrawn by GitHub Actions on every keymap change
(`.github/workflows/draw-keymaps.yml`), so `git pull` after pushing.

## Firmware

Pushing builds everything in `build.yaml`; download the `firmware` zip from the
Actions run. Flash by double-tapping reset and copying the `.uf2` onto `NICENANO`.

| File | Use |
|---|---|
| `cradio_left-nice_nano_v2-zmk.uf2` | Left half (central, has ZMK Studio) |
| `cradio_right-nice_nano_v2-zmk.uf2` | Right half |
| `cradio_right_standalone_test.uf2` | Right half as its own keyboard, for testing |
| `cradio_right_standalone_logging.uf2` | Same, with a USB serial log |
| `settings_reset-nice_nano_v2-zmk.uf2` | Clears Bluetooth pairings |

Key bindings can also be changed live with [ZMK Studio](https://zmk.studio)
(unlock with Fn → Studio Unlock). Combos and home-row-mod timing need a rebuild.
