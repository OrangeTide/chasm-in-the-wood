program chasm;

{** Third-person voxel dungeon.

  Opens an SDL3 window with an OpenGL 3.3 core context and starts in the town of
  Brackenridge, drawn from authored voxel tiles with a player voxel model on top. Move
  a tile at a time with WASD or the arrow keys (walls block); stepping into a monster
  attacks it, onto loot gathers it, and each move spends a turn the monsters answer.
  Space speaks to an adjacent townsperson, or waits a turn below. The diorama camera
  follows. Return takes the stairs underfoot: the town chasm descends, an up-stair
  climbs, depth 0's up-stair returns to town, and it respawns a slain player. I opens
  the pack and the equipment doll: drag a weapon, armour, or shield onto the doll to
  wear it, and drag it off to stow it; R quaffs a healing potion. C shows the character
  sheet. F5 saves the game and F9 loads it. Q/E orbit, -/= zoom, Escape quits.

  Args: [model.vox] [screenshot.ppm] [seed]. A screenshot path renders one frame
  and exits. The player model defaults to content/models/character.vox. }

{$mode objfpc}{$H+}

uses
  ctypes, sysutils, classes, math,
  sdl3, glcore, vecmath, camera,
  voxfile, voxmesh, gpumesh, meshshader, frustum, tilekit, prims,
  tilemap, tileworld, themes, worldgraph, world, player, gameui,
  content, entities, turns, town, townsfolk, saveload;

const
  WIN_W = 960;
  WIN_H = 720;
  FOLLOW = 0.15;
  ENTITY_RADIUS = 1;        { regions around the player that hold live entities }
  SAVE_PATH = 'chasm.sav';  { the single save slot, beside the executable }
  VIEW_TILES = 22;          { tile radius drawn around the player before culling }
  { The object voxel-unit: world units per voxel for every free-standing model, so a
    model's size is its voxel count. TILE_FOOT voxels span one tile, so TILE_FOOT * VU
    equals one tile and the tiles share the scale. }
  VU = 0.0625;
  PLAYER_DIAM = 26;         { the player placeholder ball, in voxels }
  PROP_DIAM = 8;            { a loot placeholder ball, in voxels }
  PLAYER_HEIGHT = PLAYER_DIAM * VU;   { the player's world height, for the camera }
  { Placeholder ball diameter per monster bulk, indexed by TSizeClass. }
  CREATURE_DIAM: array[TSizeClass] of LongInt = (8, 13, 18, 23, 28, 33);

var
  win: PSDL_Window;
  glctx: TSDL_GLContext;
  ev: TSDL_Event;
  shader: TMeshShader;
  playerGpu: TGpuMesh;
  playerBase: TMat4;
  creatureGpu: array[TSizeClass] of TGpuMesh;
  creatureBase: array[TSizeClass] of TMat4;
  propGpu: TGpuMesh;
  propBase: TMat4;
  gContent: TContent;
  entSet: TEntitySet;
  lastRx, lastRy: LongInt;
  inTown: Boolean;
  relicIdx: LongInt;       { content index of the objective, or -1 }
  won: Boolean;            { the objective has reached town }
  defSpecies, defKlass: LongInt;   { the new-game default character }
  startName: String;       { the name a fresh default character carries }
  cam: TCamera;
  tw: TTileWorld;
  pl: TPlayer;
  lightDir, desired: TVec3;
  voxPath, shotPath: String;
  seed, worldSeed: QWord;
  depth: LongInt;
  twInit: Boolean;
  sc: cuint32;
  running: Boolean;
  drawnTiles: LongInt;
  mx, my, wy: LongInt;
  sz: TSizeClass;
  ei: LongInt;
  pmodel: TVoxModel;
  pmesh: TVoxMesh;
  held: array[0 .. 511] of Boolean;   { which keys are held, by scancode }
  lastTicks: cuint64;
  frameDt: Single;

type
  TArrive = (arSpawn, arUp, arDown);

procedure Die(const msg: String);
begin
  writeln(StdErr, 'chasm: ', msg, ': ', SDL_GetError);
  halt(1);
end;

function FloorDivTile(t: LongInt): LongInt;
{ The region coordinate holding tile t, flooring toward negative. }
begin
  if t >= 0 then FloorDivTile := t div REGION
  else FloorDivTile := -(((-t) + REGION - 1) div REGION);
end;

function TileWorld(cx, cy: LongInt): TVec3;
begin
  TileWorld := Vec3((cx + 0.5) * TILE, FLOOR_TOP_Y, (cy + 0.5) * TILE);
end;

function FloatWorld(px, py: Single): TVec3;
{ The world point under a continuous (tile-unit) position. }
begin
  FloatWorld := Vec3(px * TILE, FLOOR_TOP_Y, py * TILE);
end;

function PlayerModelMatrix: TMat4;
var
  c: TVec3;
begin
  c := FloatWorld(pl.Px, pl.Py);
  PlayerModelMatrix := Mat4Multiply(Mat4Translate(c.X, FLOOR_TOP_Y, c.Z), playerBase);
end;

function ModelBaseVU(sx, sy, sz: LongInt): TMat4;
{ Place a z-up voxel model at the object voxel-unit, so its world size is its voxel
  count times VU. Feet at y=0, centred on x and z, the file's z-up turned to world y-up
  (height becomes sz * VU). }
var
  h: Single;
begin
  h := sz * VU;
  ModelBaseVU := Mat4Multiply(
    Mat4Multiply(Mat4Translate(0, h / 2, 0), Mat4Scale(VU)),
    Mat4Multiply(Mat4RotateX(-pi / 2),
      Mat4Translate(-sx / 2.0, -sy / 2.0, -sz / 2.0)));
end;

procedure RebuildEntities;
{ Repopulate the entity set: the hamlet's townsfolk in town, or the dungeon monsters
  and loot for the player's current region neighbourhood below. }
begin
  lastRx := FloorDivTile(pl.Cx);
  lastRy := FloorDivTile(pl.Cy);
  if inTown then
    TownsfolkBuild(entSet, TileWorldTownLayout(tw))
  else
    EntitiesBuild(entSet, gContent, tw, lastRx, lastRy, ENTITY_RADIUS, pl.Cx, pl.Cy);
end;

procedure SaveShot(const path: String);
var
  pix: array of Byte;
  y, stride: LongInt;
  fs: TFileStream;
  hdr: String;
begin
  stride := WIN_W * 3;
  SetLength(pix, stride * WIN_H);
  glReadPixels(0, 0, WIN_W, WIN_H, GL_RGB, GL_UNSIGNED_BYTE, @pix[0]);
  fs := TFileStream.Create(path, fmCreate);
  try
    hdr := 'P6'#10 + IntToStr(WIN_W) + ' ' + IntToStr(WIN_H) + #10 + '255'#10;
    fs.WriteBuffer(hdr[1], length(hdr));
    for y := WIN_H - 1 downto 0 do
      fs.WriteBuffer(pix[y * stride], stride);
  finally
    fs.Free;
  end;
  writeln('wrote ', path);
end;

procedure SnapCamera;
begin
  cam.Target := FloatWorld(pl.Px, pl.Py);
  cam.Target.Y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;
end;

procedure EnterDepth(d: LongInt; arrive: TArrive; trx, try_: LongInt);
{ Switch to dungeon depth d, place the player at the chosen entry, and rebuild the
  voxel world from the new depth's tiles. Stair arrivals land in region (trx, try_),
  on the stair that matches the one just used; if none is there, fall back to spawn. }
var
  px, py: LongInt;
  ok: Boolean;
begin
  if twInit then TileWorldFree(tw);
  TileWorldInit(tw, worldSeed, d);
  twInit := True;
  inTown := False;
  case arrive of
    arUp:   ok := TileWorldRegionUpStair(tw, trx, try_, px, py);
    arDown: ok := TileWorldRegionDownStair(tw, trx, try_, px, py);
  else      ok := False;
  end;
  if not ok then TileWorldSpawn(tw, px, py);
  { The player keeps health, purse, and pack across the descent; only a new game or a
    respawn (through the town) resets them. }
  PlayerPlace(pl, px, py);
  depth := d;
  SnapCamera;
  RebuildEntities;
  writeln('depth ', d, ', spawn (', px, ',', py, '), ',
          ThemeTable[TileWorldThemeAt(tw, px, py)].Name, ' zone, ',
          TileWorldRegionCount(tw), ' regions, ', entSet.Monsters, ' foes');
end;

function HasRelic: Boolean;
{ Whether the objective is in the pack. }
var
  i: LongInt;
begin
  HasRelic := False;
  if relicIdx < 0 then exit;
  for i := 0 to pl.NCarry - 1 do
    if pl.Carry[i] = relicIdx then exit(True);
end;

procedure CheckVictory;
{ The descent is won when the objective reaches town. Surfaced in the log for now; the
  victory screen arrives with the front end. }
begin
  if won or (not inTown) or (not HasRelic) then exit;
  won := True;
  TurnsLogAdd('You bear the Heart of the Chasm into Brackenridge. The chasm is won!');
end;

procedure EnterTown(fresh: Boolean);
{ Enter the surface hamlet. A fresh arrival is a new game, with full starting stats; a
  respawn revives the fallen player, keeping purse and pack, and sets them on the
  spawn. The world rebuilds from the town's tiles and the townsfolk take their places. }
var
  px, py: LongInt;
begin
  if twInit then TileWorldFree(tw);
  TileWorldInitTown(tw, worldSeed);
  twInit := True;
  inTown := True;
  TileWorldSpawn(tw, px, py);
  if fresh then begin
    PlayerCreate(pl, gContent, defSpecies, defKlass, startName, px, py);
    won := False;                 { a new game is not yet won }
  end
  else begin
    PlayerRevive(pl);
    PlayerPlace(pl, px, py);
  end;
  depth := 0;
  SnapCamera;
  RebuildEntities;
  CheckVictory;
  writeln('entered Brackenridge, spawn (', px, ',', py, ')');
end;

procedure RestoreAt(inT: Boolean; d: LongInt);
{ Rebuild the world at a saved location around the already-restored player, without
  touching the player's state or the loaded registries. }
begin
  if twInit then TileWorldFree(tw);
  if inT then TileWorldInitTown(tw, worldSeed)
  else TileWorldInit(tw, worldSeed, d);
  twInit := True;
  inTown := inT;
  depth := d;
  SnapCamera;
  RebuildEntities;
end;

procedure SaveCurrent;
var
  st: TSaveState;
begin
  st.Seed := worldSeed;
  st.InTown := inTown;
  st.Depth := depth;
  st.Pl := pl;
  if SaveGame(SAVE_PATH, st) then TurnsLogAdd('Game saved.')
  else TurnsLogAdd('Save failed.');
end;

procedure LoadSaved;
{ Restore a saved game: the registries and player come from the file, then the world
  is rebuilt from the seed at the saved location. }
var
  st: TSaveState;
begin
  if not LoadGame(SAVE_PATH, st) then begin
    TurnsLogAdd('No save to load.');
    exit;
  end;
  worldSeed := st.Seed;
  TurnsSeed(worldSeed);
  pl := st.Pl;
  won := False;
  RestoreAt(st.InTown, st.Depth);
  CheckVictory;
  TurnsLogAdd('Game loaded.');
end;

procedure ReportStitch;
{ Confirm the stitched world graph links zones: report how many portals the spawn room
  is from a room one zone to the right. }
var
  a, b: TRoomRef;
  tx, ty, d: LongInt;
  haveB: Boolean;
begin
  if inTown then exit;
  if not TileWorldRoomAt(tw, pl.Cx, pl.Cy, a) then exit;
  haveB := False;
  for ty := 0 to REGION - 1 do
    for tx := 0 to REGION - 1 do
      if (not haveB) and TileWorldRoomAt(tw, ZONE_REGIONS * REGION + tx, ty, b) then
        haveB := True;
  if not haveB then exit;
  d := WorldGraphDistance(tw, a, b, 8000);
  if d >= 0 then
    writeln('zones stitched: spawn reaches zone (1,0) in ', d, ' portals')
  else
    writeln('zones not connected to zone (1,0)');
end;

function ItemGlyph(const kind: String): Char;
{ A one-letter stand-in for the item's art on its inventory tile. }
begin
  if kind = 'weapon' then ItemGlyph := 'W'
  else if kind = 'armor' then ItemGlyph := 'A'
  else if kind = 'shield' then ItemGlyph := 'H'
  else if kind = 'potion' then ItemGlyph := 'P'
  else if kind = 'light' then ItemGlyph := 'T'
  else if kind = 'treasure' then ItemGlyph := '$'
  else if kind = 'key' then ItemGlyph := 'K'
  else ItemGlyph := 'M';
end;

function ItemColor(const kind: String): LongInt;
{ A tile colour per kind, ARGB, standing in for item art. }
begin
  if kind = 'weapon' then ItemColor := LongInt($FFB04030)
  else if kind = 'armor' then ItemColor := LongInt($FF8A5A2A)
  else if kind = 'shield' then ItemColor := LongInt($FF808890)
  else if kind = 'potion' then ItemColor := LongInt($FF40A050)
  else if kind = 'light' then ItemColor := LongInt($FFE0B040)
  else if kind = 'treasure' then ItemColor := LongInt($FFE0C040)
  else ItemColor := LongInt($FFA0A0A0);
end;

function BuildUIItem(itemIdx: LongInt): TUIItem;
{ Describe a content item for the panels, or an empty slot when itemIdx is negative. }
var
  kind: String;
begin
  if itemIdx < 0 then begin
    BuildUIItem.Tag := -1;
    BuildUIItem.Cat := 0;
    BuildUIItem.Color := 0;
    BuildUIItem.Glyph := ' ';
    BuildUIItem.Name := '';
    exit;
  end;
  kind := gContent.Items[itemIdx].Kind;
  BuildUIItem.Tag := itemIdx;
  BuildUIItem.Cat := GameUIItemCat(kind);
  BuildUIItem.Color := ItemColor(kind);
  BuildUIItem.Glyph := ItemGlyph(kind);
  BuildUIItem.Name := gContent.Items[itemIdx].Name;
end;

procedure PushInventory;
{ Mirror the pack and the worn gear into the inventory and equipment panels. }
var
  items: array of TUIItem;
  i: LongInt;
begin
  SetLength(items, pl.NCarry);
  for i := 0 to pl.NCarry - 1 do items[i] := BuildUIItem(pl.Carry[i]);
  GameUISetInventory(items);
  GameUISetWorn(BuildUIItem(pl.Equip[eqWeapon]),
                BuildUIItem(pl.Equip[eqArmor]),
                BuildUIItem(pl.Equip[eqShield]));
end;

function SignedStr(v: LongInt): String;
{ A signed number for a modifier display, like +2 or -1. }
begin
  if v >= 0 then SignedStr := '+' + IntToStr(v) else SignedStr := IntToStr(v);
end;

procedure PushCharStats;
{ The live character sheet: the identity header and the derived numbers. }
var
  lines: array[0 .. 4] of String;
  spName, clName: String;
begin
  lines[0] := 'LEVEL ' + IntToStr(pl.Level) + '   XP ' + IntToStr(pl.Xp) +
              '/' + IntToStr(XpToNext(pl.Level));
  lines[1] := 'HP ' + IntToStr(pl.Hp) + '/' + IntToStr(pl.MaxHp) +
              '   AC ' + IntToStr(pl.Ac);
  lines[2] := 'ATK ' + SignedStr(pl.Atk) + '   DMG 1-' + IntToStr(pl.DmgDie) +
              ' ' + SignedStr(pl.DmgBonus);
  lines[3] := 'STR ' + IntToStr(pl.Str) + '  DEX ' + IntToStr(pl.Dex) +
              '  CON ' + IntToStr(pl.Con);
  lines[4] := 'INT ' + IntToStr(pl.Int) + '  WIS ' + IntToStr(pl.Wis) +
              '  CHA ' + IntToStr(pl.Cha);
  GameUISetCharStats(lines);
  if pl.Species >= 0 then spName := gContent.Species[pl.Species].Name
  else spName := 'Wanderer';
  if pl.Klass >= 0 then clName := gContent.Classes[pl.Klass].Name
  else clName := 'Vagrant';
  GameUISetCharIdentity(pl.Name, clName, spName);
end;

procedure UpdateStatus;
{ Push the live game state into the HUD panel: health first, the world lines, then the
  tail of the combat log. The character sheet's live stats ride along. }
var
  th, i, n, show: LongInt;
  lines: array of String;
begin
  th := TileWorldThemeAt(tw, pl.Cx, pl.Cy);
  n := TurnsLogCount;
  show := Min(3, n);
  SetLength(lines, 7 + show);
  lines[0] := 'HP ' + IntToStr(pl.Hp) + '/' + IntToStr(pl.MaxHp);
  if not pl.Alive then lines[0] := lines[0] + '  YOU DIED - ENTER'
  else if won then lines[0] := lines[0] + '  CHASM WON'
  else if HasRelic then lines[0] := lines[0] + '  RELIC - CLIMB OUT';
  if inTown then
    lines[1] := 'TOWN ' + ThemeTable[th].Name
  else
    lines[1] := 'DEPTH ' + IntToStr(depth) + ' ' + ThemeTable[th].Name;
  lines[2] := 'GOLD ' + IntToStr(pl.Gold) + ' PACK ' + IntToStr(pl.NCarry);
  lines[3] := 'TILE ' + IntToStr(pl.Cx) + ' ' + IntToStr(pl.Cy);
  if inTown then
    lines[4] := 'SPACE TO SPEAK'
  else
    lines[4] := 'FOES ' + IntToStr(entSet.Monsters) + ' LOOT ' + IntToStr(entSet.Props);
  lines[5] := 'RES ' + IntToStr(TileWorldRegionCount(tw)) + ' ' +
              IntToStr(drawnTiles);
  lines[6] := 'SEED ' + IntToStr(Int64(worldSeed));
  for i := 0 to show - 1 do
    lines[7 + i] := TurnsLogLine(n - show + i);
  GameUISetStatus(lines);
  PushCharStats;
end;

procedure ApplyInventoryChange(const packTags: array of LongInt;
  weaponTag, armorTag, shieldTag: LongInt);
{ The player rearranged the panels by dragging: rebuild the pack and worn gear from the
  new layout, then recompute the derived combat stats. }
var
  i: LongInt;
begin
  pl.NCarry := 0;
  for i := 0 to High(packTags) do
    if (packTags[i] >= 0) and (pl.NCarry < MAX_CARRY) then begin
      pl.Carry[pl.NCarry] := packTags[i];
      Inc(pl.NCarry);
    end;
  pl.Equip[eqWeapon] := weaponTag;
  pl.Equip[eqArmor] := armorTag;
  pl.Equip[eqShield] := shieldTag;
  PlayerRecalc(pl, gContent);
  UpdateStatus;
end;

procedure DoCreateChar(speciesIdx, classIdx: LongInt; const name: String);
{ The player pressed Begin in the creation window: forge the chosen character and set
  them on the town spawn to start the game. }
var
  px, py: LongInt;
begin
  TileWorldSpawn(tw, px, py);
  PlayerCreate(pl, gContent, speciesIdx, classIdx, name, px, py);
  won := False;
  SnapCamera;
  RebuildEntities;
  PushInventory;
  UpdateStatus;
end;

procedure SetupCreation;
{ Build the creation window from the content tables: every species, and one class per
  quick-start archetype, with the random name pool. }
var
  spNames, clNames: array of String;
  clIdx: array of LongInt;
  i, j, ci, nc: LongInt;
  dup: Boolean;
begin
  SetLength(spNames, Length(gContent.Species));
  for i := 0 to High(gContent.Species) do spNames[i] := gContent.Species[i].Name;
  { Offer the distinct pregen classes as the class choices. }
  nc := 0;
  SetLength(clNames, Length(gContent.Pregens));
  SetLength(clIdx, Length(gContent.Pregens));
  for i := 0 to High(gContent.Pregens) do begin
    ci := ClassByIdx(gContent, gContent.Pregens[i].Klass);
    if ci < 0 then continue;
    dup := False;
    for j := 0 to nc - 1 do if clIdx[j] = ci then dup := True;
    if dup then continue;
    clIdx[nc] := ci;
    clNames[nc] := gContent.Classes[ci].Name;
    Inc(nc);
  end;
  SetLength(clNames, nc);
  SetLength(clIdx, nc);
  GameUIInitCreate(spNames, clNames, clIdx, gContent.Names, defSpecies, defKlass);
  GameUISetCreateDone(@DoCreateChar);
end;

function TileEnvAt(tx, ty: LongInt): TTileEnv;
{ The environment a tile is drawn in: the dungeon below, or on the surface the hamlet
  versus the forest around it. }
begin
  if not inTown then TileEnvAt := teDungeon
  else if TileWorldInHamlet(tw, tx, ty) then TileEnvAt := teTown
  else TileEnvAt := teForest;
end;

procedure DrawTile(tx, ty: LongInt; env: TTileEnv; kind: TTileKind);
{ Draw one authored tile mesh, scaled so its footprint fills one world cell, at the
  tile origin. The scale is per tile because the sets differ in native resolution. }
var
  m: TTileMesh;
  s: Single;
begin
  m := TileKitMesh(env, kind);
  if not m.Loaded then exit;
  if m.Sx < 1 then exit;
  s := TILE / m.Sx;
  MeshShaderModel(shader,
    Mat4Multiply(Mat4Translate(tx * TILE, 0, ty * TILE), Mat4Scale(s)));
  GpuMeshDraw(m.Gpu);
end;

function RockBordersCarved(tx, ty: LongInt): Boolean;
{ True when a rock tile has a non-rock neighbour, so it is the stone face around carved
  space rather than rock buried behind that face. Checks the eight surrounding tiles. }
var
  dx, dy: LongInt;
begin
  RockBordersCarved := True;
  for dy := -1 to 1 do
    for dx := -1 to 1 do
      if ((dx <> 0) or (dy <> 0)) and
         (TileAt(tw, tx + dx, ty + dy) <> TILE_ROCK) then exit;
  RockBordersCarved := False;
end;

procedure DrawTiles;
{ Draw the visible tiles around the player, each as an instance of its environment and
  kind's baked mesh. Reading a tile generates its region, so the window streams. }
var
  f: TFrustum;
  tx, ty: LongInt;
  t: Byte;
  env: TTileEnv;
  mn, mx: TVec3;
begin
  FrustumFromClip(Mat4Multiply(CameraProj(cam), CameraView(cam)), f);
  drawnTiles := 0;
  for ty := pl.Cy - VIEW_TILES to pl.Cy + VIEW_TILES do
    for tx := pl.Cx - VIEW_TILES to pl.Cx + VIEW_TILES do begin
      t := TileAt(tw, tx, ty);
      { Rock is the solid mass the dungeon is carved from. A rock tile touching carved
        space is drawn as a wall-height block so the rooms sit in stone, not a void; rock
        deeper than that stays unseen behind it and is skipped. }
      if t = TILE_ROCK then begin
        if not RockBordersCarved(tx, ty) then continue;
        mn := Vec3(tx * TILE, 0, ty * TILE);
        mx := Vec3((tx + 1) * TILE, TILE_MAXH * VOX * 2, (ty + 1) * TILE);
        if not FrustumTestAABB(f, mn, mx) then continue;
        DrawTile(tx, ty, TileEnvAt(tx, ty), tkWall);
        Inc(drawnTiles);
        continue;
      end;
      mn := Vec3(tx * TILE, 0, ty * TILE);
      mx := Vec3((tx + 1) * TILE, TILE_MAXH * VOX * 2, (ty + 1) * TILE);
      if not FrustumTestAABB(f, mn, mx) then continue;
      env := TileEnvAt(tx, ty);
      case t of
        TILE_WALL: DrawTile(tx, ty, env, tkWall);
        TILE_DOOR:
          begin DrawTile(tx, ty, env, tkFloor); DrawTile(tx, ty, env, tkDoor); end;
        TILE_STAIRS_DOWN:
          begin DrawTile(tx, ty, env, tkFloor); DrawTile(tx, ty, env, tkStairDn); end;
        TILE_STAIRS_UP:
          begin DrawTile(tx, ty, env, tkFloor); DrawTile(tx, ty, env, tkStairUp); end;
      else
        DrawTile(tx, ty, env, tkFloor);
      end;
      Inc(drawnTiles);
    end;
end;

procedure UpdatePlayer(dt: Single);
{ Move the player from the held keys, relative to where the camera looks, and slide along
  walls. The world's axes are read from the camera so pressing forward walks into the
  screen rather than along a fixed world axis. }
var
  eye, fwd: TVec3;
  fx, fz, rx, rz, mvx, mvz, len, step, nx, ny: Single;
begin
  if not pl.Alive then exit;
  eye := CameraEye(cam);
  fx := cam.Target.X - eye.X;
  fz := cam.Target.Z - eye.Z;
  len := Sqrt(fx * fx + fz * fz);
  if len < 1e-4 then exit;
  fx := fx / len; fz := fz / len;   { camera forward on the ground }
  rx := -fz; rz := fx;              { camera right on the ground }

  mvx := 0; mvz := 0;
  if held[SDL_SCANCODE_W] or held[SDL_SCANCODE_UP]    then begin mvx := mvx + fx; mvz := mvz + fz; end;
  if held[SDL_SCANCODE_S] or held[SDL_SCANCODE_DOWN]  then begin mvx := mvx - fx; mvz := mvz - fz; end;
  if held[SDL_SCANCODE_D] or held[SDL_SCANCODE_RIGHT] then begin mvx := mvx + rx; mvz := mvz + rz; end;
  if held[SDL_SCANCODE_A] or held[SDL_SCANCODE_LEFT]  then begin mvx := mvx - rx; mvz := mvz - rz; end;

  len := Sqrt(mvx * mvx + mvz * mvz);
  if len < 1e-4 then exit;
  mvx := mvx / len; mvz := mvz / len;
  pl.Facing := ArcTan2(mvz, mvx);
  step := PLAYER_MOVE * dt;
  nx := pl.Px + mvx * step;
  if TurnsPosFree(tw, nx, pl.Py) then pl.Px := nx;
  ny := pl.Py + mvz * step;
  if TurnsPosFree(tw, pl.Px, ny) then pl.Py := ny;
  pl.Cx := Floor(pl.Px);
  pl.Cy := Floor(pl.Py);
end;

procedure QuaffPotion;
{ Drink a healing draught from the pack, if the player is hurt and carries one. }
var
  healed: LongInt;
begin
  healed := PlayerQuaff(pl, gContent);
  if healed > 0 then begin
    TurnsLogAdd('You drink a potion. (+' + IntToStr(healed) + ')');
    PushInventory;
  end else
    TurnsLogAdd('Nothing to quaff.');
end;

procedure UseStairs;
{ Take the stairs under the player, if any. The descent or ascent lands in the same
  region on the next depth, so the stairs there line up with the one just used. }
var
  t: Byte;
  rx, ry: LongInt;
begin
  t := TileAt(tw, pl.Cx, pl.Cy);
  rx := FloorDivTile(pl.Cx);
  ry := FloorDivTile(pl.Cy);
  if inTown then begin
    { The chasm at the heart of the hamlet drops into the dungeon. }
    if t = TILE_STAIRS_DOWN then EnterDepth(0, arSpawn, 0, 0);
  end else begin
    if t = TILE_STAIRS_DOWN then EnterDepth(depth + 1, arUp, rx, ry)
    else if t = TILE_STAIRS_UP then begin
      { The climb out of depth 0 returns to the surface; deeper up-stairs ascend. }
      if depth = 0 then EnterTown(False)
      else EnterDepth(depth - 1, arDown, rx, ry);
    end;
  end;
end;

begin
  if ParamCount >= 1 then voxPath := ParamStr(1)
  else voxPath := 'content/models/character.vox';
  if ParamCount >= 2 then shotPath := ParamStr(2) else shotPath := '';
  if ParamCount >= 3 then seed := QWord(StrToInt64Def(ParamStr(3), 1337))
  else seed := 1337;

  if not SDL_Init(SDL_INIT_VIDEO) then Die('SDL_Init failed');

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

  win := SDL_CreateWindow('Chasm in the Wood', WIN_W, WIN_H, SDL_WINDOW_OPENGL);
  if win = nil then Die('SDL_CreateWindow failed');
  glctx := SDL_GL_CreateContext(win);
  if glctx = nil then Die('SDL_GL_CreateContext failed');
  SDL_GL_MakeCurrent(win, glctx);
  SDL_GL_SetSwapInterval(1);

  if not LoadGL(TGLGetProcAddr(@SDL_GL_GetProcAddress)) then begin
    writeln(StdErr, 'chasm: could not load OpenGL entry points');
    halt(1);
  end;
  writeln('GL renderer: ', glGetString(GL_RENDERER));

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LESS);
  glEnable(GL_CULL_FACE);
  glCullFace(GL_BACK);
  glFrontFace(GL_CCW);

  if not MeshShaderInit(shader) then begin
    writeln(StdErr, 'chasm: shader init failed');
    halt(1);
  end;

  { The player placeholder: a ball, placed at the object voxel-unit. }
  PrimSphere(pmodel, PLAYER_DIAM);
  BuildMesh(pmodel, pmesh);
  GpuMeshUpload(playerGpu, pmesh);
  playerBase := ModelBaseVU(pmodel.Sx, pmodel.Sy, pmodel.Sz);

  { Content tables, and the placeholder voxel models for their inhabitants. }
  if not ContentLoad('content', gContent) then
    writeln(StdErr, 'chasm: warning: some content tables failed to load');
  writeln('content: ', Length(gContent.Monsters), ' monsters, ',
          Length(gContent.Items), ' items, ', Length(gContent.Species),
          ' species, ', Length(gContent.Classes), ' classes');
  relicIdx := ItemByIdx(gContent, 'RELIC');
  won := False;
  { The new-game default character, from newgame.txt (falling back to the first entry). }
  defSpecies := SpeciesByIdx(gContent, gContent.DefSpecies);
  if defSpecies < 0 then defSpecies := 0;
  defKlass := ClassByIdx(gContent, gContent.DefKlass);
  if defKlass < 0 then defKlass := 0;
  if Length(gContent.Names) > 0 then
    startName := gContent.Names[LongInt(seed mod QWord(Length(gContent.Names)))]
  else
    startName := 'Vagrant';
  { Monster placeholders: one ball per bulk, each placed at the object voxel-unit. }
  for sz := Low(TSizeClass) to High(TSizeClass) do begin
    PrimSphere(pmodel, CREATURE_DIAM[sz]);
    BuildMesh(pmodel, pmesh);
    GpuMeshUpload(creatureGpu[sz], pmesh);
    creatureBase[sz] := ModelBaseVU(pmodel.Sx, pmodel.Sy, pmodel.Sz);
  end;
  { Loot placeholder: a small ball, tinted per entity at draw. }
  PrimSphere(pmodel, PROP_DIAM);
  BuildMesh(pmodel, pmesh);
  GpuMeshUpload(propGpu, pmesh);
  propBase := ModelBaseVU(pmodel.Sx, pmodel.Sy, pmodel.Sz);

  { The tiles, generated (plate floors and walls, arched doors, stepped stairs). }
  if not TileKitLoad('content/tiles') then begin
    writeln(StdErr, 'chasm: failed to build tiles');
    halt(1);
  end;

  { Camera, then the first place. EnterTown places the player and camera. }
  CameraInitDiorama(cam, WIN_W / WIN_H);
  cam.Distance := 11.0;
  cam.Pitch := 34 * pi / 180;
  worldSeed := seed;
  twInit := False;
  TurnsSeed(worldSeed);
  writeln('world seed ', seed);
  EnterTown(True);
  ReportStitch;
  GameUIInit(WIN_W, WIN_H);
  GameUISetInvChange(@ApplyInventoryChange);
  PushInventory;
  { Offer character creation at the start; until Begin the default character stands in. }
  SetupCreation;
  GameUIShowCreate;

  lightDir := Vec3Normalize(Vec3(0.4, 1.0, 0.55));

  lastTicks := SDL_GetTicks;
  running := True;
  while running do begin
    while SDL_PollEvent(@ev) do begin
      if ev.Etype = SDL_EVENT_QUIT then running := False
      else if ev.Etype = SDL_EVENT_KEY_DOWN then begin
        sc := ev.Key.Scancode;
        if sc <= High(held) then held[sc] := True;
        case sc of
          SDL_SCANCODE_ESCAPE: running := False;
          SDL_SCANCODE_RETURN:
            if not pl.Alive then EnterTown(False)
            else UseStairs;
          { Space acts: speak in town, swing below. }
          SDL_SCANCODE_SPACE:
            if inTown then TurnsInteract(pl, entSet, gContent)
            else TurnsPlayerSwing(pl, entSet, gContent, tw);
          SDL_SCANCODE_F5: SaveCurrent;
          SDL_SCANCODE_F9: LoadSaved;
          SDL_SCANCODE_Q: cam.Yaw := cam.Yaw - 0.1;
          SDL_SCANCODE_E: cam.Yaw := cam.Yaw + 0.1;
          SDL_SCANCODE_MINUS:  cam.Distance := Min(24.0, cam.Distance * 1.1);
          SDL_SCANCODE_EQUALS: cam.Distance := Max(5.0, cam.Distance * 0.9);
          SDL_SCANCODE_I: begin PushInventory; GameUITogglePanel(0); end;
          SDL_SCANCODE_C: GameUITogglePanel(1);
          SDL_SCANCODE_O: GameUITogglePanel(2);
          SDL_SCANCODE_R: QuaffPotion;
        end;
      end
      else if ev.Etype = SDL_EVENT_KEY_UP then begin
        sc := ev.Key.Scancode;
        if sc <= High(held) then held[sc] := False;
      end
      else if ev.Etype = SDL_EVENT_MOUSE_BUTTON_DOWN then begin
        mx := round(ev.Button.X); my := round(ev.Button.Y);
        GameUIMouse(0, mx, my, ev.Button.Button - 1, 0);
      end
      else if ev.Etype = SDL_EVENT_MOUSE_BUTTON_UP then begin
        mx := round(ev.Button.X); my := round(ev.Button.Y);
        GameUIMouse(1, mx, my, ev.Button.Button - 1, 0);
      end
      else if ev.Etype = SDL_EVENT_MOUSE_MOTION then begin
        mx := round(ev.Motion.X); my := round(ev.Motion.Y);
        GameUIMouse(2, mx, my, 0, 0);
      end
      else if ev.Etype = SDL_EVENT_MOUSE_WHEEL then begin
        wy := round(ev.Wheel.Y);
        GameUIMouse(3, mx, my, 0, wy);
      end;
    end;

    { Advance the world by the elapsed time, clamped so a long stall (a load, a drag)
      cannot teleport anyone through a wall. }
    frameDt := (SDL_GetTicks - lastTicks) / 1000.0;
    lastTicks := SDL_GetTicks;
    if frameDt > 0.05 then frameDt := 0.05;

    UpdatePlayer(frameDt);
    { Repopulate entities when the player crosses into a new region. }
    if (FloorDivTile(pl.Cx) <> lastRx) or (FloorDivTile(pl.Cy) <> lastRy) then
      RebuildEntities;
    TurnsUpdate(pl, entSet, gContent, tw, frameDt);
    TurnsAutoPickup(pl, entSet, gContent, tw);
    CheckVictory;

    desired := FloatWorld(pl.Px, pl.Py);
    cam.Target.X := cam.Target.X + (desired.X - cam.Target.X) * FOLLOW;
    cam.Target.Z := cam.Target.Z + (desired.Z - cam.Target.Z) * FOLLOW;
    cam.Target.Y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;

    glViewport(0, 0, WIN_W, WIN_H);
    glClearColor(0.05, 0.05, 0.07, 1.0);
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

    MeshShaderBegin(shader, CameraView(cam), CameraProj(cam), lightDir);
    { Underground, the view fades into the dark it is lit against, so the carved space
      reads as closed in rather than an island floating in a void. }
    if not inTown then
      MeshShaderFog(shader, 0.05, 0.05, 0.07, 6.0, 16.0);
    DrawTiles;
    { The player ball is tinted so it reads against the pale placeholder tiles. }
    MeshShaderTint(shader, 0.30, 0.45, 0.85);
    MeshShaderModel(shader, PlayerModelMatrix);
    GpuMeshDraw(playerGpu);
    MeshShaderTint(shader, 1.0, 1.0, 1.0);

    { Every free-standing thing is a placeholder ball: loot a small one, monsters and
      townsfolk one sized by bulk. Loot is tinted per entity (the objective glows in its
      own colour); the slain are skipped. }
    for ei := 0 to entSet.Count - 1 do begin
      if (entSet.List[ei].Kind = enMonster) and (not entSet.List[ei].Alive) then
        continue;
      desired := FloatWorld(entSet.List[ei].Px, entSet.List[ei].Py);
      if entSet.List[ei].Kind = enProp then begin
        if entSet.List[ei].OrigIdx = OBJECTIVE_IDX then
          MeshShaderTint(shader, entSet.List[ei].R, entSet.List[ei].G,
                         entSet.List[ei].B)
        else
          MeshShaderTint(shader, 0.85, 0.80, 0.35);
        MeshShaderModel(shader, Mat4Multiply(
          Mat4Translate(desired.X, FLOOR_TOP_Y, desired.Z), propBase));
        GpuMeshDraw(propGpu);
      end else begin
        MeshShaderTint(shader, entSet.List[ei].R, entSet.List[ei].G,
                       entSet.List[ei].B);
        MeshShaderModel(shader, Mat4Multiply(
          Mat4Translate(desired.X, FLOOR_TOP_Y, desired.Z),
          creatureBase[entSet.List[ei].Size]));
        GpuMeshDraw(creatureGpu[entSet.List[ei].Size]);
      end;
    end;
    MeshShaderTint(shader, 1.0, 1.0, 1.0);

    { Interface overlay: live status window over the diorama. }
    UpdateStatus;
    GameUIRender;

    if shotPath <> '' then begin
      writeln(TileWorldRegionCount(tw), ' regions, drew ', drawnTiles, ' tiles');
      SaveShot(shotPath);
      running := False;
    end;

    SDL_GL_SwapWindow(win);
  end;

  GameUIFree;
  TileKitFree;
  TileWorldFree(tw);
  GpuMeshFree(playerGpu);
  GpuMeshFree(propGpu);
  for sz := Low(TSizeClass) to High(TSizeClass) do GpuMeshFree(creatureGpu[sz]);
  MeshShaderFree(shader);
  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(win);
  SDL_Quit;
end.
