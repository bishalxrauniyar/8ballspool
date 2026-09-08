# 🎱 8BallsPool

An 8-ball pool game that floats over your entire macOS desktop — for the moments your AI is busy writing code.

The table, 16 balls, pockets, cushions and aim guides are drawn directly over your screen. Everything else is click-through, so your Mac works exactly as usual while you play.

## Play

- **Grab the cue ball, pull back, release to shoot** — the aim line sweeps green → red with power, ghost ball + deflection guides show where the hit goes
- Full 2-player rules: solids vs stripes assigned on the first pot, scratch → ball-in-hand behind the head string, no-contact fouls, 8-ball respots on the break
- **Sink all your group, then the 8 — but sink the 8 early (or on a foul) and you lose the rack**
- Score chip shows each player's remaining balls and running rack score
- Procedural sounds: cue strike, ball clacks, cushion thuds, pocket drops

## Setup

### Install (easiest)

1. Download the latest zip from [Releases](https://github.com/bishalxrauniyar/8ballspool/releases)
2. Unzip and drag **8BallsPool.app** to **Applications**
3. Open it. Unsigned build — if Gatekeeper complains: right-click the app → **Open** → Open
4. The pool table appears on your desktop. That's it.

### Build from source

```sh
git clone https://github.com/bishalxrauniyar/8ballspool.git
cd 8ballspool
./build.sh
open 8BallsPool.app
```

Requirements: macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

Everything is procedural — graphics, icon, audio — zero asset files. The built app is ~200 KB.

## Controls

| Action | Input |
|---|---|
| Shoot | drag from the cue ball, release |
| Show / hide | `⌃⌥P` (Ctrl+Option+P) |
| New game | `⌃⌥N` (Ctrl+Option+N) |
| Menu (sound, score reset, quit) | 🎱 in the menu bar |

## Notes

- Table floats on your main Mac screen, centered
- Only the area right around the cue ball (~76px) is interactive; every other click passes through to the app below
- Rack score persists across restarts
- Idles at 0 CPU when you're not playing

## License

MIT
