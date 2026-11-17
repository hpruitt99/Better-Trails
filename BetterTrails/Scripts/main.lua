-- Better Trails for Ski-E-O! Ski Resort Tycoon (UE4SS Lua mod)
-- Adds a "Better Trails" section to a trail's panel (Edit tab) that dresses the whole trail in one click, with the
-- game's own placeables, charged at their normal price and sold back with a refund:
--   Tower lights  everything Auto Trail Lights 1.1.1 does: Tower Lights along both edges (Uniform pairs or a Jagged
--                 zipper), evenly spaced so the trail is lit, night skiing turned on, colors and a rainbow Party mode
--   Rope lights   Festoon Lights or Hanging Lanterns, piece after piece: along both edges, zigzagging diagonally
--                 across the trail, or both
--   Snowblowers   along the edges, aimed across the trail, spaced so their spray covers it
--   Trail signs   Trail Markers showing the trail's difficulty in the sign style the player uses (North American,
--                 Alpine, Japanese or French & Nordic), at the entrance and, if wanted, all the way down
-- The mod only ever touches what it placed: things are named "<trail> Light #n" (the same names as Auto Trail Lights,
-- so its lights carry over), "<trail> Rope #n", "<trail> Snowblower #n" and "<trail> Sign #n". The game keeps those
-- names in the save. Things placed by hand are left alone.
-- How it works:
--   * The trail's shape comes from TrailMapSubsystem.RegisteredTrails (quadratic curves + corridor width); the game's
--     own IsPositionInCorridor finds the edges. Bowls get no section.
--   * Things are spawned like the game spawns them: deferred spawn, FinalizePlacement, then the price is deducted.
--   * The game only loads a building's class when one is placed or picked in the build menu, so when a class isn't
--     loaded the mod picks it in the build dock (which loads it), places the first piece, and closes the build
--     menu again a frame later.
-- Everything runs on the game thread. No files, no console commands, no keys.

local TAG = "[BetterTrails] "
local M = rawget(_G, "BETTER_TRAILS") or {}          -- the same table if this file runs again: no second loops
_G.BETTER_TRAILS = M
M.VERSION = "1.1.1"
M.stopped = false                                  -- this file running means the mod is on (see live switching below)

local CFG = {
  TOWER_CLASS     = "/Game/Blueprints/Decorations/BP_TowerLight.BP_TowerLight_C",
  TOWER_CDO       = "/Game/Blueprints/Decorations/BP_TowerLight.Default__BP_TowerLight_C",
  LIGHT_TEMPLATE  = "/Game/Blueprints/Decorations/BP_TowerLight.BP_TowerLight_C:LightZone_GEN_VARIABLE",
  LIGHT_KIND      = 3,       -- EAoEEffectKind::Light
  DEFAULT_RADIUS  = 5000,    -- cm, the tower light's LightZone radius (read from the game when it can be)
  COVER           = 0.8,     -- plan with 80% of the light radius, so slopes and the gaps between lights stay lit
  EDGE_OFFSET     = 450,     -- cm outside the trail's edge for tower lights (where players usually put them)
  FINE_STEP       = 500,     -- cm between measured points along the trail
  SPACING_STEP    = 250,     -- cm: even spacings tried, widest first
  OCCUPIED        = 800,     -- cm: a spot that already has a building this close is skipped
  MAX_EDGE_SEARCH = 20000,   -- cm: widest half-width looked for
  MAX_TOWERS      = 120,     -- per trail
  MAX_SAMPLES     = 3000,    -- trail points checked for light / snow
  CLEAR_RADIUS    = 400,     -- cm of trees cleared under something placed in the woods (charged like the game does)
  ENABLE_NIGHT    = true,    -- switch the trail's night skiing on after lighting it with towers
  REMOVE_PER_FRAME = 16,     -- things sold back per frame (cheap, and like placing: fewer, fuller frames)
  PARTY_PER_FRAME  = 60,     -- party lights recolored per frame (more than that: each one a little less often)
  PARTY_CYCLE      = 6.0,    -- seconds for the rainbow to go round once
  PARTY_WAVE       = 40000,  -- cm of trail per rainbow: the colors chase down the trail like an LED strip
  NAME_SUFFIX     = " Light #",
  -- rope lights
  ROPE_PIECE      = 616,     -- cm, one Festoon / Hanging Lanterns piece end to end (read from its mesh when loaded)
  ROPE_OFFSET     = 200,     -- cm outside the edge for strings along the edges (signs, towers, snowblowers go further out)
  ROPE_INSIDE     = 100,     -- cm inside the edge where a zigzag string turns
  ROPE_ZIG_MIN    = 2000,    -- cm along the trail per zigzag crossing, at least ...
  ROPE_ZIG_MAX    = 6000,    -- ... and at most (in between: the trail's width, so the strings run at about 45°)
  MAX_ROPE        = 400,     -- pieces per trail
  ROPE_MAX_SLOPE  = 20,      -- degrees: no rope piece where the ground is steeper: there the game flattens a pad
                             -- under each piece it places
  ROPE_PER_FRAME  = 8,
  -- snowblowers
  SNOW_OFFSET     = 500,     -- cm outside the edge
  SNOW_COVER      = 0.85,    -- plan with 85% of the spray cone's length
  SNOW_ANGLE_MARGIN = 5,     -- degrees off the cone's half angle
  SNOW_MIN_SPACING = 1500,   -- cm
  SNOW_GAP        = 600,     -- cm: a spot with a building this close slides along the edge
  MAX_SNOW        = 60,
  SNOW_PER_FRAME  = 1,
  -- signs
  SIGN_OFFSET     = 350,     -- cm outside the edge
  SIGN_ENTRANCE   = 1500,    -- cm down from the top of the trail for the entrance pair
  MAX_SIGNS       = 60,
  SIGN_PER_FRAME  = 8,
  JUNCTION_PROBE  = 300,     -- cm outside each edge where another trail is looked for
  JUNCTION_BEFORE = 1500,    -- cm up the trail from where the other trail starts, for its sign
  -- steep-section flags
  FLAG_OFFSET     = 100,     -- cm outside the edge
  FLAG_MIN_RUN    = 1000,    -- cm: steep stretches shorter than this get no flags
  MAX_FLAGS       = 120,
  FLAG_PER_FRAME  = 8,
  LIT_ON          = 0.9,     -- rope lights turn Night skiing on when they and the trail's other lights reach this much
}
M.CFG = CFG
local STYLES = { "uniform", "jagged" }
local STYLE_LABEL = { uniform = "Uniform", jagged = "Jagged" }

-- the game's placeables the mod uses: build-menu row (to load the class), class, and price until a placed one says
local KINDS = {
  tower   = { row = "TowerLight", path = CFG.TOWER_CLASS, short = "BP_TowerLight_C", cost = 820 },
  festoon = { row = "FestoonLights", short = "BP_FestoonLights_C", cost = 200, light = 1500, label = "Festoon", noShadow = true,
              path = "/Game/Blueprints/Decorations/BP_FestoonLights.BP_FestoonLights_C",
              zone = "/Game/Blueprints/Decorations/BP_FestoonLights.BP_FestoonLights_C:LightZone_GEN_VARIABLE",
              mesh = "/Game/Meshes/Props/sm_prop_light_festoon_a.sm_prop_light_festoon_a" },
  lantern = { row = "HangingLanterns", short = "BP_HangingLanterns_C", cost = 190, light = 1000, label = "Hanging Lanterns", noShadow = true,
              path = "/Game/Blueprints/Decorations/BP_HangingLanterns.BP_HangingLanterns_C",
              zone = "/Game/Blueprints/Decorations/BP_HangingLanterns.BP_HangingLanterns_C:LightZone_GEN_VARIABLE",
              mesh = "/Game/Meshes/Props/sm_prop_light_hanginglanterns_a.sm_prop_light_hanginglanterns_a" },
  snow    = { row = "Snowblower", short = "BP_Snowblower_C", cost = 6200,
              path = "/Game/Blueprints/Buildings/BP_Snowblower.BP_Snowblower_C",
              cdo = "/Game/Blueprints/Buildings/BP_Snowblower.Default__BP_Snowblower_C" },
  sign    = { row = "TrailMarkers", short = "BP_TrailMarkers_C", cost = 120,
              path = "/Game/Blueprints/Decorations/BP_TrailMarkers.BP_TrailMarkers_C" },
  flag    = { row = "Flags", short = "BP_Flags_C", cost = 100,
              path = "/Game/Blueprints/Decorations/BP_Flags.BP_Flags_C" },
}

local function log(s) print(TAG .. s .. "\n") end
local function valid(o) return o ~= nil and o:IsValid() end   -- check EVERY object: a method on a null one crashes
local function guarded(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then log(name .. ": " .. tostring(err)) end
  end
end

local P = M.P or {}                                -- the panel's state (see "the trail panel part")
M.P = P
local frame = 0                                    -- counts M.poll calls (every frame)

---------------------------------------------------------------------------------------------------------- game refs
-- The resort's world is the one its TrailMapSubsystem lives in. NOT FindFirstOf("World"): the main menu's world
-- (Map_Shared) stays loaded behind the game, and things spawned there are charged for but never seen or saved.
-- Everything here (subsystems, spawning, clocks) is taken from, or checked against, that world.
local R = {}
local refsTick = 0
local function worldOf(o)
  local ok, w = pcall(function() return o:GetWorld() end)
  if ok and valid(w) then return w end
end
local function sameObj(a, b)
  local ok, same = pcall(function() return a:GetAddress() == b:GetAddress() end)
  if ok then return same end
  return a:GetFullName() == b:GetFullName()
end
local function sameWorld(o, world)
  local w = worldOf(o)
  return (w and world) and sameObj(w, world) or false
end
local function findIn(cls, world)                  -- the object of class `cls` that lives in `world`
  for _, o in ipairs(FindAllOf(cls) or {}) do
    if valid(o) and sameWorld(o, world) then return o end
  end
end
local function pickTrailMap()                      -- the loaded resort's (an initialized one, if there are several)
  local best
  for _, o in ipairs(FindAllOf("TrailMapSubsystem") or {}) do
    if valid(o) then
      local ok, init = pcall(function() return o:IsInitialized() end)
      if ok and init then return o end
      best = best or o
    end
  end
  return best
end
local function refs(force)                         -- FindAllOf walks every object: only for what's missing, ~1/s
  refsTick = refsTick + 1
  if not force and valid(R.tm) and valid(R.world) and refsTick % 4 ~= 0 then return R end
  if not valid(R.tm) or refsTick % 240 == 0 then -- every ~60 s make sure it's still the loaded resort's
    local tm = pickTrailMap()
    if tm ~= nil and not (valid(R.tm) and sameObj(tm, R.tm)) then
      R.tm, R.eco, R.obs, R.reg, R.world, R.dock = tm, nil, nil, nil, nil, nil
    end
  end
  if not valid(R.tm) then return R end
  if not valid(R.world) then R.world = worldOf(R.tm) end
  if not valid(R.world) then return R end
  if not valid(R.eco) then R.eco = findIn("EconomySubsystem", R.world) end
  if not valid(R.obs) then R.obs = findIn("ObstacleDataManager", R.world) end
  if not valid(R.reg) then R.reg = findIn("PlaceableRegistrySubsystem", R.world) end
  if not valid(R.TU) then R.TU = StaticFindObject("/Script/SkiResortSimulator.Default__TerrainUtils") end
  if not valid(R.GS) then R.GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
  return R
end
local function ready(r)
  return valid(r.tm) and valid(r.TU) and valid(r.world) and valid(r.GS) and valid(r.reg)
end

-- An actor the mod destroyed stays findable (and IsValid) until the engine's garbage collection, and
-- IsActorBeingDestroyed() still says false; its refund value drops to 0 at once. So: remember what was destroyed
-- (by address) and treat it as gone while its refund is 0 (a new actor later at the same address has a price).
M.dead = M.dead or {}
local function addressOf(a)
  local ok, addr = pcall(function() return a:GetAddress() end)
  if ok then return addr end
  return a:GetFullName()
end
local function gone(a)
  local key = addressOf(a)
  if not M.dead[key] then return false end
  local ok, v = pcall(function() return a:GetRefundValue() end)
  if ok and v == 0 then return true end
  M.dead[key] = nil
  return false
end

-- Every actor of a class (its short name) in the loaded resort, from the resort's PlaceableRegistrySubsystem (its
-- Buildings list, or Snowblowers): about 1 ms for a few hundred buildings. FindAllOf walks every object in the game,
-- about 13 ms each time in a built-up resort, so the mod only uses it to find things once.
local function inWorld(short)
  local r = refs()
  local list = {}
  if not valid(r.reg) then return list end
  local ok = pcall(function()
    local arr = (short == "BP_Snowblower_C") and r.reg.Snowblowers or r.reg.Buildings
    for i = 1, #arr do
      local a = arr[i]
      if valid(a) and not gone(a) and a:GetClass():GetFName():ToString() == short then list[#list + 1] = a end
    end
  end)
  if not ok then                                   -- the registry couldn't be read: the slow way
    list = {}
    for _, a in ipairs(FindAllOf(short) or {}) do
      if valid(a) and not gone(a) and sameWorld(a, r.world) then list[#list + 1] = a end
    end
  end
  return list
end

-- every Tower Light in the loaded resort
local function resortTowers() return inWorld("BP_TowerLight_C") end

-- Tower Lights named like the mod's in another world than the resort's (an old Auto Trail Lights version spawned
-- some in the main menu's world): a full search, once per loaded resort
local function towersElsewhere()
  local r = refs()
  local list = {}
  if not valid(r.world) then return list end
  for _, a in ipairs(FindAllOf("BP_TowerLight_C") or {}) do
    if valid(a) and not gone(a) and not sameWorld(a, r.world) then list[#list + 1] = a end
  end
  return list
end

-- the price of one of a kind: what a placed one says (the class default is a placeholder), else the known price
M.costOf = M.costOf or {}
local function kindCost(k)
  if M.costOf[k] then return M.costOf[k] end
  for _, a in ipairs(inWorld(KINDS[k].short)) do
    local ok, c = pcall(function() return a.BaseCost end)
    if ok and type(c) == "number" and c > 0 and c < 100000 then M.costOf[k] = c; return c end
  end
  return KINDS[k].cost
end

-- Loading a kind's class: the game only loads a building's class when one exists or it's picked in the build menu.
-- So the mod picks it in the build dock (which loads it, sometimes over a few frames, and starts placing one), waits
-- for the class, closes placing again, and spawns two frames later, when the build menu's preview is gone: spawning a
-- Snowblower while its preview existed crashed the game. The class stays loaded once one of ours stands (and the
-- engine's garbage collection runs about once a minute, so the two frames in between are safe; if it ever did run
-- there, the load starts over).
-- loadStep(r, j, k) runs once a frame from the job: returns the class when it can be used, nil while loading, or
-- false, message when it can't be loaded.
local LOAD_TIMEOUT = 600                           -- frames (about 10 s)
local function dockOf(r)
  if not valid(r.dock) then r.dock = findIn("BuildDockComponent", r.world) or FindFirstOf("BuildDockComponent") end
  return valid(r.dock) and r.dock or nil
end
local function loadStep(r, j, k)
  local K = KINDS[k]
  local L = j.load
  if not L or L.k ~= k then                        -- not loading this one yet
    local c = StaticFindObject(K.path)
    if valid(c) and not L then return c end
    L = { k = k, phase = "select", tries = 0 }
    j.load = L
  end
  if L.phase == "select" then
    local dock = dockOf(r)
    if not dock then return false, "couldn't find the build menu" end
    L.tries = L.tries + 1
    if L.tries > 2 then return false, "couldn't load the game's " .. K.row .. " (is it unlocked yet?)" end
    pcall(function() dock:OnPaletteItemSelected(3, FName(K.row), FName("None")) end)   -- 3: EDockCategory::Buildings
    L.phase, L.at = "wait", frame
    return nil
  end
  if L.phase == "wait" then                        -- the class appears (now or a few frames later)
    if valid(StaticFindObject(K.path)) and frame - L.at >= 2 then
      local dock = dockOf(r)
      if dock then pcall(function() dock:OnDockCategoryChanged(0) end) end   -- 0: None (stops placing)
      L.phase, L.at = "settle", frame
    elseif frame - L.at > LOAD_TIMEOUT then
      local dock = dockOf(r)
      if dock then pcall(function() dock:OnDockCategoryChanged(0) end) end
      return false, "couldn't load the game's " .. K.row .. " (is it unlocked yet?)"
    end
    return nil
  end
  if L.phase == "settle" then                      -- the preview is gone: spawn
    if frame - L.at < 2 then return nil end
    local c = StaticFindObject(K.path)
    if valid(c) then
      j.load = nil
      log("loaded " .. K.row)
      return c
    end
    L.phase = "select"                             -- collected in between: once more
    return nil
  end
  return nil
end

local function lightRadius()
  local t = StaticFindObject(CFG.LIGHT_TEMPLATE)
  if valid(t) then
    local ok, v = pcall(function() return t.EffectRadius end)
    if ok and type(v) == "number" and v > 100 then return v end
  end
  return CFG.DEFAULT_RADIUS
end

-- the steepest ground a Tower Light may stand on, as the game checks it: towers follow the terrain, so the game's
-- limit is ConformingMaxSlopeAngle (40) rather than MaxSlopeAngle (22)
local function maxSlope()
  local cdo = StaticFindObject(CFG.TOWER_CDO)
  if valid(cdo) then
    local ok, v = pcall(function()
      local vc = cdo.ValidationComponent
      if not valid(vc) then return nil end
      if cdo.bConformsToTerrain then return vc.ConformingMaxSlopeAngle end
      return vc.MaxSlopeAngle
    end)
    if ok and type(v) == "number" and v > 0 then return v end
  end
  return 40
end

local function money(n)
  local neg = n < 0
  local s = tostring(math.floor(math.abs(n) + 0.5))
  local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-$" or "$") .. r
end

------------------------------------------------------------------------------------------------------------- trails
local function copyCurve(c)                        -- plain Lua copies: nothing holds on to game memory
  return { sx = c.StartPoint.X, sy = c.StartPoint.Y, cx = c.ControlPoint.X, cy = c.ControlPoint.Y,
           ex = c.Endpoint.X, ey = c.Endpoint.Y }
end

local function readTrails()
  local r = refs()
  local list = {}
  if not valid(r.tm) then return list end
  r.tm.RegisteredTrails:ForEach(function(k, v)
    local id, info = k:get(), v:get()
    local t = { id = id, name = info.DisplayName:ToString(), shape = info.Shape, night = info.bNightSkiing,
                curves = { copyCurve(info.Curve) } }
    pcall(function() t.diff = info.PlayerRatedDifficulty end)   -- 0 Beginner, 1 Intermediate, 2 Expert, 3 Pro, 255 none
    local extra = info.AdditionalCurves
    for i = 1, #extra do t.curves[#t.curves + 1] = copyCurve(extra[i]) end
    list[#list + 1] = t
  end)
  return list
end

local function trailNames()
  local names = {}
  for _, t in ipairs(readTrails()) do names[t.name] = true end
  return names
end

function M.trailByName(name)
  local found
  for _, t in ipairs(readTrails()) do
    if t.name == name then
      if found then return nil, "Two trails are called \"" .. name .. "\": rename one." end
      found = t
    end
  end
  return found
end

function M.trailById(id)
  for _, t in ipairs(readTrails()) do if t.id == id then return t end end
end

---------------------------------------------------------------------------------------------- measuring the trail
local function bez(a, b, c, t) local u = 1 - t; return u * u * a + 2 * u * t * b + t * t * c end
local function dbez(a, b, c, t) return 2 * (1 - t) * (b - a) + 2 * t * (c - b) end
local function inside(tm, x, y, id) return tm:IsPositionInCorridor({ X = x, Y = y, Z = 0 }, id) end

-- distance from (x, y) along (nx, ny) to the edge of trail `id`, starting the search near `guess`
local function edgeDistance(tm, x, y, nx, ny, id, guess)
  if not inside(tm, x, y, id) then return nil end
  local step = 250
  local d = math.max(0, math.floor((guess or 0) / step) * step)
  if d > 0 and not inside(tm, x + nx * d, y + ny * d, id) then
    repeat d = d - step until d <= 0 or inside(tm, x + nx * d, y + ny * d, id)
    d = math.max(d, 0)
  end
  while d < CFG.MAX_EDGE_SEARCH and inside(tm, x + nx * (d + step), y + ny * (d + step), id) do d = d + step end
  local lo, hi = d, d + step
  for _ = 1, 3 do
    local mid = (lo + hi) / 2
    if inside(tm, x + nx * mid, y + ny * mid, id) then lo = mid else hi = mid end
  end
  return lo
end

-- "segments" (curves that connect end to start make one): points every FINE_STEP with both edge distances
local function measure(tm, trail)
  local segs = {}
  for _, cv in ipairs(trail.curves) do
    local N, px, py, acc = 96, cv.sx, cv.sy, 0
    local tab = { { t = 0, s = 0 } }
    for i = 1, N do
      local t = i / N
      local x, y = bez(cv.sx, cv.cx, cv.ex, t), bez(cv.sy, cv.cy, cv.ey, t)
      acc = acc + math.sqrt((x - px) ^ 2 + (y - py) ^ 2); px, py = x, y
      tab[#tab + 1] = { t = t, s = acc }
    end
    if acc > 100 then
      local seg = { len = acc, pts = {} }
      local n = math.max(1, math.ceil(acc / CFG.FINE_STEP))
      local j, gl, gr = 1, nil, nil
      for k = 0, n do
        local s = acc * k / n
        while j < #tab - 1 and tab[j + 1].s < s do j = j + 1 end
        local a, b2 = tab[j], tab[j + 1]
        local t = a.t + (b2.t - a.t) * ((s - a.s) / math.max(b2.s - a.s, 1e-6))
        local x, y = bez(cv.sx, cv.cx, cv.ex, t), bez(cv.sy, cv.cy, cv.ey, t)
        local dx, dy = dbez(cv.sx, cv.cx, cv.ex, t), dbez(cv.sy, cv.cy, cv.ey, t)
        local l = math.sqrt(dx * dx + dy * dy)
        if l > 1e-3 then
          local nx, ny = -dy / l, dx / l
          local dl = edgeDistance(tm, x, y, nx, ny, trail.id, gl)
          local dr = edgeDistance(tm, x, y, -nx, -ny, trail.id, gr)
          gl, gr = dl or gl, dr or gr
          seg.pts[#seg.pts + 1] = { s = s, x = x, y = y, nx = nx, ny = ny, dl = dl, dr = dr }
        end
      end
      if #seg.pts >= 2 then
        local prev = segs[#segs]
        local last = prev and prev.pts[#prev.pts]
        if last and (last.x - seg.pts[1].x) ^ 2 + (last.y - seg.pts[1].y) ^ 2 < 200 ^ 2 then
          for i = 2, #seg.pts do                   -- carries on from the previous curve
            local q = seg.pts[i]; q.s = q.s + prev.len; prev.pts[#prev.pts + 1] = q
          end
          prev.len = prev.len + seg.len
        else
          segs[#segs + 1] = seg
        end
      end
    end
  end
  return segs
end

-- the point `off` cm outside the edge on `side` (1 = left, -1 = right; negative `off`: inside) at distance s along a
-- segment, with the outward normal (nx, ny), the direction of the segment (tx, ty) and the trail's width there
local function edgePoint(seg, s, side, off)
  local pts = seg.pts
  if s <= pts[1].s then s = pts[1].s end
  if s >= pts[#pts].s then s = pts[#pts].s end
  local i = 1
  while i < #pts - 1 and pts[i + 1].s < s do i = i + 1 end
  local a, b = pts[i], pts[math.min(i + 1, #pts)]
  local f = (b.s > a.s) and (s - a.s) / (b.s - a.s) or 0
  local key = side == 1 and "dl" or "dr"
  local da, db = a[key], b[key]
  if not da and not db then return nil end
  da, db = da or db, db or da
  local x, y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
  local nx, ny = a.nx + (b.nx - a.nx) * f, a.ny + (b.ny - a.ny) * f
  local l = math.sqrt(nx * nx + ny * ny); nx, ny = nx / l * side, ny / l * side
  local d = da + (db - da) * f + off
  return { x = x + nx * d, y = y + ny * d, nx = nx, ny = ny, tx = ny * side, ty = -nx * side, s = s, side = side,
           w = (a.dl or 0) + (a.dr or 0), seg = seg }
end

-- the spot EDGE_OFFSET outside the edge on `side` at distance s along a segment, facing the trail (tower lights)
local function spotAt(seg, s, side)
  local p = edgePoint(seg, s, side, CFG.EDGE_OFFSET)
  if not p then return nil end
  return { x = p.x, y = p.y, yaw = math.deg(math.atan(-p.ny, -p.nx)), s = p.s, side = side }
end

-- the mod's lights are named "<trail> Light #n" (towers) or "<trail> Rope #n" (rope light pieces), plus
-- " · <color>" when colored
local NAME_PATTERN = "^(.*)" .. CFG.NAME_SUFFIX:gsub("#", "%%#") .. "%d+$"
local ROPE_PATTERN = "^(.*) Rope #%d+$"
local COLOR_SEP = " \u{B7} "                         -- " · " between the name and the color: "... Light #3 · Blue"

-- "Upper Parlor Light #3 · Blue" -> "Upper Parlor Light #3", "Blue"
local function splitName(name)
  local base, tag = name:match("^(.-)" .. COLOR_SEP .. "(.+)$")
  if base and (base:match(NAME_PATTERN) or base:match(ROPE_PATTERN)) then return base, tag end
  return name, nil
end
local function lightTrailName(name)               -- the trail a light's name points at
  local base = splitName(name)
  return base:match(NAME_PATTERN) or base:match(ROPE_PATTERN)
end

-- everything any plan needs about one trail; built once each time the panel shows a trail (or it changes)
function M.base(trail)
  if trail.shape == 1 then return nil, "Bowls aren't trails: nothing to line here." end
  local r = refs(true)
  if not ready(r) then return nil, "The resort isn't loaded." end
  local tm = r.tm
  local b = { trail = trail, r = r }
  b.segs = measure(tm, trail)
  if #b.segs == 0 then return nil, "Couldn't find this trail's edges." end

  -- bounds of the trail, from its edges
  local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
  for _, seg in ipairs(b.segs) do
    for _, p in ipairs(seg.pts) do
      for _, side in ipairs({ 1, -1 }) do
        local d = side == 1 and p.dl or p.dr
        if d then
          local x, y = p.x + p.nx * side * d, p.y + p.ny * side * d
          minx, maxx, miny, maxy = math.min(minx, x), math.max(maxx, x), math.min(miny, y), math.max(maxy, y)
        end
      end
    end
  end
  if minx == math.huge then return nil, "Couldn't find this trail's edges." end

  -- trail points (a grid over the trail, kept if inside it): what has to be lit or covered with snow
  local area = (maxx - minx + 1) * (maxy - miny + 1)
  local step = math.max(600, math.sqrt(area / CFG.MAX_SAMPLES))
  b.samples = {}
  for x = minx + step / 2, maxx, step do
    for y = miny + step / 2, maxy, step do
      if inside(tm, x, y, trail.id) then b.samples[#b.samples + 1] = { x, y } end
    end
  end

  -- everything standing, to keep clear of: { x, y, key, small }. Strings and signs the mod placed ("... Rope #n",
  -- "... Sign #n") are small and sit at their own distance from the edge, so nothing avoids them; towers and
  -- snowblowers (both about 5 m out) avoid each other, the mod's own included.
  b.buildings = {}
  local function add(a)
    if not valid(a) or gone(a) then return end
    local ok, name = pcall(function() return a.InstanceName:ToString() end)
    name = ok and name or ""
    local l = a:K2_GetActorLocation()
    b.buildings[#b.buildings + 1] = { x = l.X, y = l.Y, key = a:GetFullName(),
                                      small = (splitName(name):match(" Rope #%d+$") or name:match(" Sign #%d+$")) and true or nil }
  end
  local list = r.reg.Buildings
  for i = 1, #list do add(list[i]) end
  pcall(function() local sb = r.reg.Snowblowers; for i = 1, #sb do add(sb[i]) end end)
  return b
end

--------------------------------------------------------------------------------------------------- the mod's lights
-- one of the mod's tower lights for this trail: named "<this trail> Light #n" (or "<a trail that no longer has that
-- name> Light #n", after a rename) and standing beside this trail. A neighbour's lights are never taken.

local PRESETS = {                                  -- hex is sRGB; nil = the game's own warm white
  { name = "Warm white" }, { name = "Cool white", hex = "#DCEBFF" }, { name = "Blue", hex = "#3A7BFF" },
  { name = "Green", hex = "#36D46A" }, { name = "Red", hex = "#FF3B30" }, { name = "Purple", hex = "#A55BFF" },
  { name = "Amber", hex = "#FFB020" }, { name = "Pink", hex = "#FF5FB4" },
}
local DEFAULT_SPOT = { R = 1, G = 1, B = 1, A = 1 }               -- the game's: NightSpot LightColor 255,255,255
local DEFAULT_GLOW = { R = 1.0, G = 0.91, B = 0.67, A = 1 }       -- MI_BrightLight "EmssiveColor" (sic)

-- A color is nil (warm white), "#RRGGBB", or "party" (the moving rainbow); in names: "Blue", "#3366FF", "Party".
local PARTY = "party"
local function tagHex(tag)                         -- the color part of a name -> "#RRGGBB" / "party" (nil: warm white)
  if not tag then return nil end
  if tag == "Party" then return PARTY end
  if tag:match("^#%x%x%x%x%x%x$") then return tag:upper() end
  for _, p in ipairs(PRESETS) do if p.name == tag then return p.hex end end
  return nil
end
local function hexTag(hex)                         -- "#RRGGBB" -> what goes in the name ("Blue", or the hex)
  if not hex then return nil end
  if hex == PARTY then return "Party" end
  for _, p in ipairs(PRESETS) do if p.hex == hex then return p.name end end
  return hex
end
local function hexRGB(hex) return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16) end
local function lin(c) c = c / 255; if c <= 0.04045 then return c / 12.92 end; return ((c + 0.055) / 1.055) ^ 2.4 end
local function hexLinear(hex) local r, g, b = hexRGB(hex); return { R = lin(r), G = lin(g), B = lin(b), A = 1 } end
local function colorName(hex)
  if not hex then return "Warm white" end
  return hexTag(hex)
end

local function isOurs(a, tm, trail, names)
  local ok, name = pcall(function() return a.InstanceName:ToString() end)
  if not (ok and name) then return false end
  local prefix = splitName(name):match(NAME_PATTERN)
  if not prefix then return false end
  if prefix ~= trail.name and names[prefix] then return false end      -- another trail's
  local l = a:K2_GetActorLocation()
  return tm:GetDistanceToCorridor({ X = l.X, Y = l.Y, Z = l.Z }, trail.id) <= CFG.EDGE_OFFSET + 500
end

function M.ourLights(trail)
  local r = refs()
  local list = {}
  if not valid(r.tm) then return list end
  local names = trailNames()
  for _, a in ipairs((resortTowers())) do
    if isOurs(a, r.tm, trail, names) then list[#list + 1] = a end
  end
  return list
end

-- the color of a trail's lights (from the first one's name); nil = warm white
local function lightsHex(ours)
  for _, a in ipairs(ours) do
    if valid(a) then
      local ok, name = pcall(function() return a.InstanceName:ToString() end)
      if ok then local _, tag = splitName(name); return tagHex(tag) end
    end
  end
  return nil
end
M.lightsHex = lightsHex

local function arrayItem(o)                        -- TArray items can come wrapped
  if o ~= nil and type(o) == "userdata" and o.IsValid == nil and o.get then return o:get() end
  return o
end
-- A Tower Light has more than one spot light: NightSpot, plus one the game's light-quality system adds at runtime
-- and fades to (it copies NightSpot's color at that moment, so one made before a recolor stays white). The beam you
-- see can be either, so every color change goes to all of them.
local LOCAL_LIGHT
local SHORT_KIND = {}                              -- class short name -> kind
for k, K in pairs(KINDS) do SHORT_KIND[K.short] = k end
local function kindOf(a)
  local ok, cn = pcall(function() return a:GetClass():GetFName():ToString() end)
  return ok and SHORT_KIND[cn] or nil
end
local function beams(a)
  local k = kindOf(a)
  if k == "festoon" or k == "lantern" then         -- a rope piece has one light: its RectLight
    local ok, l = pcall(function() return a.RectLight end)
    if ok and valid(l) then return { l } end
  end
  LOCAL_LIGHT = LOCAL_LIGHT or StaticFindObject("/Script/Engine.LocalLightComponent")
  local list = {}
  pcall(function()
    local ls = a:K2_GetComponentsByClass(LOCAL_LIGHT)
    for i = 1, #ls do
      local c = arrayItem(ls[i])
      if c ~= nil and c.IsValid ~= nil and c:IsValid() then list[#list + 1] = c end
    end
  end)
  if #list == 0 then pcall(function() if valid(a.NightSpot) then list[1] = a.NightSpot end end) end
  return list
end

-- The glowing part's material: a per-light copy (made once) of the game's material whose "EmssiveColor" (sic) can be
-- set (MI_BrightLight on a Tower Light, MI_Window on the Festoon bulbs; any material with that parameter). The
-- game's own glow and light colors per kind are remembered the first time, for "Warm white".
M.glowDefault = M.glowDefault or {}
M.spotDefault = M.spotDefault or {}
local function hasEmissive(mat)
  local found = false
  pcall(function()
    local vp = mat.VectorParameterValues
    for i = 1, #vp do
      local e = vp[i]
      if e.ParameterInfo.Name:ToString() == "EmssiveColor" then
        found = { R = e.ParameterValue.R, G = e.ParameterValue.G, B = e.ParameterValue.B, A = 1 }
      end
    end
  end)
  return found
end
local MESH_CLASS
local function glowMaterial(a)
  MESH_CLASS = MESH_CLASS or StaticFindObject("/Script/Engine.StaticMeshComponent")
  local ms = a:K2_GetComponentsByClass(MESH_CLASS)
  for i = 1, #ms do
    local m = arrayItem(ms[i])
    if m ~= nil and m.IsValid ~= nil and m:IsValid() then
      for slot = 0, m:GetNumMaterials() - 1 do
        local mat = m:GetMaterial(slot)
        if valid(mat) then
          local n = mat:GetFName():ToString()
          if n == "ATL_Glow" then return mat end
          local glow = hasEmissive(mat)
          if glow then
            local k = kindOf(a)
            if k and not M.glowDefault[k] then M.glowDefault[k] = glow end
            return m:CreateDynamicMaterialInstance(slot, mat, FName("ATL_Glow"))
          end
        end
      end
    end
  end
end

local function defaults(a)                         -- the game's own light and glow colors for this kind
  local k = kindOf(a) or "tower"
  if k == "tower" then return DEFAULT_SPOT, M.glowDefault.tower or DEFAULT_GLOW end
  if not M.spotDefault[k] then
    pcall(function()
      local t = StaticFindObject(KINDS[k].path .. ":RectLight_GEN_VARIABLE")
      local c = t.LightColor
      M.spotDefault[k] = { R = lin(c.R), G = lin(c.G), B = lin(c.B), A = 1 }
    end)
  end
  return M.spotDefault[k] or DEFAULT_SPOT, M.glowDefault[k] or { R = 1.0, G = 0.81, B = 0.28, A = 1 }
end

-- Party lights: kept in M.party (by object name) with their beam, glow material and position; M.partyStep()
-- recolors PARTY_PER_FRAME of them each frame from the real clock, so the rainbow runs at the same speed whatever
-- the game speed or frame rate.
local EMISSIVE = FName("EmssiveColor")
M.party = M.party or {}
local partyList, partyDirty, partyCursor, partyTick = {}, true, 0, 0
local BEAMS_RECHECK = 90                           -- frames between looks at a party light's spot lights

-- Each party light's distance along its own trail (from the trail's start), so the rainbow runs down the trail
-- like an LED strip and the two lights of a pair always match. Trails are sampled once (plain Lua, no game calls)
-- and again when a light names a trail that isn't sampled yet.
local trailPaths = nil
local function samplePaths()
  trailPaths = {}
  for _, t in ipairs(readTrails()) do
    local pts, acc = {}, 0
    for _, cv in ipairs(t.curves) do
      local px, py
      for i = 0, 48 do
        local u = i / 48
        local x, y = bez(cv.sx, cv.cx, cv.ex, u), bez(cv.sy, cv.cy, cv.ey, u)
        if px then acc = acc + math.sqrt((x - px) ^ 2 + (y - py) ^ 2) end
        px, py = x, y
        pts[#pts + 1] = { x, y, acc }
      end
    end
    trailPaths[t.name] = pts
  end
end
local function alongTrail(trailName, x, y)
  if not trailPaths or (trailName and not trailPaths[trailName]) then samplePaths() end
  local pts = trailName and trailPaths[trailName]
  if not pts then return nil end
  local best, bd = nil, math.huge
  for _, p in ipairs(pts) do
    local d = (p[1] - x) ^ 2 + (p[2] - y) ^ 2
    if d < bd then best, bd = p[3], d end
  end
  return best
end

local function partyAdd(a)
  local key = a:GetFullName()
  if M.party[key] and valid(M.party[key].a) then return end
  local l = a:K2_GetActorLocation()
  local mid
  pcall(function() mid = glowMaterial(a) end)
  local s
  pcall(function()
    s = alongTrail(lightTrailName(a.InstanceName:ToString()), l.X, l.Y)
  end)
  M.party[key] = { a = a, beams = beams(a), beamsAt = partyTick + BEAMS_RECHECK, mid = mid,
                    s = s or (l.X * 0.7071 + l.Y * 0.7071) }
  partyDirty = true
end

local function partyDrop(a)
  local ok, key = pcall(function() return a:GetFullName() end)
  if ok and M.party[key] then M.party[key] = nil; partyDirty = true end
end

local function hsv(h)                              -- full saturation and value, h in 0..1 -> linear color
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local q, t = 1 - f, f
  local r, g, b
  if i == 0 then r, g, b = 1, t, 0 elseif i == 1 then r, g, b = q, 1, 0 elseif i == 2 then r, g, b = 0, 1, t
  elseif i == 3 then r, g, b = 0, q, 1 elseif i == 4 then r, g, b = t, 0, 1 else r, g, b = 1, 0, q end
  return { R = lin(r * 255), G = lin(g * 255), B = lin(b * 255), A = 1 }
end

function M.partyStep()
  partyTick = partyTick + 1
  if partyDirty then
    partyList = {}
    for _, e in pairs(M.party) do partyList[#partyList + 1] = e end
    partyDirty = false
  end
  local n = #partyList
  if n == 0 then return end
  local r = refs()
  if not (valid(r.GS) and valid(r.tm)) then return end
  local now = r.GS:GetRealTimeSeconds(r.tm)          -- the resort's clock (a world-context object of that world)
  local phase = now / CFG.PARTY_CYCLE
  for _ = 1, math.min(n, CFG.PARTY_PER_FRAME) do
    partyCursor = partyCursor % n + 1
    local e = partyList[partyCursor]
    if not valid(e.a) then
      for k, v in pairs(M.party) do if v == e then M.party[k] = nil end end
      partyDirty = true
    else
      local h = phase - e.s / CFG.PARTY_WAVE
      local c = hsv(h - math.floor(h))
      if partyTick >= e.beamsAt then e.beams, e.beamsAt = beams(e.a), partyTick + BEAMS_RECHECK end
      for _, b in ipairs(e.beams) do if valid(b) then b:SetLightColor(c, true) end end
      if e.mid and valid(e.mid) then e.mid:SetVectorParameterValue(EMISSIVE, c) end
    end
  end
end

-- beam and glow of one light (hex nil: back to the game's own colors; "party": the rainbow)
local function paint(a, hex)
  if hex == PARTY then partyAdd(a) return end
  partyDrop(a)
  local spot, glow = defaults(a)
  if hex then spot = hexLinear(hex); glow = spot end
  for _, b in ipairs(beams(a)) do pcall(function() b:SetLightColor(spot, true) end) end
  pcall(function()
    local g = glowMaterial(a)
    if valid(g) then g:SetVectorParameterValue(EMISSIVE, glow) end
  end)
end

-- colors a trail's lights; rename = true also writes the color into their names (that's what gets saved)
function M.setColor(ours, hex, rename)
  local n = 0
  for _, a in ipairs(ours) do
    if valid(a) then
      paint(a, hex)
      n = n + 1
      if rename then
        local ok, name = pcall(function() return a.InstanceName:ToString() end)
        if ok then
          local base = splitName(name)
          local tag = hexTag(hex)
          pcall(function() a:SetInstanceName(FText(tag and (base .. COLOR_SEP .. tag) or base)) end)
        end
      end
    end
  end
  return n
end

-- after a resort loads the lights are the game's color again: color every light whose name says otherwise
local SPOT_CHECK = 4                               -- 0-255 tolerance when comparing the beam with its name
function M.repaintAll(skipTowers)
  local r = refs()
  if not valid(r.tm) then return 0 end
  local n = 0
  local all = skipTowers and {} or resortTowers()
  for _, k in ipairs({ "festoon", "lantern" }) do
    for _, a in ipairs(inWorld(KINDS[k].short)) do all[#all + 1] = a end
  end
  for _, a in ipairs(all) do
    if valid(a) then
      local ok, name = pcall(function() return a.InstanceName:ToString() end)
      if ok then
        local base, tag = splitName(name)
        local hex = tag and (base:match(NAME_PATTERN) or base:match(ROPE_PATTERN)) and tagHex(tag)
        if hex == PARTY then
          local okk, key = pcall(function() return a:GetFullName() end)
          if okk and not M.party[key] then paint(a, hex); n = n + 1 end
        elseif hex then
          local want = { hexRGB(hex) }
          local off = false
          for _, b in ipairs(beams(a)) do
            local okc, c = pcall(function() local lc = b.LightColor; return { lc.R, lc.G, lc.B } end)
            if not okc or math.abs(c[1] - want[1]) > SPOT_CHECK or math.abs(c[2] - want[2]) > SPOT_CHECK
               or math.abs(c[3] - want[3]) > SPOT_CHECK then off = true; break end
          end
          if off then paint(a, hex); n = n + 1 end
        end
      end
    end
  end
  if n > 0 then log("recolored " .. n .. " lights") end
  return n
end

----------------------------------------------------------------------------------------------- planning: towers
local function cellKey(x, y, size) return math.floor(x / size) .. ":" .. math.floor(y / size) end

-- how many of `samples` are within `reach` of any light in `lights` (spatial hash: lights are few, samples many)
local function coverage(samples, lights, reach, mark)
  local size, grid = reach, {}
  for _, l in ipairs(lights) do
    local k = cellKey(l.x, l.y, size); grid[k] = grid[k] or {}; table.insert(grid[k], l)
  end
  local r2, n = reach * reach, 0
  for i, p in ipairs(samples) do
    local cx, cy = math.floor(p[1] / size), math.floor(p[2] / size)
    local hit = false
    for gx = cx - 1, cx + 1 do
      for gy = cy - 1, cy + 1 do
        local cell = grid[gx .. ":" .. gy]
        if cell then
          for _, l in ipairs(cell) do
            if (p[1] - l.x) ^ 2 + (p[2] - l.y) ^ 2 <= r2 then hit = true; break end
          end
        end
        if hit then break end
      end
      if hit then break end
    end
    if hit then n = n + 1; if mark then mark[i] = true end end
  end
  return n
end

-- everything a tower plan needs about one trail (from its base)
function M.prepare(b)
  local trail, r = b.trail, b.r
  local ctx = { trail = trail, r = r, radius = lightRadius(), slopeMax = maxSlope(), segs = b.segs, samples = b.samples }
  ctx.reach = ctx.radius * CFG.COVER
  if #ctx.samples == 0 then return nil, "This trail has no area to light." end

  -- the mod's own lights on this trail (a new style replaces them) and other buildings
  ctx.ours = M.ourLights(trail)
  local oursSet = {}
  for _, a in ipairs(ctx.ours) do oursSet[a:GetFullName()] = true end
  ctx.buildings = {}
  for _, q in ipairs(b.buildings) do
    if not oursSet[q.key] and not q.small then ctx.buildings[#ctx.buildings + 1] = q end
  end
  -- what the edges can reach at all: lights every FINE_STEP on both sides
  local all = {}
  for _, seg in ipairs(ctx.segs) do
    for _, p in ipairs(seg.pts) do
      for _, side in ipairs({ 1, -1 }) do
        local sp = spotAt(seg, p.s, side); if sp then all[#all + 1] = sp end
      end
    end
  end
  ctx.reachable = coverage(ctx.samples, all, ctx.reach)
  return ctx
end

local function spotOk(ctx, sp, gap)
  local r = ctx.r
  if r.tm:GetDistanceToCorridor({ X = sp.x, Y = sp.y, Z = 0 }, -1) < CFG.EDGE_OFFSET * 0.5 then return false end
  for _, p in ipairs(ctx.buildings) do
    if (p.x - sp.x) ^ 2 + (p.y - sp.y) ^ 2 < gap * gap then return false end
  end
  if r.TU:GetSlopeAngleAtLocation(r.world, { X = sp.x, Y = sp.y }) > ctx.slopeMax then return false end
  return true
end

-- even spots for one spacing: "uniform" pairs at 0, D, 2D ... on both sides; "jagged" the same on the left and
-- half a step on (D/2, 3D/2 ...) on the right, so each light faces a gap: a zipper.
local function pattern(ctx, spacing, style)
  local list = {}
  for _, seg in ipairs(ctx.segs) do
    local n = math.max(1, math.ceil(seg.len / spacing))
    local step = seg.len / n
    for k = 0, n do local sp = spotAt(seg, step * k, 1); if sp then list[#list + 1] = sp end end
    if style == "jagged" then
      for k = 0, n - 1 do local sp = spotAt(seg, step * (k + 0.5), -1); if sp then list[#list + 1] = sp end end
    else
      for k = 0, n do local sp = spotAt(seg, step * k, -1); if sp then list[#list + 1] = sp end end
    end
  end
  return list
end

-- a spot that can't be used (another trail, a building, too steep) slides a little along the edge
local function settle(ctx, list)
  local out = {}
  for _, sp in ipairs(list) do
    local placed = false
    if spotOk(ctx, sp, CFG.OCCUPIED) then out[#out + 1] = sp; placed = true end
    if not placed then
      for _, seg in ipairs(ctx.segs) do
        for _, ds in ipairs({ 250, -250, 500, -500, 750, -750 }) do
          local p2 = spotAt(seg, sp.s + ds, sp.side)
          if p2 and (p2.x - sp.x) ^ 2 + (p2.y - sp.y) ^ 2 < 1200 ^ 2 and spotOk(ctx, p2, CFG.OCCUPIED) then
            out[#out + 1] = p2; placed = true; break
          end
        end
        if placed then break end
      end
    end
  end
  -- no two closer than 5 m (segments meet end to start)
  local final = {}
  for _, sp in ipairs(out) do
    local dup = false
    for _, q in ipairs(final) do if (q.x - sp.x) ^ 2 + (q.y - sp.y) ^ 2 < 500 ^ 2 then dup = true; break end end
    if not dup then final[#final + 1] = sp end
  end
  return final
end

-- the widest spacing at which pairs light everything the edges can reach (a zipper with the same spacing lights at
-- least as much); measured once per trail
local function evenSpacing(ctx)
  if ctx.spacing then return ctx.spacing end
  local target = ctx.reachable - math.max(1, math.floor(ctx.reachable * 0.005))
  ctx.spacing = CFG.FINE_STEP
  for spacing = math.floor(2 * ctx.reach / CFG.SPACING_STEP) * CFG.SPACING_STEP, CFG.FINE_STEP, -CFG.SPACING_STEP do
    if coverage(ctx.samples, pattern(ctx, spacing, "uniform"), ctx.reach) >= target then ctx.spacing = spacing; break end
  end
  return ctx.spacing
end

local function planEven(ctx, style)
  local best = { spacing = evenSpacing(ctx) }
  best.list = pattern(ctx, best.spacing, style)
  -- the even spacing actually used (each segment is split into equal parts no longer than `spacing`)
  local total, parts = 0, 0
  for _, seg in ipairs(ctx.segs) do
    total = total + seg.len
    parts = parts + math.max(1, math.ceil(seg.len / best.spacing))
  end
  return settle(ctx, best.list), total / math.max(parts, 1)
end

-- { style, towers = {spots}, removeCount, refund, cost (each), net, same (already installed like this) }
function M.plan(ctx, style)
  if style ~= "jagged" then style = "uniform" end
  local towers, spacing = planEven(ctx, style)
  while #towers > CFG.MAX_TOWERS do table.remove(towers) end
  local cost = kindCost("tower")
  local refund = 0
  for _, a in ipairs(ctx.ours) do
    local ok, v = pcall(function() return a:GetRefundValue() end)
    if ok and type(v) == "number" then refund = refund + v end
  end
  -- the same lights already standing? (each planned spot has one of ours within 3 m, and as many)
  local same = #ctx.ours > 0 and #ctx.ours == #towers
  if same then
    for _, sp in ipairs(towers) do
      local hit = false
      for _, a in ipairs(ctx.ours) do
        if valid(a) then
          local l = a:K2_GetActorLocation()
          if (l.X - sp.x) ^ 2 + (l.Y - sp.y) ^ 2 < 300 ^ 2 then hit = true; break end
        end
      end
      if not hit then same = false; break end
    end
  end
  local lit = coverage(ctx.samples, towers, ctx.reach)
  return { style = style, ctx = ctx, towers = towers, spacing = spacing, cost = cost, removeCount = #ctx.ours,
           refund = refund, net = cost * #towers - refund, same = same,
           dark = ctx.reachable < #ctx.samples or lit < ctx.reachable * 0.98 }
end

----------------------------------------------------------------------------------- planning: rope lights, snow, signs
-- pieces of length L laid end to end along a polyline (a list of {x, y}); the last piece ends where the line does
local function chain(poly, L, k, list, max, clear)
  if #poly < 2 then return end
  local cum = { 0 }
  for i = 2, #poly do cum[i] = cum[i - 1] + math.sqrt((poly[i].x - poly[i - 1].x) ^ 2 + (poly[i].y - poly[i - 1].y) ^ 2) end
  local total = cum[#poly]
  if total < L * 0.5 then return end
  local n = math.max(1, math.floor(total / L + 0.5))
  local step = total / n
  local j = 1
  local function at(s)                             -- s only ever grows, so j only moves forward
    while j < #poly - 1 and cum[j + 1] < s do j = j + 1 end
    local a, b = poly[j], poly[j + 1]
    local f = (cum[j + 1] > cum[j]) and (s - cum[j]) / (cum[j + 1] - cum[j]) or 0
    return a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
  end
  for i = 0, n - 1 do
    if #list >= max then return end
    local ax, ay = at(i * step)
    local bx, by = at((i + 1) * step)
    -- a piece's string runs along its own Y axis: turn it 90° less than the line's direction
    list[#list + 1] = { x = (ax + bx) / 2, y = (ay + by) / 2, yaw = math.deg(math.atan(by - ay, bx - ax)) - 90,
                        k = k, clear = clear }
  end
end

-- the line `off` cm outside one edge of a segment (split where the edge couldn't be found)
local function edgeLine(seg, side, off)
  local lines, cur = {}, {}
  for _, p in ipairs(seg.pts) do
    local d = side == 1 and p.dl or p.dr
    if d then
      cur[#cur + 1] = { x = p.x + p.nx * side * (d + off), y = p.y + p.ny * side * (d + off) }
    elseif #cur > 0 then
      lines[#lines + 1] = cur; cur = {}
    end
  end
  if #cur > 0 then lines[#lines + 1] = cur end
  return lines
end

local function ropeLength(k)
  local m = StaticFindObject(KINDS[k].mesh)
  if valid(m) then
    local ok, len = pcall(function() return m:GetBounds().BoxExtent.Y * 2 end)
    if ok and type(len) == "number" and len > 100 then return len end
  end
  return CFG.ROPE_PIECE
end

local function ropeLight(k)                        -- how far one piece lights, cm
  local t = StaticFindObject(KINDS[k].zone)
  if valid(t) then
    local ok, v = pcall(function() return t.EffectRadius end)
    if ok and type(v) == "number" and v > 100 then return v end
  end
  return KINDS[k].light
end

-- o.type: "festoon" / "lantern"; o.layout: "edges", "zigzag" (diagonal strings across the trail, edge to edge,
-- turning at each edge) or "both"
local function planRope(b, o)
  local k = o.type == "lantern" and "lantern" or "festoon"
  local L = ropeLength(k)
  local list = {}
  local r = b.r
  if o.layout ~= "zigzag" then
    for _, seg in ipairs(b.segs) do
      for _, side in ipairs({ 1, -1 }) do
        for _, line in ipairs(edgeLine(seg, side, CFG.ROPE_OFFSET)) do
          chain(line, L, k, list, CFG.MAX_ROPE, CFG.CLEAR_RADIUS * 0.6)
        end
      end
    end
  end
  if o.layout ~= "edges" then
    for _, seg in ipairs(b.segs) do
      local s, side = 0, 1
      while s < seg.len - 500 and #list < CFG.MAX_ROPE do
        local a = edgePoint(seg, s, side, -CFG.ROPE_INSIDE)
        local w = (a and a.w > 0) and a.w or CFG.ROPE_ZIG_MIN
        local s2 = math.min(seg.len, s + math.max(CFG.ROPE_ZIG_MIN, math.min(CFG.ROPE_ZIG_MAX, w)))
        local c = edgePoint(seg, s2, -side, -CFG.ROPE_INSIDE)
        if a and c then chain({ a, c }, L, k, list, CFG.MAX_ROPE, nil) end
        s, side = s2, -side
      end
    end
  end
  -- leave out pieces on ground steeper than ROPE_MAX_SLOPE (checked at the middle and at both posts)
  local kept, skipped = {}, 0
  for _, sp in ipairs(list) do
    local a = math.rad(sp.yaw + 90)                -- the string's direction
    local dx, dy = math.cos(a) * L / 2, math.sin(a) * L / 2
    local steep = false
    for _, q in ipairs({ { sp.x, sp.y }, { sp.x + dx, sp.y + dy }, { sp.x - dx, sp.y - dy } }) do
      local ok, ang = pcall(function() return r.TU:GetSlopeAngleAtLocation(r.world, { X = q[1], Y = q[2] }) end)
      if ok and type(ang) == "number" and ang > CFG.ROPE_MAX_SLOPE then steep = true; break end
    end
    if steep then skipped = skipped + 1 else kept[#kept + 1] = sp end
  end
  return kept, skipped
end

-- snowblowers spray a cone (ConeLength, ConeHalfAngleDeg) the way they face
local function snowCone()
  local len, half = 9000, 50
  local cdo = StaticFindObject(KINDS.snow.cdo)
  if valid(cdo) then
    pcall(function()
      if cdo.ConeLength > 100 then len = cdo.ConeLength end
      if cdo.ConeHalfAngleDeg > 1 then half = cdo.ConeHalfAngleDeg end
    end)
  end
  return len, half
end

-- spots every `spacing` along the edges facing into the trail: "zigzag" alternates sides, "oneside" keeps left
-- where on a trail: fractions from the top (0) to the bottom (1) of each segment
local function segDown(b, seg)                     -- true when s grows downhill
  if seg.down == nil then
    local r = b.r
    local z0 = r.TU:GetHeightAtLocation(r.world, { X = seg.pts[1].x, Y = seg.pts[1].y })
    local z1 = r.TU:GetHeightAtLocation(r.world, { X = seg.pts[#seg.pts].x, Y = seg.pts[#seg.pts].y })
    seg.down = z1 <= z0
  end
  return seg.down
end
local function segRange(b, seg, a, z)
  if segDown(b, seg) then return seg.len * a, seg.len * z end
  return seg.len * (1 - z), seg.len * (1 - a)
end
local function trailLength(b)                      -- cm
  local L = 0
  for _, seg in ipairs(b and b.segs or {}) do L = math.max(L, seg.len) end
  return L
end
local function sampleFractions(b)                  -- each sample's fraction down its nearest segment (once a trail)
  if b.frac then return b.frac end
  b.frac = {}
  for i, q in ipairs(b.samples) do
    local best, bd, bseg = 0, math.huge, b.segs[1]
    for _, seg in ipairs(b.segs) do
      for j = 1, #seg.pts, 2 do
        local p = seg.pts[j]
        local d = (p.x - q[1]) ^ 2 + (p.y - q[2]) ^ 2
        if d < bd then bd, best, bseg = d, p.s, seg end
      end
    end
    local f = best / math.max(bseg.len, 1)
    b.frac[i] = segDown(b, bseg) and f or 1 - f
  end
  return b.frac
end
local SNOW_RANGES = { full = { 0, 1 }, top = { 0, 0.5 }, bottom = { 0.5, 1 } }
local function snowRange(o)
  if o.range == "custom" then
    local a, z = o.from or 0, o.to or 1
    if a > z then a, z = z, a end
    if z - a < 0.05 then z = math.min(1, a + 0.05); a = z - 0.05 end
    return a, z
  end
  local r = SNOW_RANGES[o.range] or SNOW_RANGES.full
  return r[1], r[2]
end

local function snowPattern(b, spacing, style, ra, rz)
  local list = {}
  for _, seg in ipairs(b.segs) do
    local s0, s1 = segRange(b, seg, ra or 0, rz or 1)
    local n = math.max(1, math.ceil((s1 - s0) / spacing))
    local step = (s1 - s0) / n
    for k = 0, n do
      local side = (style == "zigzag" and k % 2 == 1) and -1 or 1
      local sp = edgePoint(seg, s0 + step * k, side, CFG.SNOW_OFFSET)
      if sp then
        sp.fx, sp.fy = -sp.nx, -sp.ny
        sp.yaw, sp.k, sp.clear = math.deg(math.atan(sp.fy, sp.fx)), "snow", CFG.CLEAR_RADIUS
        list[#list + 1] = sp
      end
    end
  end
  return list
end

local function coneCoverage(samples, guns, len, half)
  local size, grid = len, {}
  for _, g in ipairs(guns) do
    local key = cellKey(g.x, g.y, size); grid[key] = grid[key] or {}; table.insert(grid[key], g)
  end
  local l2, c, n = len * len, math.cos(math.rad(half)), 0
  for _, p in ipairs(samples) do
    local cx, cy = math.floor(p[1] / size), math.floor(p[2] / size)
    local hit = false
    for gx = cx - 1, cx + 1 do
      for gy = cy - 1, cy + 1 do
        local cell = grid[gx .. ":" .. gy]
        if cell and not hit then
          for _, g in ipairs(cell) do
            local dx, dy = p[1] - g.x, p[2] - g.y
            local d2 = dx * dx + dy * dy
            if d2 <= l2 and (d2 < 1 or dx * g.fx + dy * g.fy >= c * math.sqrt(d2)) then hit = true; break end
          end
        end
      end
    end
    if hit then n = n + 1 end
  end
  return n
end

local function freeSnowSpot(b, sp, skip)
  if b.r.tm:GetDistanceToCorridor({ X = sp.x, Y = sp.y, Z = 0 }, -1) < CFG.SNOW_OFFSET * 0.5 then return false end
  for _, q in ipairs(b.buildings) do
    if not q.small and not skip[q.key] and (q.x - sp.x) ^ 2 + (q.y - sp.y) ^ 2 < CFG.SNOW_GAP ^ 2 then return false end
  end
  return true
end

-- ours: this trail's snowblowers the plan would replace (they don't block their own spots)
local function planSnow(b, o, ours)
  local len, half = snowCone()
  len, half = len * CFG.SNOW_COVER, half - CFG.SNOW_ANGLE_MARGIN
  local style = o.style == "oneside" and "oneside" or "zigzag"
  local ra, rz = snowRange(o)
  local frac = sampleFractions(b)
  local sub = {}
  for i, q in ipairs(b.samples) do if frac[i] >= ra - 0.01 and frac[i] <= rz + 0.01 then sub[#sub + 1] = q end end
  local key = style .. ":" .. ra .. ":" .. rz
  b.snowSpacing = b.snowSpacing or {}
  if not b.snowSpacing[key] then                 -- the widest spacing that still covers what the edges can reach
    local reach = coneCoverage(sub, snowPattern(b, CFG.SNOW_MIN_SPACING, style, ra, rz), len, half)
    -- one side can't cover the strip along its own edge between guns (the cones start narrow): it aims for most of it
    local target = reach - math.max(1, math.floor(reach * (style == "oneside" and 0.12 or 0.03)))
    local best = CFG.SNOW_MIN_SPACING
    for spacing = math.floor(len * 1.6 / 500) * 500, CFG.SNOW_MIN_SPACING, -500 do
      if coneCoverage(sub, snowPattern(b, spacing, style, ra, rz), len, half) >= target then best = spacing; break end
    end
    b.snowSpacing[key] = best
  end
  local skip = {}
  for _, a in ipairs(ours or {}) do pcall(function() skip[a:GetFullName()] = true end) end
  local list = {}
  for _, sp in ipairs(snowPattern(b, b.snowSpacing[key], style, ra, rz)) do
    local use = freeSnowSpot(b, sp, skip) and sp or nil
    if not use then                                -- slide along the edge a little
      for _, ds in ipairs({ 300, -300, 600, -600, 900, -900 }) do
        local p2 = edgePoint(sp.seg, sp.s + ds, sp.side, CFG.SNOW_OFFSET)
        if p2 and freeSnowSpot(b, p2, skip) then
          p2.fx, p2.fy = -p2.nx, -p2.ny
          p2.yaw, p2.k, p2.clear = math.deg(math.atan(p2.fy, p2.fx)), "snow", CFG.CLEAR_RADIUS
          use = p2; break
        end
      end
    end
    if use and #list < CFG.MAX_SNOW then list[#list + 1] = use end
  end
  return list, b.snowSpacing[key]
end

-- sign styles: the game's Trail rating style setting (ETrailRatingStyle 1-4), or by the map's region when it's on
-- Automatic; the panel can override it. Variants of the game's Trail Markers for each difficulty (0-3).
local STYLE_NAME = { "North American", "Alpine", "Japanese", "French & Nordic" }
local VARIANTS = {
  { [0] = "GreenCircle", [1] = "BlueSquare", [2] = "BlackDiamond", [3] = "DblBlackDiamond" },   -- North American
  { [0] = "BlueCircle", [1] = "RedCircle", [2] = "BlackCircle", [3] = "OrangeRectangle" },      -- Alpine
  { [0] = "GreenCircle", [1] = "RedCircle", [2] = "BlackCircle", [3] = "DblBlackDiamond" },     -- Japanese
  { [0] = "GreenCircle", [1] = "BlueCircle", [2] = "RedCircle", [3] = "BlackCircle" },          -- French & Nordic
}
local VARIANT_LABEL = { GreenCircle = "green circle", BlueSquare = "blue square", BlackDiamond = "black diamond",
  DblBlackDiamond = "double black diamond", BlueCircle = "blue circle", RedCircle = "red circle",
  BlackCircle = "black circle", OrangeRectangle = "orange" }

local function classify(lat, lon)                  -- where on Earth a map is -> sign style
  if lat >= 30 and lat <= 46 and lon >= 128.5 and lon <= 146 then return 3 end   -- Japan
  if lat >= 54 and lon >= 4 and lon <= 32 then return 4 end                         -- Scandinavia
  if lat >= 41 and lat <= 51.5 and lon >= -5 and lon < 7.0 then return 4 end      -- France
  if lat >= 35 and lat <= 72 and lon >= -10 and lon <= 40 then return 2 end        -- the Alps and the rest of Europe
  return 1
end

local function mapStyle()
  local r = refs()
  if not valid(r.world) then return 1 end
  local key = addressOf(r.world)
  if M.mapStyleKey == key and M.mapStyle then return M.mapStyle end
  local style = 1
  pcall(function()
    local wpath = r.world:GetFullName():match("(%S+)$")
    local K = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local reg = FindFirstOf("LevelRegistryDataAsset")
    if not (valid(K) and valid(reg)) then return end
    local lv = reg.Levels
    for i = 1, #lv do
      local e = lv[i]
      local hit = false
      for _, field in ipairs({ "Map", "DioramaVariantMap", "TutorialVariantMap" }) do
        local ok, p = pcall(function() return K:Conv_SoftObjectReferenceToString(e[field]):ToString() end)
        if ok and p == wpath then hit = true end
      end
      if hit then style = classify(e.Latitude, e.Longitude); break end
    end
  end)
  M.mapStyleKey, M.mapStyle = key, style
  return style
end

local function gameStyleSetting()                  -- 0 Automatic, 1-4 a style
  local v = 0
  pcall(function()
    if not valid(M.settings) then M.settings = FindFirstOf("SkiResortGameUserSettings") end
    v = M.settings.TrailRatingStyle
  end)
  return (type(v) == "number" and v >= 1 and v <= 4) and v or 0
end

-- The style the game itself shows, read off the trail panel's difficulty picker: its four symbols are tinted, and
-- each style has its own sequence of colors (the labels are translated, the tints aren't). Automatic doesn't follow
-- the map (a Swiss map showed North American signs), so this is the reliable answer whenever the panel is open.
local TINT_STYLE = { GBKK = 1, BRKO = 2, GRKK = 3, GBRK = 4 }
local function tintClass(c)
  local r, g, b = c.R, c.G, c.B
  if math.max(r, g, b) < 0.2 then return "K" end                        -- black
  if r > 0.5 and g > 0.25 and b < 0.25 and g < r * 0.8 then return "O" end  -- orange
  if r >= g and r >= b then return "R" end
  if g >= r and g >= b then return "G" end
  return "B"
end
local function panelStyle()
  local w = P.owner
  if not valid(w) then return nil end
  local seq = {}
  pcall(function()
    local bs = w.DifficultyTierButtons
    for i = 1, math.min(#bs, 4) do seq[i] = tintClass(bs[i].Glyph.Brush.TintColor.SpecifiedColor) end
  end)
  return TINT_STYLE[table.concat(seq)]
end

-- the style used and where it comes from ("override", "game", "setting" or "map")
local function signStyle()
  if P.signStyle and P.signStyle > 0 then return P.signStyle, "override" end
  local s = panelStyle()
  if s then return s, "game" end
  local v = gameStyleSetting()
  if v > 0 then return v, "setting" end
  return mapStyle(), "map"
end

-- Where other trails join or split off: down each segment, the first point where another trail's corridor reaches
-- just outside one of this trail's edges. One per other trail and segment; none at the very top (where this trail
-- itself starts off another one: the entrance pair is there). { seg, s, side, trail } (cached on the base)
local function junctions(b)
  if b.junctions then return b.junctions end
  local tm = b.r.tm
  local list = {}
  -- other trails whose curves come anywhere near this one (bounding boxes, 200 m margin)
  local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
  for _, seg in ipairs(b.segs) do
    for _, q in ipairs(seg.pts) do
      minx, maxx, miny, maxy = math.min(minx, q.x), math.max(maxx, q.x), math.min(miny, q.y), math.max(maxy, q.y)
    end
  end
  local M2 = 20000
  local others = {}
  for _, t in ipairs(readTrails()) do
    if t.id ~= b.trail.id and t.shape ~= 1 then
      local near = false
      for _, cv in ipairs(t.curves) do
        for _, pt in ipairs({ { cv.sx, cv.sy }, { cv.cx, cv.cy }, { cv.ex, cv.ey } }) do
          if pt[1] > minx - M2 and pt[1] < maxx + M2 and pt[2] > miny - M2 and pt[2] < maxy + M2 then near = true end
        end
      end
      if near then others[#others + 1] = t end
    end
  end
  for _, seg in ipairs(b.segs) do
    local down = segDown(b, seg)
    local seen = {}
    local n = #seg.pts
    for i = 1, n do
      local q = seg.pts[down and i or (n + 1 - i)]
      local fromTop = down and q.s or (seg.len - q.s)
      for _, t in ipairs(others) do
        if not seen[t.id] then
          local dl, dr = (q.dl or 0) + CFG.JUNCTION_PROBE, (q.dr or 0) + CFG.JUNCTION_PROBE
          local inL = inside(tm, q.x + q.nx * dl, q.y + q.ny * dl, t.id)
          local inR = inside(tm, q.x - q.nx * dr, q.y - q.ny * dr, t.id)
          if inL or inR then
            seen[t.id] = true
            if fromTop > CFG.SIGN_ENTRANCE + 500 then
              list[#list + 1] = { seg = seg, s = q.s, side = inL and 1 or -1, trail = t, down = down }
            end
          end
        end
      end
    end
  end
  b.junctions = list
  return list
end

-- o.every: 0 (entrance only) or cm between signs further down, alternating sides; o.junctions: "yes" / "no"
local function planSigns(b, o)
  local d = b.trail.diff
  if d == nil or VARIANTS[1][d] == nil then return nil, "Rate this trail's difficulty first (above): the signs show it." end
  local style = signStyle()
  local variant = VARIANTS[style][d]
  local r = b.r
  local function z(p) return r.TU:GetHeightAtLocation(r.world, { X = p.x, Y = p.y }) end
  local list = {}
  for _, seg in ipairs(b.segs) do
    local down = z(seg.pts[#seg.pts]) <= z(seg.pts[1])   -- the curve runs downhill
    local dir = down and 1 or -1
    local top = down and 0 or seg.len
    local function add(s, side)
      if s < 0 or s > seg.len or #list >= CFG.MAX_SIGNS then return end
      local sp = edgePoint(seg, s, side, CFG.SIGN_OFFSET)
      if sp then
        sp.yaw = math.deg(math.atan(-dir * sp.ty, -dir * sp.tx))   -- facing up the trail, toward skiers coming down
        sp.k, sp.variant = "sign", variant
        list[#list + 1] = sp
      end
    end
    seg.down = down
    local s0 = top + dir * math.min(CFG.SIGN_ENTRANCE, seg.len * 0.25)
    add(s0, 1); add(s0, -1)
    if o.every and o.every > 0 then
      local k, side = 1, 1
      while #list < CFG.MAX_SIGNS do
        local s = s0 + dir * o.every * k
        if (dir == 1 and s > seg.len - 500) or (dir == -1 and s < 500) then break end
        add(s, side)
        side, k = -side, k + 1
      end
    end
  end
  local nj = 0
  if o.junctions ~= "no" then                      -- the other trail's sign, a little above where it starts
    for _, jn in ipairs(junctions(b)) do
      local v = jn.trail.diff ~= nil and VARIANTS[style][jn.trail.diff] or nil
      if v and #list < CFG.MAX_SIGNS then
        local dir = jn.down and 1 or -1
        local sp = edgePoint(jn.seg, jn.s - dir * CFG.JUNCTION_BEFORE, jn.side, CFG.SIGN_OFFSET)
        if sp then
          sp.yaw = math.deg(math.atan(-dir * sp.ty, -dir * sp.tx))
          sp.k, sp.variant, sp.junction = "sign", v, jn.trail.name
          list[#list + 1] = sp
          nj = nj + 1
        end
      end
    end
  end
  return list, variant, style, nj
end

-- Flags along both edges wherever the trail is steeper than o.angle degrees, every o.every cm. Returns the list,
-- the number of steep stretches and the steepest angle found.
local function planFlags(b, o)
  local r = b.r
  local list, runs, steepest = {}, 0, 0
  for _, seg in ipairs(b.segs) do
    local down = segDown(b, seg)
    local n = #seg.pts
    local stretch = nil
    local function close(sEnd)
      if not stretch then return end
      local a, z = math.min(stretch, sEnd), math.max(stretch, sEnd)
      stretch = nil
      if z - a < CFG.FLAG_MIN_RUN then return end
      runs = runs + 1
      local count = math.max(1, math.floor((z - a) / o.every + 0.5))
      local step = (z - a) / count
      for k = 0, count do
        for _, side in ipairs({ 1, -1 }) do
          if #list >= CFG.MAX_FLAGS then return end
          local sp = edgePoint(seg, a + step * k, side, CFG.FLAG_OFFSET)
          if sp then
            sp.yaw, sp.k = math.deg(math.atan(-sp.ny, -sp.nx)), "flag"
            list[#list + 1] = sp
          end
        end
      end
    end
    for i = 1, n do
      local q = seg.pts[down and i or (n + 1 - i)]
      local ok, ang = pcall(function() return r.TU:GetSlopeAngleAtLocation(r.world, { X = q.x, Y = q.y }) end)
      ang = ok and ang or 0
      if ang > steepest then steepest = ang end
      if ang >= o.angle then
        if not stretch then stretch = q.s end
      else
        close(q.s)
      end
    end
    close(down and seg.len or 0)
  end
  return list, runs, steepest
end

-- How much of the trail a light reaches, the way the game counts it: every light area (an AoE effect of kind Light)
-- in the resort's PlaceableRegistrySubsystem.AoESources. If those can't be read: the known light pieces.
local function litShare(b)
  if #b.samples == 0 then return nil end
  local r = b.r
  local lights = {}
  pcall(function()
    local arr = r.reg.AoESources
    for i = 1, #arr do
      local c = arr[i]
      if valid(c) then
        local ok, kind = pcall(function() return c.EffectKind end)
        if ok and kind == CFG.LIGHT_KIND then
          local l = c:K2_GetComponentLocation()
          local rad = c.EffectRadius
          if type(rad) == "number" and rad > 0 then lights[#lights + 1] = { x = l.X, y = l.Y, r = rad } end
        end
      end
    end
  end)
  if #lights == 0 then
    local radius = { tower = lightRadius(), festoon = KINDS.festoon.light, lantern = KINDS.lantern.light }
    for k, rad in pairs(radius) do
      for _, a in ipairs(inWorld(KINDS[k].short)) do
        local l = a:K2_GetActorLocation()
        lights[#lights + 1] = { x = l.X, y = l.Y, r = rad }
      end
    end
  end
  if #lights == 0 then return 0 end
  local size = 0
  for _, l in ipairs(lights) do if l.r > size then size = l.r end end
  local grid = {}
  for _, l in ipairs(lights) do
    local key = math.floor(l.x / size) .. ":" .. math.floor(l.y / size)
    grid[key] = grid[key] or {}; table.insert(grid[key], l)
  end
  local n = 0
  for _, q in ipairs(b.samples) do
    local cx, cy = math.floor(q[1] / size), math.floor(q[2] / size)
    local hit = false
    for gx = cx - 1, cx + 1 do
      for gy = cy - 1, cy + 1 do
        local cell = grid[gx .. ":" .. gy]
        if cell and not hit then
          for _, l in ipairs(cell) do
            if (q[1] - l.x) ^ 2 + (q[2] - l.y) ^ 2 <= l.r * l.r then hit = true; break end
          end
        end
      end
    end
    if hit then n = n + 1 end
  end
  return n / #b.samples
end
M.litShare = litShare

-------------------------------------------------------------------------------------------- the three new features
local FEATURES = {
  rope = { key = "rope", tab = "Rope lights", suffix = " Rope #", kinds = { "festoon", "lantern" }, maxDist = 900,
           perFrame = CFG.ROPE_PER_FRAME, plural = "rope light pieces", verb = "Install rope lights",
           options = {
             { id = "type", choices = { "festoon", "lantern" }, labels = { festoon = "Festoon", lantern = "Lanterns" } },
             { id = "layout", choices = { "edges", "zigzag", "both" },
               labels = { edges = "Along edges", zigzag = "Zigzag across", both = "Both" } } } },
  snow = { key = "snow", tab = "Snowblowers", suffix = " Snowblower #", kinds = { "snow" }, maxDist = 1500,
           perFrame = CFG.SNOW_PER_FRAME, plural = "snowblowers", verb = "Install snowblowers",
           options = { { id = "style", choices = { "zigzag", "oneside" }, labels = { zigzag = "Both sides", oneside = "One side" } },
                       { id = "range", choices = { "full", "top", "bottom", "custom" },
                         labels = { full = "Full length", top = "Top half", bottom = "Bottom half", custom = "Custom" } } } },
  sign = { key = "sign", tab = "Trail signs", suffix = " Sign #", kinds = { "sign" }, maxDist = 1200,
           perFrame = CFG.SIGN_PER_FRAME, plural = "signs", verb = "Install signs",
           options = { { id = "every", choices = { 0, 15000, 7500 },
                         labels = { [0] = "Entrance", [15000] = "Every 150 m", [7500] = "Every 75 m" } },
                       { id = "junctions", choices = { "yes", "no" },
                         labels = { yes = "Junction signs", no = "No junction signs" } } } },
  flag = { key = "flag", tab = "Steep flags", suffix = " Flag #", kinds = { "flag" }, maxDist = 1000,
           perFrame = CFG.FLAG_PER_FRAME, plural = "flags", verb = "Install flags",
           options = { { id = "angle", choices = { 25, 30, 35 },
                         labels = { [25] = "Steeper than 25\u{B0}", [30] = "30\u{B0}", [35] = "35\u{B0}" } },
                       { id = "every", choices = { 2000, 4000 }, labels = { [2000] = "Every 20 m", [4000] = "Every 40 m" } } } },
}
local FEATURE_ORDER = { "rope", "snow", "sign", "flag" }
M.FEATURES = FEATURES

-- the mod's things of one feature on this trail: named "<this trail><suffix>n" (or a name no trail has any more)
-- and standing by this trail
function M.oursOf(f, trail, names)
  local r = refs()
  local list = {}
  if not valid(r.tm) then return list end
  names = names or trailNames()
  local pat = "^(.*)" .. (f.suffix:gsub("#", "%%#")) .. "%d+$"
  for _, k in ipairs(f.kinds) do
    for _, a in ipairs(inWorld(KINDS[k].short)) do
      local ok, name = pcall(function() return a.InstanceName:ToString() end)
      local prefix = ok and name and splitName(name):match(pat)
      if prefix and (prefix == trail.name or not names[prefix]) then
        local l = a:K2_GetActorLocation()
        if r.tm:GetDistanceToCorridor({ X = l.X, Y = l.Y, Z = l.Z }, trail.id) <= f.maxDist then list[#list + 1] = a end
      end
    end
  end
  return list
end

-- the one of `ours` within 3 m of a spot (positions read once per list, kept on the list)
local function nearOurs(ours, sp)
  if not ours.at then
    ours.at = {}
    for i, a in ipairs(ours) do
      if valid(a) then local l = a:K2_GetActorLocation(); ours.at[i] = { l.X, l.Y } end
    end
  end
  for i, a in ipairs(ours) do
    local q = ours.at[i]
    if q and (q[1] - sp.x) ^ 2 + (q[2] - sp.y) ^ 2 < 300 ^ 2 then return a end
  end
end

-- { f, b, o, items, ours, refund, k, cost (each), net, same, restyle, err, spacing, variant, style }
function M.planFeature(f, b, o)
  local p = { f = f, b = b, o = o, refund = 0 }
  p.ours = M.oursOf(f, b.trail)
  for _, a in ipairs(p.ours) do
    local ok, v = pcall(function() return a:GetRefundValue() end)
    if ok and type(v) == "number" then p.refund = p.refund + v end
  end
  local items
  if f.key == "rope" then
    items, p.steepSkipped = planRope(b, o)
  elseif f.key == "snow" then
    items, p.spacing = planSnow(b, o, p.ours)
  elseif f.key == "flag" then
    items, p.runs, p.steepest = planFlags(b, o)
    if #items == 0 then
      p.err = string.format("No part of this trail is %d\u{B0} or steeper (the steepest is %d\u{B0}).", o.angle,
        math.floor(p.steepest + 0.5))
    end
  else
    local a2, a3, a4
    items, a2, a3, a4 = planSigns(b, o)
    if not items then p.err, items = a2, {} else p.variant, p.style, p.junctions = a2, a3, a4 end
  end
  p.items = items
  p.k = (f.key == "rope") and (o.type == "lantern" and "lantern" or "festoon") or f.kinds[1]
  p.cost = kindCost(p.k)
  p.net = p.cost * #items - p.refund
  -- already like this? (as many, each planned spot has one of ours within 3 m, of the same kind)
  local same, restyle = #p.ours > 0 and #p.ours == #items, false
  if same then
    for _, sp in ipairs(items) do
      local a = nearOurs(p.ours, sp)
      local okc, cn = pcall(function() return a:GetClass():GetFName():ToString() end)
      if not a or not okc or cn ~= KINDS[sp.k].short then same = false; break end
      if sp.variant then
        local ok, v = pcall(function() return a.VariantId:ToString() end)
        if not ok or v ~= sp.variant then restyle = true end
      end
    end
  end
  p.same, p.restyle = same and not restyle, same and restyle
  return p
end

------------------------------------------------------------------------------------------------------------ placing
-- sells one thing back; returns the refund (nil if it couldn't be removed)
local function removeOne(r, a)
  if not valid(a) or gone(a) then return nil end
  local v = 0
  pcall(function() v = a:GetRefundValue() end)
  if not pcall(function() a:K2_DestroyActor() end) then return nil end
  M.dead[addressOf(a)] = true
  if v > 0 and valid(r.eco) then pcall(function() r.eco:RefundExpense(v, 0) end) else v = 0 end   -- 0: Construction
  return v
end

-- Rope light pieces come with a shadow-casting light each; dozens of them along a trail made placing them stutter
-- badly (the GPU sets up shadows for every new light in view). Shadows from strings of bulbs barely show, so the
-- mod's pieces have them off; the game turns them back on when a resort loads, so M.background repeats this.
local function noShadows(a)
  pcall(function()
    local l = a.RectLight
    if valid(l) and l.CastShadows then l:SetCastShadows(false) end
  end)
end

function M.unshadowRopes()
  for _, k in ipairs({ "festoon", "lantern" }) do
    for _, a in ipairs(inWorld(KINDS[k].short)) do
      local ok, name = pcall(function() return a.InstanceName:ToString() end)
      if ok and name and splitName(name):match(ROPE_PATTERN) then noShadows(a) end
    end
  end
end

local function spawnActor(r, cls, sp)
  local z = r.TU:GetHeightAtLocation(r.world, { X = sp.x, Y = sp.y })
  if sp.clear and valid(r.obs) and r.obs:IsLocationBlocked({ X = sp.x, Y = sp.y, Z = z }, 300) then
    pcall(function() r.obs:ClearObstaclesInRadius({ X = sp.x, Y = sp.y, Z = z }, sp.clear, true) end)
  end
  local h = math.rad(sp.yaw) / 2
  local xf = { Rotation = { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) }, Translation = { X = sp.x, Y = sp.y, Z = z },
               Scale3D = { X = 1, Y = 1, Z = 1 } }
  local a = r.GS:BeginDeferredActorSpawnFromClass(r.world, cls, xf, 1, nil, 0)   -- 1: always spawn
  if not valid(a) then return nil end
  a = r.GS:FinishSpawningActor(a, xf, 0)
  if not valid(a) then return nil end
  pcall(function() a:K2_SetActorRotation({ Pitch = 0, Yaw = sp.yaw, Roll = 0 }, false) end)
  pcall(function() a:FinalizePlacement() end)
  pcall(function() a:SetInstanceName(FText(sp.name)) end)
  if KINDS[sp.k].noShadow then noShadows(a) end
  return a
end

-- Placing and removing run a little every frame (M.job, stepped by M.stepJob from the per-frame loop): dozens of
-- things in one frame froze the game for a second. What the job replaces goes first (sold back), then the new things.
-- job = { what ("tower" / "rope" / "snow" / "sign"), label, trail, world, remove = {actors}, items = {spots},
--         perFrame }; a spot = { x, y, yaw, k (kind), name, clear?, after? (fn(actor)) }
local function startJob(j)
  j.ri, j.si, j.removed, j.back, j.placed, j.spent = 1, 1, 0, 0, 0, 0
  j.perFrame = j.perFrame or 1
  M.job = j
end

-- starts replacing the trail's tower lights with the plan's; returns nil, or a message if it can't start
function M.apply(p)
  if M.job then return "Still busy with the last change." end
  local r = refs(true)
  if not ready(r) then return "The resort isn't loaded." end
  if p.same then return "Already installed." end
  if valid(r.eco) and p.net > 0 and not r.eco:CanAfford(p.net) then
    return "Not enough money: " .. money(p.net) .. " needed."
  end
  local trail = p.ctx.trail
  local hex = lightsHex(p.ctx.ours)                -- a new style keeps the trail's color
  local tag = hexTag(hex)
  local items = {}
  for i, sp in ipairs(p.towers) do
    items[i] = { x = sp.x, y = sp.y, yaw = sp.yaw, k = "tower", clear = CFG.CLEAR_RADIUS,
                 name = trail.name .. CFG.NAME_SUFFIX .. i .. (tag and (COLOR_SEP .. tag) or ""),
                 after = hex and function(a) paint(a, hex) end or nil }
  end
  startJob({ what = "tower", label = "lights", style = p.style, trail = trail, world = r.world, remove = p.ctx.ours,
             items = items, perFrame = 1 })
  return nil
end

-- starts selling the trail's tower lights back
function M.remove(trail)
  if M.job then return "Still busy with the last change." end
  local r = refs(true)
  if not ready(r) then return "The resort isn't loaded." end
  startJob({ what = "tower", label = "lights", trail = trail, world = r.world, remove = M.ourLights(trail), items = {} })
  return nil
end

-- starts placing a feature's plan (or, for signs whose difficulty or style changed, repaints them at once)
function M.applyFeature(p)
  if M.job then return "Still busy with the last change." end
  local r = refs(true)
  if not ready(r) then return "The resort isn't loaded." end
  if p.err then return p.err end
  if p.same then return "Already installed." end
  local f, t = p.f, p.b.trail
  if p.restyle then
    local n = 0
    for _, sp in ipairs(p.items) do
      local a = nearOurs(p.ours, sp)
      if a and pcall(function() a:ApplyVariant(FName(sp.variant)) end) then n = n + 1 end
    end
    log(string.format("trail %d \"%s\": %d signs now show %s", t.id, t.name, n, tostring(p.variant)))
    if M.P then M.P.key = nil end
    return nil
  end
  if #p.items == 0 then return "No room for " .. f.plural .. " along this trail." end
  if valid(r.eco) and p.net > 0 and not r.eco:CanAfford(p.net) then
    return "Not enough money: " .. money(p.net) .. " needed."
  end
  local hex = (f.key == "rope") and lightsHex(p.ours) or nil   -- new rope lights keep the trail's color
  local tag = hexTag(hex)
  for i, sp in ipairs(p.items) do
    sp.name = t.name .. f.suffix .. i .. (tag and (COLOR_SEP .. tag) or "")
    if hex then sp.after = function(a) paint(a, hex) end end
    if sp.variant then
      local v = sp.variant
      sp.after = function(a) a:ApplyVariant(FName(v)) end
    end
  end
  startJob({ what = f.key, label = f.plural, trail = t, world = r.world, remove = p.ours, items = p.items,
             perFrame = f.perFrame, every = f.every, removeEvery = f.removeEvery, base = p.b })
  return nil
end

-- everything Better Trails placed on a trail, by feature: { tower = {...}, rope = {...}, ... }
function M.everything(trail)
  local all = { tower = M.ourLights(trail) }
  local names = trailNames()
  for _, key in ipairs(FEATURE_ORDER) do all[key] = M.oursOf(FEATURES[key], trail, names) end
  return all
end

function M.removeAll(trail)
  if M.job then return "Still busy with the last change." end
  local r = refs(true)
  if not ready(r) then return "The resort isn't loaded." end
  local list = {}
  for _, l in pairs(M.everything(trail)) do for _, a in ipairs(l) do list[#list + 1] = a end end
  startJob({ what = "all", label = "everything", trail = trail, world = r.world, remove = list, items = {} })
  return nil
end

function M.removeFeature(f, trail)
  if M.job then return "Still busy with the last change." end
  local r = refs(true)
  if not ready(r) then return "The resort isn't loaded." end
  startJob({ what = f.key, label = f.plural, trail = trail, world = r.world, remove = M.oursOf(f, trail), items = {},
             removeEvery = f.removeEvery })
  return nil
end

-- The mod's tower lights in another world than the resort's (spawned there by an older Auto Trail Lights: unseen,
-- never saved) are sold back and removed, a few at a time.
function M.cleanupElsewhere()
  local r = refs()
  if not ready(r) then return 0 end
  local elsewhere = towersElsewhere()
  local n, back = 0, 0
  for _, a in ipairs(elsewhere) do
    local ok, name = pcall(function() return a.InstanceName:ToString() end)
    if ok and splitName(name):match(NAME_PATTERN) then
      local v = removeOne(r, a)
      if v then n = n + 1; back = back + v end
      if n >= 20 then break end
    end
  end
  if n > 0 then log(string.format("removed %d lights that were outside the resort (%s back)", n, money(back))) end
  return n
end

local function finishJob(j, r, why)
  M.job = nil
  local t = j.trail
  if j.what == "tower" and j.placed > 0 and CFG.ENABLE_NIGHT and valid(r.tm) then
    pcall(function() r.tm:SetTrailNightSkiing(t.id, true) end)
  end
  if j.what == "rope" and j.placed > 0 and j.base and CFG.ENABLE_NIGHT and valid(r.tm) and not t.night then
    local ok, share = pcall(litShare, j.base)        -- lit well enough by its lights: open it at night
    if ok and share and share >= CFG.LIT_ON then
      pcall(function() r.tm:SetTrailNightSkiing(t.id, true) end)
      log(string.format("trail %d \"%s\": %d%% lit, Night skiing on", t.id, t.name, math.floor(share * 100 + 0.5)))
    end
  end
  log(string.format("trail %d \"%s\" %s%s: removed %d (%s back), placed %d (%s)%s", t.id, t.name, j.what,
    j.style and (" " .. j.style) or "", j.removed, money(j.back), j.placed, money(j.spent),
    why and (" - " .. why) or ""))
  if M.P then
    M.P.key = nil                                  -- the panel measures the trail again
    if why then M.P.msg = "Stopped: " .. why .. "." end
  end
end

function M.stepJob()
  local j = M.job
  if not j then return end
  local r = refs()
  if not (valid(j.world) and ready(r)) then        -- the resort was closed or another one loaded
    M.job = nil
    log("stopped: the resort was closed")
    return
  end
  if (j.wait or 0) > 0 then j.wait = j.wait - 1 return end   -- pacing: frames to skip after the last batch
  if j.ri <= #j.remove then                        -- 1. the old things
    j.wait = j.removeEvery or 0
    for _ = 1, CFG.REMOVE_PER_FRAME do
      local a = j.remove[j.ri]
      if a == nil then break end
      j.ri = j.ri + 1
      local v = removeOne(r, a)
      if v then j.removed = j.removed + 1; j.back = j.back + v end
    end
    return
  end
  -- 2. the new ones, a batch a frame: each frame that adds buildings costs the game a fixed ~40 ms on top of each
  -- piece, so fewer, fuller frames finish sooner with fewer hitches. The batch is paid for in one go (each payment
  -- fires the game's balance-changed events).
  j.cls = j.cls or {}
  local batch, due = {}, 0
  for _ = 1, j.perFrame do
    local sp = j.items[j.si]
    if not sp then break end
    local cls = j.cls[sp.k]
    if not valid(cls) then
      local c, why = loadStep(r, j, sp.k)
      if c == false then finishJob(j, r, why) return end
      if not c then break end                      -- still loading: next frame
      cls = c
      j.cls[sp.k] = c
    end
    j.si = j.si + 1
    local a = spawnActor(r, cls, sp)
    if not a then log(sp.k .. " didn't spawn at " .. math.floor(sp.x) .. ", " .. math.floor(sp.y)) else
      if sp.after then
        local ok, err = pcall(sp.after, a)
        if not ok then log("after spawn: " .. tostring(err)) end
      end
      local cost = kindCost(sp.k)
      pcall(function() if a.BaseCost > 0 and a.BaseCost < 100000 then cost = a.BaseCost; M.costOf[sp.k] = cost end end)
      batch[#batch + 1] = a
      due = due + cost
    end
  end
  if #batch > 0 then
    j.wait = j.every or 0
    if valid(r.eco) and not r.eco:TryDeductFunds(due) then
      -- can't pay for the whole batch: keep what the balance covers, the rest goes
      local each = due / #batch
      local keep = 0
      while keep < #batch and r.eco:CanAfford(math.floor(each * (keep + 1) + 0.5)) do keep = keep + 1 end
      local paid = math.floor(each * keep + 0.5)
      if keep > 0 then r.eco:TryDeductFunds(paid) end
      for i = keep + 1, #batch do pcall(function() batch[i]:K2_DestroyActor() end) end
      j.placed, j.spent = j.placed + keep, j.spent + paid
      finishJob(j, r, "ran out of money")
      return
    end
    j.placed, j.spent = j.placed + #batch, j.spent + due
  end
  if j.si > #j.items then finishJob(j, r) end
end

function M.jobProgress()
  local j = M.job
  if not j then return nil end
  if j.ri <= #j.remove then return string.format("Removing %s...  %d / %d", j.label, j.ri - 1, #j.remove) end
  if j.load then return "Getting " .. j.label .. " ready..." end
  if #j.items > 0 then return string.format("Placing %s...  %d / %d", j.label, j.si - 1, #j.items) end
  return "Removing " .. j.label .. "..."
end

-- the whole thing, by trail id or name (handy from a console/REPL too); what: "tower" (default), "rope", "snow", "sign"
function M.dressTrail(idOrName, what, opts)
  local t, err
  if type(idOrName) == "number" then t = M.trailById(idOrName) else t, err = M.trailByName(idOrName) end
  if not t then return err or "no such trail" end
  local b, berr = M.base(t)
  if not b then return berr end
  if what == nil or what == "tower" then
    local ctx, cerr = M.prepare(b)
    if not ctx then return cerr end
    return M.apply(M.plan(ctx, opts or "uniform"))
  end
  local f = FEATURES[what]
  if not f then return "unknown: " .. tostring(what) end
  local o = opts or {}
  for _, op in ipairs(f.options) do if o[op.id] == nil then o[op.id] = op.choices[1] end end
  return M.applyFeature(M.planFeature(f, b, o))
end

----------------------------------------------------------------------------------------------- the trail panel part
local C = { on = { R = 0.10, G = 0.32, B = 0.62, A = 1 }, off = { R = 0.16, G = 0.18, B = 0.22, A = 1 },
            red = { R = 0.45, G = 0.14, B = 0.12, A = 1 }, text = { R = 1, G = 1, B = 1, A = 1 },
            dim = { R = 0.62, G = 0.68, B = 0.75, A = 1 }, ok = { R = 0.45, G = 0.85, B = 0.50, A = 1 },
            warn = { R = 0.98, G = 0.70, B = 0.25, A = 1 } }
local SIZE = { title = 14, tab = 11, button = 12, note = 11 }
P.styleOf = P.styleOf or {}                        -- trail id -> the tower style picked in the panel (this session)
P.opts = P.opts or {}                              -- feature -> trail id -> its options picked in the panel
P.signStyle = P.signStyle or 0                     -- 0: follow the game; 1-4: a sign style picked in the panel
P.tab = P.tab or "tower"

-- Auto Trail Lights running too? (it sets this shared variable; Better Trails includes everything it does)
local function atlRunning()
  local ok, v = pcall(function() return ModRef:GetSharedVariable("SkiEOMods.enabled.AutoTrailLights") end)
  return ok and v == true
end

local function newWidget(tree, cn) return StaticConstructObject(StaticFindObject("/Script/UMG." .. cn), tree) end
-- Text in the game's own UI font: the panel's labels use the game's default font (no font object set), so the mod
-- copies one of them (P.fontSrc) and only changes the size. Without one, the engine's Roboto.
local function newText(tree, s, size, color, bold)
  local t = newWidget(tree, "TextBlock")
  t:SetText(FText(s))
  local copied = valid(P.fontSrc) and pcall(function() t:SetFont(P.fontSrc.Font) end)
  local f = t.Font                                 -- edit the font in place: a partial struct table crashes
  f.Size = size
  if not copied then f.TypefaceFontName = FName(bold and "Bold" or "Regular") end
  t:SetFont(f)
  t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
  return t
end
local function newButton(tree, row, label, fill, fn, size)
  local b = newWidget(tree, "Button")
  b:SetBackgroundColor(C.off)
  local t = newText(tree, label, size or SIZE.button, C.text, true)
  t:SetJustification(1)
  b:SetContent(t)
  local s = row:AddChildToHorizontalBox(b)
  s:SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 0 })
  s:SetSize({ Value = fill or 1, SizeRule = 1 })
  local c = { w = b, label = t, fn = fn, was = false, enabled = true }
  P.controls[#P.controls + 1] = c
  return c
end
local function setButton(c, text, color, enabled)
  if text then c.label:SetText(FText(text)) end
  c.w:SetBackgroundColor(color)
  c.enabled = enabled
end
local function newRow(tree, parent, bottom)
  local row = newWidget(tree, "HorizontalBox")
  parent:AddChildToVerticalBox(row):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = bottom or 3 })
  return row
end
local function newNote(tree, parent)
  local t = newText(tree, "", SIZE.note, C.dim, false)
  t:SetAutoWrapText(true)
  parent:AddChildToVerticalBox(t):SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 0 })
  return t
end
-- a slider row: label, slider (0..1), value text; returns { w, val, last }
local function newSlider(tree, parent, label)
  local row = newWidget(tree, "HorizontalBox")
  parent:AddChildToVerticalBox(row):SetPadding({ Left = 2, Top = 1, Right = 2, Bottom = 1 })
  local lab = newText(tree, label, SIZE.note, C.dim, true)
  local ls = row:AddChildToHorizontalBox(lab)
  ls:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 }); ls:SetVerticalAlignment(2)
  local sl = newWidget(tree, "Slider")
  local ss = row:AddChildToHorizontalBox(sl)
  ss:SetSize({ Value = 1, SizeRule = 1 }); ss:SetVerticalAlignment(2)
  local val = newText(tree, "", SIZE.note, C.dim, false)
  local vs = row:AddChildToHorizontalBox(val)
  vs:SetPadding({ Left = 6, Top = 0, Right = 0, Bottom = 0 }); vs:SetVerticalAlignment(2)
  return { w = sl, val = val, last = nil }
end

local refresh, refreshTab                          -- below

------------------------------------------------------------------------------------------- color box (towers, ropes)
-- Swatches, Custom color (R/G/B sliders, shown while dragging, saved in the names when let go) and Party. One box for
-- the tower lights, one for the rope lights; cb.ours is the trail's lights it colors.
local function swatchTint(hex)                     -- what a swatch button shows
  if not hex then return { R = 1.0, G = 0.80, B = 0.45, A = 1 } end
  return hexLinear(hex)
end

local function pickColor(cb, hex, commit)
  if not (cb.ours and #cb.ours > 0) then return end
  M.setColor(cb.ours, hex, commit)
  cb.color = hex
end

local function buildColorBox(tree, parent, title)
  local cb = { title = title }
  cb.box = newWidget(tree, "VerticalBox")
  parent:AddChildToVerticalBox(cb.box):SetPadding({ Left = 0, Top = 8, Right = 0, Bottom = 0 })
  cb.titleText = newText(tree, title, SIZE.button, C.text, true)
  cb.box:AddChildToVerticalBox(cb.titleText):SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 3 })
  local sw = newRow(tree, cb.box)
  cb.swatches = {}
  for _, pr in ipairs(PRESETS) do
    local c = newButton(tree, sw, " ", 1, function()
      pickColor(cb, pr.hex, true)
      cb.open = false
      refreshTab()
    end)
    c.hex = pr.hex
    c.w:SetBackgroundColor(swatchTint(pr.hex))
    cb.swatches[#cb.swatches + 1] = c
  end
  local crow = newRow(tree, cb.box)
  cb.customBtn = newButton(tree, crow, "Custom color", 1, function()
    cb.open = not cb.open
    refreshTab()
  end)
  cb.partyBtn = newButton(tree, crow, "Party", 1, function()
    if cb.color == PARTY then pickColor(cb, nil, true) else pickColor(cb, PARTY, true) end   -- off again: warm white
    cb.open = false
    refreshTab()
  end)
  cb.sliderBox = newWidget(tree, "VerticalBox")
  cb.box:AddChildToVerticalBox(cb.sliderBox)
  cb.sliders = {}
  for _, ch in ipairs({ "R", "G", "B" }) do cb.sliders[#cb.sliders + 1] = newSlider(tree, cb.sliderBox, ch) end
  return cb
end

local function setColorSliders(cb, hex)            -- show a color on the sliders without it counting as a change
  local r, g, b = 255, 232, 171                     -- warm white, roughly
  if hex and hex ~= PARTY then r, g, b = hexRGB(hex) end
  for i, v in ipairs({ r, g, b }) do
    local s = cb.sliders[i]
    s.w:SetValue(v / 255)
    s.last = s.w:GetValue()
    s.val:SetText(FText(tostring(v)))
  end
end

local function refreshColorBox(cb, ours)
  cb.ours = ours or {}
  if #cb.ours == 0 then cb.box:SetVisibility(1); cb.open = false; return end
  cb.box:SetVisibility(0)
  local hex = lightsHex(cb.ours)
  cb.color = hex
  cb.titleText:SetText(FText(cb.title .. ": " .. colorName(hex)))
  local isPreset = false
  for _, c in ipairs(cb.swatches) do
    local on = (c.hex == hex)
    if on then isPreset = true end
    c.label:SetText(FText(on and "\u{2022}" or " "))   -- a dot on the chosen one
    c.enabled = true
  end
  local party = (hex == PARTY)
  local custom = not isPreset and not party
  setButton(cb.customBtn, custom and ("Custom: " .. hex) or "Custom color", (cb.open or custom) and C.on or C.off, true)
  setButton(cb.partyBtn, party and "Party: on" or "Party", party and C.on or C.off, true)
  cb.sliderBox:SetVisibility(cb.open and 0 or 1)
  setColorSliders(cb, hex)
end

local function pollColorSliders(cb)
  if not (cb and cb.open and cb.ours and #cb.ours > 0) then return end
  local changed = false
  for _, s in ipairs(cb.sliders) do
    local v = s.w:GetValue()
    if s.last == nil then s.last = v end
    if math.abs(v - s.last) > 0.001 then
      s.last = v; changed = true
      s.val:SetText(FText(tostring(math.floor(v * 255 + 0.5))))
    end
  end
  if changed then cb.slideAt = frame end
  if cb.slideAt then
    local function hexNow()
      local c = {}
      for i, s in ipairs(cb.sliders) do c[i] = math.floor(s.last * 255 + 0.5) end
      return string.format("#%02X%02X%02X", c[1], c[2], c[3])
    end
    if frame - cb.slideAt > 20 then                -- let go: save it in the names
      cb.slideAt = nil
      pickColor(cb, hexNow(), true)
      cb.titleText:SetText(FText(cb.title .. ": " .. colorName(cb.color)))
      for _, c in ipairs(cb.swatches) do c.label:SetText(FText(c.hex == cb.color and "\u{2022}" or " ")) end
      setButton(cb.customBtn, "Custom: " .. cb.color, C.on, true)
    elseif frame % 4 == 0 then                     -- dragging: show it
      pickColor(cb, hexNow(), false)
    end
  end
end

--------------------------------------------------------------------------------------------------------------- tabs
local function optsFor(f, t)
  P.opts[f.key] = P.opts[f.key] or {}
  local o = P.opts[f.key][t.id]
  if not o then
    o = {}
    for _, op in ipairs(f.options) do o[op.id] = op.choices[1] end
    if f.key == "rope" then                        -- rope lights already there: start on their kind
      local ours = M.oursOf(f, t)
      if ours[1] then
        local ok, cn = pcall(function() return ours[1]:GetClass():GetFName():ToString() end)
        if ok and cn == KINDS.lantern.short then o.type = "lantern" end
      end
    end
    if f.key == "snow" then o.from, o.to = 0, 1 end
    P.opts[f.key][t.id] = o
  end
  return o
end

-- the tower lights tab (Auto Trail Lights' section)
local function buildTowerTab(tree, box)
  local styles = newRow(tree, box)
  P.styleButtons = {}
  for _, st in ipairs(STYLES) do
    P.styleButtons[st] = newButton(tree, styles, STYLE_LABEL[st], 1, function()
      if P.trail then P.styleOf[P.trail.id] = st end
      refreshTab()
    end)
  end
  local actions = newRow(tree, box)
  P.main = newButton(tree, actions, "Install trail lights", 3, function()
    if not P.plan then return end
    local msg = M.apply(P.plan)                    -- runs over the next frames; the panel re-plans when it's done
    if msg then P.msg = msg; P.key = nil end
  end)
  P.removeBtn = newButton(tree, actions, "Remove", 1, function()
    if not P.trail then return end
    local msg = M.remove(P.trail)
    if msg then P.msg = msg; P.key = nil end
  end)
  P.note = newNote(tree, box)
  P.towerCB = buildColorBox(tree, box, "Light color")
end

-- a rope lights / snowblowers / trail signs tab
local function buildFeatureTab(tree, box, f)
  local U = { f = f, box = box, opt = {} }
  for _, op in ipairs(f.options) do
    local row = newRow(tree, box)
    U.opt[op.id] = {}
    for _, ch in ipairs(op.choices) do
      U.opt[op.id][ch] = newButton(tree, row, op.labels[ch], 1, function()
        if P.trail then optsFor(f, P.trail)[op.id] = ch end
        refreshTab()
      end)
    end
  end
  if f.key == "snow" then                          -- Custom: where on the trail, from the top
    U.rangeBox = newWidget(tree, "VerticalBox")
    box:AddChildToVerticalBox(U.rangeBox):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 3 })
    U.rangeSliders = { newSlider(tree, U.rangeBox, "From"), newSlider(tree, U.rangeBox, "To") }
  end
  if f.key == "sign" then                          -- the sign style: the game's, or one picked here
    local row = newRow(tree, box)
    U.styleBtn = newButton(tree, row, "Sign style", 1, function()
      P.signStyle = (P.signStyle + 1) % 5
      refreshTab()
    end)
  end
  local actions = newRow(tree, box)
  U.main = newButton(tree, actions, f.verb, 3, function()
    if not U.plan then return end
    local msg = M.applyFeature(U.plan)
    if msg then P.msg = msg; P.key = nil end
  end)
  U.remove = newButton(tree, actions, "Remove", 1, function()
    if not P.trail then return end
    local msg = M.removeFeature(f, P.trail)
    if msg then P.msg = msg; P.key = nil end
  end)
  U.note = newNote(tree, box)
  if f.key == "rope" then U.cb = buildColorBox(tree, box, "Rope light color") end
  return U
end

local TABS = { "tower", "rope", "snow", "sign", "flag" }
local TAB_LABEL = { tower = "Towers", rope = "Ropes", snow = "Snow", sign = "Signs", flag = "Flags" }

local function inject(w)
  local tree = w.WidgetTree
  local box = w.EditTabContent
  if not (valid(tree) and valid(box)) then return false end
  P.controls = {}
  P.fontSrc = nil                                  -- a game label to copy the font from
  for _, k in ipairs({ "GroomNowLabel", "EditShapeButtonLabel", "OpenClosedToggleLabel", "LengthLabel" }) do
    if not P.fontSrc then pcall(function() if valid(w[k]) then P.fontSrc = w[k] end end) end
  end
  local root = newWidget(tree, "VerticalBox")
  local title = newText(tree, "Better Trails", SIZE.title, C.text, true)
  root:AddChildToVerticalBox(title):SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 3 })

  local tabs = newRow(tree, root, 6)
  P.tabButtons = {}
  for _, key in ipairs(TABS) do
    P.tabButtons[key] = newButton(tree, tabs, TAB_LABEL[key], 1, function()
      P.tab = key
      refreshTab()
    end, SIZE.tab)
  end
  P.atlNote = newText(tree, "Auto Trail Lights is on too, so its own section handles tower lights here. Better "
    .. "Trails includes it: switch Auto Trail Lights off in the Mods menu to use the Tower lights tab.", SIZE.note, C.warn, false)
  P.atlNote:SetAutoWrapText(true)
  root:AddChildToVerticalBox(P.atlNote):SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 4 })

  P.boxes = {}
  for _, key in ipairs(TABS) do
    local b = newWidget(tree, "VerticalBox")
    root:AddChildToVerticalBox(b)
    P.boxes[key] = b
  end
  buildTowerTab(tree, P.boxes.tower)
  P.F = {}
  for _, key in ipairs(FEATURE_ORDER) do P.F[key] = buildFeatureTab(tree, P.boxes[key], FEATURES[key]) end

  -- everything on this trail, and one button to sell it all back (a second click confirms)
  P.allBox = newWidget(tree, "VerticalBox")
  root:AddChildToVerticalBox(P.allBox):SetPadding({ Left = 0, Top = 10, Right = 0, Bottom = 0 })
  P.allNote = newNote(tree, P.allBox)
  local arow = newRow(tree, P.allBox)
  P.allBtn = newButton(tree, arow, "Remove everything", 1, function()
    if not P.trail then return end
    if not P.confirmAt or frame - P.confirmAt > 240 then
      P.confirmAt = frame
      setButton(P.allBtn, "Click again to remove everything", C.red, true)
      return
    end
    P.confirmAt = nil
    local msg = M.removeAll(P.trail)
    if msg then P.msg = msg; P.key = nil end
  end)

  -- right under the Night skiing switch if its row can be found, else at the end of the Edit tab
  local slot
  pcall(function()
    local rows = w.OptionRows
    for i = 1, #rows do
      if rows[i].GlossaryTermKey:ToString() == "nightskiing" then
        local row = rows[i].Row
        local parent = valid(row) and row:GetParent() or nil
        if valid(parent) and parent:GetClass():GetFName():ToString() == "VerticalBox" then
          local at = parent:GetChildIndex(row)
          if at >= 0 then slot = parent:InsertChildAt(at + 1, root) end
        end
      end
    end
  end)
  if not slot then slot = box:AddChild(root) end
  pcall(function() slot:SetPadding({ Left = 0, Top = 8, Right = 0, Bottom = 6 }) end)
  P.owner, P.root, P.key, P.base, P.ctx, P.plan, P.trail = w, root, nil, nil, nil, nil, nil
  log("added to the trail panel")
  return true
end

local function setNote(t, text, color)
  t:SetText(FText(text or ""))
  t:SetColorAndOpacity({ SpecifiedColor = color or C.dim, ColorUseRule = 0 })
end

local function disableAll(msg, color)
  if P.allBox then P.allBox:SetVisibility(1) end
  for _, st in ipairs(STYLES) do setButton(P.styleButtons[st], nil, C.off, false) end
  setButton(P.main, "Install trail lights", C.off, false)
  P.removeBtn.w:SetVisibility(1)
  P.towerCB.box:SetVisibility(1)
  P.plan = nil
  setNote(P.note, msg, color)
  for _, key in ipairs(FEATURE_ORDER) do
    local U = P.F[key]
    for _, op in ipairs(U.f.options) do
      for _, ch in ipairs(op.choices) do setButton(U.opt[op.id][ch], nil, C.off, false) end
    end
    if U.styleBtn then setButton(U.styleBtn, nil, C.off, false) end
    if U.rangeBox then U.rangeBox:SetVisibility(1) end
    if U.cb then U.cb.box:SetVisibility(1) end
    setButton(U.main, U.f.verb, C.off, false)
    U.remove.w:SetVisibility(1)
    U.plan = nil
    setNote(U.note, msg, color)
  end
end

local function sellBack(n, refund)                 -- the end of a note when there's something to sell back
  if n == 0 then return "" end
  return " Remove sells them back for " .. money(refund) .. "."
end

local function litNote()                           -- " Lit now: 87% of the trail."
  local ok, share = pcall(litShare, P.base)
  if not (ok and share) then return "" end
  return string.format(" Lit now: %d%% of the trail.", math.floor(share * 100 + 0.5))
end

-- the summary under the tabs: what Better Trails placed on this trail and what it all sells back for
local SUMMARY_WORDS = { { "tower", "tower light" }, { "rope", "rope light piece" }, { "snow", "snowblower" },
                        { "sign", "sign" }, { "flag", "flag" } }
local function refreshSummary()
  if not (P.allBox and P.trail) then return end
  local all = M.everything(P.trail)
  local parts, total, refund = {}, 0, 0
  for _, w in ipairs(SUMMARY_WORDS) do
    local l = all[w[1]] or {}
    if #l > 0 then parts[#parts + 1] = #l .. " " .. w[2] .. (#l == 1 and "" or "s") end
    total = total + #l
    for _, a in ipairs(l) do
      local ok, v = pcall(function() return a:GetRefundValue() end)
      if ok and type(v) == "number" then refund = refund + v end
    end
  end
  P.allBox:SetVisibility(total > 0 and 0 or 1)
  if total == 0 then return end
  setNote(P.allNote, "On this trail: " .. table.concat(parts, ", ") .. ". Remove everything sells them back for "
    .. money(refund) .. ".")
  P.confirmAt = nil
  setButton(P.allBtn, "Remove everything", C.red, true)
end

local function towerRefresh()
  local t = P.trail
  if not P.ctx then
    local ctx, cerr = M.prepare(P.base)
    if not ctx then
      for _, st in ipairs(STYLES) do setButton(P.styleButtons[st], nil, C.off, false) end
      setButton(P.main, "Install trail lights", C.off, false)
      P.removeBtn.w:SetVisibility(1); P.towerCB.box:SetVisibility(1); P.plan = nil
      setNote(P.note, cerr, C.warn)
      return
    end
    P.ctx = ctx
  end
  local ctx = P.ctx
  local style = P.styleOf[t.id] or "uniform"
  for _, st in ipairs(STYLES) do setButton(P.styleButtons[st], nil, st == style and C.on or C.off, true) end
  local p = M.plan(ctx, style)
  P.plan = p
  local n = #p.towers
  P.removeBtn.w:SetVisibility(p.removeCount > 0 and 0 or 1)
  setButton(P.removeBtn, "Remove", C.red, p.removeCount > 0)
  local each = string.format("%d Tower Light%s", n, n == 1 and "" or "s")
  local spacing = p.spacing and string.format(", every %d m", math.floor(p.spacing / 100 + 0.5)) or ""
  local back = sellBack(p.removeCount, p.refund)
  if p.same then
    setButton(P.main, "Installed (" .. STYLE_LABEL[style] .. ")", C.off, false)
    setNote(P.note, each .. spacing .. ". Pick another style to change them." .. (t.night and "" or " Night skiing is off above.") .. back, C.ok)
  elseif n == 0 then
    setButton(P.main, "Install trail lights", C.off, false)
    setNote(P.note, "No room for lights along this trail's edges." .. back, C.warn)
  elseif p.removeCount > 0 then
    setButton(P.main, string.format("Switch to %s  %s", STYLE_LABEL[style], money(p.net)), C.on, true)
    setNote(P.note, string.format("Replaces this trail's %d lights with %s%s (old ones sold back for %s).", p.removeCount,
      each, spacing, money(p.refund)))
  else
    setButton(P.main, string.format("Install trail lights  %s", money(p.net)), C.on, true)
    setNote(P.note, string.format("Places %s%s (%s each)%s.", each, spacing, money(p.cost),
      CFG.ENABLE_NIGHT and " and turns Night skiing on" or ""))
  end
  if P.msg then setNote(P.note, P.msg, C.warn); P.msg = nil end
  if p.dark and n > 0 then P.note:SetText(FText(P.note:GetText():ToString() .. " Parts too far from the edges stay dark.")) end
  P.note:SetText(FText(P.note:GetText():ToString() .. litNote()))
  refreshColorBox(P.towerCB, ctx.ours)
end

local LAYOUT_WORDS = { edges = "along both edges", zigzag = "zigzagging diagonally across the trail",
                       both = "along both edges and zigzagging across the trail" }

local function rangeWords(p)
  local a, z = snowRange(p.o)
  if a <= 0.001 and z >= 0.999 then return "" end
  if p.o.range == "top" then return " on the top half" end
  if p.o.range == "bottom" then return " on the bottom half" end
  local L = trailLength(p.b)
  return string.format(" from %d m to %d m down the trail", math.floor(a * L / 100 + 0.5), math.floor(z * L / 100 + 0.5))
end

local function describe(p)
  local n, f, o = #p.items, p.f, p.o
  if f.key == "rope" then
    local K = KINDS[p.k]
    return string.format("%d %s piece%s %s (%s each). Each lights %d m around it%s", n, K.label, n == 1 and "" or "s",
      LAYOUT_WORDS[o.layout] or "", money(p.cost), math.floor(ropeLight(p.k) / 100 + 0.5),
      (n >= CFG.MAX_ROPE and (". That's the most per trail (" .. CFG.MAX_ROPE .. "), so the far end of this long trail goes without") or "")
      .. ((p.steepSkipped or 0) > 0 and string.format(". %d piece%s left out where the ground is steeper than %d\u{B0}, so the game doesn't flatten it",
        p.steepSkipped, p.steepSkipped == 1 and " is" or "s are", CFG.ROPE_MAX_SLOPE) or ""))
  elseif f.key == "snow" then
    return string.format("%d snowblower%s every %d m%s%s, aimed across the trail (%s each, plus their running cost)", n,
      n == 1 and "" or "s", math.floor((p.spacing or 0) / 100 + 0.5),
      o.style == "oneside" and " on one side" or ", alternating sides", rangeWords(p), money(p.cost))
  end
  if f.key == "flag" then
    return string.format("%d flag%s along %d stretch%s %d\u{B0} or steeper, every %d m (%s each)", n,
      n == 1 and "" or "s", p.runs or 0, (p.runs or 0) == 1 and "" or "es", o.angle, math.floor(o.every / 100),
      money(p.cost))
  end
  local nj = p.junctions or 0
  local own = n - nj
  return string.format("%d %s sign%s, %s%s (%s each)", own, VARIANT_LABEL[p.variant] or "difficulty", own == 1 and "" or "s",
    (o.every or 0) > 0 and ("a pair at the top, then every " .. math.floor(o.every / 100) .. " m") or "a pair at the top",
    nj > 0 and string.format(", plus %d junction sign%s showing the trail%s that join%s or split%s off", nj,
      nj == 1 and "" or "s", nj == 1 and "" or "s", nj == 1 and "s" or "", nj == 1 and "s" or "") or "",
    money(p.cost))
end

-- the Custom range sliders: show the picked stretch (without it counting as a change)
local function setRangeSliders(U, o)
  local L = trailLength(P.base)
  for i, v in ipairs({ o.from or 0, o.to or 1 }) do
    local s = U.rangeSliders[i]
    s.w:SetValue(v)
    s.last = s.w:GetValue()
    s.val:SetText(FText(string.format("%d m", math.floor(v * L / 100 + 0.5))))
  end
end

local function featureRefresh(U)
  local f, t = U.f, P.trail
  local o = optsFor(f, t)
  for _, op in ipairs(f.options) do
    for _, ch in ipairs(op.choices) do setButton(U.opt[op.id][ch], nil, o[op.id] == ch and C.on or C.off, true) end
  end
  if U.rangeBox then
    U.rangeBox:SetVisibility(o.range == "custom" and 0 or 1)
    if o.range == "custom" and not U.rangeSlideAt then setRangeSliders(U, o) end
  end
  if U.styleBtn then
    local st, from = signStyle()
    local where = (from == "override") and "picked here" or ((from == "game" or from == "setting") and "as in the game" or "from the map")
    setButton(U.styleBtn, "Sign style: " .. STYLE_NAME[st] .. " (" .. where .. ")", from == "override" and C.on or C.off, true)
    P.lastStyle = st
  end
  local p = M.planFeature(f, P.base, o)
  U.plan = p
  local n = #p.items
  local back = sellBack(#p.ours, p.refund)
  U.remove.w:SetVisibility(#p.ours > 0 and 0 or 1)
  setButton(U.remove, "Remove", C.red, #p.ours > 0)
  if p.err then
    setButton(U.main, f.verb, C.off, false)
    setNote(U.note, p.err .. back, C.warn)
  elseif p.same then
    setButton(U.main, "Installed", C.off, false)
    setNote(U.note, describe(p) .. ". Pick other options to change them." .. back, C.ok)
  elseif p.restyle then
    setButton(U.main, "Update signs (free)", C.on, true)
    setNote(U.note, "The trail's difficulty or the sign style changed: update the signs to " .. (VARIANT_LABEL[p.variant] or "") .. "." .. back)
  elseif n == 0 then
    setButton(U.main, f.verb, C.off, false)
    setNote(U.note, "No room for " .. f.plural .. " along this trail." .. back, C.warn)
  elseif #p.ours > 0 then
    setButton(U.main, "Switch  " .. money(p.net), C.on, true)
    setNote(U.note, string.format("Replaces this trail's %d %s with %s (old ones sold back for %s).", #p.ours, f.plural,
      describe(p), money(p.refund)))
  else
    setButton(U.main, f.verb .. "  " .. money(p.net), C.on, true)
    setNote(U.note, "Places " .. describe(p) .. ".")
  end
  if P.msg then setNote(U.note, P.msg, C.warn); P.msg = nil end
  if f.key == "rope" then
    local extra = litNote()
    if #p.ours == 0 and not P.trail.night then extra = extra .. " Night skiing turns on if they light 90% of it." end
    U.note:SetText(FText(U.note:GetText():ToString() .. extra))
  end
  if U.cb then refreshColorBox(U.cb, p.ours) end
end

-- shows the picked tab and plans what it would do
refreshTab = function()
  P.atl = atlRunning()
  if P.atl and P.tab == "tower" then P.tab = "rope" end
  P.tabButtons.tower.w:SetVisibility(P.atl and 1 or 0)
  P.atlNote:SetVisibility(P.atl and 0 or 1)
  for _, key in ipairs(TABS) do
    P.boxes[key]:SetVisibility(key == P.tab and 0 or 1)
    setButton(P.tabButtons[key], nil, key == P.tab and C.on or C.off, true)
  end
  if not (P.base and P.trail) then return end
  if P.tab == "tower" then towerRefresh() else featureRefresh(P.F[P.tab]) end
end

-- remeasure = true: the trail changed (or another one is shown)
refresh = function(remeasure)
  if remeasure or not P.base then
    P.base, P.ctx, P.trail = nil, nil, nil
    local name = ""
    pcall(function() name = P.owner.TrailNameLabel:GetText():ToString() end)
    local t, err = M.trailByName(name)
    P.root:SetVisibility((t and t.shape == 1) and 1 or 0)   -- bowls: no section at all
    if t and t.shape == 1 then P.plan = nil; return end
    refreshTab()                                   -- tabs shown even when there's nothing to plan
    if not t then disableAll(err or "Finish the trail first.") return end
    local b, berr = M.base(t)
    if not b then disableAll(berr, C.warn) return end
    P.base, P.trail = b, t
    local ok, err = pcall(refreshSummary)
    if not ok then log("summary: " .. tostring(err)) end
  end
  refreshTab()
end

local function panelShown(w)
  if not (valid(w) and w:IsVisible()) then return false end
  local ok, v = pcall(function() return w.EditTabContent:IsVisible() end)
  return ok and v
end

-- the snowblowers' Custom range: values shown while dragging, the plan redone once let go
local function pollRangeSliders(U)
  if not (U and U.rangeSliders and P.trail and P.base) then return end
  local o = optsFor(U.f, P.trail)
  if o.range ~= "custom" then return end
  local L = trailLength(P.base)
  local changed = false
  for _, s in ipairs(U.rangeSliders) do
    local v = s.w:GetValue()
    if s.last == nil then s.last = v end
    if math.abs(v - s.last) > 0.001 then
      s.last = v; changed = true
      s.val:SetText(FText(string.format("%d m", math.floor(v * L / 100 + 0.5))))
    end
  end
  if changed then U.rangeSlideAt = frame end
  if U.rangeSlideAt and frame - U.rangeSlideAt > 20 then
    U.rangeSlideAt = nil
    o.from, o.to = U.rangeSliders[1].last, U.rangeSliders[2].last
    refreshTab()
  end
end

local function pollSliders()
  if P.tab == "tower" then pollColorSliders(P.towerCB)
  elseif P.tab == "rope" then pollColorSliders(P.F.rope.cb)
  elseif P.tab == "snow" then pollRangeSliders(P.F.snow) end
end

local function sliding()
  return (P.towerCB and P.towerCB.slideAt) or (P.F and P.F.rope and P.F.rope.cb and P.F.rope.cb.slideAt)
end

function M.poll()                                  -- every frame: a click lasts one frame
  if M.stopped then return end
  frame = frame + 1
  if M.job then
    local ok, err = pcall(M.stepJob)
    if not ok then log("job: " .. tostring(err)); M.job = nil; P.key = nil end
  end
  local okp, perr = pcall(M.partyStep)
  if not okp and frame % 600 == 0 then log("party: " .. tostring(perr)) end
  if not panelShown(P.owner) or not P.controls then return end
  if M.job then                                    -- busy: show how far it is, take no clicks
    for _, d in ipairs(P.controls) do d.enabled = false; d.was = false end
    if frame % 5 == 0 then
      local main = (P.tab == "tower") and P.main or (P.F and P.F[P.tab] and P.F[P.tab].main)
      if main and valid(main.w) then
        main.label:SetText(FText(M.jobProgress() or ""))
        main.w:SetBackgroundColor(C.off)
      end
    end
    return
  end
  local oks, serr = pcall(pollSliders)
  if not oks then log("sliders: " .. tostring(serr)) end
  for _, c in ipairs(P.controls) do
    if valid(c.w) then
      local p = c.w:IsPressed()
      if c.was and not p and c.w:IsHovered() and c.enabled then
        for _, d in ipairs(P.controls) do d.enabled = false end   -- one action per click, until re-planned
        local ok, err = pcall(c.fn)
        if not ok then log("click: " .. tostring(err)); pcall(refreshTab) end
        c.was = false
        return
      end
      c.was = p
    end
  end
end

local bgTick = 0
function M.background()                            -- 4 times a second
  if M.stopped then return end
  bgTick = bgTick + 1
  if bgTick % 20 == 0 and not sliding() then       -- every 5 s (not mid-drag): saved colors back on lights
    local ok, err = pcall(M.repaintAll, P.atl)      -- (tower lights are Auto Trail Lights' when it runs)
    if not ok then log("repaint: " .. tostring(err)) end
  end
  if not P.atl then
    local r = refs()
    if valid(r.world) and bgTick % 20 == 10 and not M.job and M.cleanedWorld ~= addressOf(r.world) then
      M.cleanedWorld = addressOf(r.world)          -- once per loaded resort
      local ok, err = pcall(M.cleanupElsewhere)
      if not ok then log("cleanup: " .. tostring(err)) end
    end
  end
  if bgTick % 20 == 5 and not M.job then           -- every 5 s: the mod's rope light pieces without shadows
    local ok, err = pcall(M.unshadowRopes)
    if not ok then log("shadows: " .. tostring(err)) end
  end
  local w = P.owner
  if not valid(w) then
    P.owner = nil
    local r = refs()
    if not valid(r.world) then return end
    -- the game makes the trail panel the first time one is opened: it tells us (see the notification below); a
    -- full search (13 ms) only every 15 s, in case the notification didn't come
    local cand = M.newPanel
    M.newPanel = nil
    if not (valid(cand) and sameWorld(cand, r.world)) then
      if bgTick % 60 ~= 0 then return end
      cand = findIn("TrailEditWidget", r.world)
    end
    if not valid(cand) then return end
    if not inject(cand) then M.newPanel = cand; return end   -- not built yet: next time
    w = cand
  end
  if not panelShown(w) then P.key = nil; return end
  if M.job then return end                         -- re-plan once it's done
  local key = ""
  pcall(function() key = w.TrailNameLabel:GetText():ToString() .. "|" .. w.LengthLabel:GetText():ToString() end)
  if key ~= P.key then                             -- another trail, or this one changed or was just dressed
    P.key = key
    local ok, err = pcall(refresh, true)
    if not ok then
      log("refresh: " .. tostring(err))
      pcall(disableAll, "Something went wrong (see UE4SS.log).", C.warn)
    end
    return
  end
  -- every 2 s on the signs tab: the trail's difficulty or the sign style may have changed
  if bgTick % 8 == 0 and P.tab == "sign" and P.trail then
    local t = M.trailById(P.trail.id)
    if (t and t.diff ~= P.trail.diff) or signStyle() ~= P.lastStyle then P.key = nil end
  end
  -- Auto Trail Lights switched on or off while the panel is open
  if bgTick % 8 == 4 and atlRunning() ~= P.atl then pcall(refreshTab) end
end

if not M.started then
  M.started = true
  pcall(function()
    NotifyOnNewObject("/Script/SkiResortSimulator.TrailEditWidget", function(w) M.newPanel = w end)
  end)
  LoopInGameThreadAfterFrames(1, guarded("poll", function() M.poll() end))
  LoopInGameThreadAfterFrames(15, guarded("background", function() M.background() end))
  log("loaded " .. M.VERSION .. " - open a trail's panel, Edit tab: \"Better Trails\"")
end

-- Z's Mod Loader live switching (its Mod Manager can turn mods on and off while the game runs): say we're on at
-- startup; on unload stop working, take the section out of the panel and clear the flag. Things already placed stay:
-- they're ordinary buildings, saved with the resort. Without that loader (plain UE4SS) this only sets an unused
-- shared variable.
local ENABLED_KEY = "SkiEOMods.enabled.BetterTrails"
local function setEnabledFlag(on)
  if on then pcall(function() ModRef:SetSharedVariable(ENABLED_KEY, true) end) return end
  if not pcall(function() ModRef:SetSharedVariable(ENABLED_KEY, nil) end) then
    pcall(function() ModRef:SetSharedVariable(ENABLED_KEY, false) end)
  end
end
if ModRef then
  setEnabledFlag(true)
  pcall(function()
    ModRef.OnUnload = function()
      M.stopped = true
      if M.job then log("switched off mid-job: stopped there"); M.job = nil end
      pcall(function()
        local root = M.P and M.P.root
        if root and root:IsValid() then root:RemoveFromParent() end
      end)
      if M.P then M.P.owner, M.P.root, M.P.key = nil, nil, nil end
      setEnabledFlag(false)
      log("switched off")
    end
  end)
end

return M
