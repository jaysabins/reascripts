# Color Palette

A palette window for coloring tracks, items, and markers and regions in REAPER. Same look as Wwise Tool and GunKit RPM, and it follows Wwise Tool's **Settings > Appearance** (font, colors, rounding).

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
- **Drag** (your palettes): reorder. Drop a swatch on another palette in the list on the left (or from Generated or Recent onto your palette) to copy it there.
- **Right-click**: color, spread from here, make it the current color, copy the hex code, edit, set it to the selection's color, remove, add to another palette.

**Current** (top right) is a free color picker. **Apply** colors the selection with it, and **+** adds it to the palette that's showing.

## Palettes

The list on the left holds **Generated** and your own palettes.

- **Generated**: a grid of hues and shades. Set Hues, Shades, Saturation and Lightness right under it, add a grey row, or **Save as palette** to make an editable copy.
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
- **Shade children**: for selected folder tracks, gives the tracks inside them lighter and lighter shades of the folder's color.
- **Lighter / Darker**: nudges the selection's colors (step set in Settings).
- **Default**: removes the colors.

Each action is one undo point.

## Settings (gear button)

- **Coloring**: folder children follow their parent; items follow their track (coloring a track clears its items' own colors); clear take colors when coloring items (on by default, since a take color hides the item color); close the window after coloring; Lighter/Darker step.
- **New tracks**: color new tracks automatically while the window is open, with the next color of a palette or always one color. Tracks that already come with a color (duplicates, for example) are left alone.
- **Appearance**: swatch size, gap and corner rounding, and the accent color.
- **Palettes**: import, export, add the starter palettes again, clear Recent.
