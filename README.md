# Better Trails

**The new and improved [Auto Trail Lights](https://github.com/hpruitt99/Auto-Trail-Lights)**: Better Trails is
Auto Trail Lights 2.0. A mod for
**Ski-E-O! Ski Resort Tycoon**, made for [Z's Mod Loader](https://mods.bigz.studio/), that dresses a whole trail in
one click with the game's own pieces, at their normal prices.

Open a trail's panel and go to the **Edit** tab. The **Better Trails** section has five tabs:

- **Towers:** everything Auto Trail Lights does. Tower Lights along both edges, evenly spaced so the whole run is lit,
  as *Uniform* pairs or a *Jagged* zipper, with 8 colors, custom R/G/B and a rainbow *Party* mode. Night skiing is
  turned on.
- **Ropes:** Festoon Lights or Hanging Lanterns, piece after piece, along both edges, zigzagging diagonally across
  the trail, or both. Same colors and Party mode. They skip ground steeper than 20° so the game doesn't flatten it.
- **Snow:** snowblowers aimed across the trail, spaced so their spray covers it, on both sides or one. Cover the full
  length, the top or bottom half, or a stretch you mark with two sliders.
- **Signs:** difficulty signs in the style your game uses (North American, Alpine, Japanese or French & Nordic), at
  the entrance and on the way down, plus junction signs wherever another trail joins or splits off.
- **Flags:** flags along both edges of every stretch steeper than 25°, 30° or 35°.

Also:

- **Lit now:** how much of the trail is in reach of a light, counting every light in the resort.
- **Switch and Remove:** pick other options and the old pieces are sold back as the new ones go in. **Remove** sells
  a tab's pieces back, and **Remove everything** clears the trail (it asks first).
- **Your pieces only:** the mod only manages what it placed. Hand-placed pieces and other trails' pieces are left
  alone. Lights placed by Auto Trail Lights carry over.
- **Smooth:** pieces go in a batch a frame, with rope light shadows off, so even 160 pieces take about a second.

## Install

1. Install [Z's Mod Loader](https://mods.bigz.studio/) with its installer, then open **Ski-E-O Mod Manager**.
2. If you have **Auto Trail Lights**, update it: version 2.0 is Better Trails, and your lights carry over.
   Otherwise, find **Auto Trail Lights** under **Discover** and install it. The update is listed once it's approved.
   - To install by hand instead, download `BetterTrails-2.0.0.zip` from the
     [latest release](https://github.com/hpruitt99/Better-Trails/releases/latest), copy its
     [`BetterTrails`](BetterTrails) folder into the game's `mods` folder (`skieogame\mods\`), turn it on under
     **Mods → Installed**, and turn the old **Auto Trail Lights** off if it's there.
3. Start the game.

The Mod Manager can switch the mod off and on while the game is running. Pieces you've already placed stay.

The mod folder's own [README](BetterTrails/README.md) has the details on each tab, and its limits.

## How it works

The script is all in [`BetterTrails/Scripts/main.lua`](BetterTrails/Scripts/main.lua):

- **Trail shape:** read from `TrailMapSubsystem.RegisteredTrails` (curves plus corridor width). The game's own
  `IsPositionInCorridor` finds the edges, and other trails' corridors give the junctions.
- **Placing:** a deferred spawn of the game's `BP_TowerLight`, `BP_FestoonLights`, `BP_HangingLanterns`,
  `BP_Snowblower`, `BP_TrailMarkers` or `BP_Flags`, then `FinalizePlacement` and `TryDeductFunds`, the same steps as a
  normal placement. The game only loads a building once it's picked in the build menu, so the mod picks it there for a
  moment first.
- **Finding its pieces:** through the resort's `PlaceableRegistrySubsystem`, by name ("*Trail* Rope #12 · Blue"). The
  name also keeps a light's color, which the game doesn't save.
- **Lit now:** the game's own light areas (`AoESources` of kind Light) against points across the trail.
- **Sign style:** read off the trail panel's own difficulty buttons, so the signs always match what the game shows.

## Compatibility

- Tested with game build CL7918 on Z's Mod Loader 1.3.
- Auto Trail Lights 2.0: replaces the old version (same mod Id, `auto-trail-lights`).
- Single-player game; the mod contains no game files.

## Credits

- **Author:** made by iPros with Claude (Anthropic), an AI assistant, which wrote the code.
- **Loader:** [Z's Mod Loader](https://mods.bigz.studio/).

## License

[MIT](LICENSE)
