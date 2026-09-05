# Bundled faces — provenance, licence, integrity

Two voices (`DESIGN.md` §2.16): **IBM Plex Mono** is the machine — labels, numbers,
detection rules, asset strings, chips, ECG readouts, log-like evidence details, the
stamp. **Space Grotesk** is the human — alert titles, trigger prose, `why`, `learn`,
Vale's messages, headlines.

**Six faces, all of them used.** Three machine weights (regular · medium · semibold)
and three human ones (regular · medium · bold), each called by a step of
`Typography`'s seven-step scale. A registered face that no step calls is dead weight
in the bundle, so the roster and the scale move together.

**`SPEC.md` §6 names `SpaceGrotesk-SemiBold`, which does not exist upstream.**
`.../space-grotesk/2.0.0/fonts/ttf/static/SpaceGrotesk-SemiBold.ttf` answers 404 while
`-Medium` and `-Bold` answer 200 — the spec named a cut the project never cut. Bold
stands in as the heavy human weight and carries the 34 pt grade headline. Reported to
the lead as a proposed amendment to the §6 roster.

**Static instances only** (`SPEC.md` §1). The variable `SpaceGrotesk[wght].ttf` that
`google/fonts` ships was rejected after measurement: registering it exposes the named
instances as `SpaceGrotesk-Light`, `SpaceGrotesk-Light_Regular`,
`SpaceGrotesk-Light_Medium`, `SpaceGrotesk-Light_Bold` — the ambiguous `UIAppFonts`
registration §1 warns about, and a `Font.custom("SpaceGrotesk-Medium", …)` that
resolves by luck rather than by name. The three static cuts from the upstream project
resolve exactly, which is what `FontRegistrationTests` asserts.

`UIAppFonts` lists these as **bare filenames** (D21): XcodeGen adds
`SentrySOC/Resources` as a resources build phase, which flattens each file into the
bundle root.

## Files

| File | PostScript name | Source |
|---|---|---|
| `IBMPlexMono-Regular.ttf` | `IBMPlexMono-Regular` | google/fonts `ofl/ibmplexmono` |
| `IBMPlexMono-Medium.ttf` | `IBMPlexMono-Medium` | google/fonts `ofl/ibmplexmono` |
| `IBMPlexMono-SemiBold.ttf` | `IBMPlexMono-SemiBold` | google/fonts `ofl/ibmplexmono` |
| `SpaceGrotesk-Regular.ttf` | `SpaceGrotesk-Regular` | floriankarsten/space-grotesk `2.0.0` |
| `SpaceGrotesk-Medium.ttf` | `SpaceGrotesk-Medium` | floriankarsten/space-grotesk `2.0.0` |
| `SpaceGrotesk-Bold.ttf` | `SpaceGrotesk-Bold` | floriankarsten/space-grotesk `2.0.0` |

## Which step calls which face

| Face | Steps in `Typography` |
|---|---|
| `IBMPlexMono-Regular` | `meta` · `bodyMono` |
| `IBMPlexMono-Medium` | `label` (the 11 pt tracked floor) · `metaStrong` |
| `IBMPlexMono-SemiBold` | `stamp` |
| `SpaceGrotesk-Regular` | `body` |
| `SpaceGrotesk-Medium` | `rowTitle` · `screenTitle` · `hero` |
| `SpaceGrotesk-Bold` | `grade` |

## URLs

```
https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf
https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-Medium.ttf
https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/IBMPlexMono-SemiBold.ttf
https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/OFL.txt          → OFL-IBMPlex.txt
https://raw.githubusercontent.com/floriankarsten/space-grotesk/2.0.0/fonts/ttf/static/SpaceGrotesk-Regular.ttf
https://raw.githubusercontent.com/floriankarsten/space-grotesk/2.0.0/fonts/ttf/static/SpaceGrotesk-Medium.ttf
https://raw.githubusercontent.com/floriankarsten/space-grotesk/2.0.0/fonts/ttf/static/SpaceGrotesk-Bold.ttf
https://raw.githubusercontent.com/floriankarsten/space-grotesk/2.0.0/OFL.txt         → OFL-SpaceGrotesk.txt
```

## SHA256

```
6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46  IBMPlexMono-Regular.ttf
a9b4c49bb299e05b5f6c481e7fb5e78943d2793249a0c8874ab574a2d1ea6755  IBMPlexMono-Medium.ttf
d3c38e55c78f5b0f28009fddba4834ec503278936a5986032424c9bd2d23aa46  IBMPlexMono-SemiBold.ttf
5ede28c4425f3fe4830c8f4754b39e9a87a93d0c3baa5e0a9924532aaa8a98bd  SpaceGrotesk-Regular.ttf
3183b7eb0b4241476360e2cd8e527868616cc16d3ce332c4376505989b772b44  SpaceGrotesk-Medium.ttf
7209bbb75fc0f5c546a5f5773b0db74ffc6abf04c2148c1105cace5765a96bdb  SpaceGrotesk-Bold.ttf
7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da  OFL-IBMPlex.txt
564ce565c371c5e5bbf286006565a7c9aa55a9f56e7ca58d56e05d649dd61a72  OFL-SpaceGrotesk.txt
```

Verify with `shasum -a 256 -c` against that block from `ios/SentrySOC/Resources`.

## Licence

Both families are SIL Open Font License 1.1. `OFL-IBMPlex.txt` and
`OFL-SpaceGrotesk.txt` sit beside the faces and are rendered in
Settings → About → Licences (C9). Copyright lines, verbatim from those files:

- Copyright © 2017 IBM Corp. with Reserved Font Name "Plex".
- Copyright 2020 The Space Grotesk Project Authors
  (https://github.com/floriankarsten/space-grotesk).
