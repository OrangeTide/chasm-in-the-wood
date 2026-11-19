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
  wear it, and drag it off to stow it; R quaffs a healing potion, F reads a scroll. C
  shows the character sheet. F5 saves the game and F9 loads it. Q/E orbit, -/= zoom,
  Escape quits.

  Args: [model.vox] [screenshot.ppm] [seed]. A screenshot path renders one frame
  and exits. The player model defaults to content/models/character.vox. }

{$mode objfpc}{$H+}

uses
  ctypes, sysutils, classes, math,
  sdl3, glcore, vecmath, camera,
  voxfile, voxmesh, gpumesh, meshshader, frustum, tilekit, prims,
  tilemap, tileworld, themes, worldgraph, world, player, gameui,
  content, entities, turns, trade, town, townsfolk, saveload, audio,
  rng, dice, uitext, flags, quests, dialogtext, sfx;

const
  WIN_W = 960;
  WIN_H = 720;
  FOLLOW = 0.15;
  ENTITY_RADIUS = 1;        { regions around the player that hold live entities }
  SAVE_PATH = 'chasm.sav';  { the single save slot, beside the executable }
  VIEW_TILES = 22;          { tile radius drawn around the player before culling }
  { The object voxel-unit: world units per voxel for every free-standing model, so a
    model's size is its voxel count. One voxel is 0.0625 m and one cell (a world unit, TILE)
    is 1.5 m, so VU = 0.0625 / 1.5 world units per voxel (see docs/asset-pipeline.md). Tiles
    scale on their own (the mesh is fitted to the cell by TILE / footprint, see DrawTile),
    so this is the model scale alone. }
  VU = 0.0625 / 1.5;
  PLAYER_DIAM = 26;         { the player placeholder ball, in voxels }
  PROP_DIAM = 8;            { a loot placeholder ball, in voxels }
  PLAYER_HEIGHT = PLAYER_DIAM * VU;   { the player's world height, for the camera }
  PLAYER_MODEL_FACING = Pi;  { the authored player model's front faces -Z; aligns it to the heading }
  { Placeholder ball diameter per monster bulk, indexed by TSizeClass. }
  CREATURE_DIAM: array[TSizeClass] of LongInt = (8, 13, 18, 23, 28, 33);

type
  { The front-end state: a menu screen (title, victory, death), the creation window,
    or live play. The world simulates and reads input only during asPlay. }
  TAppState = (asTitle, asCreate, asPlay, asVictory, asDead);

  { An authored voxel model for a monster or an item, keyed by its content index. When
    the file is absent, Loaded is False and the placeholder ball stands in. }
  TEntModel = record
    Gpu:    TGpuMesh;
    Base:   TMat4;
    Loaded: Boolean;
  end;

const
  { Action tags the front-end menu hands back when a button is clicked. }
  ACT_NEW      = 1;
  ACT_CONTINUE = 2;
  ACT_QUIT     = 3;
  ACT_RESPAWN  = 4;

  { Seconds one torch burns before the next from the pack takes over. }
  TORCH_BURN   = 75.0;

  { Sound effects the main program fires; silent when the file is absent. }
  SFX_STAIRS   = 'content/sfx/stairs.ogg';
  SFX_MENU     = 'content/sfx/menu.ogg';

var
  win: PSDL_Window;
  glctx: TSDL_GLContext;
  ev: TSDL_Event;
  shader: TMeshShader;
  playerGpu: TGpuMesh;
  playerBase: TMat4;
  playerVox: Boolean;   { true when an authored player model stands in for the ball }
  creatureGpu: array[TSizeClass] of TGpuMesh;
  creatureBase: array[TSizeClass] of TMat4;
  propGpu: TGpuMesh;
  propBase: TMat4;
  gContent: TContent;
  entSet: TEntitySet;
  lastRx, lastRy: LongInt;
  inTown: Boolean;
  won: Boolean;            { the sealed gate below has been opened; the run is over }
  gFlags: TFlagSet;        { quest and story flags, raised by events and dialogue }
  gDialogs: TDialogSet;    { the conversation tables (dialogs.txt) }
  gConvo: TConvo;          { the conversation in play, if any }
  gTalkSpeaker: String;    { the name shown in the open conversation's title bar }
  gShop: String;           { the shop id the open trade window draws from }
  doorMsgX, doorMsgY: LongInt;   { the locked door last reported, to not repeat the line }
  appState: TAppState;     { which front-end screen, or live play }
  defSpecies, defKlass, defBg: LongInt;   { the new-game default character }
  startName: String;       { the name a fresh default character carries }
  createRng: TRng;         { rolls starting coin from a background's dice expression }
  cam: TCamera;
  tw: TTileWorld;
  pl: TPlayer;
  lightDir, desired: TVec3;
  voxPath, shotPath: String;
  seed, worldSeed: QWord;
  depth: LongInt;
  deepReached: LongInt;    { the deepest dungeon depth reached, driving shop stock }
  twInit: Boolean;
  sc: cuint32;
  running: Boolean;
  drawnTiles: LongInt;
  mx, my, wy: LongInt;
  sz: TSizeClass;
  ei, ei2, i, nMon, nItem: LongInt;
  monModel:  array of TEntModel;   { authored monster models, per content index }
  itemModel: array of TEntModel;   { authored loot models, per content index }
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
  { Turn the model to face its heading. The model's local +Z swings to the movement
    direction; PLAYER_MODEL_FACING corrects where the authored model's front points. }
  PlayerModelMatrix := Mat4Multiply(Mat4Translate(c.X, FLOOR_TOP_Y, c.Z),
    Mat4Multiply(Mat4RotateY(Pi / 2 - pl.Facing + PLAYER_MODEL_FACING), playerBase));
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

procedure PlaceQuestPoints;
{ Stand this depth's quest interaction point, or the demon boss, in its objective room,
  according to the story flags. Each point retires itself once the flag its dialogue
  raises is set: the crypt altar and the grotto give their shards, the bottom holds the
  demon lord (a talk until the fight is joined, then the boss) and, once the demon is
  felled, the sealed gate that ends the descent. }
begin
  if inTown then exit;
  case depth of
    1: if not FlagTest(gFlags, 'SHARD_CRYPT') then
         EntitiesAddShrine(entSet, tw, 'SHRINE', 0.60, 0.75, 1.00, pl.Cx, pl.Cy);
    3: if not FlagTest(gFlags, 'SHARD_CAVE') then
         EntitiesAddShrine(entSet, tw, 'GROTTO', 0.40, 0.90, 0.85, pl.Cx, pl.Cy);
    DUNGEON_BOTTOM:
      if not FlagTest(gFlags, 'SHARD_INFER') then begin
        if FlagTest(gFlags, 'DEMON_WOKE') then
          EntitiesAddGuardian(entSet, gContent, tw, depth, pl.Cx, pl.Cy)
        else
          EntitiesAddShrine(entSet, tw, 'DEMONLORD', 0.90, 0.20, 0.20, pl.Cx, pl.Cy);
      end else if not FlagTest(gFlags, 'QUEST_WON') then
        EntitiesAddShrine(entSet, tw, 'DEPTHS', 0.72, 0.52, 0.95, pl.Cx, pl.Cy);
  end;
end;

procedure RebuildEntities;
{ Repopulate the entity set: the hamlet's townsfolk in town, or the dungeon monsters
  and loot for the player's current region neighbourhood below, then any quest point. }
begin
  lastRx := FloorDivTile(pl.Cx);
  lastRy := FloorDivTile(pl.Cy);
  if inTown then
    TownsfolkBuild(entSet, TileWorldTownLayout(tw))
  else begin
    EntitiesBuild(entSet, gContent, tw, lastRx, lastRy, ENTITY_RADIUS, pl.Cx, pl.Cy);
    PlaceQuestPoints;
  end;
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
  if d > deepReached then deepReached := d;
  SnapCamera;
  RebuildEntities;
  writeln('depth ', d, ', spawn (', px, ',', py, '), ',
          ThemeTable[TileWorldThemeAt(tw, px, py)].Name, ' zone, ',
          TileWorldRegionCount(tw), ' regions, ', entSet.Monsters, ' foes');
end;

procedure ShowTitle;
{ The front door: new game, continue when a save exists, and quit. }
var
  labels: array of String;
  acts: array of LongInt;
begin
  appState := asTitle;
  if FileExists(SAVE_PATH) then begin
    SetLength(labels, 3); SetLength(acts, 3);
    labels[0] := UIStr('btn_newgame');  acts[0] := ACT_NEW;
    labels[1] := UIStr('btn_continue'); acts[1] := ACT_CONTINUE;
    labels[2] := UIStr('btn_quit');     acts[2] := ACT_QUIT;
  end else begin
    SetLength(labels, 2); SetLength(acts, 2);
    labels[0] := UIStr('btn_newgame'); acts[0] := ACT_NEW;
    labels[1] := UIStr('btn_quit');    acts[1] := ACT_QUIT;
  end;
  GameUIShowMenu(UIStr('menu_title_head'), UIStrList('menu_title_body'), labels, acts);
end;

procedure ShowVictory;
{ The objective reached town: the run is won. }
begin
  appState := asVictory;
  GameUIShowMenu(UIStr('menu_victory_head'), UIStrList('menu_victory_body'),
    [UIStr('btn_newgame'), UIStr('btn_quit')], [ACT_NEW, ACT_QUIT]);
end;

procedure ShowDeath;
{ The player fell: offer the respawn the town already performs, or quit. }
begin
  appState := asDead;
  GameUIShowMenu(UIStr('menu_death_head'), UIStrList('menu_death_body'),
    [UIStr('btn_respawn'), UIStr('btn_quit')], [ACT_RESPAWN, ACT_QUIT]);
end;

procedure CheckVictory;
{ The descent is won when the sealed gate below is opened, which raises QUEST_WON through
  the gate's dialogue. The first time, the victory screen takes over. }
begin
  if won or not FlagTest(gFlags, 'QUEST_WON') then exit;
  won := True;
  TurnsLogAdd(UIStr('msg_victory'));
  ShowVictory;
end;

function RollBgGold(bgIdx: LongInt): LongInt;
{ Roll the starting coin a background brings, from its dice expression. A missing
  background or a malformed expression yields no coin. }
var
  ok: Boolean;
  g: LongInt;
begin
  RollBgGold := 0;
  if (bgIdx < 0) or (bgIdx > High(gContent.Backgrounds)) then exit;
  g := DiceEval(gContent.Backgrounds[bgIdx].Gold, createRng, ok);
  if ok and (g > 0) then RollBgGold := g;
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
    PlayerCreate(pl, gContent, defSpecies, defKlass, defBg,
      RollBgGold(defBg), startName, px, py);
    won := False;                 { a new game is not yet won }
    deepReached := 0;             { a fresh descent has reached nowhere yet }
    FlagClearAll(gFlags);         { a fresh story carries no flags; the elder's talk
                                    raises QUEST_MAIN once the player accepts the charge }
    TileWorldClearOpened;         { and every door is shut again }
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
  st.DeepReached := deepReached;
  st.Pl := pl;
  st.Flags := gFlags;
  if SaveGame(SAVE_PATH, st) then TurnsLogAdd(UIStr('msg_saved'))
  else TurnsLogAdd(UIStr('msg_save_failed'));
end;

procedure LoadSaved;
{ Restore a saved game: the registries and player come from the file, then the world
  is rebuilt from the seed at the saved location. }
var
  st: TSaveState;
begin
  if not LoadGame(SAVE_PATH, st) then begin
    TurnsLogAdd(UIStr('msg_no_save'));
    exit;
  end;
  worldSeed := st.Seed;
  TurnsSeed(worldSeed);
  pl := st.Pl;
  gFlags := st.Flags;
  QuestSettle(gContent, gFlags);   { re-derive any composite flags after the load }
  won := False;
  deepReached := st.DeepReached;
  RestoreAt(st.InTown, st.Depth);
  CheckVictory;
  TurnsLogAdd(UIStr('msg_loaded'));
end;

procedure OnMenuAction(action: LongInt);
{ A front-end menu button was clicked. The actions move between the title, creation,
  live play, and the endings. }
begin
  PlaySfx(SFX_MENU);
  case action of
    ACT_NEW: begin
        GameUIHideMenu;
        EnterTown(True);            { a fresh town and default character }
        appState := asCreate;
        GameUIShowCreate;
      end;
    ACT_CONTINUE: begin
        GameUIHideMenu;
        LoadSaved;
        { Loading in town with the relic already wins; leave that menu up. }
        if not GameUIMenuShown then appState := asPlay;
      end;
    ACT_RESPAWN: begin
        GameUIHideMenu;
        EnterTown(False);           { revive, keeping purse and pack }
        if not GameUIMenuShown then appState := asPlay;
      end;
    ACT_QUIT:
      running := False;
  end;
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

procedure OpenShopWindow(const shopId: String);
{ Fill the trade window from a shop's stock and the player's pack. A stock row carries
  the item's content index and its buy price; a pack row carries the pack slot (what a
  trade gives) and the sell price. The shop id is remembered so a settled trade refreshes
  the same shop. }
var
  si, i, n: LongInt;
  stock, pack: array of TUIItem;
begin
  si := ShopByIdx(gContent, shopId);
  if si < 0 then exit;
  gShop := shopId;
  { Offer only the stock whose depth gate the player has reached, so the trader's wares
    grow with the descent. }
  n := 0;
  SetLength(stock, Length(gContent.Shops[si].Stock));
  for i := 0 to High(gContent.Shops[si].Stock) do begin
    if gContent.Shops[si].StockMin[i] > deepReached then continue;
    stock[n] := BuildUIItem(gContent.Shops[si].Stock[i]);
    stock[n].Price := ItemBuyPrice(gContent, gContent.Shops[si].Stock[i]);
    Inc(n);
  end;
  SetLength(stock, n);
  SetLength(pack, pl.NCarry);
  for i := 0 to pl.NCarry - 1 do begin
    pack[i] := BuildUIItem(pl.Carry[i]);
    pack[i].Tag := i;
    pack[i].Price := ItemSellPrice(gContent, pl.Carry[i]);
  end;
  GameUIOpenTrade(UIStr('trade_title'), stock, pack, pl.Gold);
end;

procedure OpenTraderWindow;
{ The town trader's general store, opened by stepping up and pressing Space. }
begin
  OpenShopWindow('GENERAL');
end;

procedure DoTrade(const giveSlots: array of LongInt; const takeItems: array of LongInt);
{ Settle a confirmed deal. On success refresh the pack, the purse, and the window;
  on failure say so and leave the staged offer in place. }
var
  o: TTradeOffer;
  i: LongInt;
begin
  SetLength(o.Give, Length(giveSlots));
  for i := 0 to High(giveSlots) do o.Give[i] := giveSlots[i];
  SetLength(o.Take, Length(takeItems));
  for i := 0 to High(takeItems) do o.Take[i] := takeItems[i];
  if (Length(o.Give) = 0) and (Length(o.Take) = 0) then exit;
  if TradeSettle(gContent, pl, o) then begin
    TurnsLogAdd(UIStr('msg_trade_ok'));
    PushInventory;
    OpenShopWindow(gShop);
  end else
    TurnsLogAdd(UIStr('msg_trade_fail'));
end;

function RoleDialog(role: LongInt): String;
{ The conversation a town role opens, or '' when the role has only a flavor greeting. }
begin
  case role of
    ROLE_INNKEEPER: RoleDialog := 'BARKEEP';
    ROLE_REEVE:     RoleDialog := 'ELDER';
    ROLE_VILLAGER:  RoleDialog := 'APOTHECARY';
  else              RoleDialog := '';
  end;
end;

procedure ShowConvoNode;
{ Push the current conversation node into the talk window, or close it when the talk has
  ended. }
var
  tmpL: array[0..15] of String;
  tmpP: array[0..15] of LongInt;
  labels: array of String;
  picks:  array of LongInt;
  n, i: LongInt;
begin
  if gConvo.Dlg < 0 then begin
    GameUICloseTalk;
    exit;
  end;
  n := ConvoResps(gDialogs, gConvo, gFlags, tmpL, tmpP);
  SetLength(labels, n);
  SetLength(picks, n);
  for i := 0 to n - 1 do begin
    labels[i] := tmpL[i];
    picks[i]  := tmpP[i];
  end;
  GameUIOpenTalk(gTalkSpeaker, ConvoText(gDialogs, gConvo), labels, picks);
end;

procedure StartConvo(const dlgId, speaker: String);
{ Begin a conversation, if the id is known, and show its first node. }
begin
  if ConvoStart(gDialogs, dlgId, gConvo) then begin
    gTalkSpeaker := speaker;
    ShowConvoNode;
  end;
end;

function DialogSpeaker(const dlg, fallback: String): String;
{ The name shown over a conversation. A known speaker overrides the caller's fallback. }
begin
  if dlg = 'BARKEEP' then DialogSpeaker := UIStr('role_innkeeper')
  else if dlg = 'ELDER' then DialogSpeaker := UIStr('role_reeve')
  else if dlg = 'APOTHECARY' then DialogSpeaker := UIStr('role_apothecary')
  else if dlg = 'SHRINE' then DialogSpeaker := UIStr('talk_altar')
  else if dlg = 'GROTTO' then DialogSpeaker := UIStr('talk_grotto')
  else if dlg = 'DEMONLORD' then DialogSpeaker := UIStr('talk_demon')
  else if dlg = 'DEPTHS' then DialogSpeaker := UIStr('talk_gate')
  else DialogSpeaker := fallback;
end;

procedure ApothecaryRevive;
{ The temple's blessing restores the wounded to full. }
begin
  if pl.Hp >= pl.MaxHp then
    TurnsLogAdd(UIStr('msg_revive_hale'))
  else begin
    PlayerRevive(pl);
    TurnsLogAdd(UIStr('msg_revive_done'));
  end;
end;

procedure ApothecaryIdentify;
{ There is no unidentified-item system yet, so every find is already plain. }
begin
  TurnsLogAdd(UIStr('msg_identify_none'));
end;

procedure OnTalkPick(pick: LongInt);
{ The player clicked a response: settle it, carry out its action, then move on in the
  talk or close it. Recruit is stubbed with a log line until followers land. }
var
  oc: TDlgOutcome;
begin
  ConvoChoose(gDialogs, gContent, gFlags, gConvo, pick, oc);
  case oc.Kind of
    daShop: begin
        GameUICloseTalk;
        OpenShopWindow(oc.Arg);
      end;
    daRecruit:  begin TurnsLogAdd(UIStr('msg_recruit_soon')); ShowConvoNode; end;
    daRevive:   begin ApothecaryRevive;   ShowConvoNode; end;
    daIdentify: begin ApothecaryIdentify; ShowConvoNode; end;
    daFight: begin
        { Joining the fight wakes the boss: the interaction point gives way to the demon
          lord, whose death raises the shard flag (see QuestTick). }
        GameUICloseTalk;
        QuestRaise(gContent, gFlags, 'DEMON_WOKE');
        TurnsLogAdd(UIStr('msg_demon_rises'));
        RebuildEntities;
      end;
  else
    { daGoto left the talk on a new node; daSetflag and daEnd closed it. }
    if gConvo.Dlg < 0 then GameUICloseTalk else ShowConvoNode;
  end;
end;

procedure TalkToAdjacent;
{ Space by a townsperson. The trader opens the store directly; a role with a conversation
  opens it; the rest fall back to their one-line greeting. }
var
  role: LongInt;
  dlg: String;
begin
  role := TurnsAdjacentRole(pl, entSet);
  if role < 0 then exit;
  if role = ROLE_TRADER then begin
    OpenTraderWindow;
    exit;
  end;
  dlg := RoleDialog(role);
  if dlg <> '' then StartConvo(dlg, DialogSpeaker(dlg, TownRoleName(role)))
  else TurnsInteract(pl, entSet, gContent);
end;

function DungeonTalk: Boolean;
{ Space below ground: if an interaction point stands next to the player, open its talk.
  Returns False when there is nothing to speak to, so the caller swings instead. }
const
  DX: array[0..3] of LongInt = (1, -1, 0, 0);
  DY: array[0..3] of LongInt = (0, 0, 1, -1);
var
  k, ii: LongInt;
begin
  DungeonTalk := False;
  for k := 0 to 3 do begin
    ii := EntityInteractAt(entSet, pl.Cx + DX[k], pl.Cy + DY[k]);
    if ii >= 0 then begin
      StartConvo(entSet.List[ii].Dialog,
                 DialogSpeaker(entSet.List[ii].Dialog, UIStr('win_talk')));
      exit(True);
    end;
  end;
end;

procedure QuestTick;
{ Once per frame below ground: when the woken demon lord has been felled, award the
  infernal shard, which may complete the relic, and rebuild so the gate takes its place. }
begin
  if inTown then exit;
  if (depth = DUNGEON_BOTTOM) and FlagTest(gFlags, 'DEMON_WOKE') and
     not FlagTest(gFlags, 'SHARD_INFER') and EntitiesGuardianSlain(depth) then begin
    QuestRaise(gContent, gFlags, 'SHARD_INFER');
    TurnsLogAdd(UIStr('msg_demon_felled'));
    RebuildEntities;
  end;
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
  lines[0] := UIStrFmt('sheet_level', [pl.Level, pl.Xp, XpToNext(pl.Level)]);
  lines[1] := UIStrFmt('sheet_hp_ac', [pl.Hp, pl.MaxHp, pl.Ac]);
  lines[2] := UIStrFmt('sheet_atk_dmg', [SignedStr(pl.Atk), pl.DmgDie,
                                         SignedStr(pl.DmgBonus)]);
  lines[3] := UIStrFmt('sheet_abil1', [pl.Str, pl.Dex, pl.Con]);
  lines[4] := UIStrFmt('sheet_abil2', [pl.Int, pl.Wis, pl.Cha]);
  GameUISetCharStats(lines);
  if pl.Species >= 0 then spName := gContent.Species[pl.Species].Name
  else spName := UIStr('name_wanderer');
  if pl.Klass >= 0 then clName := gContent.Classes[pl.Klass].Name
  else clName := UIStr('name_vagrant');
  GameUISetCharIdentity(pl.Name, clName, spName);
end;

function DepthPointLabel(out lbl: String): Boolean;
{ Whether this depth still holds a live quest interaction point, and its compass label. }
begin
  DepthPointLabel := True;
  case depth of
    1: if not FlagTest(gFlags, 'SHARD_CRYPT') then begin
         lbl := UIStr('quest_altar'); exit;
       end;
    3: if not FlagTest(gFlags, 'SHARD_CAVE') then begin
         lbl := UIStr('quest_grotto'); exit;
       end;
    DUNGEON_BOTTOM: begin
      if not FlagTest(gFlags, 'SHARD_INFER') then begin
        lbl := UIStr('quest_demon'); exit;
      end;
      { The gate guides the player only once the elder has opened the road; before that
        the compass sends them back out to see the elder. }
      if FlagTest(gFlags, 'QUEST_DEPTHS') and not FlagTest(gFlags, 'QUEST_WON') then begin
        lbl := UIStr('quest_gate'); exit;
      end;
    end;
  end;
  DepthPointLabel := False;
end;

function QuestObjective(out tcx, tcy: LongInt; out lbl: String): Boolean;
{ The current goal and where it lies, as a tile, driven by the story flags. In town the
  compass points at the chasm until the relic is whole, then at the elder. Below it points
  at this depth's live interaction point, or at the stairs toward the next step. }
var
  rx, ry, sx, sy: LongInt;
  lay: TTownLayout;
begin
  QuestObjective := False;
  rx := FloorDivTile(pl.Cx);
  ry := FloorDivTile(pl.Cy);
  if inTown then begin
    lay := TileWorldTownLayout(tw);
    { Relic whole but the road not yet opened: return to the elder to be sent down. }
    if FlagTest(gFlags, 'QUEST_RELIC') and not FlagTest(gFlags, 'QUEST_DEPTHS') then begin
      tcx := lay.Reeve.X; tcy := lay.Reeve.Y;
      lbl := UIStr('quest_elder'); exit(True);
    end;
    tcx := lay.Chasm.X; tcy := lay.Chasm.Y;
    lbl := UIStr('quest_chasm'); exit(True);
  end;
  { Below: point at this depth's live interaction point when it has one. }
  if DepthPointLabel(lbl) and EntitiesObjectiveTile(tw, tcx, tcy) then exit(True);
  { Otherwise keep moving: down toward the deeper points, or up to climb back to town. }
  if not FlagTest(gFlags, 'QUEST_RELIC') or FlagTest(gFlags, 'QUEST_DEPTHS') then begin
    lbl := UIStr('quest_descend');
    if TileWorldRegionDownStair(tw, rx, ry, sx, sy) then begin
      tcx := sx; tcy := sy; exit(True);
    end;
  end;
  lbl := UIStr('quest_climb');
  if TileWorldRegionUpStair(tw, rx, ry, sx, sy) then begin
    tcx := sx; tcy := sy; exit(True);
  end;
end;

procedure UpdateCompass;
{ Point the HUD compass at the objective, in screen space: project the world direction
  to the goal onto the camera's ground forward and right, so the arrow tracks the view. }
var
  tcx, tcy: LongInt;
  lbl: String;
  eye: TVec3;
  fx, fz, rx, rz, wx, wz, len, fc, rc: Single;
begin
  if not QuestObjective(tcx, tcy, lbl) then begin
    GameUISetCompass(0, '', False);
    exit;
  end;
  eye := CameraEye(cam);
  fx := cam.Target.X - eye.X;
  fz := cam.Target.Z - eye.Z;
  len := Sqrt(fx * fx + fz * fz);
  if len < 1e-4 then begin GameUISetCompass(0, '', False); exit; end;
  fx := fx / len; fz := fz / len;
  rx := -fz; rz := fx;
  wx := (tcx + 0.5) - pl.Px;
  wz := (tcy + 0.5) - pl.Py;
  fc := wx * fx + wz * fz;        { how far ahead the goal is }
  rc := wx * rx + wz * rz;        { how far to the right }
  GameUISetCompass(ArcTan2(rc, fc), lbl, True);
end;

procedure UpdateMusic;
{ Loop the track for the current place. AudioPlay no-ops when it is already playing, so
  this is cheap to call every frame, and silent if the track file is absent. }
begin
  if inTown then AudioPlay('content/music/town.ogg')
  else AudioPlay('content/music/dungeon.ogg');
  AudioUpdate;
end;

procedure UpdateLog;
{ Tail the message log into its own transparent HUD panel. }
const
  LOG_SHOW = 6;
var
  i, n, show: LongInt;
  lines: array of String;
begin
  n := TurnsLogCount;
  show := Min(LOG_SHOW, n);
  SetLength(lines, show);
  for i := 0 to show - 1 do
    lines[i] := TurnsLogLine(n - show + i);
  GameUISetLog(lines);
end;

function TorchCount: LongInt;
{ Spare light sources still in the pack. }
var
  i: LongInt;
begin
  TorchCount := 0;
  for i := 0 to pl.NCarry - 1 do
    if gContent.Items[pl.Carry[i]].Kind = 'light' then Inc(TorchCount);
end;

function ThemeName(th: LongInt): String;
{ The zone theme's display name, from the string table. }
begin
  if th = THEME_TOWN then ThemeName := UIStr('theme_town')
  else ThemeName := UIStr('theme_' + IntToStr(th));
end;

procedure UpdateQuestLog;
{ Build the quest-log panel from the flag set: completed quests first, then the active
  quests with their current stage, then the journal lines gathered from the set flags. }
var
  lines: array of String;
  j: TJournal;
  i, st, any: LongInt;

  procedure Add(const s: String);
  begin
    SetLength(lines, Length(lines) + 1);
    lines[High(lines)] := s;
  end;

begin
  SetLength(lines, 0);
  any := 0;
  for i := 0 to High(gContent.Quests) do begin
    if QuestComplete(gContent, gFlags, i) then begin
      Add(gContent.Quests[i].Title + UIStr('quest_done_tag'));
      Inc(any);
    end
    else if QuestActive(gContent, gFlags, i) then begin
      Add(gContent.Quests[i].Title);
      st := QuestStageReached(gContent, gFlags, i);
      if st >= 0 then Add('  ' + gContent.Quests[i].Stages[st].Text);
      Inc(any);
    end;
  end;
  if any = 0 then Add(UIStr('quest_none'));
  QuestJournal(gContent, gFlags, j);
  if Length(j.Lines) > 0 then begin
    Add('');
    Add(UIStr('quest_journal'));
    for i := 0 to High(j.Lines) do Add('  ' + j.Lines[i]);
  end;
  GameUISetQuests(lines);
end;

procedure UpdateStatus;
{ Push the live game state into the status panel: health first, then the world lines.
  The message log rides in its own panel; the character sheet's live stats ride along. }
var
  th: LongInt;
  lines: array of String;
begin
  th := TileWorldThemeAt(tw, pl.Cx, pl.Cy);
  SetLength(lines, 8);
  lines[0] := UIStrFmt('hud_hp', [pl.Hp, pl.MaxHp]);
  if not pl.Alive then lines[0] := lines[0] + UIStr('hud_suffix_dead')
  else if won then lines[0] := lines[0] + UIStr('hud_suffix_won')
  else if FlagTest(gFlags, 'QUEST_RELIC') and not FlagTest(gFlags, 'QUEST_DEPTHS') then
    lines[0] := lines[0] + UIStr('hud_suffix_relic');
  if inTown then
    lines[1] := UIStrFmt('hud_town', [ThemeName(th)])
  else
    lines[1] := UIStrFmt('hud_depth', [depth, ThemeName(th)]);
  lines[2] := UIStrFmt('hud_gold_pack', [pl.Gold, pl.NCarry]);
  if PlayerCountKind(pl, gContent, 'key') > 0 then
    lines[2] := lines[2] + UIStrFmt('hud_keys', [PlayerCountKind(pl, gContent, 'key')]);
  lines[3] := UIStrFmt('hud_tile', [pl.Cx, pl.Cy]);
  if inTown then
    lines[4] := UIStr('hud_speak')
  else
    lines[4] := UIStrFmt('hud_foes_loot', [entSet.Monsters, entSet.Props]);
  lines[5] := UIStrFmt('hud_res', [TileWorldRegionCount(tw), drawnTiles]);
  lines[6] := UIStrFmt('hud_seed', [Int64(worldSeed)]);
  if inTown then
    lines[7] := UIStrFmt('hud_torches', [TorchCount])
  else if pl.LightLeft > 0 then
    lines[7] := UIStrFmt('hud_torch', [LongInt(Ceil(pl.LightLeft)), TorchCount])
  else
    lines[7] := UIStr('hud_dark');
  GameUISetStatus(lines);
  UpdateLog;
  UpdateCompass;
  UpdateQuestLog;
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
  { A two-handed weapon and a shield cannot be worn together; bump the shield to the
    pack and re-sync the doll when the drag left both in place. }
  if PlayerEnforceHands(pl, gContent) then PushInventory;
  PlayerRecalc(pl, gContent);
  UpdateStatus;
end;

procedure DoCreateChar(speciesIdx, classIdx, bgIdx: LongInt; const name: String);
{ The player pressed Begin in the creation window: forge the chosen character, roll the
  starting coin their background brings, and set them on the town spawn to start. }
var
  px, py: LongInt;
begin
  TileWorldSpawn(tw, px, py);
  PlayerCreate(pl, gContent, speciesIdx, classIdx, bgIdx,
    RollBgGold(bgIdx), name, px, py);
  won := False;
  appState := asPlay;              { creation done; the world is live }
  SnapCamera;
  RebuildEntities;
  PushInventory;
  UpdateStatus;
end;

procedure SetupCreation;
{ Build the creation window from the content tables: every species, and one class per
  quick-start archetype, with the random name pool. }
var
  spNames, clNames, bgNames: array of String;
  clIdx: array of LongInt;
  i, j, ci, nc: LongInt;
  dup: Boolean;
begin
  SetLength(spNames, Length(gContent.Species));
  for i := 0 to High(gContent.Species) do spNames[i] := gContent.Species[i].Name;
  SetLength(bgNames, Length(gContent.Backgrounds));
  for i := 0 to High(gContent.Backgrounds) do bgNames[i] := gContent.Backgrounds[i].Name;
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
  GameUIInitCreate(spNames, clNames, clIdx, bgNames, gContent.Names,
    defSpecies, defKlass, defBg);
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

procedure LoadEntModel(const id: String; out m: TEntModel);
{ Load content/models/<id>.vox (the content id, lower-cased) as an entity's model, baked
  at the object voxel-unit with its feet on the floor. When the file is absent the model
  stays unloaded and the placeholder ball stands in. }
var
  vm: TVoxModel;
  mesh: TVoxMesh;
  path: String;
begin
  m.Loaded := False;
  path := 'content/models/' + LowerCase(id) + '.vox';
  if FileExists(path) and VoxLoad(path, vm) then begin
    BuildMesh(vm, mesh);
    GpuMeshUpload(m.Gpu, mesh);
    m.Base := ModelBaseVU(vm.Sx, vm.Sy, vm.Sz);
    m.Loaded := True;
  end;
end;

procedure DrawTile(tx, ty: LongInt; env: TTileEnv; kind: TTileKind);
{ Draw one authored tile mesh, scaled so its footprint fills one world cell, at the
  tile origin. The scale is per tile because the sets differ in native resolution. }
var
  m: TTileMesh;
  s: Single;
begin
  m := TileKitPick(env, kind, tx, ty);
  if not m.Loaded then exit;
  if m.Sx < 1 then exit;
  s := TILE / m.Sx;
  MeshShaderModel(shader,
    Mat4Multiply(Mat4Translate(tx * TILE, 0, ty * TILE), Mat4Scale(s)));
  GpuMeshDraw(m.Gpu);
end;

function TileSolid(tx, ty: LongInt): Boolean;
{ A cell that reads as stone: unexcavated rock or a built wall. Wall brushes stand on the
  boundary between an open cell and a solid one, so out-of-bounds (which reads as rock)
  walls the carved region at its edge. }
var
  t: Byte;
begin
  t := TileAt(tw, tx, ty);
  TileSolid := (t = TILE_ROCK) or (t = TILE_WALL);
end;

procedure DrawBrush(const m: TTileMesh; const xform: TMat4);
{ Draw a baked brush mesh (in voxel space) under an arbitrary transform. }
begin
  if (not m.Loaded) or (m.Sx < 1) then exit;
  MeshShaderModel(shader, xform);
  GpuMeshDraw(m.Gpu);
end;

procedure DrawWallPanel(tx, ty, ndx, ndy: LongInt; env: TTileEnv);
{ Place the thin wall panel on the edge of cell (tx,ty) toward the solid neighbour
  (ndx,ndy), rotated so its face points into the open cell and its depth sits in the
  neighbour. The canonical orientation (dir 0) is the north (-z) edge; RotateY(+90) walks
  the edge north -> west -> south -> east, so the neighbour maps N,W,S,E to dir 0,1,2,3. }
var
  m: TTileMesh;
  s, depth, cx, cz: Single;
  dir: LongInt;
  local: TMat4;
begin
  m := TileKitMesh(env, tkWall);
  if (not m.Loaded) or (m.Sx < 1) then exit;
  s := TILE / m.Sx;
  depth := s * m.Sz;
  if      (ndx = 0) and (ndy = -1) then dir := 0
  else if (ndx = -1) and (ndy = 0) then dir := 1
  else if (ndx = 0) and (ndy = 1)  then dir := 2
  else                                  dir := 3;
  cx := (tx + 0.5) * TILE;
  cz := (ty + 0.5) * TILE;
  { Width scales to TILE, centred on x; the depth sits just outside the -z edge with its
    inner face flush at the cell boundary (-TILE/2). }
  local := Mat4Multiply(Mat4Translate(-TILE / 2, 0, -(TILE / 2 + depth)), Mat4Scale(s));
  DrawBrush(m, Mat4Multiply(Mat4Multiply(Mat4Translate(cx, 0, cz),
    Mat4RotateY(dir * (Pi / 2))), local));
end;

function PostAtCorner(gx, gy: LongInt): Boolean;
{ A beam post belongs at a grid corner where wall panels turn, not along a straight run.
  The corner touches four cells; a post goes in unless all four are the same or they split
  as a straight half (one full side solid, the other open). }
var
  a, b, c, d: Boolean;
begin
  a := TileSolid(gx - 1, gy - 1);   { NW }
  b := TileSolid(gx,     gy - 1);   { NE }
  c := TileSolid(gx - 1, gy);       { SW }
  d := TileSolid(gx,     gy);       { SE }
  if (a = b) and (b = c) and (c = d) then begin PostAtCorner := False; exit; end;
  if (a and b and (not c) and (not d)) or (c and d and (not a) and (not b)) or
     (a and c and (not b) and (not d)) or (b and d and (not a) and (not c)) then begin
    PostAtCorner := False; exit;
  end;
  PostAtCorner := True;
end;

procedure DrawPost(gx, gy: LongInt; env: TTileEnv);
{ Stand a beam post centred on the grid corner (gx,gy), base on the floor. A post is a
  free-standing brush, so it scales by the object voxel-unit, not fitted to a cell. }
var
  m: TTileMesh;
begin
  m := TileKitMesh(env, tkPost);
  if (not m.Loaded) or (m.Sx < 1) then exit;
  DrawBrush(m, Mat4Multiply(
    Mat4Translate(gx * TILE - m.Sx * VU / 2, 0, gy * TILE - m.Sz * VU / 2),
    Mat4Scale(VU)));
end;

procedure DrawStairDown(tx, ty: LongInt; env: TTileEnv);
{ The down-stair is the kit flight placed descending into the ground: rotated 180 about X
  so it falls below the floor, its top step flush at the floor plane. The floor tile is
  left off this cell by the caller, so the flight reads as a stairwell hole rather than
  steps rising. The kit has one stair, so the up and down stairs are the same mesh. }
var
  m: TTileMesh;
  s: Single;
begin
  m := TileKitMesh(env, tkStairDn);
  if (not m.Loaded) or (m.Sx < 1) then exit;
  s := TILE / m.Sx;
  DrawBrush(m, Mat4Multiply(Mat4Multiply(
    Mat4Translate(tx * TILE, 0, ty * TILE + s * m.Sz), Mat4RotateX(Pi)), Mat4Scale(s)));
end;

function DoorWallAlongZ(tx, ty: LongInt): Boolean;
{ A door sits in a wall: the two solid neighbours are the wall it breaks, the two open ones
  the passage through it. True when that wall runs north-south (along z), so the leaf spans
  z; false when it runs east-west (along x). }
begin
  DoorWallAlongZ := TileSolid(tx, ty - 1) and TileSolid(tx, ty + 1);
end;

procedure DrawGate(tx, ty: LongInt; env: TTileEnv);
{ The locked door: the barred gate shut across the passage, centred in the cell and turned
  to lie along the wall, base on the floor. }
var
  m: TTileMesh;
  s, depth, cx, cz, rot: Single;
begin
  m := TileKitMesh(env, tkDoorLeaf);
  if (not m.Loaded) or (m.Sx < 1) then exit;
  s := TILE / m.Sx;
  depth := s * m.Sz;
  cx := (tx + 0.5) * TILE;
  cz := (ty + 0.5) * TILE;
  if DoorWallAlongZ(tx, ty) then rot := Pi / 2 else rot := 0;
  DrawBrush(m, Mat4Multiply(Mat4Multiply(Mat4Translate(cx, 0, cz), Mat4RotateY(rot)),
    Mat4Multiply(Mat4Translate(-TILE / 2, 0, -depth / 2), Mat4Scale(s))));
end;

procedure DrawDoorOpen(tx, ty: LongInt; env: TTileEnv);
{ The open door: the iron leaf swung back on its hinge at one jamb, so it stands ajar
  against the wall rather than barring the way. }
var
  m: TTileMesh;
  s, cx, cz, rot, leafD: Single;
  leaf: TMat4;
begin
  m := TileKitMesh(env, tkDoor);
  if (not m.Loaded) or (m.Sx < 1) then exit;
  s := TILE / m.Sx;
  leafD := s * m.Sz;
  cx := (tx + 0.5) * TILE;
  cz := (ty + 0.5) * TILE;
  if DoorWallAlongZ(tx, ty) then rot := Pi / 2 else rot := 0;
  { Hinge at the left jamb (x = -TILE/2), swung most of the way open into the passage. }
  leaf := Mat4Multiply(Mat4Multiply(Mat4Translate(-TILE / 2, 0, 0),
    Mat4RotateY(-Pi * 0.45)), Mat4Multiply(Mat4Translate(0, 0, -leafD / 2), Mat4Scale(s)));
  DrawBrush(m, Mat4Multiply(Mat4Multiply(Mat4Translate(cx, 0, cz), Mat4RotateY(rot)), leaf));
end;

procedure DrawTiles;
{ Draw the visible map as brushes. Each open cell gets its floor (and door or stairs) and a
  wall panel on every edge facing a solid neighbour; beam posts stand where panels turn.
  Solid cells draw nothing, since the panels are their visible faces. Reading a tile
  generates its region, so the window streams. }
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
      if TileSolid(tx, ty) then continue;
      mn := Vec3(tx * TILE, 0, ty * TILE);
      mx := Vec3((tx + 1) * TILE, TILE_MAXH * VOX * 2, (ty + 1) * TILE);
      if not FrustumTestAABB(f, mn, mx) then continue;
      t := TileAt(tw, tx, ty);
      env := TileEnvAt(tx, ty);
      case t of
        TILE_DOOR:
          begin DrawTile(tx, ty, env, tkFloor); DrawDoorOpen(tx, ty, env); end;
        TILE_DOOR_LOCKED:
          { A shut door: the barred gate bars the way until a key opens it, when the tile
            becomes an open TILE_DOOR. }
          begin DrawTile(tx, ty, env, tkFloor); DrawGate(tx, ty, env); end;
        TILE_STAIRS_DOWN:
          { No floor tile: the stairwell opens down into the ground. }
          DrawStairDown(tx, ty, env);
        TILE_STAIRS_UP:
          begin DrawTile(tx, ty, env, tkFloor); DrawTile(tx, ty, env, tkStairUp); end;
      else
        DrawTile(tx, ty, env, tkFloor);
      end;
      if TileSolid(tx, ty - 1) then DrawWallPanel(tx, ty, 0, -1, env);
      if TileSolid(tx - 1, ty) then DrawWallPanel(tx, ty, -1, 0, env);
      if TileSolid(tx, ty + 1) then DrawWallPanel(tx, ty, 0, 1, env);
      if TileSolid(tx + 1, ty) then DrawWallPanel(tx, ty, 1, 0, env);
      Inc(drawnTiles);
    end;
  { Corner posts: iterate the grid corners spanning the view, one past each edge so a post
    on the boundary is not clipped before it is tested. }
  for ty := pl.Cy - VIEW_TILES to pl.Cy + VIEW_TILES + 1 do
    for tx := pl.Cx - VIEW_TILES to pl.Cx + VIEW_TILES + 1 do
      if PostAtCorner(tx, ty) then begin
        mn := Vec3(tx * TILE - TILE, 0, ty * TILE - TILE);
        mx := Vec3(tx * TILE + TILE, TILE_MAXH * VOX * 2, ty * TILE + TILE);
        if FrustumTestAABB(f, mn, mx) then DrawPost(tx, ty, TileEnvAt(tx, ty));
      end;
end;

procedure TryOpenDoor(tx, ty: LongInt);
{ Spend a key to open the locked door at (tx, ty). With no key it stays shut, and the
  line is shown once per door so holding against it does not spam the log. }
begin
  if PlayerCountKind(pl, gContent, 'key') = 0 then begin
    if (tx <> doorMsgX) or (ty <> doorMsgY) then begin
      TurnsLogAdd(UIStr('msg_door_locked'));
      doorMsgX := tx; doorMsgY := ty;
    end;
    exit;
  end;
  PlayerConsumeKind(pl, gContent, 'key');
  TileWorldOpenDoor(tw, tx, ty);
  TurnsLogAdd(UIStr('msg_door_open'));
  PushInventory;
  doorMsgX := MaxLongint; doorMsgY := MaxLongint;
end;

procedure UpdatePlayer(dt: Single);
{ Move the player from the held keys, relative to where the camera looks, and slide along
  walls. The world's axes are read from the camera so pressing forward walks into the
  screen rather than along a fixed world axis. }
var
  eye, fwd: TVec3;
  fx, fz, rx, rz, mvx, mvz, len, step, nx, ny: Single;
  tgx, tgy: LongInt;
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

  { Walking into a locked door tries a key on it. Opening it flips the tile to an open
    door, so the step below then carries through; without a key it stays shut. }
  if not inTown then begin
    tgx := Floor(pl.Px + mvx * 0.55);
    tgy := Floor(pl.Py + mvz * 0.55);
    if ((tgx <> pl.Cx) or (tgy <> pl.Cy)) and
       (TileAt(tw, tgx, tgy) = TILE_DOOR_LOCKED) then
      TryOpenDoor(tgx, tgy)
    else begin
      doorMsgX := MaxLongint; doorMsgY := MaxLongint;   { clear of any door: re-arm }
    end;
  end;

  step := PLAYER_MOVE * dt;
  nx := pl.Px + mvx * step;
  if TurnsPosFree(tw, nx, pl.Py) then pl.Px := nx;
  ny := pl.Py + mvz * step;
  if TurnsPosFree(tw, pl.Px, ny) then pl.Py := ny;
  pl.Cx := Floor(pl.Px);
  pl.Cy := Floor(pl.Py);
end;

procedure UpdateLight(dt: Single);
{ Underground a lit torch burns down; when it gutters out another from the pack takes
  over, and with none left the player presses on in the dark. Town is daylit, so nothing
  burns there. }
begin
  if inTown then begin pl.LightLeft := 0; exit; end;
  if pl.LightLeft > 0 then begin
    pl.LightLeft := pl.LightLeft - dt;
    if pl.LightLeft < 0 then pl.LightLeft := 0;
  end;
  if pl.LightLeft <= 0 then
    if PlayerConsumeKind(pl, gContent, 'light') then begin
      pl.LightLeft := TORCH_BURN;
      TurnsLogAdd(UIStr('msg_torch_strike'));
      PushInventory;
    end;
end;

procedure QuaffPotion;
{ Drink a healing draught from the pack, if the player is hurt and carries one. }
var
  healed: LongInt;
begin
  healed := PlayerQuaff(pl, gContent);
  if healed > 0 then begin
    TurnsLogAdd(UIStrFmt('msg_quaff', [healed]));
    PushInventory;
  end else
    TurnsLogAdd(UIStr('msg_quaff_none'));
end;

procedure ReadScroll;
{ Read a scroll from the pack, applying its effect. }
var
  r: TUseResult;
begin
  r := PlayerReadScroll(pl, gContent);
  if not r.Ok then begin
    TurnsLogAdd(UIStr('msg_scroll_none'));
    exit;
  end;
  if r.Effect = 'heal' then
    TurnsLogAdd(UIStrFmt('msg_scroll_heal', [r.Name, r.Amount]))
  else if r.Effect = 'light' then
    TurnsLogAdd(UIStrFmt('msg_scroll_light', [r.Name]))
  else
    TurnsLogAdd(UIStrFmt('msg_scroll_plain', [r.Name]));
  PushInventory;
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
  if (inTown and (t = TILE_STAIRS_DOWN)) or
     ((not inTown) and ((t = TILE_STAIRS_DOWN) or (t = TILE_STAIRS_UP))) then
    PlaySfx(SFX_STAIRS);
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

  AudioInit;
  AudioSetVolume(0.7);
  AudioSetSfxVolume(0.9);
  SfxHook := @AudioSfx;   { route gameplay sound effects to the audio backend }

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LESS);
  glEnable(GL_CULL_FACE);
  glCullFace(GL_BACK);
  glFrontFace(GL_CCW);

  if not MeshShaderInit(shader) then begin
    writeln(StdErr, 'chasm: shader init failed');
    halt(1);
  end;

  { An authored player model from content/models/player.vox if present, else the
    placeholder ball. Both stand at the object voxel-unit with feet on the floor. }
  playerVox := VoxLoad('content/models/player.vox', pmodel);
  if playerVox then
    writeln('player model: content/models/player.vox (',
            pmodel.Sx, 'x', pmodel.Sy, 'x', pmodel.Sz, ')')
  else
    PrimSphere(pmodel, PLAYER_DIAM);
  BuildMesh(pmodel, pmesh);
  GpuMeshUpload(playerGpu, pmesh);
  playerBase := ModelBaseVU(pmodel.Sx, pmodel.Sy, pmodel.Sz);

  { Content tables, and the placeholder voxel models for their inhabitants. }
  if not ContentLoad('content', gContent) then
    writeln(StdErr, 'chasm: warning: some content tables failed to load');
  if not LoadDialogs('content/dialogs.txt', gDialogs) then
    writeln(StdErr, 'chasm: warning: dialogs.txt failed to load');
  gShop := 'GENERAL';
  doorMsgX := MaxLongint; doorMsgY := MaxLongint;
  if not UIStrLoad('content/strings.txt') then
    writeln(StdErr, 'chasm: warning: strings.txt failed to load');
  writeln('content: ', Length(gContent.Monsters), ' monsters, ',
          Length(gContent.Items), ' items, ', Length(gContent.Species),
          ' species, ', Length(gContent.Classes), ' classes');
  won := False;
  { The new-game default character, from newgame.txt (falling back to the first entry). }
  defSpecies := SpeciesByIdx(gContent, gContent.DefSpecies);
  if defSpecies < 0 then defSpecies := 0;
  defKlass := ClassByIdx(gContent, gContent.DefKlass);
  if defKlass < 0 then defKlass := 0;
  defBg := BackgroundByIdx(gContent, gContent.DefBg);
  if (defBg < 0) and (Length(gContent.Backgrounds) > 0) then defBg := 0;
  if Length(gContent.Names) > 0 then
    startName := gContent.Names[LongInt(seed mod QWord(Length(gContent.Names)))]
  else
    startName := UIStr('name_vagrant');
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

  { Authored models per monster and item, keyed by content id, each falling back to the
    placeholder ball when its file is absent. }
  SetLength(monModel, Length(gContent.Monsters));
  nMon := 0;
  for i := 0 to High(gContent.Monsters) do begin
    LoadEntModel(gContent.Monsters[i].Id, monModel[i]);
    if monModel[i].Loaded then Inc(nMon);
  end;
  SetLength(itemModel, Length(gContent.Items));
  nItem := 0;
  for i := 0 to High(gContent.Items) do begin
    LoadEntModel(gContent.Items[i].Id, itemModel[i]);
    if itemModel[i].Loaded then Inc(nItem);
  end;
  writeln('models: ', nMon, ' of ', Length(gContent.Monsters), ' monsters, ',
          nItem, ' of ', Length(gContent.Items), ' items (rest are placeholders)');

  { The tiles, authored where present, else generated placeholders. }
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
  RngSeed(createRng, worldSeed xor QWord($B0C0FFEE));
  writeln('world seed ', seed);
  EnterTown(True);
  ReportStitch;
  GameUIInit(WIN_W, WIN_H);
  GameUISetInvChange(@ApplyInventoryChange);
  GameUISetTradeDone(@DoTrade);
  GameUISetMenuPick(@OnMenuAction);
  GameUISetTalkPick(@OnTalkPick);
  PushInventory;
  { Open on the title screen over the town backdrop; the world holds until New Game. }
  SetupCreation;
  ShowTitle;

  lightDir := Vec3Normalize(Vec3(0.4, 1.0, 0.55));

  lastTicks := SDL_GetTicks;
  running := True;
  while running do begin
    while SDL_PollEvent(@ev) do begin
      if ev.Etype = SDL_EVENT_QUIT then running := False
      else if ev.Etype = SDL_EVENT_KEY_DOWN then begin
        sc := ev.Key.Scancode;
        if sc <= High(held) then held[sc] := True;
        { Escape always quits. The rest drive live play only; while a front-end menu
          or the creation window holds, gameplay keys are inert and the menu is
          mouse-driven. }
        if sc = SDL_SCANCODE_ESCAPE then running := False
        else if appState = asPlay then
          case sc of
            SDL_SCANCODE_RETURN: UseStairs;
            { Space acts: trade or speak in town; speak to an interaction point below, or
              swing when there is none adjacent. }
            SDL_SCANCODE_SPACE:
              if inTown then TalkToAdjacent
              else if not DungeonTalk then TurnsPlayerSwing(pl, entSet, gContent, tw);
            SDL_SCANCODE_F5: SaveCurrent;
            SDL_SCANCODE_F9: LoadSaved;
            SDL_SCANCODE_Q: cam.Yaw := cam.Yaw - 0.1;
            SDL_SCANCODE_E: cam.Yaw := cam.Yaw + 0.1;
            SDL_SCANCODE_MINUS:  cam.Distance := Min(24.0, cam.Distance * 1.1);
            SDL_SCANCODE_EQUALS: cam.Distance := Max(5.0, cam.Distance * 0.9);
            SDL_SCANCODE_I: begin PushInventory; GameUITogglePanel(0); end;
            SDL_SCANCODE_C: GameUITogglePanel(1);
            SDL_SCANCODE_O: GameUITogglePanel(2);
            SDL_SCANCODE_J: GameUITogglePanel(3);
            SDL_SCANCODE_R: QuaffPotion;
            SDL_SCANCODE_F: ReadScroll;
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

    { The world simulates only during live play; a front-end menu or the creation
      window freezes it, leaving the town as a still backdrop. }
    if appState = asPlay then begin
      UpdatePlayer(frameDt);
      { Repopulate entities when the player crosses into a new region. }
      if (FloorDivTile(pl.Cx) <> lastRx) or (FloorDivTile(pl.Cy) <> lastRy) then
        RebuildEntities;
      TurnsUpdate(pl, entSet, gContent, tw, frameDt);
      TurnsAutoPickup(pl, entSet, gContent, tw);
      UpdateLight(frameDt);
      QuestTick;
      CheckVictory;
      { A fall ends the run: the death screen takes over until respawn or quit. }
      if (not pl.Alive) and (appState = asPlay) then ShowDeath;
    end;
    UpdateMusic;

    desired := FloatWorld(pl.Px, pl.Py);
    cam.Target.X := cam.Target.X + (desired.X - cam.Target.X) * FOLLOW;
    cam.Target.Z := cam.Target.Z + (desired.Z - cam.Target.Z) * FOLLOW;
    cam.Target.Y := FLOOR_TOP_Y + PLAYER_HEIGHT / 2;

    glViewport(0, 0, WIN_W, WIN_H);
    glClearColor(0.05, 0.05, 0.07, 1.0);
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

    MeshShaderBegin(shader, CameraView(cam), CameraProj(cam), lightDir);
    { Underground, the view fades into the dark it is lit against, so the carved space
      reads as closed in rather than an island floating in a void. A lit torch pushes
      that dark back; without one, it closes in to arm's reach. }
    if not inTown then begin
      if pl.LightLeft > 0 then
        MeshShaderFog(shader, 0.05, 0.05, 0.07, 7.0, 18.0)
      else
        { Unlit, only the player and the tiles at their feet stay visible; the fog is
          measured from the camera, which orbits well back, so the near edge sits past
          it and the far edge just beyond. }
        MeshShaderFog(shader, 0.05, 0.05, 0.07, 9.0, 13.5);
    end;
    DrawTiles;
    { The placeholder ball is tinted so it reads against the pale tiles; an authored
      model carries its own colours, so it draws untinted. }
    if not playerVox then
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
      ei2 := entSet.List[ei].DefIdx;
      if entSet.List[ei].Kind = enProp then begin
        { Loose loot with an authored model draws it untinted; the objective, a locked
          chest, and an interaction point keep their own-coloured placeholder ball. }
        if (ei2 >= 0) and (ei2 <= High(itemModel)) and itemModel[ei2].Loaded and
           (entSet.List[ei].OrigIdx <> OBJECTIVE_IDX) and (not entSet.List[ei].Locked) then
        begin
          MeshShaderTint(shader, 1.0, 1.0, 1.0);
          MeshShaderModel(shader, Mat4Multiply(
            Mat4Translate(desired.X, FLOOR_TOP_Y, desired.Z), itemModel[ei2].Base));
          GpuMeshDraw(itemModel[ei2].Gpu);
        end else begin
          if (entSet.List[ei].OrigIdx = OBJECTIVE_IDX) or entSet.List[ei].Locked then
            MeshShaderTint(shader, entSet.List[ei].R, entSet.List[ei].G,
                           entSet.List[ei].B)
          else
            MeshShaderTint(shader, 0.85, 0.80, 0.35);
          MeshShaderModel(shader, Mat4Multiply(
            Mat4Translate(desired.X, FLOOR_TOP_Y, desired.Z), propBase));
          GpuMeshDraw(propGpu);
        end;
      end else if (entSet.List[ei].Kind = enMonster) and (ei2 >= 0) and
                  (ei2 <= High(monModel)) and monModel[ei2].Loaded then begin
        { An authored monster model carries its own colours; townsfolk keep the ball. }
        MeshShaderTint(shader, 1.0, 1.0, 1.0);
        MeshShaderModel(shader, Mat4Multiply(
          Mat4Translate(desired.X, FLOOR_TOP_Y, desired.Z), monModel[ei2].Base));
        GpuMeshDraw(monModel[ei2].Gpu);
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

  AudioShutdown;
  GameUIFree;
  TileKitFree;
  TileWorldFree(tw);
  GpuMeshFree(playerGpu);
  GpuMeshFree(propGpu);
  for sz := Low(TSizeClass) to High(TSizeClass) do GpuMeshFree(creatureGpu[sz]);
  for i := 0 to High(monModel) do
    if monModel[i].Loaded then GpuMeshFree(monModel[i].Gpu);
  for i := 0 to High(itemModel) do
    if itemModel[i].Loaded then GpuMeshFree(itemModel[i].Gpu);
  MeshShaderFree(shader);
  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(win);
  SDL_Quit;
end.
