# Ryoku lockscreen packages

Store packages for `qylock` lockscreens on Ryoku. One folder per skin, plus the
index the store reads. Nothing here is terminal-specific: any lock skin added
later follows the same layout.

## Packages in this repository

| id | version | summary |
|---|---|---|
| `terminal` | 1.1.3 | phosphor CRT console with a tty clock, status readout, session switcher |

## Install a skin

Replace `terminal` with the id you want:

```bash
SLUG=terminal
mkdir -p ~/.local/share/qylock/themes/$SLUG
cp -a lockscreens/$SLUG/content/. ~/.local/share/qylock/themes/$SLUG/
printf '%s\n' "$SLUG" > ~/.config/qylock/theme
```

Then lock the session. The qylock engine loads the skin named in
`~/.config/qylock/theme`.

Do **not** apply a skin as an SDDM greeter theme. The Hub's apply button rewrites
`/usr/share/sddm/themes/ryoku`, and these skins are written for the qylock engine,
not for SDDM.

## Package layout

Every skin uses the same five entries:

```
lockscreens/<id>/
  manifest.json      schema 1: id, category, version, destination, and every file
                     with source, destination, mode, size, sha256 and install flag
  content/           the installed payload: Main.qml, theme.conf,
                     metadata.desktop, shaders/ (precompiled .qsb only)
  assets/            catalogue media, not installed: preview.gif, shot-1.png
  LICENSE            full licence text
  PROVENANCE.txt     author, upstream, original path
```

`lockscreens/registry.json` holds one entry per skin with `official: false`,
`path: lockscreens/<id>`, and `manifestSha256` equal to the sha256 of that skin's
`manifest.json`.

## Verify a download

Any skin, not just the first one:

```bash
SLUG=terminal
cd lockscreens/$SLUG
python3 -c "import json,hashlib;m=json.load(open('manifest.json'));print(all(f['sha256']==hashlib.sha256(open(f['source'],'rb').read()).hexdigest() and f['size']==len(open(f['source'],'rb').read()) for f in m['files']))"
```

It prints `True` when every file matches the manifest. To check the index against
the package:

```bash
python3 -c "import json,hashlib;r=json.load(open('../registry.json'))['lockscreens'][0];print(r['manifestSha256']==hashlib.sha256(open('manifest.json','rb').read()).hexdigest())"
```

## Adding a package

1. Build the folder above for the new id.
2. Add one entry to `lockscreens/registry.json` with the same `version` as the
   manifest, `manifestSha256` = sha256 of that manifest, and `official: false`.
3. Tag the release as `<id>-vX.Y.Z`.

One folder and one registry entry per skin. No other files are required, and the
package must not reference paths outside `lockscreens/<id>/`.

## Licence

Each package carries its own `LICENSE` and `PROVENANCE.txt`; read those in
`lockscreens/<id>/`.
