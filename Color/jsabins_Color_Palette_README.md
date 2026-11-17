# Color Palette

A palette window for coloring tracks, items, and markers and regions in REAPER. Same style as Wwise Tool and GunKit RPM, with its own **Settings > Appearance** (it doesn't depend on any other script's settings).

Requires ReaImGui (Extensions > ReaPack > Browse packages, search "ReaImGui").

## What gets colored

The buttons along the top choose the target:

- **Auto** (default): follows where you last clicked in REAPER. If you last clicked in the arrange view and items are selected, it colors the items; otherwise the selected tracks. The button shows which one it picked.
- **Tracks**: the selected tracks.
- **Items**: the selected items.
- **Markers**: the markers and regions in the time selection. With no time selection, the region around the edit cursor (or a marker right at it).

The title bar shows how many things are selected. Swatches that the selection already uses get a white outline.

## Swatches

- **Click**: color the selection.
- **Shift+click**: spread the palette across the selection, starting at that swatch (wraps around).
- **Alt+click** (your palettes): edit the swatch with a color picker.
- **Drag** (your palettes): reorder. Drop a swatch on another palette in the list on the left (or from Build palette or Recent onto your palette) to copy it there.
- **Right-click**: color, spread from here, make it the current color, copy the hex code, edit, set it to the selection's color, remove, add to another palette.

**Current** (top right) is a free color picker. **Apply** colors the selection with it, and **+** adds it to the palette that's showing.

## Palettes

The list on the left holds **Build palette** and your own palettes.

- **Build palette**: tools that make a set of colors. Pick one along the top, adjust it under the grid, then **Save as new palette** or **Add to palette...** (adds them to the end of one of yours). The grid's swatches color the selection like any other.
  - **Spectrum**: hues around the color wheel in rows of shades (Hues, Shades, Saturation, Lightness, optional grey row).
  - **Gradient**: steps from one color to another. **Swap** flips the ends, **From selection** takes them from the first and last selected things, and **Around the color wheel** travels through the hues instead of blending straight across.
  - **Shades**: light to dark versions of a base color (Steps, Range).
  - **Harmony**: colors that go with a base color: Analogous, Complementary, Split, Triadic or Tetradic, one row per color with as many shades as you like.
  - **Random**: random colors around a saturation and lightness you set, with Variation. **Reroll** for new ones.
  - Base colors can come from the current color (**Use current**) or the selection (**From selection**).
- **Your palettes**: **New palette** starts an empty one. In a palette, **+** adds the current color and **From selection** adds the colors of what's selected. The **...** button (or right-click a palette in the list) renames, duplicates, sorts by hue, exports, moves or deletes it. Double-click a palette in the list to rename it.
- **Import...** reads a palette file: one `#RRGGBB` per line (a `name: ...` line names it), or a GIMP `.gpl` palette. **Export** writes the same `.txt` format (with js_ReaScriptAPI you pick where; without it the file goes to `REAPER resource folder\Data\jsabins_Color Palette\`).
- Four starter palettes (Basic, Game audio, Soft, Deep) are added the first time. Settings > Palettes adds them again.
- **Recent** shows the last 16 colors you used.

Palettes are saved for every project, not per project.

## Actions (bottom row)

They use the palette that's showing.

- **Spread**: the palette's colors in order across the selection.
- **Random**: a random color from the palette for each selected thing (no two neighbors the same where possible).
- **Gradient**: blends from the first selected thing's color to the last one's (select at least 3). Something with no color uses the current color.
- **Random gradient**: blends between two random colors that go well together across the selection (2 or more). Click again for another.
- **Shade children**: for selected folder tracks, gives the tracks inside them lighter and lighter shades of the folder's color.
- **Lighter / Darker**: nudges the selection's colors (step set in Settings).
- **Default**: removes the colors.

Each action is one undo point.

## Settings (gear button)

- **Coloring**: folder children follow their parent; items follow their track (coloring a track clears its items' own colors); clear take colors when coloring items (on by default, since a take color hides the item color); close the window after coloring; Lighter/Darker step.
- **New tracks**: color new tracks automatically while the window is open, with the next color of a palette or always one color. Tracks that already come with a color (duplicates, for example) are left alone.
- **Appearance**: swatch size, gap and corners; accent color; title, text, dim text, background and outline colors; window and button corners; font, text size and heading size (font changes show the next time the window opens). **Reset appearance** goes back to the standard look.
- **Palettes**: import, export, add the starter palettes again, clear Recent.
