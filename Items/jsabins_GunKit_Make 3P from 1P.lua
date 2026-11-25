-- @description GunKit: Make 3P from 1P
-- @author Jay Sabins
-- @version 2.0.0
-- @changelog
--   Now works from selected folder items instead of whole tracks.
--   Select the 1P folder items of the shots you want and run: each shot's 3P copy is placed right after it on the timeline, on a 3P track group, and everything later in the project moves right to make room (items, regions, markers, automation).
--   A region named like the shot's original region (1P -> 3P) is added around the 3P copy.
--   The 3P track group is made the first time and reused after that, so running it on more shots doesn't create more tracks.
--   Fixed layers coming out staggered: items are now collected before anything moves.
-- @about
--   Makes third-person (3P) versions of first-person (1P) gun shots.
--
--   Select the folder items of the 1P shots you want (NVK auto-select of the
--   children is fine) and run. For each shot:
--     - everything after the shot moves right to make room (items on every
--       track, regions, markers and track automation), like a ripple edit
--     - the shot's items are copied into that space, 1 second after the shot
--       (or after its region) ends, with all layer timing kept exactly
--     - the copies go on the 3P track group, not the 1P tracks, and play their
--       left channel only (take channel mode "Left", source files untouched)
--     - if the shot sits in a region, a matching region is added around the
--       copy with 1P changed to 3P in its name
--
--   The 3P track group is made below the 1P group the first time, and reused
--   on later runs. It is a copy of the 1P group's tracks (FX, routing, colors)
--   with no items, where:
--     - Body and Thump sit inside one new folder track with Body's name; they
--       keep their own FX and children, the new folder has no FX
--     - Mech stays as it is
--     - Pre and everything inside it is left out (its items aren't copied)
--     - the top folder keeps its name with " - 3p" added
--     - "1P" becomes "3P" in the track names (only where 1P stands on its own)
--
--   The 1P group is the folder holding tracks named Body, Mech, Thump and Pre
--   (ignoring case; a word separated by _ - . or spaces, so "Pressure" is not
--   Pre). Shots from several gun groups at the same time share one ripple.
--   The 1P items are never changed. Everything is one undo step.
--
--   Not moved by the ripple: tempo and time signature changes.
--
--   No extensions required.

local r = reaper
local TITLE = "GunKit: Make 3P from 1P"

-- Gap (seconds) between the end of the 1P shot (or its region) and the 3P copy
local GAP = 1.0

-- Added to the end of the 3P group's top folder name
local PARENT_SUFFIX = " - 3p"

-- Stored on every 3P track: the GUID of the 1P track it copies ("wrap" on the
-- Body/Thump folder). This is how later runs find the 3P group again.
local EXT_SRC = "P_EXT:jsabins_3P_src"

local EPS = 1e-6

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function track_name(tr)
  local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return name
end

local function track_index(tr) -- 0-based
  return math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
end

local function depth_of(tr)
  return math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH"))
end

local function get_src(tr)
  local _, v = r.GetSetMediaTrackInfo_String(tr, EXT_SRC, "", false)
  return v or ""
end

local function set_src(tr, v)
  r.GetSetMediaTrackInfo_String(tr, EXT_SRC, v, true)
end

-- true if `word` appears in `name` as its own token (case-insensitive)
local function has_token(name, word)
  word = word:lower()
  for tok in name:lower():gmatch("[^%s_%-%.]+") do
    if tok == word then return true end
  end
  return false
end

local function role_of(name)
  if has_token(name, "body") then return "body" end
  if has_token(name, "mech") then return "mech" end
  if has_token(name, "thump") then return "thump" end
  if has_token(name, "pre") then return "pre" end
  return nil
end

-- "1P" -> "3P" only where it stands alone (Wep_1P_SNS, "1P Body", ...)
local function to_3p(name)
  local out = name:gsub("%f[%w]1([Pp])%f[%W]", "3%1")
  return out
end

-- The tracks of a folder: the parent and every descendant, in order,
-- as a list of { tr, level } with the parent at level 0.
local function folder_block(parent)
  local first = track_index(parent)
  local list = { { tr = parent, level = 0 } }
  local d = depth_of(parent)
  if d <= 0 then return list, first, first end
  local level, i, n = d, first + 1, r.CountTracks(0)
  while i < n do
    local tr = r.GetTrack(0, i)
    list[#list + 1] = { tr = tr, level = level }
    level = level + depth_of(tr)
    if level <= 0 then break end
    i = i + 1
  end
  return list, first, first + #list - 1
end

local function item_bounds(item)
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  return pos, pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
end

----------------------------------------------------------------------
-- Finding the 1P groups
----------------------------------------------------------------------

-- a 1P gun group: a folder (not one of our 3P tracks) with a Body/Mech/Thump/Pre
-- track directly inside it
local function is_gun_group(tr)
  if depth_of(tr) <= 0 or get_src(tr) ~= "" then return false end
  local block = folder_block(tr)
  for k = 2, #block do
    if block[k].level == 1 and role_of(track_name(block[k].tr)) then return true end
  end
  return false
end

-- the 1P group a track belongs to, or nil (tracks of a 3P group give nil)
local function group_of_track(tr)
  if get_src(tr) ~= "" then return nil end
  local cur = tr
  while cur do
    if is_gun_group(cur) then return cur end
    cur = r.GetParentTrack(cur)
  end
  return nil
end

----------------------------------------------------------------------
-- The 3P track group
----------------------------------------------------------------------

local function find_3p_group(parent)
  local g = r.GetTrackGUID(parent)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if get_src(tr) == g then return tr end
  end
  return nil
end

local function clear_track_contents(tr)
  for i = r.CountTrackMediaItems(tr) - 1, 0, -1 do
    r.DeleteTrackMediaItem(tr, r.GetTrackMediaItem(tr, i))
  end
  for ei = 0, r.CountTrackEnvelopes(tr) - 1 do
    local env = r.GetTrackEnvelope(tr, ei)
    r.DeleteEnvelopePointRangeEx(env, -1, -1e10, 1e10)
  end
end

-- Builds the 3P group below the 1P group. Returns its top track, or nil + error.
local function create_3p_group(parent, notes)
  local orig = folder_block(parent)
  local last = track_index(orig[#orig].tr)
  if #orig < 2 then return nil, track_name(parent) .. ": not a folder with tracks inside" end

  local orig_depth = {}
  for k, e in ipairs(orig) do orig_depth[k] = depth_of(e.tr) end

  -- duplicate exactly the group
  r.SetOnlyTrackSelected(parent)
  for k = 2, #orig do r.SetTrackSelected(orig[k].tr, true) end
  r.Main_OnCommand(40062, 0) -- Track: Duplicate tracks

  local n = r.CountSelectedTracks(0)
  if n ~= #orig then
    return nil, track_name(parent) .. ": duplicate failed (got " .. n .. " tracks, expected " .. #orig .. ")"
  end
  local dup = {}
  for k = 1, n do
    local tr = r.GetSelectedTrack(0, k - 1)
    if track_index(tr) ~= last + k then
      return nil, track_name(parent) .. ": duplicate didn't land right after the original"
    end
    dup[k] = { tr = tr, level = orig[k].level }
  end

  -- put the 1P group's folder depths back; the copy's last track takes over
  -- closing any outer folders the 1P group's last track closed
  local extra = orig_depth[#orig] + orig[#orig].level
  for k, e in ipairs(orig) do r.SetMediaTrackInfo_Value(e.tr, "I_FOLDERDEPTH", orig_depth[k]) end
  r.SetMediaTrackInfo_Value(orig[#orig].tr, "I_FOLDERDEPTH", -orig[#orig].level)

  -- empty copy, linked to its 1P tracks
  for k, e in ipairs(dup) do
    clear_track_contents(e.tr)
    set_src(e.tr, r.GetTrackGUID(orig[k].tr))
  end

  -- layer tracks: directly inside the group
  local role = {}
  for k = 2, #dup do
    if dup[k].level == 1 then
      local ro = role_of(track_name(dup[k].tr))
      if ro and not role[ro] then role[ro] = k end
    end
  end
  local function subtree(k)
    local lv, j = dup[k].level, k
    while dup[j + 1] and dup[j + 1].level > lv do j = j + 1 end
    return k, j
  end

  local level_of = {}
  for _, e in ipairs(dup) do level_of[e.tr] = e.level end

  local delete = {}
  if role.pre then
    local a, b = subtree(role.pre)
    for k = a, b do delete[dup[k].tr] = true end
  else
    notes[#notes + 1] = track_name(parent) .. ": no Pre track found"
  end

  local body_tracks, thump_tracks = {}, {}
  if role.body and role.thump then
    local a, b = subtree(role.body)
    for k = a, b do body_tracks[#body_tracks + 1] = dup[k].tr end
    a, b = subtree(role.thump)
    for k = a, b do thump_tracks[#thump_tracks + 1] = dup[k].tr end
    for _, tr in ipairs(body_tracks) do level_of[tr] = level_of[tr] + 1 end
    for _, tr in ipairs(thump_tracks) do level_of[tr] = level_of[tr] + 1 end
  else
    if not role.body then notes[#notes + 1] = track_name(parent) .. ": no Body track found" end
    if not role.thump then notes[#notes + 1] = track_name(parent) .. ": no Thump track found" end
  end
  if not role.mech then notes[#notes + 1] = track_name(parent) .. ": no Mech track found" end

  -- names
  for _, e in ipairs(dup) do
    local name = track_name(e.tr)
    local new = to_3p(name)
    if new ~= name then r.GetSetMediaTrackInfo_String(e.tr, "P_NAME", new, true) end
  end
  local top = track_name(dup[1].tr)
  if top:sub(-#PARENT_SUFFIX):lower() ~= PARENT_SUFFIX:lower() then
    r.GetSetMediaTrackInfo_String(dup[1].tr, "P_NAME", top .. PARENT_SUFFIX, true)
  end

  -- final order
  local in_thump = {}
  for _, tr in ipairs(thump_tracks) do in_thump[tr] = true end
  local order, placed_thump = {}, false
  for _, e in ipairs(dup) do
    if not delete[e.tr] and not in_thump[e.tr] then
      if #body_tracks > 0 and e.tr == body_tracks[1] then order[#order + 1] = "WRAP" end
      order[#order + 1] = e.tr
      if #body_tracks > 0 and e.tr == body_tracks[#body_tracks] then
        for _, t in ipairs(thump_tracks) do order[#order + 1] = t end
        placed_thump = true
      end
    end
  end

  for tr in pairs(delete) do r.DeleteTrack(tr) end

  -- folder holding Body and Thump, named like Body
  local wrap
  if #body_tracks > 0 then
    local body = body_tracks[1]
    local at = track_index(body)
    r.InsertTrackAtIndex(at, false)
    wrap = r.GetTrack(0, at)
    r.GetSetMediaTrackInfo_String(wrap, "P_NAME", track_name(body), true)
    local col = r.GetMediaTrackInfo_Value(body, "I_CUSTOMCOLOR")
    if col ~= 0 then r.SetMediaTrackInfo_Value(wrap, "I_CUSTOMCOLOR", col) end
    set_src(wrap, "wrap")
    level_of[wrap] = level_of[body] - 1
    for k, v in ipairs(order) do if v == "WRAP" then order[k] = wrap end end
  end

  -- Thump right after Body
  if placed_thump and #thump_tracks > 0 then
    local body_end = body_tracks[#body_tracks]
    if track_index(thump_tracks[1]) ~= track_index(body_end) + 1 then
      r.SetOnlyTrackSelected(thump_tracks[1])
      for k = 2, #thump_tracks do r.SetTrackSelected(thump_tracks[k], true) end
      local after
      for k, v in ipairs(order) do
        if v == thump_tracks[#thump_tracks] then after = order[k + 1] break end
      end
      local target = after and track_index(after) or (track_index(body_end) + 1)
      r.ReorderSelectedTracks(target, 0)
    end
  end

  local start = track_index(order[1])
  for k, tr in ipairs(order) do
    if track_index(tr) ~= start + k - 1 then
      return nil, track_name(parent) .. ": couldn't arrange the 3P tracks (undo to restore)"
    end
  end

  for k, tr in ipairs(order) do
    local nxt = order[k + 1]
    local d = nxt and (level_of[nxt] - level_of[tr]) or (extra - level_of[tr])
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", d)
  end
  if wrap then r.SetMediaTrackInfo_Value(wrap, "I_FOLDERCOMPACT", 0) end

  return order[1]
end

-- 1P track GUID -> 3P track, for one 3P group
local function map_3p_group(top3p)
  local map = {}
  for _, e in ipairs(folder_block(top3p)) do
    local s = get_src(e.tr)
    if s ~= "" and s ~= "wrap" then map[s] = e.tr end
  end
  return map
end

----------------------------------------------------------------------
-- Ripple: move everything at or after `at` right by `len`
----------------------------------------------------------------------

local function shift_envelope(env, at, len)
  local n = r.CountEnvelopePointsEx(env, -1)
  -- read first, then write (no reordering while we iterate)
  local moves = {}
  for i = 0, n - 1 do
    local ok, t = r.GetEnvelopePointEx(env, -1, i)
    if ok and t >= at - EPS then moves[#moves + 1] = { i = i, t = t } end
  end
  for _, m in ipairs(moves) do
    r.SetEnvelopePointEx(env, -1, m.i, m.t + len, nil, nil, nil, nil, true)
  end
  if #moves > 0 then r.Envelope_SortPointsEx(env, -1) end
  for ai = 0, r.CountAutomationItems(env) - 1 do
    local p = r.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
    if p >= at - EPS then r.GetSetAutomationItemInfo(env, ai, "D_POSITION", p + len, true) end
  end
end

local function ripple(at, len)
  -- items: collect every one first, then move (moving re-sorts a track's
  -- item list, so moving while walking it skips or double-moves items)
  local moves = {}
  for i = 0, r.CountMediaItems(0) - 1 do
    local item = r.GetMediaItem(0, i)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    if pos >= at - EPS then moves[#moves + 1] = { item = item, pos = pos } end
  end
  for _, m in ipairs(moves) do r.SetMediaItemInfo_Value(m.item, "D_POSITION", m.pos + len) end

  -- track automation (master too, except the tempo map)
  local tracks = { r.GetMasterTrack(0) }
  for i = 0, r.CountTracks(0) - 1 do tracks[#tracks + 1] = r.GetTrack(0, i) end
  for _, tr in ipairs(tracks) do
    for ei = 0, r.CountTrackEnvelopes(tr) - 1 do
      local env = r.GetTrackEnvelope(tr, ei)
      local _, ename = r.GetEnvelopeName(env)
      if ename ~= "Tempo map" then shift_envelope(env, at, len) end
    end
  end

  -- markers and regions
  local marks = {}
  local i = 0
  while true do
    local ret, isrgn, pos, rend, name, idx, color = r.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    marks[#marks + 1] = { isrgn = isrgn, pos = pos, rend = rend, name = name, idx = idx, color = color }
    i = i + 1
  end
  for _, m in ipairs(marks) do
    local np, ne = m.pos, m.rend
    if m.pos >= at - EPS then
      np = m.pos + len
      if m.isrgn then ne = m.rend + len end
    elseif m.isrgn and m.rend > at + EPS then
      ne = m.rend + len -- region spanning the insert point grows
    end
    if np ~= m.pos or ne ~= m.rend then
      r.SetProjectMarker3(0, m.idx, m.isrgn, np, ne, m.name, m.color)
    end
  end
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

-- 1. Selected items that belong to a 1P gun group
local sel = {}
local groups, group_list = {}, {}
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  local g = group_of_track(r.GetMediaItem_Track(item))
  if g then
    local s, e = item_bounds(item)
    sel[#sel + 1] = { s = s, e = e, g = g }
    if not groups[g] then groups[g] = true; group_list[#group_list + 1] = g end
  end
end
if #sel == 0 then
  r.MB("Select the folder items of the 1P shots you want to make 3P versions of (items on a gun group: the folder holding the Body, Mech, Thump and Pre tracks), then run again.", TITLE, 0)
  return
end

-- 2. Shots: selected items that overlap in time form one shot
table.sort(sel, function(a, b) return a.s < b.s end)
local shots = {}
for _, it in ipairs(sel) do
  local cur = shots[#shots]
  if cur and it.s <= cur.e + EPS then
    if it.e > cur.e then cur.e = it.e end
    if not cur.gset[it.g] then cur.gset[it.g] = true; cur.groups[#cur.groups + 1] = it.g end
  else
    shots[#shots + 1] = { s = it.s, e = it.e, gset = { [it.g] = true }, groups = { it.g } }
  end
end

-- the region a shot sits in (most overlap; the smaller one on a tie)
local function region_for(s, e)
  local best, best_ov, best_len
  local i = 0
  while true do
    local ret, isrgn, pos, rend, name, _, color = r.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    if isrgn then
      local ov = math.min(e, rend) - math.max(s, pos)
      local len = rend - pos
      if ov > EPS and (not best or ov > best_ov + EPS or (math.abs(ov - best_ov) <= EPS and len < best_len)) then
        best = { pos = pos, rend = rend, name = name, color = color }
        best_ov, best_len = ov, len
      end
    end
    i = i + 1
  end
  return best
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local notes, errors = {}, {}

-- 3. Make sure every group has its 3P tracks
local maps = {}
for _, g in ipairs(group_list) do
  local top = find_3p_group(g)
  if not top then
    local err
    top, err = create_3p_group(g, notes)
    if not top then errors[#errors + 1] = err end
  end
  if top then maps[g] = map_3p_group(top) end
end

-- 4. Each shot, latest first so earlier shots' positions stay put
local new_items = {}
local made = 0
for si = #shots, 1, -1 do
  local shot = shots[si]
  local rgn = region_for(shot.s, shot.e)
  local bs, be = shot.s, shot.e
  if rgn then bs = math.min(bs, rgn.pos); be = math.max(be, rgn.rend) end
  local insert_at = be
  local offset = (be + GAP) - bs        -- how far the copy sits from the 1P shot
  local space = (be - bs) + GAP         -- how much everything later moves

  -- collect what to copy before anything moves
  local copies, env_copies = {}, {}
  for _, g in ipairs(shot.groups) do
    local map = maps[g]
    if map then
      for _, e in ipairs(folder_block(g)) do
        local dest = map[r.GetTrackGUID(e.tr)]
        if dest then
          for i = 0, r.CountTrackMediaItems(e.tr) - 1 do
            local item = r.GetTrackMediaItem(e.tr, i)
            local s = item_bounds(item)
            if s >= shot.s - EPS and s < shot.e - EPS then
              local _, chunk = r.GetItemStateChunk(item, "", false)
              copies[#copies + 1] = { dest = dest, chunk = chunk, pos = s }
            end
          end
          -- automation inside the shot goes along to the same-named envelope
          for ei = 0, r.CountTrackEnvelopes(e.tr) - 1 do
            local env = r.GetTrackEnvelope(e.tr, ei)
            local _, ename = r.GetEnvelopeName(env)
            local pts = {}
            for pi = 0, r.CountEnvelopePointsEx(env, -1) - 1 do
              local ok, t, v, shape, tension = r.GetEnvelopePointEx(env, -1, pi)
              if ok and t >= shot.s - EPS and t <= shot.e + EPS then
                pts[#pts + 1] = { t = t, v = v, shape = shape, tension = tension }
              end
            end
            if #pts > 0 then env_copies[#env_copies + 1] = { dest = dest, name = ename, pts = pts } end
          end
        end
      end
    end
  end

  if #copies > 0 then
    ripple(insert_at, space)

    for _, c in ipairs(copies) do
      local item = r.AddMediaItemToTrack(c.dest)
      -- fresh GUIDs for the copy
      local chunk = c.chunk:gsub("\n%s*IGUID [^\n]*", ""):gsub("\n%s*GUID [^\n]*", "")
      r.SetItemStateChunk(item, chunk, false)
      r.SetMediaItemInfo_Value(item, "D_POSITION", c.pos + offset)
      for t = 0, r.CountTakes(item) - 1 do
        local take = r.GetTake(item, t)
        if take then r.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", 3) end -- left only
      end
      new_items[#new_items + 1] = item
    end

    for _, ec in ipairs(env_copies) do
      for ei = 0, r.CountTrackEnvelopes(ec.dest) - 1 do
        local env = r.GetTrackEnvelope(ec.dest, ei)
        local _, ename = r.GetEnvelopeName(env)
        if ename == ec.name then
          for _, p in ipairs(ec.pts) do
            r.InsertEnvelopePointEx(env, -1, p.t + offset, p.v, p.shape, p.tension, false, true)
          end
          r.Envelope_SortPointsEx(env, -1)
          break
        end
      end
    end

    if rgn then
      r.AddProjectMarker2(0, true, rgn.pos + offset, rgn.rend + offset, to_3p(rgn.name), -1, rgn.color)
    else
      notes[#notes + 1] = string.format("shot at %.3f s has no region, so no 3P region was made", shot.s)
    end
    made = made + 1
  end
end

-- leave the new 3P items selected
r.SelectAllMediaItems(0, false)
for _, item in ipairs(new_items) do r.SetMediaItemSelected(item, true) end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Make 3P from 1P", -1)

if made == 0 and #errors == 0 then
  notes[#notes + 1] = "nothing was copied (no items on the 3P group's tracks inside the selection)"
end
if #errors > 0 or #notes > 0 then
  local lines = {}
  if #errors > 0 then
    lines[#lines + 1] = "Problems:"
    for _, e in ipairs(errors) do lines[#lines + 1] = "  " .. e end
  end
  if #notes > 0 then
    if #lines > 0 then lines[#lines + 1] = "" end
    lines[#lines + 1] = "Notes:"
    for _, n in ipairs(notes) do lines[#lines + 1] = "  " .. n end
  end
  r.MB(table.concat(lines, "\n"), TITLE, 0)
end
