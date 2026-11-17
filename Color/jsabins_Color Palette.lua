-- @description Color Palette (color tracks, items, markers and regions from saved palettes)
-- @author Jay Sabins
-- @version 1.0.0
-- @changelog
--   First release. Click a swatch to color the selected tracks, items, or markers and regions.
--   Build palette: spectrum, gradient, shades, color harmony and random tools, saved as your own
--   palettes. Your palettes: add, edit, drag to reorder, import and export (including GIMP .gpl).
--   Recent row.
--   Actions: spread a palette across the selection, random colors, gradient between the first
--   and last selected, random gradient, shade a folder's children, lighter, darker, default.
--   Optional: color new tracks automatically while the window is open, folder children follow
--   their parent, items follow their track, close after coloring.
--   Same style as Wwise Tool and GunKit RPM, with its own Appearance settings.
-- @about
--   # Color Palette
--
--   A palette window for coloring tracks, items, and markers and regions. Click a swatch to
--   color what's selected. The target follows where you last clicked in REAPER (track list or
--   items), or pick Tracks, Items or Markers yourself.
--
--   - Build palette: tools that make a set of colors (Spectrum, Gradient, Shades, Harmony,
--     Random). Save the result as a palette of your own or add it to one.
--   - Your palettes: as many as you like, listed on the left. Add the current color or the
--     selection's colors, edit a swatch (Alt+click), drag swatches to reorder them or drag one
--     onto another palette to copy it. Import and export palette files (.txt or GIMP .gpl).
--   - Recent: the last colors you used.
--   - Actions: Spread (palette colors in order across the selection), Random, Gradient (from
--     the first selected to the last), Random gradient, Shade children (a folder's children in shades of its
--     color), Lighter, Darker, Default.
--   - Swatches already used by the selection get a white outline.
--
--   Shift+click a swatch to spread the palette across the selection starting from it.
--   Right-click a swatch for more.
--
--   Requires ReaImGui (ReaPack > ReaTeam Extensions). Same look as Wwise Tool.
--
--   Guide: https://github.com/jaysabins/reascripts/blob/main/Color/jsabins_Color_Palette_README.md

local r = reaper
local NAME = "Color Palette"
if not r.ImGui_GetBuiltinPath then
  r.ShowMessageBox("This script needs ReaImGui.\nInstall it from Extensions > ReaPack > Browse packages (search \"ReaImGui\"), then restart REAPER.",
    NAME, 0)
  return
end
package.path = r.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

local ctx = ImGui.CreateContext(NAME)
local EXT = "jsabins_ColorPalette"
local VERSION = "1.0.0"
local MAX_RECENT = 16
local MAX_SWATCHES = 256

------------------------------------------------------------------------------------------------
-- SAVED OPTIONS
------------------------------------------------------------------------------------------------

local function ext_get(key, default)
  local v = r.GetExtState(EXT, key)
  if v == nil or v == "" then return default end
  return v
end

-- Options: name = default. Booleans are saved as 1/0, numbers as numbers.
local O_DEFAULTS = {
  target = "auto",       -- auto, tracks, items, markers
  quit_after = false,    -- close the window after coloring
  children_follow = false, -- coloring a folder track colors everything under it too
  items_follow = false,  -- coloring a track clears its items' own colors (they show the track's)
  clear_takes = true,    -- coloring an item clears its takes' own colors (so the item color shows)
  auto_new = false,      -- color new tracks while the window is open
  auto_source = "palette", -- palette (next color of auto_palette) or fixed (auto_color)
  auto_palette = 0,      -- 0 = Build palette, else index of a saved palette
  auto_color = 0x3A7BD5,
  auto_next = 1,         -- next color index for new tracks
  gen_hues = 24,
  gen_rows = 3,
  gen_sat = 0.62,
  gen_light = 0.50,
  gen_greys = true,
  -- Build palette tools
  b_mode = "spectrum",   -- spectrum, gradient, shades, harmony, random
  b_from = 0x2E6FD8,     -- gradient ends
  b_to = 0xE0583A,
  b_steps = 12,          -- gradient steps
  b_wheel = false,       -- gradient goes around the color wheel instead of straight across
  b_base = 0x3A7BD5,     -- base color for Shades and Harmony
  b_shades = 9,          -- Shades: how many; Harmony: shades per hue
  b_span = 0.6,          -- Shades: how far from darkest to lightest
  b_scheme = "triadic",  -- analogous, complementary, split, triadic, tetradic
  b_count = 24,          -- Random: how many colors
  b_rsat = 0.65,
  b_rlight = 0.52,
  b_vary = 0.15,         -- Random: how much saturation and lightness vary
  b_seed = 1,
  -- Appearance (this script's own; defaults match Wwise Tool's look)
  look_font = "Verdana",
  look_size = 12,
  look_head = 14,
  look_win_round = 14,
  look_frame_round = 8,
  look_title = 0xFFFFFF,
  look_text = 0xFFFFFF,
  look_dim = 0x9A9A9A,
  look_bg = 0x191919,
  look_outline = 0x505050,
  swatch = 24,           -- swatch size (px)
  swatch_gap = 4,
  swatch_round = 5,
  accent = 0,            -- 0 = default accent
  current = 0x3A7BD5,    -- the "Current color" swatch
  shade_step = 0.06,     -- Lighter / Darker step (lightness)
  sel = 0,               -- the palette showing (0 = Build palette)
}
local O = {}
for k, d in pairs(O_DEFAULTS) do
  local v = ext_get("o_" .. k, nil)
  if v == nil then O[k] = d
  elseif type(d) == "boolean" then O[k] = v == "1"
  elseif type(d) == "number" then O[k] = tonumber(v) or d
  else O[k] = v end
end
local function save_opt(k)
  local v = O[k]
  if type(v) == "boolean" then v = v and "1" or "0" end
  r.SetExtState(EXT, "o_" .. k, tostring(v), true)
end
local function set_opt(k, v) O[k] = v; save_opt(k) end

------------------------------------------------------------------------------------------------
-- COLOR MATH (colors are 0xRRGGBB everywhere inside this script)
------------------------------------------------------------------------------------------------

local C = {}

C.split = function(c) return (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF end
C.join = function(R, G, B)
  local function b(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
  return (b(R) << 16) | (b(G) << 8) | b(B)
end
C.rgba = function(c, a) return (c << 8) | (a or 0xFF) end
C.hex = function(c) return string.format("#%06X", c) end
C.parse_hex = function(s)
  local h = s and s:match("^%s*#?(%x%x%x%x%x%x)%s*$")
  return h and tonumber(h, 16) or nil
end
C.luma = function(c)
  local R, G, B = C.split(c)
  return (0.299 * R + 0.587 * G + 0.114 * B) / 255
end

-- REAPER's own color value (with the "custom color" flag) for a 0xRRGGBB color.
C.to_native = function(c) return r.ColorToNative(C.split(c)) | 0x1000000 end
-- 0xRRGGBB from a REAPER color value, or nil when it has no custom color.
C.from_native = function(n)
  n = math.floor(n or 0)
  if n & 0x1000000 == 0 then return nil end
  local R, G, B = r.ColorFromNative(n & 0xFFFFFF)
  return C.join(R, G, B)
end

-- Hue, saturation, lightness (all 0..1) to 0xRRGGBB.
C.from_hsl = function(h, s, l)
  h = h % 1
  s = math.max(0, math.min(1, s))
  l = math.max(0, math.min(1, l))
  local q = l < 0.5 and l * (1 + s) or (l + s - l * s)
  local p = 2 * l - q
  local function ch(t)
    t = t % 1
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  return C.join(ch(h + 1 / 3) * 255, ch(h) * 255, ch(h - 1 / 3) * 255)
end

C.to_hsl = function(c)
  local R, G, B = C.split(c)
  R, G, B = R / 255, G / 255, B / 255
  local hi, lo = math.max(R, G, B), math.min(R, G, B)
  local l = (hi + lo) / 2
  if hi == lo then return 0, 0, l end
  local d = hi - lo
  local s = l > 0.5 and d / (2 - hi - lo) or d / (hi + lo)
  local h
  if hi == R then h = (G - B) / d + (G < B and 6 or 0)
  elseif hi == G then h = (B - R) / d + 2
  else h = (R - G) / d + 4 end
  return h / 6, s, l
end

C.lighten = function(c, dl)
  local h, s, l = C.to_hsl(c)
  return C.from_hsl(h, s, l + dl)
end

C.mix = function(a, b, t)
  local ar, ag, ab = C.split(a)
  local br, bg, bb = C.split(b)
  return C.join(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

------------------------------------------------------------------------------------------------
-- PALETTES
------------------------------------------------------------------------------------------------
-- Saved palettes: { name, colors = { 0xRRGGBB, ... } }. Saved for every project (ExtState),
-- one line per palette: name|RRGGBB,RRGGBB,...

local PAL = { list = {}, recent = {} }

local function enc(str) return (str:gsub("[%%|\r\n]", function(ch) return string.format("%%%02X", ch:byte()) end)) end
local function dec(str) return (str:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function hex_list(colors)
  local t = {}
  for i, c in ipairs(colors) do t[i] = string.format("%06X", c) end
  return table.concat(t, ",")
end
local function parse_list(s)
  local t = {}
  for h in (s or ""):gmatch("%x%x%x%x%x%x") do t[#t + 1] = tonumber(h, 16) end
  return t
end

-- Palettes that come with the script (used the first time, and by "Add starter palettes").
PAL.STARTERS = {
  { "Basic", { 0xD94848, 0xE5813A, 0xE8C547, 0x8CC152, 0x3FAE6A, 0x37BC9B, 0x3BAFDA, 0x4A89DC,
               0x6E5BD6, 0x9B59B6, 0xD770AD, 0x8E8E8E } },
  { "Game audio", { 0x4F8FE0, 0x63C08A, 0xE0A040, 0xC75C5C, 0x9A7BD1, 0x4DB6AC, 0xD9D06A, 0xB07A50,
                    0x7F8C99, 0xE07AA8 } },
  { "Soft", { 0xF2A7A7, 0xF5C49A, 0xF3E19C, 0xBFE3A5, 0xA6DCC6, 0xA7D3EE, 0xB4BDF0, 0xD3B4EE,
              0xEFB5D6, 0xD6D6D6 } },
  { "Deep", { 0x8E2C2C, 0x9A5420, 0x8A7420, 0x4E7A26, 0x23705A, 0x1F5E86, 0x2F3F8C, 0x5A2F86,
              0x86306A, 0x404040 } },
}

PAL.save = function()
  local lines = {}
  for _, p in ipairs(PAL.list) do lines[#lines + 1] = enc(p.name) .. "|" .. hex_list(p.colors) end
  r.SetExtState(EXT, "palettes", table.concat(lines, "\n"), true)
  r.SetExtState(EXT, "palettes_saved", "1", true) -- so deleting every palette doesn't bring the starters back
end
PAL.save_recent = function() r.SetExtState(EXT, "recent", hex_list(PAL.recent), true) end

PAL.unique_name = function(base)
  local used = {}
  for _, p in ipairs(PAL.list) do used[p.name:lower()] = true end
  if not used[base:lower()] then return base end
  local n = 2
  while used[(base .. " " .. n):lower()] do n = n + 1 end
  return base .. " " .. n
end

PAL.add_starters = function()
  for _, s in ipairs(PAL.STARTERS) do
    local cols = {}
    for i, c in ipairs(s[2]) do cols[i] = c end
    PAL.list[#PAL.list + 1] = { name = PAL.unique_name(s[1]), colors = cols }
  end
  PAL.save()
end

PAL.load = function()
  local raw = r.GetExtState(EXT, "palettes")
  if r.GetExtState(EXT, "palettes_saved") ~= "1" then
    PAL.add_starters()
  else
    for line in (raw or ""):gmatch("[^\n]+") do
      local name, list = line:match("^([^|]*)|(.*)$")
      if name then PAL.list[#PAL.list + 1] = { name = dec(name), colors = parse_list(list) } end
    end
  end
  PAL.recent = parse_list(r.GetExtState(EXT, "recent"))
  if O.sel > #PAL.list then O.sel = 0 end
end
PAL.load()

-- Build palette: the colors the Build palette tools make right now, as rows (for the grid) and
-- flat (in order). Rebuilt only when a setting changes.
PAL.BUILD_KEYS = { "b_mode", "gen_hues", "gen_rows", "gen_sat", "gen_light", "gen_greys", "b_from", "b_to",
  "b_steps", "b_wheel", "b_base", "b_shades", "b_span", "b_scheme", "b_count", "b_rsat", "b_rlight", "b_vary", "b_seed" }
PAL.SCHEMES = {
  { "analogous", "Analogous", { -2 / 12, -1 / 12, 0, 1 / 12, 2 / 12 }, "Neighbors on the color wheel: calm, related colors." },
  { "complementary", "Complementary", { 0, 1 / 2 }, "The base and the color opposite it." },
  { "split", "Split", { 0, 5 / 12, 7 / 12 }, "The base and the two colors either side of its opposite." },
  { "triadic", "Triadic", { 0, 1 / 3, 2 / 3 }, "Three colors evenly around the wheel." },
  { "tetradic", "Tetradic", { 0, 1 / 4, 1 / 2, 3 / 4 }, "Four colors evenly around the wheel." },
}
PAL.gen_cache = nil

-- Lightness values from light to dark: n steps across `span`, centered on l (kept inside 0.08-0.94).
local function light_steps(l, n, span)
  local lo, hi = l - span / 2, l + span / 2
  if lo < 0.08 then hi, lo = hi + (0.08 - lo), 0.08 end
  if hi > 0.94 then lo, hi = math.max(0.08, lo - (hi - 0.94)), 0.94 end
  local t = {}
  for i = 1, n do t[i] = n == 1 and l or hi - (hi - lo) * (i - 1) / (n - 1) end
  return t
end

PAL.build_rows = function()
  local mode, rows = O.b_mode, {}
  if mode == "gradient" then
    local n = math.max(2, math.min(48, math.floor(O.b_steps)))
    local line = {}
    local h1, s1, l1 = C.to_hsl(O.b_from)
    local h2, s2, l2 = C.to_hsl(O.b_to)
    if h2 < h1 then h2 = h2 + 1 end -- around the wheel: always the same direction
    for i = 1, n do
      local t = (i - 1) / (n - 1)
      line[i] = O.b_wheel and C.from_hsl(h1 + (h2 - h1) * t, s1 + (s2 - s1) * t, l1 + (l2 - l1) * t)
        or C.mix(O.b_from, O.b_to, t)
    end
    rows[1] = line
  elseif mode == "shades" then
    local h, sat, l = C.to_hsl(O.b_base)
    local line = {}
    for i, lv in ipairs(light_steps(l, math.max(2, math.min(32, math.floor(O.b_shades))), O.b_span)) do
      line[i] = C.from_hsl(h, sat, lv)
    end
    rows[1] = line
  elseif mode == "harmony" then
    local h, sat, l = C.to_hsl(O.b_base)
    local scheme = PAL.SCHEMES[4]
    for _, sc in ipairs(PAL.SCHEMES) do if sc[1] == O.b_scheme then scheme = sc end end
    local n = math.max(1, math.min(12, math.floor(O.b_shades)))
    local steps = light_steps(l, n, n == 1 and 0 or math.min(0.7, 0.1 * (n - 1)))
    for _, off in ipairs(scheme[3]) do
      local line = {}
      for i, lv in ipairs(steps) do line[i] = C.from_hsl(h + off, sat, lv) end
      rows[#rows + 1] = line
    end
  elseif mode == "random" then
    -- Its own little random generator, so the same seed gives the same colors every frame.
    local state = math.floor(O.b_seed) % 2147483647
    if state <= 0 then state = 1 end
    local function rnd()
      state = (state * 48271) % 2147483647
      return state / 2147483647
    end
    local n = math.max(1, math.min(96, math.floor(O.b_count)))
    local line
    for i = 1, n do
      if (i - 1) % 12 == 0 then line = {}; rows[#rows + 1] = line end
      local sat = O.b_rsat + (rnd() * 2 - 1) * O.b_vary
      local lv = O.b_rlight + (rnd() * 2 - 1) * O.b_vary
      line[#line + 1] = C.from_hsl(rnd(), sat, lv)
    end
  else
    local hues = math.max(4, math.min(48, math.floor(O.gen_hues)))
    local n = math.max(1, math.min(7, math.floor(O.gen_rows)))
    local step = 0.13
    for row = 1, n do
      local l = O.gen_light + (((n + 1) / 2) - row) * step -- lightest row on top
      local line = {}
      for i = 1, hues do line[i] = C.from_hsl((i - 1) / hues, O.gen_sat, l) end
      rows[#rows + 1] = line
    end
    if O.gen_greys then
      local line = {}
      for i = 1, hues do line[i] = C.from_hsl(0, 0, 0.08 + 0.84 * (i - 1) / math.max(1, hues - 1)) end
      rows[#rows + 1] = line
    end
  end
  return rows
end

PAL.generated = function()
  local parts = {}
  for i, k in ipairs(PAL.BUILD_KEYS) do parts[i] = tostring(O[k]) end
  local key = table.concat(parts, "|")
  if PAL.gen_cache and PAL.gen_cache.key == key then return PAL.gen_cache end
  local t = { key = key, rows = PAL.build_rows(), flat = {} }
  for _, line in ipairs(t.rows) do
    for _, c in ipairs(line) do t.flat[#t.flat + 1] = c end
  end
  PAL.gen_cache = t
  return t
end

-- The colors of palette i in order (0 = Build palette, -1 = Recent).
PAL.colors_of = function(i)
  if i == 0 then return PAL.generated().flat end
  if i == -1 then return PAL.recent end
  return PAL.list[i] and PAL.list[i].colors or {}
end

PAL.add_recent = function(c)
  for i = #PAL.recent, 1, -1 do if PAL.recent[i] == c then table.remove(PAL.recent, i) end end
  table.insert(PAL.recent, 1, c)
  while #PAL.recent > MAX_RECENT do table.remove(PAL.recent) end
  PAL.save_recent()
end

-- Palette files: one color per line as #RRGGBB (a "name: ..." line names it). GIMP .gpl files
-- ("R G B  name" lines after the header) are read too.
PAL.read_file = function(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  local name = path:match("([^/\\]+)%.%w+$") or path:match("([^/\\]+)$") or "Imported"
  local cols = {}
  for line in text:gmatch("[^\r\n]+") do
    local n = line:match("^%s*[Nn]ame:%s*(.-)%s*$")
    if n and n ~= "" then name = n
    else
      local hx = line:match("^%s*#?(%x%x%x%x%x%x)%s*$") or line:match("^%s*#(%x%x%x%x%x%x)")
      if hx then cols[#cols + 1] = tonumber(hx, 16)
      else
        local R, G, B = line:match("^%s*(%d+)%s+(%d+)%s+(%d+)")
        if R then cols[#cols + 1] = C.join(tonumber(R), tonumber(G), tonumber(B)) end
      end
    end
    if #cols >= MAX_SWATCHES then break end
  end
  if #cols == 0 then return nil end
  return { name = PAL.unique_name(name), colors = cols }
end

PAL.write_file = function(path, p)
  local f = io.open(path, "w")
  if not f then return false end
  f:write("name: ", p.name, "\n")
  for _, c in ipairs(p.colors) do f:write(C.hex(c), "\n") end
  f:close()
  return true
end

------------------------------------------------------------------------------------------------
-- WHAT GETS COLORED
------------------------------------------------------------------------------------------------
-- Each target is { kind, ptr (track/item) or idx (marker), name } with get/put through T.get /
-- T.put, in timeline/track order.

local T = { msg = nil, msg_ok = true, list = {}, kind = "tracks", in_use = {}, sig = nil }

-- Which kind the "Auto" target means right now: items when the last click was in the arrange
-- view and items are selected, else tracks.
T.resolve_kind = function()
  if O.target ~= "auto" then return O.target end
  local cx = r.GetCursorContext2(true)
  if cx == 1 and r.CountSelectedMediaItems(0) > 0 then return "items" end
  if r.CountSelectedTracks(0) > 0 then return "tracks" end
  if r.CountSelectedMediaItems(0) > 0 then return "items" end
  return "tracks"
end

T.time_range = function()
  local s, e = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if e > s then return s, e end
  local cur = r.GetCursorPosition()
  return cur, cur
end

T.collect = function()
  local kind = T.resolve_kind()
  local list = {}
  if kind == "tracks" then
    for i = 0, r.CountSelectedTracks(0) - 1 do
      local tr = r.GetSelectedTrack(0, i)
      list[#list + 1] = { kind = "track", ptr = tr }
    end
  elseif kind == "items" then
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
      local it = r.GetSelectedMediaItem(0, i)
      local tr = r.GetMediaItem_Track(it)
      list[#list + 1] = { kind = "item", ptr = it,
        order = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") * 1e7 + r.GetMediaItemInfo_Value(it, "D_POSITION") }
    end
    table.sort(list, function(a, b) return a.order < b.order end)
  else
    -- Markers and regions in the time selection. With no time selection: the regions around the
    -- edit cursor and the markers right at it.
    local s, e = T.time_range()
    local point = e <= s
    local _, nm, nr = r.CountProjectMarkers(0)
    for i = 0, nm + nr - 1 do
      local ok, isrgn, pos, rend, name, id = r.EnumProjectMarkers3(0, i)
      if ok and ok > 0 then
        local hit
        if point then
          hit = isrgn and (pos <= s + 1e-9 and rend > s) or (not isrgn and math.abs(pos - s) < 1e-6)
        else
          hit = isrgn and (pos < e - 1e-9 and rend > s + 1e-9) or (not isrgn and pos >= s - 1e-9 and pos <= e + 1e-9)
        end
        if hit then list[#list + 1] = { kind = "marker", idx = i, isrgn = isrgn, pos = pos, rend = rend, name = name, id = id } end
      end
    end
    table.sort(list, function(a, b) return a.pos < b.pos end)
  end
  T.kind, T.list = kind, list
end

-- The color something shows (0xRRGGBB), or nil when it has the default color.
T.get = function(t)
  if t.kind == "track" then
    if not r.ValidatePtr2(0, t.ptr, "MediaTrack*") then return nil end
    return C.from_native(r.GetMediaTrackInfo_Value(t.ptr, "I_CUSTOMCOLOR"))
  elseif t.kind == "item" then
    if not r.ValidatePtr2(0, t.ptr, "MediaItem*") then return nil end
    local take = r.GetActiveTake(t.ptr)
    local c = take and C.from_native(r.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR"))
    return c or C.from_native(r.GetMediaItemInfo_Value(t.ptr, "I_CUSTOMCOLOR"))
      or C.from_native(r.GetMediaTrackInfo_Value(r.GetMediaItem_Track(t.ptr), "I_CUSTOMCOLOR"))
  else
    local ok, _, _, _, _, _, col = r.EnumProjectMarkers3(0, t.idx)
    if not ok or ok == 0 then return nil end
    return C.from_native(col)
  end
end

local function each_descendant(tr, fn)
  local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) -- 0-based index of the next track
  if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") ~= 1 then return end
  local depth = 1
  while idx < r.CountTracks(0) and depth > 0 do
    local ch = r.GetTrack(0, idx)
    fn(ch, depth)
    depth = depth + r.GetMediaTrackInfo_Value(ch, "I_FOLDERDEPTH")
    idx = idx + 1
  end
end

local function clear_item_colors(it)
  r.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", 0)
  for k = 0, r.CountTakes(it) - 1 do
    local tk = r.GetTake(it, k)
    if tk then r.SetMediaItemTakeInfo_Value(tk, "I_CUSTOMCOLOR", 0) end
  end
end

local function color_track(tr, c)
  r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", c and C.to_native(c) or 0)
  if O.items_follow then
    for k = 0, r.CountTrackMediaItems(tr) - 1 do clear_item_colors(r.GetTrackMediaItem(tr, k)) end
  end
end

-- Give one target a color (nil = back to default).
T.put = function(t, c)
  if t.kind == "track" then
    if not r.ValidatePtr2(0, t.ptr, "MediaTrack*") then return end
    color_track(t.ptr, c)
    if O.children_follow then each_descendant(t.ptr, function(ch) color_track(ch, c) end) end
  elseif t.kind == "item" then
    if not r.ValidatePtr2(0, t.ptr, "MediaItem*") then return end
    r.SetMediaItemInfo_Value(t.ptr, "I_CUSTOMCOLOR", c and C.to_native(c) or 0)
    if O.clear_takes or not c then
      for k = 0, r.CountTakes(t.ptr) - 1 do
        local tk = r.GetTake(t.ptr, k)
        if tk then r.SetMediaItemTakeInfo_Value(tk, "I_CUSTOMCOLOR", 0) end
      end
    end
  else
    r.SetProjectMarkerByIndex2(0, t.idx, t.isrgn, t.pos, t.rend, t.id, t.name, c and C.to_native(c) or 0, 0)
  end
end

T.noun = function(n, kind)
  kind = kind or T.kind
  local one = kind == "tracks" and "track" or kind == "items" and "item" or "marker/region"
  local many = kind == "tracks" and "tracks" or kind == "items" and "items" or "markers/regions"
  return string.format("%d %s", n, n == 1 and one or many)
end

-- Run fn(list) as one undo point. fn returns the undo text (or nil to skip the undo).
T.edit = function(fn)
  T.collect()
  if #T.list == 0 then
    T.msg, T.msg_ok = "Nothing selected to color.", false
    return false
  end
  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)
  local what = fn(T.list)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.UpdateTimeline()
  r.TrackList_AdjustWindows(false)
  r.Undo_EndBlock2(0, NAME .. ": " .. (what or "color"), -1)
  T.msg, T.msg_ok = what and (what:sub(1, 1):upper() .. what:sub(2)) or nil, true
  T.sig = nil
  T.colored = true
  return true
end

-- The colors in use by the selection (for the white outlines), refreshed when the project
-- changes or every few frames.
T.frame = 0
T.refresh = function()
  T.frame = T.frame + 1
  local sig = tostring(r.GetProjectStateChangeCount(0)) .. "|" .. O.target .. "|" .. r.GetCursorContext2(true)
    .. "|" .. r.CountSelectedTracks(0) .. "|" .. r.CountSelectedMediaItems(0)
  if sig == T.sig and T.frame % 15 ~= 0 then return end
  T.sig = sig
  T.collect()
  T.in_use = {}
  for i, t in ipairs(T.list) do
    if i > 500 then break end
    local c = T.get(t)
    if c then T.in_use[c] = true end
  end
end

------------------------------------------------------------------------------------------------
-- ACTIONS
------------------------------------------------------------------------------------------------

local A = {}

A.color = function(c)
  if T.edit(function(list)
    for _, t in ipairs(list) do T.put(t, c) end
    return string.format("color %s %s", T.noun(#list), C.hex(c))
  end) then PAL.add_recent(c) end
end

-- Palette colors in order across the selection, starting at color `from` (wraps around).
A.spread = function(pi, from)
  local cols = PAL.colors_of(pi)
  if #cols == 0 then T.msg, T.msg_ok = "This palette is empty.", false; return end
  from = from or 1
  T.edit(function(list)
    for k, t in ipairs(list) do T.put(t, cols[((from - 1 + k - 1) % #cols) + 1]) end
    return string.format("spread palette across %s", T.noun(#list))
  end)
end

A.random = function(pi)
  local cols = PAL.colors_of(pi)
  if #cols == 0 then T.msg, T.msg_ok = "This palette is empty.", false; return end
  T.edit(function(list)
    local last
    for _, t in ipairs(list) do
      local c = cols[math.random(#cols)]
      if #cols > 1 then
        local tries = 0
        while c == last and tries < 8 do c = cols[math.random(#cols)]; tries = tries + 1 end
      end
      T.put(t, c)
      last = c
    end
    return string.format("random colors on %s", T.noun(#list))
  end)
end

-- Gradient from the first selected thing's color to the last one's. If either has no color,
-- the current color is used for it.
A.gradient = function()
  T.collect()
  if #T.list < 3 then
    T.msg, T.msg_ok = "Select at least 3 things: the first and last set the gradient's ends.", false
    return
  end
  local a = T.get(T.list[1]) or O.current
  local b = T.get(T.list[#T.list]) or O.current
  T.edit(function(list)
    for k, t in ipairs(list) do T.put(t, C.mix(a, b, (k - 1) / (#list - 1))) end
    return string.format("gradient across %s", T.noun(#list))
  end)
end

-- Gradient between two random colors that go well together, across the selection.
A.random_gradient = function()
  T.collect()
  if #T.list < 2 then
    T.msg, T.msg_ok = "Select at least 2 things for a gradient.", false
    return
  end
  local h1 = math.random()
  local h2 = h1 + (0.12 + math.random() * 0.38) * (math.random() < 0.5 and -1 or 1)
  local a = C.from_hsl(h1, 0.55 + math.random() * 0.3, 0.40 + math.random() * 0.2)
  local b = C.from_hsl(h2, 0.55 + math.random() * 0.3, 0.40 + math.random() * 0.2)
  T.edit(function(list)
    for k, t in ipairs(list) do T.put(t, C.mix(a, b, (k - 1) / (#list - 1))) end
    return string.format("random gradient %s to %s across %s", C.hex(a), C.hex(b), T.noun(#list))
  end)
end

-- Each selected folder track's children in shades of its color: lighter the deeper the child
-- sits in the list.
A.shade_children = function()
  T.collect()
  if T.kind ~= "tracks" then
    T.msg, T.msg_ok = "Shade children works on folder tracks.", false
    return
  end
  local folders = {}
  for _, t in ipairs(T.list) do
    if r.GetMediaTrackInfo_Value(t.ptr, "I_FOLDERDEPTH") == 1 then folders[#folders + 1] = t.ptr end
  end
  if #folders == 0 then T.msg, T.msg_ok = "Select a folder track (its children get the shades).", false; return end
  T.edit(function()
    for _, f in ipairs(folders) do
      local base = C.from_native(r.GetMediaTrackInfo_Value(f, "I_CUSTOMCOLOR")) or O.current
      if not C.from_native(r.GetMediaTrackInfo_Value(f, "I_CUSTOMCOLOR")) then
        r.SetMediaTrackInfo_Value(f, "I_CUSTOMCOLOR", C.to_native(base))
      end
      local kids = {}
      each_descendant(f, function(ch) kids[#kids + 1] = ch end)
      local _, _, l = C.to_hsl(base)
      local room = math.min(0.32, math.max(0.1, 0.88 - l)) -- how much lighter the last child gets
      for k, ch in ipairs(kids) do
        r.SetMediaTrackInfo_Value(ch, "I_CUSTOMCOLOR", C.to_native(C.lighten(base, room * k / #kids)))
      end
    end
    return string.format("shade the children of %d folder%s", #folders, #folders == 1 and "" or "s")
  end)
end

A.shift_light = function(dl)
  T.edit(function(list)
    local n = 0
    for _, t in ipairs(list) do
      local c = T.get(t)
      if c then T.put(t, C.lighten(c, dl)); n = n + 1 end
    end
    if n == 0 then return nil end
    return string.format("%s %s", dl > 0 and "lighten" or "darken", T.noun(n))
  end)
  if T.msg == nil then T.msg, T.msg_ok = "Nothing selected has a color yet.", false end
end

A.default = function()
  T.edit(function(list)
    for _, t in ipairs(list) do T.put(t, nil) end
    return string.format("default color on %s", T.noun(#list))
  end)
end

-- Colors of the selection (in order, no repeats).
A.selection_colors = function()
  T.collect()
  local seen, out = {}, {}
  for _, t in ipairs(T.list) do
    local c = T.get(t)
    if c and not seen[c] then seen[c] = true; out[#out + 1] = c end
  end
  return out
end

------------------------------------------------------------------------------------------------
-- NEW TRACKS (while the window is open)
------------------------------------------------------------------------------------------------

local AUTO = { known = nil, count = -1, proj = nil }

AUTO.scan = function()
  local proj = r.EnumProjects(-1)
  local n = r.CountTracks(0)
  if proj ~= AUTO.proj then AUTO.proj, AUTO.known, AUTO.count = proj, nil, -1 end
  if n == AUTO.count and AUTO.known then return end
  local first = AUTO.known == nil
  local known = {}
  local fresh = {}
  for i = 0, n - 1 do
    local tr = r.GetTrack(0, i)
    local g = r.GetTrackGUID(tr)
    known[g] = true
    if not first and not AUTO.known[g] then fresh[#fresh + 1] = tr end
  end
  AUTO.known, AUTO.count = known, n
  if not O.auto_new or #fresh == 0 then return end
  local cols = O.auto_source == "palette" and PAL.colors_of(O.auto_palette) or nil
  r.PreventUIRefresh(1)
  for _, tr in ipairs(fresh) do
    if r.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR") == 0 then -- leave tracks that came with a color
      local c = O.auto_color
      if cols and #cols > 0 then
        local i = ((math.floor(O.auto_next) - 1) % #cols) + 1
        c = cols[i]
        O.auto_next = i + 1
      end
      r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", C.to_native(c))
    end
  end
  save_opt("auto_next")
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
end

------------------------------------------------------------------------------------------------
-- LOOK (same style as Wwise Tool and GunKit RPM, with its own settings)
------------------------------------------------------------------------------------------------
-- Defaults match Wwise Tool's look: Verdana 12, 14px bold headings, #191919 background, 14px
-- window corners, 8px corners on buttons/fields/panels, a thin #505050 outline. Settings >
-- Appearance changes them for this script only.

local UI = {}
UI.FONT_CHOICES = { "Verdana", "Tahoma", "Segoe UI", "Arial", "Calibri", "Consolas" }
UI.COLOR_OK, UI.COLOR_BAD = 0x6BCB77FF, 0xFF6B6BFF
UI.ACCENT_DEFAULT = 0x3A7BD5
UI.FOOT_H = 34 -- action button height (same as Wwise Tool's Transfer button)
UI.GUIDE_URL = "https://github.com/jaysabins/reascripts/blob/main/Color/jsabins_Color_Palette_README.md"
UI.LOOK_KEYS = { "look_font", "look_size", "look_head", "look_win_round", "look_frame_round",
  "look_title", "look_text", "look_dim", "look_bg", "look_outline" }

-- The look in use, from this script's own options (colors as 0xRRGGBBAA). Called every frame,
-- so color and corner changes show right away.
UI.sync_look = function()
  local font = UI.FONT_CHOICES[1]
  for _, f in ipairs(UI.FONT_CHOICES) do if f == O.look_font then font = f end end
  UI.look = {
    font = font,
    size = math.max(9, math.min(18, math.floor(O.look_size))),
    head = math.max(10, math.min(24, math.floor(O.look_head))),
    title = C.rgba(O.look_title), text = C.rgba(O.look_text), dim = C.rgba(O.look_dim),
    bg = C.rgba(O.look_bg), outline = C.rgba(O.look_outline),
  }
  UI.WINDOW_ROUNDING = math.max(0, math.min(20, O.look_win_round))
  UI.FRAME_ROUNDING = math.max(0, math.min(12, O.look_frame_round))
end
UI.sync_look()
UI.bg_rgb = function() return UI.look.bg >> 8 end
UI.dim_col = function() return UI.look.dim end

-- Fonts are made once at startup. Any that can't be made fall back to ImGui's own font.
UI.make_font = function(size, bold)
  local flags = 0
  if bold then
    local okb, b = pcall(function() return ImGui.FontFlags_Bold end)
    if okb and type(b) == "number" then flags = b end
  end
  local ok, f = pcall(ImGui.CreateFont, UI.look.font, size, flags)
  if not (ok and f) then ok, f = pcall(ImGui.CreateFont, UI.look.font, size) end
  if ok and f and pcall(ImGui.Attach, ctx, f) then return f end
end
UI.main_font = UI.make_font(UI.look.size)
UI.section_font = UI.make_font(UI.look.head, true)
UI.title_font = UI.make_font(UI.look.head + 1, true)

-- Constant names changed between ReaImGui versions, so use whichever exists.
UI.const = function(...)
  for _, name in ipairs({ ... }) do
    local ok, v = pcall(function() return ImGui[name] end)
    if ok and type(v) == "number" then return v end
  end
end

-- Dark grey theme in place of ImGui's default blue (same colors as Wwise Tool).
UI.GREY_THEME = {
  { { "Col_WindowBg" }, 0x191919FF },
  { { "Col_Border" }, 0x2E2E2EFF },
  { { "Col_Button" }, 0x3A3A3AFF },
  { { "Col_ButtonHovered" }, 0x4C4C4CFF },
  { { "Col_ButtonActive" }, 0x5E5E5EFF },
  { { "Col_FrameBg" }, 0x2A2A2AFF },
  { { "Col_FrameBgHovered" }, 0x383838FF },
  { { "Col_FrameBgActive" }, 0x464646FF },
  { { "Col_Header" }, 0x3A3A3AFF },
  { { "Col_HeaderHovered" }, 0x4A4A4AFF },
  { { "Col_HeaderActive" }, 0x585858FF },
  { { "Col_CheckMark" }, 0xD8D8D8FF },
  { { "Col_SliderGrab" }, 0x8A8A8AFF },
  { { "Col_SliderGrabActive" }, 0xB4B4B4FF },
  { { "Col_SeparatorHovered" }, 0x707070C8 },
  { { "Col_SeparatorActive" }, 0x909090FF },
  { { "Col_ResizeGrip" }, 0x5A5A5A40 },
  { { "Col_ResizeGripHovered" }, 0x7A7A7AAA },
  { { "Col_ResizeGripActive" }, 0x9A9A9AF2 },
  { { "Col_Tab" }, 0x2C2C2CFF },
  { { "Col_TabHovered" }, 0x4C4C4CFF },
  { { "Col_TabSelected", "Col_TabActive" }, 0x3C3C3CFF },
  { { "Col_TabDimmed", "Col_TabUnfocused" }, 0x242424FF },
  { { "Col_TabDimmedSelected", "Col_TabUnfocusedActive" }, 0x333333FF },
  { { "Col_TextSelectedBg" }, 0x6A6A6A80 },
  { { "Col_NavCursor", "Col_NavHighlight" }, 0x9A9A9AFF },
  { { "Col_DockingPreview" }, 0x8A8A8AB3 },
}
for _, t in ipairs(UI.GREY_THEME) do t[1] = UI.const(table.unpack(t[1])) end

-- Push the grey theme; returns how many colors to pop.
UI.push_theme = function()
  local n = 0
  for _, t in ipairs(UI.GREY_THEME) do
    if t[1] then
      ImGui.PushStyleColor(ctx, t[1], t[1] == ImGui.Col_WindowBg and ((UI.bg_rgb() << 8) | 0xFF) or t[2]); n = n + 1
    end
  end
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, UI.look.text)
  ImGui.PushStyleColor(ctx, ImGui.Col_TextDisabled, UI.look.dim)
  n = n + 2
  return n
end

UI.ROUNDING_VARS = { "StyleVar_FrameRounding", "StyleVar_GrabRounding", "StyleVar_PopupRounding",
  "StyleVar_ChildRounding", "StyleVar_TabRounding", "StyleVar_ScrollbarRounding" }
UI.push_rounding = function()
  local n = 0
  for _, k in ipairs(UI.ROUNDING_VARS) do
    local ok, v = pcall(function() return ImGui[k] end)
    if ok and type(v) == "number" then ImGui.PushStyleVar(ctx, v, UI.FRAME_ROUNDING); n = n + 1 end
  end
  return n
end

UI.accent = function() return (O.accent and O.accent > 0) and O.accent or UI.ACCENT_DEFAULT end
UI.shade = function(c, f)
  local R, G, B = C.split(c)
  local function ch(v) return f >= 0 and (v + (255 - v) * f) or (v * (1 + f)) end
  return C.join(ch(R), ch(G), ch(B))
end

-- Accent on checkmarks, slider grabs and the selected sidebar row. Returns the pop count.
UI.push_accent = function()
  local a = UI.accent()
  ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, C.rgba(UI.shade(a, 0.35)))
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, C.rgba(UI.shade(a, 0.1)))
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, C.rgba(UI.shade(a, 0.3)))
  return 3
end

-- Accent-colored button. Returns the pop count.
UI.push_accent_button = function()
  local a = UI.accent()
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.rgba(a))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.rgba(UI.shade(a, 0.15)))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.rgba(UI.shade(a, -0.2)))
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.luma(a) > 0.62 and 0x111111FF or 0xFFFFFFFF)
  return 4
end

------------------------------------------------------------------------------------------------
-- GUI HELPERS
------------------------------------------------------------------------------------------------

local function tip(text)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then ImGui.SetTooltip(ctx, text) end
end
local function dim(text) ImGui.TextColored(ctx, UI.dim_col(), text) end

local function section_title(text)
  local big = UI.section_font and pcall(ImGui.PushFont, ctx, UI.section_font)
  ImGui.SeparatorText(ctx, text)
  if big then ImGui.PopFont(ctx) end
  ImGui.Dummy(ctx, 0, 0)
end

UI.draw_title = function(dl, x, y, col, text)
  ImGui.DrawList_AddText(dl, x, y, col, text)
  ImGui.DrawList_AddText(dl, x + 1, y, col, text)
end

UI.open_url = function(url)
  if r.CF_ShellExecute then r.CF_ShellExecute(url); return end
  local os_name = r.GetOS()
  if os_name:match("^Win") then
    r.ExecProcess('explorer.exe "' .. url .. '"', -2)
  elseif os_name:match("^OSX") or os_name:match("^macOS") then
    r.ExecProcess('/usr/bin/open "' .. url .. '"', -2)
  else
    r.ExecProcess('xdg-open "' .. url .. '"', -2)
  end
end

-- Title-bar buttons: twice the font size, flat until hovered (grey box; the X goes red).
UI.close_size = function() return math.floor(ImGui.GetFontSize(ctx) * 2 + 0.5) end
UI.close_margin = function() return math.floor(ImGui.GetFontSize(ctx) * 0.5 + 0.5) end
UI.title_bar_size = function() return UI.close_size() + UI.close_margin() + math.max(2, math.floor(UI.close_margin() * 0.4)) end

UI.close_button = function(id, size)
  local pressed = ImGui.InvisibleButton(ctx, id, size, size)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local x1, y1 = ImGui.GetItemRectMin(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local fg = hovered and 0xFFFFFFFF or ImGui.GetColor(ctx, ImGui.Col_Text)
  if hovered or held then
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x1 + size, y1 + size, held and 0xB8323AFF or 0xE04048FF, size * 0.22)
  end
  local m, th = size * 0.30, math.max(2, size * 0.08)
  local a, b = m - 0.5, size - m - 0.5
  ImGui.DrawList_AddLine(dl, x1 + a, y1 + a, x1 + b, y1 + b, fg, th)
  ImGui.DrawList_AddLine(dl, x1 + b, y1 + a, x1 + a, y1 + b, fg, th)
  return pressed
end

UI.icon_button = function(id, size, draw)
  local pressed = ImGui.InvisibleButton(ctx, id, size, size)
  local hovered, held = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local x1, y1 = ImGui.GetItemRectMin(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local fg = hovered and 0xFFFFFFFF or ImGui.GetColor(ctx, ImGui.Col_Text)
  if hovered or held then
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x1 + size, y1 + size, held and 0x5E5E5EFF or 0x4C4C4CFF, size * 0.22)
  end
  draw(dl, x1, y1, size, fg)
  return pressed
end

UI.draw_question = function(dl, x1, y1, size, fg)
  local big = UI.section_font and pcall(ImGui.PushFont, ctx, UI.section_font)
  local tw, th = ImGui.CalcTextSize(ctx, "?")
  ImGui.DrawList_AddText(dl, x1 + (size - tw) / 2, y1 + (size - th) / 2, fg, "?")
  if big then ImGui.PopFont(ctx) end
end

UI.draw_gear = function(dl, x1, y1, size, col)
  local cx, cy = x1 + size / 2, y1 + size / 2
  local ro, ri = size * 0.34, size * 0.255
  local th = math.max(1.2, size * 0.065)
  for i = 0, 7 do
    local a = i * math.pi / 4 - math.pi / 2
    for _, pt in ipairs({ { ri, a - 0.27 }, { ro, a - 0.17 }, { ro, a + 0.17 }, { ri, a + 0.27 } }) do
      ImGui.DrawList_PathLineTo(dl, cx + math.cos(pt[2]) * pt[1], cy + math.sin(pt[2]) * pt[1])
    end
  end
  ImGui.DrawList_PathStroke(dl, col, ImGui.DrawFlags_Closed, th)
  ImGui.DrawList_AddCircle(dl, cx, cy, size * 0.115, col, 0, th)
end

-- Small flat "..." button (menu) drawn as three dots.
UI.draw_dots = function(dl, x1, y1, size, fg)
  local cy = y1 + size / 2
  local rad = math.max(1.5, size * 0.08)
  for k = -1, 1 do ImGui.DrawList_AddCircleFilled(dl, x1 + size / 2 + k * size * 0.22, cy, rad, fg) end
end

-- Segmented choice (a row of buttons, the chosen one in the accent). Returns the new value.
UI.segmented = function(id, value, choices, w)
  local sp = 2
  local avail = w or ImGui.GetContentRegionAvail(ctx)
  local bw = math.floor((avail - sp * (#choices - 1)) / #choices)
  local out = value
  for i, ch in ipairs(choices) do
    if i > 1 then ImGui.SameLine(ctx, 0, sp) end
    local on = ch[1] == value -- decided once for the push/pop pair
    local pushed = on and UI.push_accent_button() or 0
    if ImGui.Button(ctx, ch[2] .. "##" .. id .. i, bw, 0) then out = ch[1] end
    if pushed > 0 then ImGui.PopStyleColor(ctx, pushed) end
    if ch[3] then tip(ch[3]) end
  end
  return out
end

------------------------------------------------------------------------------------------------
-- SWATCHES
------------------------------------------------------------------------------------------------

local SW = { edit = nil, open_edit = false, menu = nil, open_menu = false, drag_type = "jsabins_swatch" }

-- One swatch. Returns clicked, right_clicked.
SW.draw = function(id, c, w, h)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)
  local rclicked = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
  local x1, y1 = ImGui.GetItemRectMin(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local rd = math.min(O.swatch_round, math.min(w, h) / 2)
  ImGui.DrawList_AddRectFilled(dl, x1, y1, x1 + w, y1 + h, C.rgba(c), rd)
  if T.in_use[c] then
    ImGui.DrawList_AddRect(dl, x1 + 0.5, y1 + 0.5, x1 + w - 0.5, y1 + h - 0.5, 0xFFFFFFFF, rd, 0, 2)
  elseif hovered then
    ImGui.DrawList_AddRect(dl, x1 + 0.5, y1 + 0.5, x1 + w - 0.5, y1 + h - 0.5, 0xFFFFFFB0, rd, 0, 1.5)
  end
  return clicked, rclicked
end

-- Modifier keys held right now.
SW.mods = function()
  local m = ImGui.GetKeyMods(ctx)
  return (m & ImGui.Mod_Shift) ~= 0, (m & ImGui.Mod_Alt) ~= 0
end

-- What a click on swatch ci of palette pi does: color, Shift = spread from here, Alt = edit.
SW.click = function(pi, ci, c)
  local shift, alt = SW.mods()
  if alt and pi > 0 then
    SW.edit = { pi = pi, ci = ci, orig = c }
    SW.open_edit = true
  elseif shift then
    A.spread(pi, ci)
  else
    A.color(c)
  end
end

SW.hover_tip = function(pi, c)
  if not ImGui.IsItemHovered(ctx) or ImGui.IsMouseDragging(ctx, ImGui.MouseButton_Left) then return end
  local lines = C.hex(c) .. (T.in_use[c] and "  (in use by the selection)" or "") ..
    "\nClick: color the selection\nShift+click: spread the palette from here"
  if pi > 0 then lines = lines .. "\nAlt+click: edit\nDrag: reorder (or drop on another palette to copy)" end
  ImGui.SetTooltip(ctx, lines .. "\nRight-click: more")
end

-- Drag and drop: payload "<palette>,<index>,<RRGGBB>". Dropping on a swatch of the same saved
-- palette moves the color there; from anywhere else it's inserted as a copy.
SW.drag_source = function(pi, ci, c)
  if ImGui.BeginDragDropSource(ctx, ImGui.DragDropFlags_None) then
    ImGui.SetDragDropPayload(ctx, SW.drag_type, string.format("%d,%d,%06X", pi, ci, c))
    local x, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.Dummy(ctx, 28, 18)
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), x, y, x + 28, y + 18, C.rgba(c), 4)
    ImGui.EndDragDropSource(ctx)
  end
end

SW.parse_payload = function(payload)
  local spi, sci, hx = (payload or ""):match("^(%-?%d+),(%d+),(%x+)$")
  if not spi then return nil end
  return tonumber(spi), tonumber(sci), tonumber(hx, 16)
end

-- Drop handling for a target at palette pi, before index ci (ci = #colors + 1 = at the end).
SW.drop = function(pi, ci, payload)
  local spi, sci, c = SW.parse_payload(payload)
  local p = PAL.list[pi]
  if not (spi and p) then return end
  if spi == pi then
    if sci == ci or not p.colors[sci] then return end
    local col = table.remove(p.colors, sci)
    if sci < ci then ci = ci - 1 end
    table.insert(p.colors, math.min(ci, #p.colors + 1), col)
  else
    if #p.colors >= MAX_SWATCHES then return end
    table.insert(p.colors, math.min(ci, #p.colors + 1), c)
  end
  PAL.save()
end

SW.drag_target = function(pi, ci)
  if pi <= 0 then return end
  if ImGui.BeginDragDropTarget(ctx) then
    local ok, payload = ImGui.AcceptDragDropPayload(ctx, SW.drag_type)
    if ok then SW.drop(pi, ci, payload) end
    ImGui.EndDragDropTarget(ctx)
  end
end

-- A wrapping grid of fixed-size swatches (saved palettes and Recent).
SW.grid = function(pi, colors)
  local size, gap = math.floor(O.swatch), math.floor(O.swatch_gap)
  local avail = ImGui.GetContentRegionAvail(ctx)
  local cols = math.max(1, math.floor((avail + gap) / (size + gap)))
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, gap, gap)
  local action
  for i, c in ipairs(colors) do
    if (i - 1) % cols ~= 0 then ImGui.SameLine(ctx) end
    local clicked, rclicked = SW.draw("##sw" .. pi .. "_" .. i, c, size, size)
    SW.hover_tip(pi, c)
    if clicked then action = { "click", i, c } end
    if rclicked then action = { "menu", i, c } end
    SW.drag_source(pi, i, c)
    SW.drag_target(pi, i)
  end
  ImGui.PopStyleVar(ctx)
  if action then
    if action[1] == "click" then SW.click(pi, action[2], action[3])
    else SW.menu = { pi = pi, ci = action[2], c = action[3] }; SW.open_menu = true end
  end
end

-- The generated palette: its rows stretched to the panel's width.
SW.gen_grid = function()
  local g = PAL.generated()
  local gap = math.floor(O.swatch_gap)
  local avail = ImGui.GetContentRegionAvail(ctx)
  local n = #g.rows[1]
  local w = math.max(6, (avail - gap * (n - 1)) / n)
  local h = math.floor(O.swatch)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, gap, gap)
  local action
  local k = 0
  for row, line in ipairs(g.rows) do
    for i, c in ipairs(line) do
      k = k + 1
      if i > 1 then ImGui.SameLine(ctx) end
      local clicked, rclicked = SW.draw("##gen" .. row .. "_" .. i, c, w, h)
      SW.hover_tip(0, c)
      if clicked then action = { "click", k, c } end
      if rclicked then action = { "menu", k, c } end
      SW.drag_source(0, k, c)
    end
  end
  ImGui.PopStyleVar(ctx)
  if action then
    if action[1] == "click" then SW.click(0, action[2], action[3])
    else SW.menu = { pi = 0, ci = action[2], c = action[3] }; SW.open_menu = true end
  end
end

-- Right-click menu of a swatch.
SW.menu_popup = function()
  if SW.open_menu then ImGui.OpenPopup(ctx, "swatchmenu"); SW.open_menu = false end
  if not ImGui.BeginPopup(ctx, "swatchmenu") then return end
  local m = SW.menu
  if m then
    local x, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.Dummy(ctx, 18, ImGui.GetTextLineHeight(ctx))
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), x, y + 1, x + 18, y + ImGui.GetTextLineHeight(ctx) - 1, C.rgba(m.c), 3)
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, C.hex(m.c))
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Color the selection") then A.color(m.c) end
    if ImGui.MenuItem(ctx, "Spread the palette from here") then A.spread(m.pi, m.ci) end
    if ImGui.MenuItem(ctx, "Make it the current color") then set_opt("current", m.c) end
    if ImGui.MenuItem(ctx, "Copy hex code") then ImGui.SetClipboardText(ctx, C.hex(m.c)) end
    local p = m.pi > 0 and PAL.list[m.pi]
    if p then
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Edit...") then SW.edit = { pi = m.pi, ci = m.ci, orig = m.c }; SW.open_edit = true end
      local sel = A.selection_colors()
      local has_sel = #sel > 0 -- decided once
      if ImGui.MenuItem(ctx, "Set to the selection's color", nil, false, has_sel) and has_sel then
        p.colors[m.ci] = sel[1]; PAL.save()
      end
      if ImGui.MenuItem(ctx, "Remove") then table.remove(p.colors, m.ci); PAL.save() end
    elseif m.pi == -1 then
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Remove from Recent") then table.remove(PAL.recent, m.ci); PAL.save_recent() end
    end
    if #PAL.list > 0 and ImGui.BeginMenu(ctx, "Add to palette") then
      for i, q in ipairs(PAL.list) do
        if i ~= m.pi and ImGui.MenuItem(ctx, q.name .. "##addto" .. i) then
          if #q.colors < MAX_SWATCHES then q.colors[#q.colors + 1] = m.c; PAL.save() end
        end
      end
      ImGui.EndMenu(ctx)
    end
  end
  ImGui.EndPopup(ctx)
end

-- Alt+click / Edit...: a color picker that edits the swatch live; Cancel puts it back.
SW.edit_popup = function()
  if SW.open_edit then ImGui.OpenPopup(ctx, "swatchedit"); SW.open_edit = false end
  local e = SW.edit
  local p = e and PAL.list[e.pi]
  if not ImGui.BeginPopup(ctx, "swatchedit") then
    -- Closed by clicking outside: keep the edit.
    if e and p and p.colors[e.ci] and p.colors[e.ci] ~= e.orig then PAL.save() end
    SW.edit = nil
    return
  end
  if not (p and p.colors[e.ci]) then
    ImGui.CloseCurrentPopup(ctx)
  else
    ImGui.SetNextItemWidth(ctx, 220)
    local ch, nc = ImGui.ColorPicker3(ctx, "##swedit", p.colors[e.ci],
      ImGui.ColorEditFlags_NoAlpha | ImGui.ColorEditFlags_NoSidePreview)
    if ch then p.colors[e.ci] = nc end
    if ImGui.Button(ctx, "OK", 80) then PAL.save(); e.orig = p.colors[e.ci]; ImGui.CloseCurrentPopup(ctx) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 80) then p.colors[e.ci] = e.orig; ImGui.CloseCurrentPopup(ctx) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Color selection", -1) then PAL.save(); A.color(p.colors[e.ci]) end
  end
  ImGui.EndPopup(ctx)
end

------------------------------------------------------------------------------------------------
-- SIDEBAR (palette list)
------------------------------------------------------------------------------------------------

local SB = { rename = nil, rename_text = "", open_rename = false, menu = nil, open_menu = false,
             confirm_delete = nil, open_delete = false }

SB.select = function(i) set_opt("sel", i) end

SB.new_palette = function(colors, name)
  PAL.list[#PAL.list + 1] = { name = PAL.unique_name(name or "My palette"), colors = colors or {} }
  PAL.save()
  SB.select(#PAL.list)
end

SB.move = function(i, d)
  local j = i + d
  if not (PAL.list[i] and PAL.list[j]) then return end
  PAL.list[i], PAL.list[j] = PAL.list[j], PAL.list[i]
  if O.sel == i then SB.select(j) elseif O.sel == j then SB.select(i) end
  if O.auto_palette == i then set_opt("auto_palette", j) elseif O.auto_palette == j then set_opt("auto_palette", i) end
  PAL.save()
end

SB.delete = function(i)
  if not PAL.list[i] then return end
  table.remove(PAL.list, i)
  if O.sel == i then SB.select(math.min(i, #PAL.list)) elseif O.sel > i then SB.select(O.sel - 1) end
  if O.auto_palette == i then set_opt("auto_palette", 0) elseif O.auto_palette > i then set_opt("auto_palette", O.auto_palette - 1) end
  PAL.save()
end

SB.import = function()
  local ok, path = r.GetUserFileNameForRead("", "Import palette", "*.txt;*.gpl;*.hex")
  if not ok or not path or path == "" then return end
  local p = PAL.read_file(path)
  if not p then T.msg, T.msg_ok = "No colors found in that file.", false; return end
  PAL.list[#PAL.list + 1] = p
  PAL.save()
  SB.select(#PAL.list)
  T.msg, T.msg_ok = string.format("Imported \"%s\" (%d colors).", p.name, #p.colors), true
end

SB.export = function(i)
  local p = PAL.list[i]
  if not p then return end
  local fname = p.name:gsub('[<>:"/\\|%?%*]', "_") .. ".txt"
  local path
  if r.JS_Dialog_BrowseForSaveFile then
    local rv, out = r.JS_Dialog_BrowseForSaveFile("Export palette", "", fname, "Palette (*.txt)\0*.txt\0\0")
    if rv ~= 1 or not out or out == "" then return end
    path = out:match("%.%w+$") and out or (out .. ".txt")
  else
    local dir = r.GetResourcePath() .. "/Data/jsabins_Color Palette"
    r.RecursiveCreateDirectory(dir, 0)
    path = dir .. "/" .. fname
  end
  if PAL.write_file(path, p) then
    T.msg, T.msg_ok = "Exported to " .. path, true
  else
    T.msg, T.msg_ok = "Couldn't write " .. path, false
  end
end

SB.draw = function()
  local action
  if ImGui.Selectable(ctx, "Build palette##pal0", O.sel == 0) then action = { "sel", 0 } end
  tip("Tools to build a palette: spectrum, gradient, shades, color harmony or random.\nSave the result as a palette of your own.")
  ImGui.Dummy(ctx, 0, 2)
  dim("Your palettes")
  for i, p in ipairs(PAL.list) do
    if ImGui.Selectable(ctx, p.name .. "##pal" .. i, O.sel == i) then action = { "sel", i } end
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then action = { "rename", i } end
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then action = { "menu", i } end
    SW.drag_target(i, #p.colors + 1)
    tip(string.format("%d color%s. Double-click to rename, right-click for more.\nDrop a swatch here to add it.",
      #p.colors, #p.colors == 1 and "" or "s"))
  end
  if #PAL.list == 0 then dim("(none yet)") end
  ImGui.Dummy(ctx, 0, 4)
  local bw = ImGui.GetContentRegionAvail(ctx)
  if ImGui.Button(ctx, "New palette", bw) then action = { "new" } end
  tip("Start an empty palette. Add colors with + or by dragging swatches onto it.")
  if ImGui.Button(ctx, "Import...", bw) then action = { "import" } end
  tip("Read a palette file: one #RRGGBB per line, or a GIMP .gpl palette.")

  if action then
    local a, i = action[1], action[2]
    if a == "sel" then SB.select(i)
    elseif a == "rename" then SB.rename, SB.rename_text, SB.open_rename = i, PAL.list[i].name, true
    elseif a == "menu" then SB.menu, SB.open_menu = i, true
    elseif a == "new" then SB.new_palette()
    elseif a == "import" then SB.import() end
  end
end

-- Palette menu (sidebar right-click and the ... button), rename and delete popups.
SB.popups = function()
  if SB.open_menu then ImGui.OpenPopup(ctx, "palmenu"); SB.open_menu = false end
  if ImGui.BeginPopup(ctx, "palmenu") then
    local i = SB.menu
    local p = i and PAL.list[i]
    if not p then ImGui.CloseCurrentPopup(ctx)
    else
      dim(p.name)
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Rename...") then SB.rename, SB.rename_text, SB.open_rename = i, p.name, true end
      if ImGui.MenuItem(ctx, "Duplicate") then
        local cols = {}
        for k, c in ipairs(p.colors) do cols[k] = c end
        table.insert(PAL.list, i + 1, { name = PAL.unique_name(p.name .. " copy"), colors = cols })
        PAL.save()
        SB.select(i + 1)
      end
      if ImGui.MenuItem(ctx, "Sort by hue") then
        table.sort(p.colors, function(a, b)
          local ha, sa, la = C.to_hsl(a)
          local hb, sb, lb = C.to_hsl(b)
          local ga, gb = sa < 0.08, sb < 0.08 -- greys last, dark to light
          if ga ~= gb then return gb end
          if ga then return la < lb end
          if math.abs(ha - hb) > 1e-3 then return ha < hb end
          return la > lb
        end)
        PAL.save()
      end
      if ImGui.MenuItem(ctx, "Export...") then SB.export(i) end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Move up", nil, false, i > 1) and i > 1 then SB.move(i, -1) end
      if ImGui.MenuItem(ctx, "Move down", nil, false, i < #PAL.list) and i < #PAL.list then SB.move(i, 1) end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Delete...") then SB.confirm_delete, SB.open_delete = i, true end
    end
    ImGui.EndPopup(ctx)
  end

  if SB.open_rename then ImGui.OpenPopup(ctx, "palrename"); SB.open_rename = false end
  if ImGui.BeginPopup(ctx, "palrename") then
    local p = SB.rename and PAL.list[SB.rename]
    if not p then ImGui.CloseCurrentPopup(ctx)
    else
      ImGui.SetNextItemWidth(ctx, 220)
      if ImGui.IsWindowAppearing(ctx) then ImGui.SetKeyboardFocusHere(ctx) end
      local ch, txt = ImGui.InputText(ctx, "##palname", SB.rename_text)
      if ch then
        SB.rename_text = txt
        local name = txt:match("^%s*(.-)%s*$")
        if name ~= "" then p.name = name; PAL.save() end
      end
      if ImGui.IsItemDeactivatedAfterEdit(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then ImGui.CloseCurrentPopup(ctx) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "OK") then ImGui.CloseCurrentPopup(ctx) end
    end
    ImGui.EndPopup(ctx)
  end

  if SB.open_delete then ImGui.OpenPopup(ctx, "paldelete"); SB.open_delete = false end
  if ImGui.BeginPopup(ctx, "paldelete") then
    local p = SB.confirm_delete and PAL.list[SB.confirm_delete]
    if not p then ImGui.CloseCurrentPopup(ctx)
    else
      ImGui.Text(ctx, string.format("Delete \"%s\" (%d colors)?", p.name, #p.colors))
      dim("Export it first if you might want it back.")
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x8E2A2AFF)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xB23636FF)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x6E1F1FFF)
      local del = ImGui.Button(ctx, "Delete", 90)
      ImGui.PopStyleColor(ctx, 3)
      if del then SB.delete(SB.confirm_delete); ImGui.CloseCurrentPopup(ctx) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Cancel", 90) then ImGui.CloseCurrentPopup(ctx) end
    end
    ImGui.EndPopup(ctx)
  end
end

------------------------------------------------------------------------------------------------
-- MAIN PANEL
------------------------------------------------------------------------------------------------

local MP = {}

-- Target row: Auto / Tracks / Items / Markers, plus the current color and Apply on the right.
MP.target_row = function()
  local avail = ImGui.GetContentRegionAvail(ctx)
  local right_w = math.floor(ImGui.GetFontSize(ctx) * 14)
  local seg_w = math.max(200, avail - right_w - 12)
  local auto_lbl = "Auto"
  if O.target == "auto" then auto_lbl = "Auto: " .. (T.kind == "tracks" and "Tracks" or T.kind == "items" and "Items" or "Markers") end
  local nv = UI.segmented("target", O.target, {
    { "auto", auto_lbl, "Follow where you last clicked in REAPER: items when you clicked in the arrange view\nand items are selected, otherwise the selected tracks." },
    { "tracks", "Tracks", "Color the selected tracks." },
    { "items", "Items", "Color the selected items." },
    { "markers", "Markers", "Color the markers and regions in the time selection\n(no time selection: the region around the edit cursor, or a marker right at it)." },
  }, seg_w)
  if nv ~= O.target then set_opt("target", nv); T.sig = nil end

  ImGui.SameLine(ctx, 0, 12)
  ImGui.AlignTextToFramePadding(ctx)
  dim("Current")
  ImGui.SameLine(ctx)
  local ch, nc = ImGui.ColorEdit3(ctx, "##current", O.current,
    ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha | ImGui.ColorEditFlags_NoLabel)
  if ch then O.current = nc end
  if ImGui.IsItemDeactivated(ctx) then save_opt("current") end
  tip("Current color: click to pick any color.\nUsed by Apply, +, and Gradient / Shade children when something has no color yet.")
  ImGui.SameLine(ctx)
  local pushed = UI.push_accent_button()
  local apply = ImGui.Button(ctx, "Apply##applycur", -1, 0)
  ImGui.PopStyleColor(ctx, pushed)
  if apply then save_opt("current"); A.color(O.current) end
  tip("Color the selection with the current color.")
end

MP.BUILD_MODES = {
  { "spectrum", "Spectrum", "Hues around the color wheel, in rows of lighter and darker shades." },
  { "gradient", "Gradient", "Steps from one color to another." },
  { "shades", "Shades", "Light to dark versions of one color." },
  { "harmony", "Harmony", "Colors that go together with a base color (one row per color, in shades)." },
  { "random", "Random", "Random colors within a saturation and lightness you set. Reroll for new ones." },
}

-- A labeled slider in a column (label width col, slider width w). Saves on release.
MP.slider = function(label, key, lo, hi, fmt, is_int, col, w, help, scale)
  scale = scale or 1
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, label)
  ImGui.SameLine(ctx, 0, math.max(4, col - ImGui.CalcTextSize(ctx, label)))
  ImGui.SetNextItemWidth(ctx, w)
  local ch, v
  if is_int then ch, v = ImGui.SliderInt(ctx, "##" .. key, math.floor(O[key]), lo, hi, fmt)
  else ch, v = ImGui.SliderDouble(ctx, "##" .. key, O[key] * scale, lo, hi, fmt); v = v / scale end
  if ch then O[key] = v end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then save_opt(key) end
  tip(help)
end

-- A color button with a label; saves when the picker closes.
MP.color = function(label, key, help)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, label)
  ImGui.SameLine(ctx)
  local ch, nc = ImGui.ColorEdit3(ctx, "##" .. key, O[key], ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
  if ch then O[key] = nc end
  if ImGui.IsItemDeactivated(ctx) then save_opt(key) end
  tip(help)
end

-- Two columns of sliders: each entry { label, key, lo, hi, fmt, is_int, help, scale }.
MP.two_columns = function(left, right)
  local col = math.floor(ImGui.CalcTextSize(ctx, "Saturation") + ImGui.GetFontSize(ctx))
  local half = (ImGui.GetContentRegionAvail(ctx) - 12) / 2
  ImGui.BeginGroup(ctx)
  for _, e in ipairs(left) do MP.slider(e[1], e[2], e[3], e[4], e[5], e[6], col, half - col, e[7], e[8]) end
  ImGui.EndGroup(ctx)
  if #right > 0 then
    ImGui.SameLine(ctx, 0, 12)
    ImGui.BeginGroup(ctx)
    for _, e in ipairs(right) do MP.slider(e[1], e[2], e[3], e[4], e[5], e[6], col, half - col, e[7], e[8]) end
    ImGui.EndGroup(ctx)
  end
end

-- "Current" and "From selection" helpers for a base color.
MP.base_buttons = function(key)
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Use current##" .. key) then set_opt(key, O.current) end
  tip("Use the current color (top right).")
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "From selection##" .. key) then
    local cols = A.selection_colors()
    if cols[1] then set_opt(key, cols[1]) else T.msg, T.msg_ok = "The selection has no colors.", false end
  end
  tip("Use the color of the first selected thing.")
end

MP.build_controls = function()
  local m = O.b_mode
  if m == "spectrum" then
    MP.two_columns({
      { "Hues", "gen_hues", 6, 36, "%d", true, "How many colors across." },
      { "Shades", "gen_rows", 1, 6, "%d rows", true, "How many rows of lighter and darker versions." },
    }, {
      { "Saturation", "gen_sat", 0.1, 1, "%.2f", false, "How strong the colors are." },
      { "Lightness", "gen_light", 0.2, 0.8, "%.2f", false, "How light the middle row is." },
    })
    local cg, gv = ImGui.Checkbox(ctx, "Grey row", O.gen_greys)
    if cg then set_opt("gen_greys", gv) end
    tip("A row of greys, dark to light, under the colors.")
  elseif m == "gradient" then
    MP.color("From", "b_from", "The first color.")
    ImGui.SameLine(ctx, 0, 14)
    MP.color("To", "b_to", "The last color.")
    ImGui.SameLine(ctx, 0, 14)
    if ImGui.Button(ctx, "Swap") then O.b_from, O.b_to = O.b_to, O.b_from; save_opt("b_from"); save_opt("b_to") end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "From selection##grad") then
      T.collect()
      local a = T.list[1] and T.get(T.list[1])
      local b = T.list[#T.list] and T.get(T.list[#T.list])
      if a and b then set_opt("b_from", a); set_opt("b_to", b)
      else T.msg, T.msg_ok = "Select two or more colored things: the first and last set the ends.", false end
    end
    tip("Take the ends from the first and last selected things.")
    MP.two_columns({ { "Steps", "b_steps", 2, 32, "%d colors", true, "How many colors in the gradient." } }, {})
    local cw, wv = ImGui.Checkbox(ctx, "Around the color wheel", O.b_wheel)
    if cw then set_opt("b_wheel", wv) end
    tip("Off: blend straight across (passes through greyer colors).\nOn: travel around the hues, so it stays colorful.")
  elseif m == "shades" then
    MP.color("Base", "b_base", "The color to make shades of.")
    MP.base_buttons("b_base")
    MP.two_columns({ { "Steps", "b_shades", 2, 24, "%d colors", true, "How many shades." } },
      { { "Range", "b_span", 10, 86, "%.0f %%", false, "How far apart the lightest and darkest are.", 100 } })
  elseif m == "harmony" then
    MP.color("Base", "b_base", "The color the others are worked out from.")
    MP.base_buttons("b_base")
    local choices = {}
    for i, sc in ipairs(PAL.SCHEMES) do choices[i] = { sc[1], sc[2], sc[4] } end
    local nv = UI.segmented("scheme", O.b_scheme, choices)
    if nv ~= O.b_scheme then set_opt("b_scheme", nv) end
    MP.two_columns({ { "Shades", "b_shades", 1, 9, "%d per color", true, "How many shades of each color (one row per color)." } }, {})
  else
    MP.two_columns({
      { "Colors", "b_count", 4, 96, "%d", true, "How many colors." },
      { "Variation", "b_vary", 0, 0.4, "%.2f", false, "How much saturation and lightness change from color to color." },
    }, {
      { "Saturation", "b_rsat", 0.1, 1, "%.2f", false, "How strong the colors are on average." },
      { "Lightness", "b_rlight", 0.2, 0.8, "%.2f", false, "How light the colors are on average." },
    })
    local pushed = UI.push_accent_button()
    local reroll = ImGui.Button(ctx, "Reroll", 100)
    ImGui.PopStyleColor(ctx, pushed)
    if reroll then set_opt("b_seed", math.random(1, 2147483646)) end
    tip("New random colors.")
  end
end

-- Build palette page: pick a tool, adjust it, then save the result as a palette or add it to one.
MP.build = function()
  section_title("Build palette")
  local mode = UI.segmented("bmode", O.b_mode, MP.BUILD_MODES)
  if mode ~= O.b_mode then set_opt("b_mode", mode) end
  ImGui.Dummy(ctx, 0, 2)
  SW.gen_grid()
  ImGui.Dummy(ctx, 0, 4)
  MP.build_controls()
  ImGui.Dummy(ctx, 0, 4)
  local flat = PAL.generated().flat
  local label = "Built"
  for _, bm in ipairs(MP.BUILD_MODES) do if bm[1] == O.b_mode then label = bm[2] end end
  local pushed = UI.push_accent_button()
  local save = ImGui.Button(ctx, "Save as new palette")
  ImGui.PopStyleColor(ctx, pushed)
  if save then
    local cols = {}
    for i, c in ipairs(flat) do if i <= MAX_SWATCHES then cols[i] = c end end
    SB.new_palette(cols, label)
  end
  tip(string.format("Make a palette of your own from these %d colors (then edit, reorder or rename it).", #flat))
  ImGui.SameLine(ctx)
  local has_pals = #PAL.list > 0 -- decided once for the Begin/EndDisabled pair
  if not has_pals then ImGui.BeginDisabled(ctx) end
  if ImGui.Button(ctx, "Add to palette...") then ImGui.OpenPopup(ctx, "buildadd") end
  if not has_pals then ImGui.EndDisabled(ctx) end
  tip("Add these colors to the end of one of your palettes.")
  if ImGui.BeginPopup(ctx, "buildadd") then
    for i, q in ipairs(PAL.list) do
      if ImGui.MenuItem(ctx, q.name .. "##badd" .. i) then
        local added = 0
        for _, c in ipairs(flat) do
          if #q.colors < MAX_SWATCHES then q.colors[#q.colors + 1] = c; added = added + 1 end
        end
        PAL.save()
        T.msg, T.msg_ok = string.format("Added %d color%s to \"%s\".", added, added == 1 and "" or "s", q.name), true
      end
    end
    ImGui.EndPopup(ctx)
  end
end

-- Header of a saved palette: name, + (current color), From selection, and the ... menu.
MP.palette_header = function(i, p)
  local x0 = ImGui.GetCursorPosX(ctx)
  local full = ImGui.GetContentRegionAvail(ctx)
  local big = UI.section_font and pcall(ImGui.PushFont, ctx, UI.section_font)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, p.name)
  if big then ImGui.PopFont(ctx) end
  ImGui.SameLine(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  dim(string.format("%d color%s", #p.colors, #p.colors == 1 and "" or "s"))
  local fh = ImGui.GetFrameHeight(ctx)
  local add_w = math.floor(ImGui.CalcTextSize(ctx, "From selection") + ImGui.GetFontSize(ctx) * 1.5)
  ImGui.SameLine(ctx)
  local sp = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  ImGui.SetCursorPosX(ctx, math.max(ImGui.GetCursorPosX(ctx), x0 + full - (fh * 2 + add_w + sp * 2)))
  local is_full = #p.colors >= MAX_SWATCHES -- decided once
  if is_full then ImGui.BeginDisabled(ctx) end
  local add = ImGui.Button(ctx, "+##addcur", fh, fh)
  if is_full then ImGui.EndDisabled(ctx) end
  if add and not is_full then p.colors[#p.colors + 1] = O.current; PAL.save() end
  tip("Add the current color (" .. C.hex(O.current) .. ") to this palette.")
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "From selection", add_w, fh) then
    local added = 0
    for _, c in ipairs(A.selection_colors()) do
      if #p.colors < MAX_SWATCHES then p.colors[#p.colors + 1] = c; added = added + 1 end
    end
    PAL.save()
    T.msg, T.msg_ok = added > 0 and string.format("Added %d color%s from the selection.", added, added == 1 and "" or "s")
      or "The selection has no colors to add.", added > 0
  end
  tip("Add the colors of the selected tracks, items or markers to this palette.")
  ImGui.SameLine(ctx)
  if UI.icon_button("##palmore", fh, UI.draw_dots) then SB.menu, SB.open_menu = i, true end
  tip("Rename, duplicate, sort, export, reorder or delete this palette.")
end

MP.body = function()
  if O.sel == 0 then
    MP.build()
  else
    local p = PAL.list[O.sel]
    if not p then SB.select(0); return end
    MP.palette_header(O.sel, p)
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 0, 2)
    if #p.colors == 0 then
      dim("Empty. Click + to add the current color, From selection to add the selection's\ncolors, or drag swatches here from Build palette or Recent.")
      local w = ImGui.GetContentRegionAvail(ctx)
      ImGui.Dummy(ctx, w, 40)
      SW.drag_target(O.sel, 1)
    else
      SW.grid(O.sel, p.colors)
      -- Room after the last swatch to drop at the end.
      local w = ImGui.GetContentRegionAvail(ctx)
      ImGui.Dummy(ctx, w, 8)
      SW.drag_target(O.sel, #p.colors + 1)
    end
  end
  ImGui.Dummy(ctx, 0, 6)
  section_title("Recent")
  if #PAL.recent == 0 then dim("Colors you use show up here.") else SW.grid(-1, PAL.recent) end
end

-- Bottom row of actions.
MP.footer = function()
  local has_sel = #T.list > 0 -- decided once for the Begin/EndDisabled pair
  local acts = {
    { "Spread", function() A.spread(O.sel) end, "Color the selection with this palette's colors in order (wraps around)." },
    { "Random", function() A.random(O.sel) end, "A random color from this palette for each selected thing." },
    { "Gradient", A.gradient, "Blend from the first selected thing's color to the last one's.\n(Something with no color uses the current color.)" },
    { "Random gradient", A.random_gradient, "Blend between two random colors that go well together, across the selection.\nClick again for another." },
    { "Shade children", A.shade_children, "Selected folder tracks: give their children lighter and lighter shades of the folder's color." },
    { "Lighter", function() A.shift_light(O.shade_step) end, "Make the selection's colors a little lighter." },
    { "Darker", function() A.shift_light(-O.shade_step) end, "Make the selection's colors a little darker." },
    { "Default", A.default, "Remove the selection's colors (back to the theme's default)." },
  }
  -- Each button as wide as its label plus an equal share of the room left over.
  local sp = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local avail = ImGui.GetContentRegionAvail(ctx)
  local text_w, widths = 0, {}
  for k, a in ipairs(acts) do widths[k] = ImGui.CalcTextSize(ctx, a[1]); text_w = text_w + widths[k] end
  local extra = math.max(0, (avail - sp * (#acts - 1) - text_w) / #acts)
  local run
  if not has_sel then ImGui.BeginDisabled(ctx) end
  for k, a in ipairs(acts) do
    if k > 1 then ImGui.SameLine(ctx) end
    if ImGui.Button(ctx, a[1] .. "##act" .. k, k == #acts and -1 or math.floor(widths[k] + extra), UI.FOOT_H) then run = a[2] end
    tip(has_sel and a[3] or "Select some tracks, items or markers first.")
  end
  if not has_sel then ImGui.EndDisabled(ctx) end
  if run and has_sel then run() end
end

------------------------------------------------------------------------------------------------
-- SETTINGS WINDOW (own window, page list on the left, like Wwise Tool's)
------------------------------------------------------------------------------------------------

local ST = { open = false, request = false, page = 1, docked = false }

local function checkbox(label, key, help)
  local ch, v = ImGui.Checkbox(ctx, label, O[key])
  if ch then set_opt(key, v) end
  if help then tip(help) end
end

ST.page_coloring = function()
  section_title("Tracks")
  checkbox("Folder children follow their parent", "children_follow",
    "Coloring a folder track gives everything inside it the same color.")
  checkbox("Items follow their track", "items_follow",
    "Coloring a track clears its items' own colors, so they show the track's color.")
  ImGui.Dummy(ctx, 0, 4)
  section_title("Items")
  checkbox("Clear take colors", "clear_takes",
    "Coloring an item also clears its takes' own colors (a take color would hide the item color).")
  ImGui.Dummy(ctx, 0, 4)
  section_title("Window")
  checkbox("Close the window after coloring", "quit_after", "Handy when the script is on a shortcut: pick a color and it's gone.")
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Lighter / Darker step")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  local ch, v = ImGui.SliderDouble(ctx, "##shade_step", O.shade_step * 100, 1, 20, "%.0f %%")
  if ch then O.shade_step = v / 100 end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then save_opt("shade_step") end
  tip("How much each click of Lighter or Darker changes the lightness.")
end

ST.page_new_tracks = function()
  section_title("New tracks")
  checkbox("Color new tracks automatically", "auto_new",
    "While this window is open, tracks you add get a color right away\n(tracks that already have a color, like duplicates, are left alone).")
  local on = O.auto_new -- decided once for the Begin/EndDisabled pair
  if not on then ImGui.BeginDisabled(ctx) end
  ImGui.Indent(ctx)
  if ImGui.RadioButton(ctx, "Next color from a palette", O.auto_source == "palette") then set_opt("auto_source", "palette") end
  ImGui.Indent(ctx)
  ImGui.SetNextItemWidth(ctx, 220)
  local cur = O.auto_palette == 0 and "Build palette" or (PAL.list[O.auto_palette] and PAL.list[O.auto_palette].name or "Build palette")
  if ImGui.BeginCombo(ctx, "##autopal", cur) then
    if ImGui.Selectable(ctx, "Build palette##ap0", O.auto_palette == 0) then set_opt("auto_palette", 0); set_opt("auto_next", 1) end
    for i, p in ipairs(PAL.list) do
      if ImGui.Selectable(ctx, p.name .. "##ap" .. i, O.auto_palette == i) then set_opt("auto_palette", i); set_opt("auto_next", 1) end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Start over") then set_opt("auto_next", 1) end
  tip("The next new track gets the palette's first color again.")
  ImGui.Unindent(ctx)
  if ImGui.RadioButton(ctx, "Always this color", O.auto_source == "fixed") then set_opt("auto_source", "fixed") end
  ImGui.SameLine(ctx)
  local ch, nc = ImGui.ColorEdit3(ctx, "##autocol", O.auto_color, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
  if ch then O.auto_color = nc end
  if ImGui.IsItemDeactivated(ctx) then save_opt("auto_color") end
  ImGui.Unindent(ctx)
  if not on then ImGui.EndDisabled(ctx) end
  ImGui.Dummy(ctx, 0, 4)
  dim("Works only while the Color Palette window is open.")
end

ST.page_appearance = function()
  section_title("Swatches")
  local function slider(label, key, lo, hi, fmt, help)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, label)
    ImGui.SameLine(ctx, 120)
    ImGui.SetNextItemWidth(ctx, 200)
    local ch, v = ImGui.SliderInt(ctx, "##" .. key, math.floor(O[key]), lo, hi, fmt)
    if ch then O[key] = v end
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then save_opt(key) end
    tip(help)
  end
  slider("Size", "swatch", 12, 48, "%d px", "Height of a swatch, and width in your palettes (the Build palette grid stretches to fit across).")
  slider("Gap", "swatch_gap", 0, 12, "%d px", "Space between swatches.")
  slider("Corners", "swatch_round", 0, 24, "%d px", "How rounded the swatches are.")
  ImGui.Dummy(ctx, 0, 4)
  section_title("Accent")
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Accent color")
  ImGui.SameLine(ctx, 120)
  local ch, nc = ImGui.ColorEdit3(ctx, "##accent", UI.accent(), ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
  if ch then O.accent = nc end
  if ImGui.IsItemDeactivated(ctx) then save_opt("accent") end
  tip("The chosen target, Apply, checkmarks and sliders.")
  ImGui.SameLine(ctx)
  local is_default = not (O.accent and O.accent > 0) -- decided once
  if is_default then ImGui.BeginDisabled(ctx) end
  local reset = ImGui.Button(ctx, "Reset##accent")
  if is_default then ImGui.EndDisabled(ctx) end
  if reset and not is_default then set_opt("accent", 0) end
  ImGui.Dummy(ctx, 0, 4)
  section_title("Colors")
  local function color_row(label, key, help)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, label)
    ImGui.SameLine(ctx, 120)
    local cc, cv = ImGui.ColorEdit3(ctx, "##" .. key, O[key], ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
    if cc then O[key] = cv end
    if ImGui.IsItemDeactivated(ctx) then save_opt(key) end
    tip(help)
  end
  color_row("Title", "look_title", "The big title at the top of the window.")
  color_row("Text", "look_text", "All normal text.")
  color_row("Dim text", "look_dim", "Hints and labels.")
  color_row("Background", "look_bg", "The window background.")
  color_row("Outline", "look_outline", "The thin line around the window.")
  ImGui.Dummy(ctx, 0, 4)
  section_title("Corners")
  slider("Window", "look_win_round", 0, 20, "%d px", "How rounded the window's corners are.")
  slider("Buttons", "look_frame_round", 0, 12, "%d px", "How rounded buttons, fields and panels are.")
  ImGui.Dummy(ctx, 0, 4)
  section_title("Font")
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Font")
  ImGui.SameLine(ctx, 120)
  ImGui.SetNextItemWidth(ctx, 200)
  if ImGui.BeginCombo(ctx, "##look_font", O.look_font) then
    for _, f in ipairs(UI.FONT_CHOICES) do
      if ImGui.Selectable(ctx, f, O.look_font == f) then set_opt("look_font", f) end
    end
    ImGui.EndCombo(ctx)
  end
  slider("Text size", "look_size", 9, 18, "%d px", "Size of normal text.")
  slider("Heading size", "look_head", 10, 24, "%d px", "Size of section headings (the title is 1px bigger).")
  dim("Font changes show the next time the window opens.")
  ImGui.Dummy(ctx, 0, 4)
  if ImGui.Button(ctx, "Reset appearance") then
    for _, k in ipairs(UI.LOOK_KEYS) do set_opt(k, O_DEFAULTS[k]) end
    for _, k in ipairs({ "swatch", "swatch_gap", "swatch_round", "accent" }) do set_opt(k, O_DEFAULTS[k]) end
  end
  tip("Back to the standard look (same as Wwise Tool's defaults).")
end

ST.page_palettes = function()
  section_title("Palettes")
  if ImGui.Button(ctx, "Import palette...") then SB.import() end
  tip("Read a palette file: one #RRGGBB per line, or a GIMP .gpl palette.")
  ImGui.SameLine(ctx)
  local has = O.sel > 0 and PAL.list[O.sel] ~= nil -- decided once
  if not has then ImGui.BeginDisabled(ctx) end
  local ex = ImGui.Button(ctx, "Export showing palette...")
  if not has then ImGui.EndDisabled(ctx) end
  if ex and has then SB.export(O.sel) end
  tip("Save the palette that's showing to a .txt file (one #RRGGBB per line).")
  ImGui.Dummy(ctx, 0, 4)
  if ImGui.Button(ctx, "Add the starter palettes") then PAL.add_starters() end
  tip("Adds Basic, Game audio, Soft and Deep again (your own palettes are kept).")
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Clear Recent") then PAL.recent = {}; PAL.save_recent() end
  ImGui.Dummy(ctx, 0, 4)
  dim("Palettes are saved for every project, not just this one.")
end

ST.PAGES = {
  { "Coloring", ST.page_coloring },
  { "New tracks", ST.page_new_tracks },
  { "Appearance", ST.page_appearance },
  { "Palettes", ST.page_palettes },
}

ST.window = function()
  if ST.request then
    ST.request = false
    ST.open = true
    ImGui.SetNextWindowFocus(ctx)
  end
  if not ST.open then return end
  ImGui.SetNextWindowSize(ctx, 620, 400, ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowSizeConstraints(ctx, 480, 300, 3000, 3000)
  local own_bg = not ST.docked
  ImGui.SetNextWindowBgAlpha(ctx, own_bg and 0 or 1)
  local bg_rgba = (UI.bg_rgb() << 8) | 0xFF
  local title_bg = own_bg and (bg_rgba & 0xFFFFFF00) or bg_rgba
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_rgba)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, title_bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, title_bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgCollapsed, title_bg)
  local col_n = 4
  if own_bg then ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00000000); col_n = 5 end -- title drawn by us
  local fp_x, fp_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, fp_x, math.max(fp_y, (UI.title_bar_size() - ImGui.GetFontSize(ctx)) / 2))
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, UI.WINDOW_ROUNDING)
  local visible, open = ImGui.Begin(ctx, "Color Palette Settings###cp_settings", (not own_bg) and true or nil, ImGui.WindowFlags_NoCollapse)
  ImGui.PopStyleVar(ctx, 2)
  ImGui.PopStyleColor(ctx, col_n)
  if open == false then ST.open = false end
  if not visible then return end
  ST.docked = ImGui.IsWindowDocked(ctx)
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww, wh = ImGui.GetWindowSize(ctx)
  if own_bg then
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.PushClipRect(ctx, wx, wy, wx + ww, wy + wh, false)
    ImGui.DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + wh, bg_rgba, UI.WINDOW_ROUNDING)
    ImGui.DrawList_AddRect(dl, wx + 0.5, wy + 0.5, wx + ww - 0.5, wy + wh - 0.5, UI.look.outline, UI.WINDOW_ROUNDING, 0, 1)
    ImGui.PopClipRect(ctx)
  end
  local round_n = UI.push_rounding()

  local footer_h = ImGui.GetFrameHeightWithSpacing(ctx) + 8
  local pad_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_WindowPadding)
  local side_w = 0
  for _, t in ipairs(ST.PAGES) do side_w = math.max(side_w, (ImGui.CalcTextSize(ctx, t[1]))) end
  side_w = math.floor(side_w + pad_x * 2 + 16)
  if ImGui.BeginChild(ctx, "##settings_nav", side_w, -footer_h, ImGui.ChildFlags_Border) then
    for i, t in ipairs(ST.PAGES) do
      if ImGui.Selectable(ctx, t[1] .. "##sp" .. i, ST.page == i) then ST.page = i end
    end
    ImGui.EndChild(ctx)
  end
  ImGui.SameLine(ctx)
  local page = ST.PAGES[ST.page] or ST.PAGES[1]
  if ImGui.BeginChild(ctx, "##settings_" .. page[1], 0, -footer_h) then
    page[2]()
    ImGui.EndChild(ctx)
  end

  ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, NAME .. " " .. VERSION)
  ImGui.SameLine(ctx)
  local w = 80
  local avail = ImGui.GetContentRegionAvail(ctx)
  if avail > w then ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + avail - w) end
  local esc = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows)
    and not ImGui.IsAnyItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)
  if ImGui.Button(ctx, "Close", w) or esc then ST.open = false end
  if own_bg then
    local size, m = UI.close_size(), UI.close_margin()
    local gap = math.floor(m * 0.6 + 0.5)
    ImGui.PushClipRect(ctx, wx, wy, wx + ww, wy + UI.title_bar_size(), false)
    ImGui.SetCursorScreenPos(ctx, wx + ww - size - m - gap, wy + m)
    if UI.close_button("##closesettings", size) then ST.open = false end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Close Settings") end
    local big = UI.title_font and pcall(ImGui.PushFont, ctx, UI.title_font)
    local _, th = ImGui.CalcTextSize(ctx, "Settings")
    UI.draw_title(ImGui.GetWindowDrawList(ctx), wx + m + 12, wy + m + (size - th) / 2 + 3,
      UI.look.title, "Settings")
    if big then ImGui.PopFont(ctx) end
    ImGui.PopClipRect(ctx)
  end
  if round_n > 0 then ImGui.PopStyleVar(ctx, round_n) end
  ImGui.End(ctx)
end

------------------------------------------------------------------------------------------------
-- MAIN WINDOW
------------------------------------------------------------------------------------------------

local W = { close = false, docked = false }

-- Status in the title bar: the dot, what's selected, and the last message.
W.status_items = function()
  local n = #T.list
  if n == 0 then
    return { { "Nothing selected", UI.dim_col(), "Select tracks, items, or markers/regions (time selection) to color." } }, UI.dim_col()
  end
  return { { T.noun(n), nil, "What a click on a swatch colors." } }, UI.COLOR_OK
end

W.title_status = function(right_x, top, h)
  local items, dot_col = W.status_items()
  local sp = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local dot = 8
  local w = dot + sp
  for i, it in ipairs(items) do w = w + ImGui.CalcTextSize(ctx, it[1]) + (i > 1 and sp or 0) end
  local th = ImGui.GetTextLineHeight(ctx)
  local x, y = right_x - w, top + (h - th) / 2
  ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx), x + dot / 2, top + h / 2, dot / 2, dot_col)
  x = x + dot + sp
  for _, it in ipairs(items) do
    ImGui.SetCursorScreenPos(ctx, x, y)
    if it[2] then ImGui.TextColored(ctx, it[2], it[1]) else ImGui.Text(ctx, it[1]) end
    if it[3] and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, it[3]) end
    x = x + ImGui.CalcTextSize(ctx, it[1]) + sp
  end
end

-- Floating: big bold title on the left; status, gear, ? and X on the right.
W.title_bar = function()
  local size, m = UI.close_size(), UI.close_margin()
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  ImGui.PushClipRect(ctx, wx, wy, wx + ww, wy + UI.title_bar_size(), false)
  local gap = math.floor(m * 0.6 + 0.5)
  local x = wx + ww - size - m - gap
  ImGui.SetCursorScreenPos(ctx, x, wy + m)
  if UI.close_button("##closewin", size) then W.close = true end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Close " .. NAME) end
  x = x - gap - size
  ImGui.SetCursorScreenPos(ctx, x, wy + m)
  if UI.icon_button("##guide_t", size, UI.draw_question) then UI.open_url(UI.GUIDE_URL) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open the Color Palette guide on GitHub") end
  x = x - gap - size
  ImGui.SetCursorScreenPos(ctx, x, wy + m)
  if UI.icon_button("##settings_t", size, UI.draw_gear) then ST.request = true end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Settings") end
  W.title_status(x - gap * 2, wy + m, size)
  local big = UI.title_font and pcall(ImGui.PushFont, ctx, UI.title_font)
  local _, th = ImGui.CalcTextSize(ctx, NAME)
  UI.draw_title(ImGui.GetWindowDrawList(ctx), wx + m + 12, wy + m + (size - th) / 2 + 3,
    UI.look.title, NAME)
  if big then ImGui.PopFont(ctx) end
  ImGui.PopClipRect(ctx)
end

-- Docked (no title bar): status, gear and ? on one row at the top, right-aligned.
W.docked_header = function()
  local size = ImGui.GetFrameHeight(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local aw = ImGui.GetContentRegionAvail(ctx)
  local gap = 6
  W.title_status(x0 + aw - 2 * size - gap * 3, y0, size)
  ImGui.SetCursorScreenPos(ctx, x0 + aw - 2 * size - gap, y0)
  if UI.icon_button("##settings_d", size, UI.draw_gear) then ST.request = true end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Settings") end
  ImGui.SetCursorScreenPos(ctx, x0 + aw - size, y0)
  if UI.icon_button("##guide_d", size, UI.draw_question) then UI.open_url(UI.GUIDE_URL) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open the Color Palette guide on GitHub") end
  ImGui.SetCursorScreenPos(ctx, x0, y0 + size + 4)
end

W.body = function()
  MP.target_row()
  ImGui.Dummy(ctx, 0, 2)
  local _, sp_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local msg_h = ImGui.GetTextLineHeightWithSpacing(ctx)
  local footer_h = UI.FOOT_H + sp_y + msg_h
  -- Sidebar as wide as its longest palette name (within limits).
  local side_w = ImGui.CalcTextSize(ctx, "Your palettes") + 40
  for _, p in ipairs(PAL.list) do side_w = math.max(side_w, ImGui.CalcTextSize(ctx, p.name) + 32) end
  side_w = math.floor(math.max(150, math.min(240, side_w)))
  if ImGui.BeginChild(ctx, "##sidebar", side_w, -footer_h, ImGui.ChildFlags_Border) then
    SB.draw()
    ImGui.EndChild(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.BeginChild(ctx, "##palette", 0, -footer_h, ImGui.ChildFlags_Border) then
    MP.body()
    ImGui.EndChild(ctx)
  end
  if T.msg then
    ImGui.TextColored(ctx, T.msg_ok and UI.COLOR_OK or UI.COLOR_BAD, T.msg)
  else
    dim("Click a swatch to color the selection. Shift+click spreads the palette from it.")
  end
  MP.footer()
  SW.menu_popup()
  SW.edit_popup()
  SB.popups()
end

W.frame = function()
  UI.sync_look()
  ImGui.SetNextWindowSize(ctx, 820, 560, ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowSizeConstraints(ctx, 720, 420, 4000, 4000)
  local main_font = UI.main_font and pcall(ImGui.PushFont, ctx, UI.main_font)
  ImGui.SetNextWindowCollapsed(ctx, false, ImGui.Cond_Always)
  local own_bg = not W.docked
  local bg_col = (UI.bg_rgb() << 8) | 0xFF
  ImGui.SetNextWindowBgAlpha(ctx, own_bg and 0 or 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, 0x202020FF) -- solid popups and tooltips
  local title_bg = own_bg and (UI.bg_rgb() << 8) or bg_col
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, title_bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, title_bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgCollapsed, title_bg)
  local theme_n = UI.push_theme()
  local accent_n = UI.push_accent()
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, UI.FRAME_ROUNDING)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, UI.FRAME_ROUNDING)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, UI.FRAME_ROUNDING)
  local pad_x, pad_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  local title_pad = (UI.title_bar_size() - ImGui.GetFontSize(ctx)) / 2
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, pad_x, math.max(pad_y, title_pad))
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, UI.WINDOW_ROUNDING)
  local hide_title = not W.docked -- decided once for the push/pop pair
  if hide_title then ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00000000) end
  local visible, open = ImGui.Begin(ctx, NAME, W.docked and true or nil,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if hide_title then ImGui.PopStyleColor(ctx) end
  ImGui.PopStyleVar(ctx, 2)
  if open == nil then open = true end
  if visible then
    local round_n = UI.push_rounding()
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 14)
    if own_bg then
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      ImGui.PushClipRect(ctx, wx, wy, wx + ww, wy + wh, false)
      ImGui.DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + wh, bg_col, UI.WINDOW_ROUNDING)
      ImGui.DrawList_AddRect(dl, wx + 0.5, wy + 0.5, wx + ww - 0.5, wy + wh - 0.5,
        UI.look.outline, UI.WINDOW_ROUNDING, 0, 1)
      ImGui.PopClipRect(ctx)
    end
    W.docked = ImGui.IsWindowDocked(ctx)
    if W.docked then W.docked_header() end

    W.body()

    if not W.docked then W.title_bar() end
    ImGui.PopStyleVar(ctx, 1)
    if round_n > 0 then ImGui.PopStyleVar(ctx, round_n) end
    ImGui.End(ctx)
  end
  -- Settings: its own window, drawn with the same theme and font.
  ST.window()
  ImGui.PopStyleVar(ctx, 3)
  ImGui.PopStyleColor(ctx, 4 + theme_n + accent_n)
  if main_font then ImGui.PopFont(ctx) end
  if W.close then open = false end
  return open
end

------------------------------------------------------------------------------------------------
-- DEFER LOOP
------------------------------------------------------------------------------------------------

local function loop()
  T.refresh()
  if O.auto_new or AUTO.known then AUTO.scan() end
  T.colored = false
  local open = W.frame()
  if T.colored and O.quit_after then open = false end
  if open then r.defer(loop) end
end

math.randomseed(math.floor(r.time_precise() * 1000) % 2147483647)
r.defer(loop)
