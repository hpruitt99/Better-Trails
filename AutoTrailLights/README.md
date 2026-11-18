# Better Trails

**The new and improved Auto Trail Lights.** A mod for Ski-E-O! Ski Resort Tycoon, made for
[Z's Mod Loader](https://mods.bigz.studio/), that dresses a whole trail in one click: tower lights, rope lights,
snowblowers, difficulty signs and flags, all made of the game's own pieces at their normal prices. Version 3.0 also
splits a trail in two and joins trails end to end.

Better Trails is Auto Trail Lights 2.0 and up: it does everything Auto Trail Lights does, and more. It comes as an update to
Auto Trail Lights in the Mod Manager, and the lights you placed with Auto Trail Lights carry over.

## What it does

Click a trail and open its **Edit** tab. Under the Night skiing switch there's a **Better Trails** section with six
tabs, in two rows: **Towers**, **Ropes**, **Snow**, **Signs**, **Flags** and **Shape**. On the first five, pick the
options, then click **Install**.
**Remove** sells that tab's pieces back for a refund. If you pick other options later, the button reads **Switch** and
replaces the old pieces in one go.

**Preview** on the Ropes, Snow, Signs and Flags tabs shows see-through pieces (the game's own placement preview)
where the plan puts them, before you spend anything. They follow your option changes and disappear when you
install, switch Preview off, or close the panel.

- **Tower lights**: the game's Tower Light along both edges, spaced so the whole trail is lit, and Night skiing
  turned on.
  - **Uniform** pairs face each other across the trail. **Jagged** is a zipper: each light faces a gap.
  - **Auto spacing** picks the widest spacing that still lights the whole trail. **Custom** shows two sliders:
    **Spacing** (10 to 200 m between lights) and **Lights** (how many in all); moving one moves the other. Uniform or
    Jagged still decides how they sit on the two edges. The note shows how much of the trail these lights will light,
    and turns orange below 100% so you can space them closer.
  - With **Custom**, see-through towers (the game's own placement preview) show where the lights will go before you
    buy them. They're free and disappear when you install, switch to Auto, or close the panel.
  - **Light color** appears once the trail has lights: 8 swatches, **Custom color** (R/G/B sliders), and **Party**,
    a rainbow that chases down the trail. Color changes are free.
- **Rope lights**: the game's Festoon Lights or Hanging Lanterns, piece after piece.
  - **Along edges**: a string on both sides of the trail.
  - **Zigzag across**: strings running diagonally from edge to edge, turning at each side.
  - **Both**.
  - Each piece lights the snow around it (Festoon 15 m, Lanterns 10 m).
  - **Rope light color** works like the tower lights' (swatches, custom R/G/B, Party). Lanterns tint their glowing
    paper too.
  - If the rope lights (with any other lights) light 90% of the trail, Night skiing is turned on.
  - No piece goes where the ground is steeper than 20°: there the game would flatten a pad under it. The string
    has a gap there, and the tab says how many pieces were left out.
- **Snowblowers**: the game's Snowblower along the edges, aimed across the trail and spaced so their spray covers
  it. **Both sides** alternates sides; **One side** keeps them on one edge. **Full length**, **Top half**,
  **Bottom half** or **Custom**: drag **From** and **To** to mark the stretch that needs snow. They start with the
  game's own automatic settings, and you can change each one as usual.
- **Trail signs**: the game's Trail Markers showing the trail's difficulty.
  - A pair at the top of the trail, or more on the way down: **Entrance**, **Every 150 m** or **Every 75 m**.
  - The signs match the ones your game shows (your **Trail rating style** setting: North American, Alpine, Japanese
    or French & Nordic). The **Sign style** button picks one by hand for this session.
  - **Junction signs**: where another trail joins or splits off, a sign showing *that* trail's difficulty stands a
    little above the split, on its side.
  - Rate the trail's difficulty first. If you change it later, the tab offers **Update signs**, which is free.
- **Flags**: the game's Flags along both edges wherever the trail is steeper than 25°, 30° or 35°, every 20 or 40 m.
  If no part is that steep, the tab says how steep the steepest part is.
- **Shape**: split this trail, or join it with another one. Both are free and use the game's own trail tools, so
  the trails stay ordinary trails.
  - **Split**: drag **Split at** (each part keeps at least 30 m), then click **Split here** twice. **Preview** puts
    two see-through flags across the trail at the cut. The top part keeps the trail's name, settings and stats. The
    bottom part becomes a new trail, "*Trail* Lower", with the same difficulty, grooming and night skiing. Better
    Trails pieces on the bottom part go with it.
  - **Join**: the tab lists up to three trails with an end within 50 m of one of this trail's ends (or twice the
    trail's width on wide trails, up to 100 m). It doesn't matter which way either trail was drawn. Click
    **Join "*Trail*"** twice. You get one trail running downhill, with the upper trail's name, difficulty, grooming and
    night skiing. The two ends become one bend point halfway between them. If the trails are different widths, the
    curve on each side of the joint tapers so the width changes gradually. Better Trails pieces on both come along.
- **Lit now**: the Towers and Ropes tabs say how much of the trail is in reach of a light, counting every light in
  the resort the way the game does, including ones you placed by hand.
- **Remove everything**: under the tabs, a summary of what Better Trails placed on this trail, what it cost, and what
  its snowblowers cost to run. **Remove everything**
  sells it all back (click twice: the first click asks).

The mod only ever touches what it placed. Pieces are named after their trail: "*Trail* Light #*n*", "*Trail* Rope
#*n*", "*Trail* Snowblower #*n*", "*Trail* Sign #*n*" and "*Trail* Flag #*n*". The game keeps those names in your
save. Things you place by hand are left alone, and so are other trails' pieces. Everything placed is an ordinary
building, so you can still select, move or bulldoze pieces one by one.

## Install

1. Install [Z's Mod Loader](https://mods.bigz.studio/) with its installer, then open **Ski-E-O Mod Manager**.
2. If you have **Auto Trail Lights**, update it: version 2.0 and up is Better Trails. Otherwise, find **Auto Trail Lights**
   under **Discover** and install it. The update is listed once the release is approved.
   - To install by hand instead, copy the `AutoTrailLights` folder from the zip into the game's `mods` folder
     (`skieogame\mods\`), replacing the old one, then turn it on under **Mods → Installed**.
3. Start the game.

The Mod Manager can switch the mod off and on while the game is running. Pieces you've already placed stay.

## Notes

- There's no key to press; everything is in the trail panel.
- The first time a tab places something, the build menu opens for a moment and closes again. That's how the mod
  gets the game to load that piece.
- Placing a lot of pieces makes the game stutter for a second or so (adding buildings costs the game a fixed amount
  each frame). Rope lights along both edges of a 500 m trail are about 160 pieces and take about a second. The
  button counts up while it works.
- A trail gets at most 400 rope light pieces (about 2.5 km of string). On a very long trail the panel says when the
  far end goes without.
- Rope light pieces have their light's shadows turned off, so dozens of them stay cheap to draw. The bulbs look the
  same.
- Bowls don't get the section, because they're open areas without two edges.
- Distances from the trail's edge: flags 1 m, rope strings 2 m, signs 3.5 m, tower lights 4.5 m, snowblowers 5 m.
  Tower lights and snowblowers keep clear of buildings, other trails and each other, and slide a little along the
  edge when a spot is taken. Trees under a tower light, a snowblower or an edge string are cleared, and the clearing
  is charged the way the game charges it.
- Snowblowers are expensive ($6,200 each plus their running cost). The tab shows the total before you click.
- Tested with game build CL7957 (2026-11-17, split and join on 2026-11-18) on Z's Mod Loader 1.3.

## Credits

- **Author:** made by iPros with Claude (Anthropic), an AI assistant, which wrote the code.
- **Assets:** uses the game's own Tower Light, Festoon Lights, Hanging Lanterns, Snowblower, Trail Markers and Flags.
  The mod contains no game files.
- **Loader:** Z's Mod Loader (https://mods.bigz.studio/).
- **Idea:** Ski-E-O roadmap requests "Automatic Slope Signs", "Automatic Snowblower for Slopes", "Parametric night
  lights", "Add lights automatically when Night skiing is checked", "Night lighting map overlay and feedback" and
  "Slope safety signage". Split and join: requested by a player of the mod.
