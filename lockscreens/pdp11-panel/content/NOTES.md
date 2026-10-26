# PDP-11 Panel - notes for this skin

Shipped inside `content/`, so it lands next to `Main.qml` in
`~/.local/share/qylock/themes/pdp11-panel/NOTES.md`.

## No daemon, no service

Both side columns are live on a clean install. `CONSOLE` reads `/proc/version`,
`/proc/uptime`, `/proc/loadavg`, `/proc/meminfo` and
`/sys/class/thermal/thermal_zone0/temp` directly. `SYSTEM MAP` reads
`sessionModel`. Nothing else is required, and no cache file is involved.

## Keys on the plate

| key | what it does |
|---|---|
| `LOAD ADRS` | cycles the session that `sddm.login` will start |
| `EXAM` | toggles the CONSOLE reading in the status line |
| `DEP` | drawn but inert, and the plate says so |
| `CONT` | clears the password field, stops a running fault |
| `START` | submits, and stays latched while authentication is in flight |
| `SLEEP` | `sddm.suspend()` -> `ryoku-shell suspend` |
| `REBOOT` | `sddm.reboot()` -> `ryoku-host power reboot` |
| `SHUTDOWN` | `sddm.powerOff()` -> `ryoku-host power poweroff` |

The three power keys need a second press within three seconds; the first press
arms the key and tints it red. They are inert if `powerRow=false`.

`ENABLE/HALT` is a visual lever: it freezes the lamp refresh. It does not stop
the machine. The engine shim has no `halt`, and `ryoku-host power` accepts
`poweroff`, `reboot`, `suspend` and `hibernate` only, so there is no honest way
to wire a halt key from inside a skin.

## What a refused password looks like

It does not flood the panel red. One red lamp sweeps the DATA row from bit 15 to
bit 0 in 560 ms, the row blinks twice with a blank frame between, holds red for
400 ms, then the panel returns to normal. The status line reports the attempt
count throughout, which matters because the first 560 ms carry no colour at all.
Any new keystroke, `CONT`, or `Esc` cuts the sequence short.

## Lamp behaviour

Address lamps are static: they show `lockStartUptime & 0xFFFF` as the start
address. Data lamps shift one bit per keystroke (`dataReg = (dataReg << 1) |
code & 1`).

## Configuration

`theme.conf` carries `powerRow=true`. Set it to `false` to make the three power
keys inert; nothing else changes. Values from `theme.conf` arrive as strings, so
the skin compares against `"true"`.

## Layout

Content driven, no fixed panel height: the plate grows with its own column, and
the whole stack is centred on the screen. `s = clamp(min(w/1920, h/1080), 0.7, 2)`
scales every dimension. The two side columns fade out when the space beside the
plate drops below `260s`, which is the case on a portrait 1080x1920 display.
