-- @description GunKit: Make 3P from 1P
-- @author Jay Sabins
-- @version 1.1.0
-- @changelog
--   The new folder holding Body and Thump keeps Body's name (e.g. ..._3P_..._Body) instead of ..._Body_Thump.
--   The copy's items (and automation) move to the right, starting 1 second after the original group's last item ends, so they don't sit under the original.
-- @about
--   Makes a third-person (3P) version of a first-person (1P) gun layer group.
--
--   Select the group's parent folder track (e.g. "SNS_SMG_BRP_Barrel_02") and run.
--   Selecting any track inside the group works too; the script climbs up to the
--   folder that holds the Body/Mech/Thump/Pre tracks. Several groups can be
--   selected at once. Only tracks directly inside the group count as layers.
--
--   For each group the script duplicates the folder and everything in it, right
--   below the original, and then on the copy only:
--     - moves all items (and automation) to the right so the copy starts
--       1 second after the original group's last item ends, timing kept
--     - sets every take to its left channel only (mono, non-destructive: take
--       channel mode "Left", so the source files are untouched)
--     - puts the Body and Thump folders inside one new folder track with Body's
--       name (e.g. "Wep_3P_..._Body"). Body and Thump keep their own tracks, FX and
--       children, so their processing is unchanged; the new folder has no FX.
--     - keeps Mech as it is
--     - deletes the Pre track and everything inside it
--     - changes "1P" to "3P" in every track name (only where 1P stands on its
--       own, like Wep_1P_SNS, so a name like "B1P2" is left alone)
--
--   Layer tracks are found by name, ignoring case: a word "Body", "Mech",
--   "Thump" or "Pre" separated by _ - . or spaces (so "Pressure" is not Pre).
--   The original group is never changed. Everything is one undo step.
--
--   No extensions required.

local r = reaper
local TITLE = "GunKit: Make 3P from 1P"

-- Gap (seconds) between the end of the original group's last item and the
-- start of the 3P copy's first item.
local GAP_AFTER_ORIGINAL = 1.0

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

-- The tracks of a folder: the parent and every descendant, in order.
-- Returns a list of { tr, level } with the parent at level 0, plus the
-- 0-based index range.
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

-- The parent folder of a track, or nil
local function parent_of(tr)
  return r.GetParentTrack(tr)
end

----------------------------------------------------------------------
-- Work out which groups to process
----------------------------------------------------------------------

-- true if the folder track has a Body/Mech/Thump/Pre track directly inside it
local function is_gun_group(tr)
  if depth_of(tr) <= 0 then return false end
  local block = folder_block(tr)
  for k = 2, #block do
    if block[k].level == 1 and role_of(track_name(block[k].tr)) then return true end
  end
  return false
end

local function collect_groups()
  local groups, seen = {}, {}
  for i = 0, r.CountSelectedTracks(0) - 1 do
    -- climb from the selected track until we reach a folder holding layer tracks
    local cur, g = r.GetSelectedTrack(0, i), nil
    while cur do
      if is_gun_group(cur) then g = cur break end
      cur = parent_of(cur)
    end
    if g and not seen[g] then
      seen[g] = true
      groups[#groups + 1] = g
    end
  end
  -- drop groups that sit inside another selected group
  local keep = {}
  for _, g in ipairs(groups) do
    local inside = false
    local p = parent_of(g)
    while p do
      if seen[p] then inside = true break end
      p = parent_of(p)
    end
    if not inside then keep[#keep + 1] = g end
  end
  -- bottom-most first, so earlier groups' indexes don't move under us
  table.sort(keep, function(a, b) return track_index(a) > track_index(b) end)
  return keep
end

----------------------------------------------------------------------
-- Process one group
----------------------------------------------------------------------

local function process_group(parent)
  local orig, first, last = folder_block(parent)
  if #orig < 2 then return false, track_name(parent) .. ": not a folder with tracks inside" end

  -- snapshot original folder depths so we can put them back exactly
  local orig_depth = {}
  for k, e in ipairs(orig) do orig_depth[k] = depth_of(e.tr) end

  -- 1. Duplicate: select exactly the group and run Track: Duplicate tracks
  r.SetOnlyTrackSelected(parent)
  for k = 2, #orig do r.SetTrackSelected(orig[k].tr, true) end
  r.Main_OnCommand(40062, 0) -- Track: Duplicate tracks

  local n = r.CountSelectedTracks(0)
  if n ~= #orig then
    return false, track_name(parent) .. ": duplicate failed (got " .. n .. " tracks, expected " .. #orig .. ")"
  end
  local dup = {}
  for k = 1, n do
    local tr = r.GetSelectedTrack(0, k - 1)
    if track_index(tr) ~= last + k then
      return false, track_name(parent) .. ": duplicate didn't land right after the original"
    end
    dup[k] = { tr = tr, level = orig[k].level }
  end

  -- Put the original's folder depths back. If the original's last track also
  -- closed outer folders, the copy's last track does that job now.
  local extra = orig_depth[#orig] + orig[#orig].level -- <= 0: outer folders closed
  for k, e in ipairs(orig) do
    r.SetMediaTrackInfo_Value(e.tr, "I_FOLDERDEPTH", orig_depth[k])
  end
  r.SetMediaTrackInfo_Value(orig[#orig].tr, "I_FOLDERDEPTH", -orig[#orig].level)

  -- 2. Find the layer tracks on the copy: tracks directly inside the group
  local role = {}  -- role -> index into dup
  for k = 2, #dup do
    if dup[k].level == 1 then
      local ro = role_of(track_name(dup[k].tr))
      if ro and not role[ro] then role[ro] = k end
    end
  end

  -- subtree (index range in dup) of the track at index k
  local function subtree(k)
    local lv, j = dup[k].level, k
    while dup[j + 1] and dup[j + 1].level > lv do j = j + 1 end
    return k, j
  end

  local notes = {}
  local level_of = {}  -- track -> new level
  for _, e in ipairs(dup) do level_of[e.tr] = e.level end

  -- 3. Delete Pre and everything inside it
  local delete = {}
  if role.pre then
    local a, b = subtree(role.pre)
    for k = a, b do delete[dup[k].tr] = true end
  else
    notes[#notes + 1] = "no Pre track found"
  end

  -- 4. Body + Thump into one new folder
  local wrap = nil
  local body_tracks, thump_tracks = {}, {}
  if role.body and role.thump then
    local a, b = subtree(role.body)
    for k = a, b do body_tracks[#body_tracks + 1] = dup[k].tr end
    a, b = subtree(role.thump)
    for k = a, b do thump_tracks[#thump_tracks + 1] = dup[k].tr end
    for _, tr in ipairs(body_tracks) do level_of[tr] = level_of[tr] + 1 end
    for _, tr in ipairs(thump_tracks) do level_of[tr] = level_of[tr] + 1 end
  else
    if not role.body then notes[#notes + 1] = "no Body track found" end
    if not role.thump then notes[#notes + 1] = "no Thump track found" end
  end
  if not role.mech then notes[#notes + 1] = "no Mech track found" end

  -- 4b. Move the copy to the right of the original: first item of the copy
  -- starts GAP_AFTER_ORIGINAL seconds after the original's last item ends
  local min_start, max_end = math.huge, -math.huge
  for _, e in ipairs(orig) do
    for i = 0, r.CountTrackMediaItems(e.tr) - 1 do
      local item = r.GetTrackMediaItem(e.tr, i)
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if pos < min_start then min_start = pos end
      if pos + len > max_end then max_end = pos + len end
    end
  end
  if max_end > min_start then
    local offset = (max_end - min_start) + GAP_AFTER_ORIGINAL
    for _, e in ipairs(dup) do
      if not delete[e.tr] then
        for i = 0, r.CountTrackMediaItems(e.tr) - 1 do
          local item = r.GetTrackMediaItem(e.tr, i)
          r.SetMediaItemInfo_Value(item, "D_POSITION", r.GetMediaItemInfo_Value(item, "D_POSITION") + offset)
        end
        -- automation follows the items
        for ei = 0, r.CountTrackEnvelopes(e.tr) - 1 do
          local env = r.GetTrackEnvelope(e.tr, ei)
          local np = r.CountEnvelopePointsEx(env, -1)
          for pi = 0, np - 1 do
            local ok, time = r.GetEnvelopePointEx(env, -1, pi)
            if ok then r.SetEnvelopePointEx(env, -1, pi, time + offset, nil, nil, nil, nil, true) end
          end
          if np > 0 then r.Envelope_SortPointsEx(env, -1) end
          for ai = 0, r.CountAutomationItems(env) - 1 do
            local p0 = r.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
            r.GetSetAutomationItemInfo(env, ai, "D_POSITION", p0 + offset, true)
          end
        end
      end
    end
  end

  -- 5. Mono from the left channel on every take of the copy (not the deleted Pre)
  for _, e in ipairs(dup) do
    if not delete[e.tr] then
      for i = 0, r.CountTrackMediaItems(e.tr) - 1 do
        local item = r.GetTrackMediaItem(e.tr, i)
        for t = 0, r.CountTakes(item) - 1 do
          local take = r.GetTake(item, t)
          if take then r.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", 3) end -- 3 = left only
        end
      end
    end
  end

  -- 6. Rename 1P -> 3P on the copy
  for _, e in ipairs(dup) do
    local name = track_name(e.tr)
    local new = to_3p(name)
    if new ~= name then r.GetSetMediaTrackInfo_String(e.tr, "P_NAME", new, true) end
  end

  -- Apply the structural changes. Build the final order first, then make the
  -- project match it and set every folder depth from the levels.
  local order = {}
  local placed_thump = false
  local in_thump = {}
  for _, tr in ipairs(thump_tracks) do in_thump[tr] = true end
  for _, e in ipairs(dup) do
    if delete[e.tr] then
      -- skip
    elseif in_thump[e.tr] then
      -- placed right after Body below
    else
      if #body_tracks > 0 and e.tr == body_tracks[1] then
        order[#order + 1] = "WRAP"
      end
      order[#order + 1] = e.tr
      if #body_tracks > 0 and e.tr == body_tracks[#body_tracks] then
        for _, t in ipairs(thump_tracks) do order[#order + 1] = t end
        placed_thump = true
      end
    end
  end

  -- delete Pre
  for tr in pairs(delete) do r.DeleteTrack(tr) end

  -- create the folder track that holds Body and Thump (named like Body)
  if #body_tracks > 0 then
    local body = body_tracks[1]
    local at = track_index(body)
    r.InsertTrackAtIndex(at, false)
    wrap = r.GetTrack(0, at)
    local bname = track_name(body)
    r.GetSetMediaTrackInfo_String(wrap, "P_NAME", bname, true)
    local col = r.GetMediaTrackInfo_Value(body, "I_CUSTOMCOLOR")
    if col ~= 0 then r.SetMediaTrackInfo_Value(wrap, "I_CUSTOMCOLOR", col) end
    level_of[wrap] = level_of[body] - 1
    for k, v in ipairs(order) do if v == "WRAP" then order[k] = wrap end end
  end

  -- move the Thump tracks so they follow Body (if they aren't there already)
  if placed_thump and #thump_tracks > 0 then
    local body_end = body_tracks[#body_tracks]
    if track_index(thump_tracks[1]) ~= track_index(body_end) + 1 then
      r.SetOnlyTrackSelected(thump_tracks[1])
      for k = 2, #thump_tracks do r.SetTrackSelected(thump_tracks[k], true) end
      -- the track that should come right after Thump in the final order
      local after = nil
      for k, v in ipairs(order) do
        if v == thump_tracks[#thump_tracks] then after = order[k + 1] break end
      end
      local target
      if after then target = track_index(after) else target = track_index(body_end) + 1 end
      r.ReorderSelectedTracks(target, 0)
    end
  end

  -- sanity check: the project now holds `order` contiguously from the parent
  local start = track_index(order[1])
  for k, tr in ipairs(order) do
    if track_index(tr) ~= start + k - 1 then
      return false, track_name(parent) .. ": couldn't arrange the copy's tracks (undo to restore)"
    end
  end

  -- set folder depths from the levels
  for k, tr in ipairs(order) do
    local lv = level_of[tr]
    local nxt = order[k + 1]
    local d
    if nxt then d = level_of[nxt] - lv else d = extra - lv end
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", d)
  end
  -- make sure the new folder's parent shows its children
  if wrap then r.SetMediaTrackInfo_Value(wrap, "I_FOLDERCOMPACT", 0) end

  local msg = nil
  if #notes > 0 then msg = to_3p(track_name(order[1])) .. ": " .. table.concat(notes, ", ") end
  return true, msg, order[1]
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

local groups = collect_groups()
if #groups == 0 then
  r.MB("Select the parent folder track of a 1P gun group (the folder holding the Body, Mech, Thump and Pre tracks) and run again.", TITLE, 0)
  return
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local errors, notes, made = {}, {}, {}
for _, g in ipairs(groups) do
  local ok, msg, new_parent = process_group(g)
  if ok then
    made[#made + 1] = new_parent
    if msg then notes[#notes + 1] = msg end
  else
    errors[#errors + 1] = msg
  end
end

-- leave the new 3P folders selected
r.SetOnlyTrackSelected(made[1] or groups[1])
for k = 2, #made do r.SetTrackSelected(made[k], true) end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Make 3P from 1P", -1)

if #errors > 0 or #notes > 0 then
  local lines = {}
  if #errors > 0 then
    lines[#lines + 1] = "Problems:"
    for _, e in ipairs(errors) do lines[#lines + 1] = "  " .. e end
  end
  if #notes > 0 then
    if #lines > 0 then lines[#lines + 1] = "" end
    lines[#lines + 1] = "Done, with notes:"
    for _, n in ipairs(notes) do lines[#lines + 1] = "  " .. n end
  end
  r.MB(table.concat(lines, "\n"), TITLE, 0)
end
