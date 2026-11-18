unit entities;
{ Deterministic placement of monsters and item props in the dungeon. Like the tiles  }
{ themselves, an entity is a pure function of the depth and region, so walking away    }
{ and back regenerates the same inhabitants. Each monster carries the runtime state    }
{ the turn loop reads and writes: hit points, an energy counter for scheduling, and    }
{ alive and awake flags. Kills are recorded in a slain registry keyed by the monster's  }
{ stable identity, so a regenerated region leaves the dead dead.                        }

{$mode objfpc}{$H+}

interface

uses
  tileworld, content;

type
  TEntityKind = (enMonster, enProp, enTownsfolk);

  TEntity = record
    Kind:   TEntityKind;
    Cx, Cy: LongInt;          { global tile, derived from Px,Py }
    Px, Py: Single;           { continuous world position (tile units, TILE = 1) }
    AtkCd:  Single;           { seconds until this monster's next strike is ready }
    DefIdx: LongInt;          { index into content Monsters or Items }
    R, G, B: Single;          { draw tint }
    Size:   TSizeClass;       { monster bulk (enMonster only) }
    Role:   LongInt;          { townsperson role (enTownsfolk only) }
    { Stable identity, for the slain and taken registries. }
    OrigRx, OrigRy, OrigIdx: LongInt;
    { Runtime combat state (enMonster only). }
    Hp, MaxHp: LongInt;
    Energy:    LongInt;       { turn-scheduling accumulator }
    Bonus:     LongInt;       { depth bump to the monster's to-hit and damage }
    Alive:     Boolean;
    Awake:     Boolean;       { has sighted the player and begun to chase }
    Locked:    Boolean;       { a chest prop the player must unlock with a key }
    Notified:  Boolean;       { runtime: the locked-chest message has been shown }
  end;

  TEntitySet = record
    List:     array of TEntity;
    Count:    LongInt;
    Monsters: LongInt;        { live monsters }
    Props:    LongInt;
  end;

{ Rebuild the entity set for the square of regions within radius of (centerRx,
  centerRy). The tile (avoidCx, avoidCy) is left empty, so the player never shares a
  tile with a freshly placed monster. Monsters already recorded as slain are skipped. }
procedure EntitiesBuild(var es: TEntitySet; const c: TContent; var tw: TTileWorld;
  centerRx, centerRy, radius, avoidCx, avoidCy: LongInt);

const
  { The objective's stable identity: the bottom's origin region, with a reserved index
    that no room uses, so the taken registry remembers it once carried off. The guardian
    shares the region but takes its own reserved index in the slain registry. }
  OBJECTIVE_RX  = 0;
  OBJECTIVE_RY  = 0;
  OBJECTIVE_IDX = 1000000;
  GUARDIAN_IDX  = 1000001;

{ The roaming area a zone theme maps to, for picking the local monsters. }
function ThemeArea(theme: LongInt): TArea;

{ Index of the live monster on tile (cx, cy), or -1. }
function EntityMonsterAt(const es: TEntitySet; cx, cy: LongInt): LongInt;

{ Index of the live prop on tile (cx, cy), or -1. }
function EntityPropAt(const es: TEntitySet; cx, cy: LongInt): LongInt;

{ Index of the townsperson on tile (cx, cy), or -1. }
function EntityTownsfolkAt(const es: TEntitySet; cx, cy: LongInt): LongInt;

{ True when a live monster stands on tile (cx, cy). }
function EntityBlocked(const es: TEntitySet; cx, cy: LongInt): Boolean;

{ True when a live monster or townsperson stands on tile (cx, cy), so the player
  cannot step there. }
function EntitySolidAt(const es: TEntitySet; cx, cy: LongInt): Boolean;

{ Reset the set to empty, and append one entity, for callers that build their own
  roster (the townsfolk builder). }
procedure EntitiesClear(var es: TEntitySet);
procedure EntityAppend(var es: TEntitySet; const e: TEntity);

{ The slain registry: a kill is remembered by the monster's stable identity so a
  region that regenerates omits it. The registry lives for the session. }
procedure EntitiesSlay(depth, rx, ry, idx: LongInt);
function EntitiesIsSlain(depth, rx, ry, idx: LongInt): Boolean;
procedure EntitiesClearSlain;
function EntitiesSlainCount: LongInt;

{ The taken registry: a picked-up prop is remembered the same way, so its room
  regenerates empty of loot. }
procedure EntitiesTakeProp(depth, rx, ry, idx: LongInt);
function EntitiesIsTaken(depth, rx, ry, idx: LongInt): Boolean;
procedure EntitiesClearTaken;
function EntitiesTakenCount: LongInt;

{ The tile the objective sits on: the far room of the origin region. Valid only when tw
  is the bottom depth, the one that hosts it. False when the layout has no such room. }
function EntitiesObjectiveTile(var tw: TTileWorld; out gx, gy: LongInt): Boolean;

{ Enumerate the registries, so a save can record them. Index i runs 0..count-1;
  False when i is out of range. }
function EntitiesSlainKey(i: LongInt; out depth, rx, ry, idx: LongInt): Boolean;
function EntitiesTakenKey(i: LongInt; out depth, rx, ry, idx: LongInt): Boolean;

implementation

{ ---- slain registry ---- }

type
  TKey = record
    Depth, Rx, Ry, Idx: LongInt;
  end;
  TKeySet = record
    Keys: array of TKey;
    N: LongInt;
  end;

var
  gSlain: TKeySet;
  gTaken: TKeySet;

function KeySetHas(const s: TKeySet; depth, rx, ry, idx: LongInt): Boolean;
var
  i: LongInt;
begin
  for i := 0 to s.N - 1 do
    if (s.Keys[i].Depth = depth) and (s.Keys[i].Rx = rx) and
       (s.Keys[i].Ry = ry) and (s.Keys[i].Idx = idx) then
      exit(True);
  KeySetHas := False;
end;

procedure KeySetAdd(var s: TKeySet; depth, rx, ry, idx: LongInt);
begin
  if KeySetHas(s, depth, rx, ry, idx) then exit;
  if s.N >= Length(s.Keys) then SetLength(s.Keys, (s.N + 1) * 2);
  s.Keys[s.N].Depth := depth; s.Keys[s.N].Rx := rx;
  s.Keys[s.N].Ry := ry; s.Keys[s.N].Idx := idx;
  Inc(s.N);
end;

procedure KeySetClear(var s: TKeySet);
begin
  s.N := 0;
  SetLength(s.Keys, 0);
end;

procedure EntitiesSlay(depth, rx, ry, idx: LongInt);
begin
  KeySetAdd(gSlain, depth, rx, ry, idx);
end;

function EntitiesIsSlain(depth, rx, ry, idx: LongInt): Boolean;
begin
  EntitiesIsSlain := KeySetHas(gSlain, depth, rx, ry, idx);
end;

procedure EntitiesClearSlain;
begin
  KeySetClear(gSlain);
end;

function EntitiesSlainCount: LongInt;
begin
  EntitiesSlainCount := gSlain.N;
end;

procedure EntitiesTakeProp(depth, rx, ry, idx: LongInt);
begin
  KeySetAdd(gTaken, depth, rx, ry, idx);
end;

function EntitiesIsTaken(depth, rx, ry, idx: LongInt): Boolean;
begin
  EntitiesIsTaken := KeySetHas(gTaken, depth, rx, ry, idx);
end;

procedure EntitiesClearTaken;
begin
  KeySetClear(gTaken);
end;

function EntitiesTakenCount: LongInt;
begin
  EntitiesTakenCount := gTaken.N;
end;

function KeyAt(const s: TKeySet; i: LongInt; out depth, rx, ry, idx: LongInt): Boolean;
begin
  if (i < 0) or (i >= s.N) then exit(False);
  depth := s.Keys[i].Depth; rx := s.Keys[i].Rx;
  ry := s.Keys[i].Ry; idx := s.Keys[i].Idx;
  KeyAt := True;
end;

function EntitiesSlainKey(i: LongInt; out depth, rx, ry, idx: LongInt): Boolean;
begin
  EntitiesSlainKey := KeyAt(gSlain, i, depth, rx, ry, idx);
end;

function EntitiesTakenKey(i: LongInt; out depth, rx, ry, idx: LongInt): Boolean;
begin
  EntitiesTakenKey := KeyAt(gTaken, i, depth, rx, ry, idx);
end;

{ ---- placement ---- }

function ThemeArea(theme: LongInt): TArea;
begin
  case theme of
    0: ThemeArea := arCrypt;      { Catacombs }
    1: ThemeArea := arCave;       { Warrens }
    2: ThemeArea := arCoast;      { Cistern }
    3: ThemeArea := arCrypt;      { Cathedral }
    4: ThemeArea := arInfernal;   { Embers }
  else ThemeArea := arCave;
  end;
end;

function HashRC(a, b, c, d: LongInt): LongWord;
{ A small FNV-1a mix over the inputs; wraps mod 2^32 by LongWord arithmetic. }
begin
  { The FNV prime multiply wraps mod 2^32 by design, so overflow and range
    checking are off. }
  {$push}{$Q-}{$R-}
  HashRC := 2166136261;
  HashRC := (HashRC xor LongWord(a)) * 16777619;
  HashRC := (HashRC xor LongWord(b)) * 16777619;
  HashRC := (HashRC xor LongWord(c)) * 16777619;
  HashRC := (HashRC xor LongWord(d)) * 16777619;
  {$pop}
end;

function StrHash(const s: String): LongWord;
var
  i: LongInt;
begin
  { FNV-1a: the prime multiply wraps mod 2^32 by design, so overflow and range
    checking are off here. }
  {$push}{$Q-}{$R-}
  StrHash := 2166136261;
  for i := 1 to Length(s) do
    StrHash := (StrHash xor LongWord(Ord(s[i]))) * 16777619;
  {$pop}
end;

function RollHp(hd: LongInt; h: LongWord): LongInt;
{ Hit points from hit dice, as a stable function of the monster's identity hash, so
  a regenerated monster has the same health. Each die contributes 1..8. }
var
  k, hp: LongInt;
begin
  if hd < 1 then hd := 1;
  if hd > 8 then hd := 8;
  hp := 0;
  for k := 1 to hd do
    hp := hp + 1 + LongInt((h shr (k * 3)) and 7);
  RollHp := hp;
end;

function DepthAtkBonus(depth: LongInt): LongInt;
{ A bump to a monster's to-hit and damage that grows with depth, so the deeper levels
  are genuinely deadlier, not just slower to clear. }
begin
  if depth < 0 then depth := 0;
  DepthAtkBonus := depth div 2;
end;

function ScaleHp(hp, depth: LongInt): LongInt;
{ Deeper monsters are hardier: roughly a fifth more health per depth. }
begin
  if depth < 0 then depth := 0;
  ScaleHp := hp + (hp * depth) div 5;
end;

procedure MonsterColor(const id: String; out r, g, b: Single);
{ A stable colour per monster type, kept bright enough to read against the floor. }
var
  h: LongWord;
begin
  h := StrHash(id);
  r := 0.40 + ((h shr 0)  and 255) / 255.0 * 0.60;
  g := 0.40 + ((h shr 8)  and 255) / 255.0 * 0.60;
  b := 0.40 + ((h shr 16) and 255) / 255.0 * 0.60;
end;

function IsPropKind(const kind: String): Boolean;
begin
  IsPropKind := (kind = 'treasure') or (kind = 'potion') or
                (kind = 'light') or (kind = 'misc') or (kind = 'key') or
                (kind = 'scroll');
end;

procedure PropColor(const kind: String; out r, g, b: Single);
begin
  if kind = 'treasure' then begin r := 0.85; g := 0.70; b := 0.20; end
  else if kind = 'potion' then begin r := 0.30; g := 0.75; b := 0.40; end
  else if kind = 'light' then begin r := 0.95; g := 0.65; b := 0.25; end
  else if kind = 'key' then begin r := 0.80; g := 0.80; b := 0.90; end
  else if kind = 'scroll' then begin r := 0.90; g := 0.85; b := 0.60; end
  else begin r := 0.75; g := 0.70; b := 0.55; end;   { misc }
end;

procedure Append(var es: TEntitySet; const e: TEntity);
begin
  if es.Count >= Length(es.List) then
    SetLength(es.List, (es.Count + 1) * 2);
  es.List[es.Count] := e;
  { Start the continuous position at the tile centre; monsters move from there. }
  es.List[es.Count].Px := e.Cx + 0.5;
  es.List[es.Count].Py := e.Cy + 0.5;
  es.List[es.Count].AtkCd := 0;
  es.List[es.Count].Notified := False;
  Inc(es.Count);
end;

function PickMonster(const c: TContent; area: TArea; depth: LongInt;
  h: LongWord): LongInt;
{ Choose a monster for a room. The area's weighted encounter table decides it, and
  deeper down a second draw can supplant the first with a tougher foe, so the danger
  tilts upward as the descent goes on. With no table, the monster's own area set (then
  the whole roster) stands in. }
var
  cand: array of LongInt;
  nc, i, pick, alt, table: LongInt;
begin
  PickMonster := -1;
  if Length(c.Monsters) = 0 then exit;
  table := EncTableFor(c, area);
  pick := EncPick(c, table, h shr 8);
  if pick < 0 then begin
    SetLength(cand, Length(c.Monsters));
    nc := 0;
    for i := 0 to High(c.Monsters) do
      if area in c.Monsters[i].Areas then begin cand[nc] := i; Inc(nc); end;
    if nc = 0 then
      for i := 0 to High(c.Monsters) do begin cand[nc] := i; Inc(nc); end;
    pick := cand[(h shr 8) mod LongWord(nc)];
  end;
  if (depth > 0) and (table >= 0) then begin
    alt := EncPick(c, table, h shr 17);
    if (alt >= 0) and (c.Monsters[alt].HD > c.Monsters[pick].HD) and
       ((h shr 26) mod 100 < LongWord(depth) * 15) then pick := alt;
  end;
  PickMonster := pick;
end;

procedure AddMonster(var es: TEntitySet; const c: TContent; area: TArea;
  gx, gy, rx, ry, idx, depth: LongInt; h: LongWord);
var
  pick: LongInt;
  e: TEntity;
begin
  FillChar(e, SizeOf(e), 0);
  pick := PickMonster(c, area, depth, h);
  if pick < 0 then exit;
  e.Kind := enMonster;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := pick;
  e.Size := c.Monsters[pick].Size;
  MonsterColor(c.Monsters[pick].Id, e.R, e.G, e.B);
  e.OrigRx := rx; e.OrigRy := ry; e.OrigIdx := idx;
  e.MaxHp := ScaleHp(RollHp(c.Monsters[pick].HD, h), depth);
  e.Hp := e.MaxHp;
  e.Energy := LongInt(h and 3);     { phase 0..3; the turn engine's cost is 4 }
  e.Bonus := DepthAtkBonus(depth);
  e.Alive := True;
  e.Awake := False;
  e.Role := 0;
  Append(es, e);
  Inc(es.Monsters);
end;

function PropWeight(const c: TContent; idx, depth: LongInt): LongInt;
{ A prop's draw weight. A flat base keeps every kind of loot possible at any depth; the
  value term, scaled by depth, tilts deeper rooms toward richer finds, so treasure and
  elixirs crowd out torches and rations the further down the descent goes. }
var
  v: LongInt;
begin
  v := c.Items[idx].Value;
  if v < 0 then v := 0;
  if depth < 0 then depth := 0;
  PropWeight := 4 + (v * depth) div 8;
end;

procedure AddProp(var es: TEntitySet; const c: TContent;
  gx, gy, rx, ry, idx, depth: LongInt; h: LongWord);
var
  cand: array of LongInt;
  nc, i, pick, total, r: LongInt;
  e: TEntity;
begin
  FillChar(e, SizeOf(e), 0);
  if Length(c.Items) = 0 then exit;
  SetLength(cand, Length(c.Items));
  nc := 0;
  for i := 0 to High(c.Items) do
    if IsPropKind(c.Items[i].Kind) then begin cand[nc] := i; Inc(nc); end;
  if nc = 0 then exit;
  { Weighted draw: sum the depth-scaled weights, then walk them with the hash. }
  total := 0;
  for i := 0 to nc - 1 do Inc(total, PropWeight(c, cand[i], depth));
  r := LongInt((h shr 8) mod LongWord(total));
  pick := cand[nc - 1];
  for i := 0 to nc - 1 do begin
    Dec(r, PropWeight(c, cand[i], depth));
    if r < 0 then begin pick := cand[i]; break; end;
  end;
  e.Kind := enProp;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := pick;
  e.Size := szSmall;
  PropColor(c.Items[pick].Kind, e.R, e.G, e.B);
  e.OrigRx := rx; e.OrigRy := ry; e.OrigIdx := idx;
  e.MaxHp := 0; e.Hp := 0; e.Energy := 0; e.Bonus := 0;
  e.Alive := True;
  e.Awake := False;
  e.Locked := False;
  e.Role := 0;
  Append(es, e);
  Inc(es.Props);
end;

function ChestReward(const c: TContent; h: LongWord): LongInt;
{ A locked chest holds a better-than-average find: a handful of loot draws with the
  richest kept, so the key it costs always buys something worth the trouble. A key is
  never the prize. }
var
  cand: array of LongInt;
  nc, i, k, pick, best, bestv: LongInt;
begin
  ChestReward := -1;
  SetLength(cand, Length(c.Items));
  nc := 0;
  for i := 0 to High(c.Items) do
    if IsPropKind(c.Items[i].Kind) and (c.Items[i].Kind <> 'key') then begin
      cand[nc] := i; Inc(nc);
    end;
  if nc = 0 then exit;
  best := cand[0]; bestv := -1;
  for k := 0 to 3 do begin
    pick := cand[(h shr (k * 4 + 4)) mod LongWord(nc)];
    if c.Items[pick].Value > bestv then begin
      bestv := c.Items[pick].Value; best := pick;
    end;
  end;
  ChestReward := best;
end;

procedure AddChest(var es: TEntitySet; const c: TContent;
  gx, gy, rx, ry, idx: LongInt; h: LongWord);
{ A locked chest: a prop that yields its reward only once a key is spent on it. Its
  contents are fixed by the room's hash, so the same chest always holds the same prize. }
var
  reward: LongInt;
  e: TEntity;
begin
  FillChar(e, SizeOf(e), 0);
  reward := ChestReward(c, h);
  if reward < 0 then exit;
  e.Kind := enProp;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := reward;
  e.Size := szSmall;
  e.R := 0.70; e.G := 0.45; e.B := 0.20;        { brass-bound, to read as a chest }
  e.OrigRx := rx; e.OrigRy := ry; e.OrigIdx := idx;
  e.MaxHp := 0; e.Hp := 0; e.Energy := 0; e.Bonus := 0;
  e.Alive := True;
  e.Awake := False;
  e.Locked := True;
  e.Role := 0;
  Append(es, e);
  Inc(es.Props);
end;

function EntitiesObjectiveTile(var tw: TTileWorld; out gx, gy: LongInt): Boolean;
var
  n: LongInt;
  ref: TRoomRef;
begin
  EntitiesObjectiveTile := False;
  n := TileWorldRegionRoomCount(tw, OBJECTIVE_RX, OBJECTIVE_RY);
  if n = 0 then exit;
  ref.Rx := OBJECTIVE_RX; ref.Ry := OBJECTIVE_RY; ref.Idx := n - 1;
  EntitiesObjectiveTile := TileWorldRoomCenter(tw, ref, gx, gy);
end;

procedure AddObjective(var es: TEntitySet; const c: TContent; var tw: TTileWorld;
  depth, avoidCx, avoidCy: LongInt);
{ Place the single objective on the bottom's origin region, in its far room, unless it
  has already been carried off. It is picked up and recorded like any prop, so a return
  to the region finds it gone. }
var
  relic, n, gx, gy: LongInt;
  ref: TRoomRef;
  e: TEntity;
begin
  FillChar(e, SizeOf(e), 0);
  relic := ItemByIdx(c, 'RELIC');
  if relic < 0 then exit;
  if EntitiesIsTaken(depth, OBJECTIVE_RX, OBJECTIVE_RY, OBJECTIVE_IDX) then exit;
  n := TileWorldRegionRoomCount(tw, OBJECTIVE_RX, OBJECTIVE_RY);
  if n = 0 then exit;
  ref.Rx := OBJECTIVE_RX; ref.Ry := OBJECTIVE_RY; ref.Idx := n - 1;
  if not TileWorldRoomCenter(tw, ref, gx, gy) then exit;
  if (gx = avoidCx) and (gy = avoidCy) then exit;
  e.Kind := enProp;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := relic;
  e.Size := szSmall;
  e.R := 1.0; e.G := 0.85; e.B := 0.25;        { a bright gold, to read as the goal }
  e.OrigRx := OBJECTIVE_RX; e.OrigRy := OBJECTIVE_RY; e.OrigIdx := OBJECTIVE_IDX;
  e.MaxHp := 0; e.Hp := 0; e.Energy := 0; e.Bonus := 0;
  e.Alive := True;
  e.Awake := False;
  e.Locked := False;
  e.Role := 0;
  Append(es, e);
  Inc(es.Props);
end;

procedure AddGuardian(var es: TEntitySet; const c: TContent; var tw: TTileWorld;
  depth, avoidCx, avoidCy: LongInt);
{ A boss stands beside the objective on the bottom, far tougher than the rank and file,
  and must be beaten to carry the relic out. It is recorded slain like any monster, by a
  reserved identity, so it stays dead once felled. }
const
  DX: array[0..3] of LongInt = (0, 0, -1, 1);
  DY: array[0..3] of LongInt = (-1, 1, 0, 0);
var
  boss, n, gx, gy, bx, by, k: LongInt;
  ref: TRoomRef;
  e: TEntity;
  h: LongWord;
begin
  FillChar(e, SizeOf(e), 0);
  boss := MonsterByIdx(c, 'DEMON');
  if boss < 0 then exit;
  if EntitiesIsSlain(depth, OBJECTIVE_RX, OBJECTIVE_RY, GUARDIAN_IDX) then exit;
  n := TileWorldRegionRoomCount(tw, OBJECTIVE_RX, OBJECTIVE_RY);
  if n = 0 then exit;
  ref.Rx := OBJECTIVE_RX; ref.Ry := OBJECTIVE_RY; ref.Idx := n - 1;
  if not TileWorldRoomCenter(tw, ref, gx, gy) then exit;
  { Stand the boss on a walkable tile beside the relic, clear of the player. }
  bx := gx; by := gy;
  for k := 0 to 3 do
    if TileWorldWalkable(tw, gx + DX[k], gy + DY[k]) and
       not ((gx + DX[k] = avoidCx) and (gy + DY[k] = avoidCy)) then begin
      bx := gx + DX[k]; by := gy + DY[k];
      break;
    end;
  if (bx = avoidCx) and (by = avoidCy) then exit;
  h := HashRC(depth, OBJECTIVE_RX, OBJECTIVE_RY, GUARDIAN_IDX);
  e.Kind := enMonster;
  e.Cx := bx; e.Cy := by;
  e.DefIdx := boss;
  e.Size := c.Monsters[boss].Size;
  e.R := 0.90; e.G := 0.15; e.B := 0.15;       { a menacing red }
  e.OrigRx := OBJECTIVE_RX; e.OrigRy := OBJECTIVE_RY; e.OrigIdx := GUARDIAN_IDX;
  e.MaxHp := 70 + depth * 10;                   { a boss's bulk }
  e.Hp := e.MaxHp;
  e.Energy := 0;
  e.Bonus := DepthAtkBonus(depth) + 2;
  e.Alive := True;
  e.Awake := False;
  e.Role := 0;
  Append(es, e);
  Inc(es.Monsters);
end;

procedure EntitiesBuild(var es: TEntitySet; const c: TContent; var tw: TTileWorld;
  centerRx, centerRy, radius, avoidCx, avoidCy: LongInt);
var
  rx, ry, n, idx, depth, gx, gy, roll: LongInt;
  area: TArea;
  ref: TRoomRef;
  h: LongWord;
begin
  es.Count := 0; es.Monsters := 0; es.Props := 0;
  depth := TileWorldDepth(tw);
  for ry := centerRy - radius to centerRy + radius do
    for rx := centerRx - radius to centerRx + radius do begin
      area := ThemeArea(TileWorldThemeAt(tw,
        rx * REGION + REGION div 2, ry * REGION + REGION div 2));
      n := TileWorldRegionRoomCount(tw, rx, ry);
      for idx := 0 to n - 1 do begin
        h := HashRC(depth, rx, ry, idx);
        { roll 0..5: 0,1 a monster, 2 a prop, 3..5 an empty room }
        roll := LongInt(h mod 6);
        { Deeper levels crowd in: rooms that would be empty up top fill with monsters,
          more of them the deeper the level. Depth 0 is left exactly as it was. }
        if (roll > 2) and (depth > 0) and
           ((h shr 20) mod 100 < LongWord(depth) * 8) then roll := 0;
        if roll > 2 then continue;
        { A slain monster or a taken prop leaves its room empty on regeneration. }
        if (roll <= 1) and EntitiesIsSlain(depth, rx, ry, idx) then continue;
        if (roll = 2) and EntitiesIsTaken(depth, rx, ry, idx) then continue;
        ref.Rx := rx; ref.Ry := ry; ref.Idx := idx;
        if not TileWorldRoomCenter(tw, ref, gx, gy) then continue;
        if (gx = avoidCx) and (gy = avoidCy) then continue;
        if roll <= 1 then AddMonster(es, c, area, gx, gy, rx, ry, idx, depth, h)
        { Underground, roughly a third of loot rooms hold a locked chest instead:
          richer than a loose find, but closed until a key is spent on it. }
        else if (depth >= 1) and ((h shr 23) mod 100 < 30) then
          AddChest(es, c, gx, gy, rx, ry, idx, h)
        else AddProp(es, c, gx, gy, rx, ry, idx, depth, h);
      end;
    end;
  { The bottom's origin region carries the objective and its guardian, once in range. }
  if (depth = DUNGEON_BOTTOM) and
     (centerRx - radius <= OBJECTIVE_RX) and (OBJECTIVE_RX <= centerRx + radius) and
     (centerRy - radius <= OBJECTIVE_RY) and (OBJECTIVE_RY <= centerRy + radius) then begin
    AddObjective(es, c, tw, depth, avoidCx, avoidCy);
    AddGuardian(es, c, tw, depth, avoidCx, avoidCy);
  end;
end;

function EntityMonsterAt(const es: TEntitySet; cx, cy: LongInt): LongInt;
var
  i: LongInt;
begin
  for i := 0 to es.Count - 1 do
    if (es.List[i].Kind = enMonster) and es.List[i].Alive and
       (es.List[i].Cx = cx) and (es.List[i].Cy = cy) then
      exit(i);
  EntityMonsterAt := -1;
end;

function EntityPropAt(const es: TEntitySet; cx, cy: LongInt): LongInt;
var
  i: LongInt;
begin
  for i := 0 to es.Count - 1 do
    if (es.List[i].Kind = enProp) and es.List[i].Alive and
       (es.List[i].Cx = cx) and (es.List[i].Cy = cy) then
      exit(i);
  EntityPropAt := -1;
end;

function EntityTownsfolkAt(const es: TEntitySet; cx, cy: LongInt): LongInt;
var
  i: LongInt;
begin
  for i := 0 to es.Count - 1 do
    if (es.List[i].Kind = enTownsfolk) and
       (es.List[i].Cx = cx) and (es.List[i].Cy = cy) then
      exit(i);
  EntityTownsfolkAt := -1;
end;

function EntityBlocked(const es: TEntitySet; cx, cy: LongInt): Boolean;
begin
  EntityBlocked := EntityMonsterAt(es, cx, cy) >= 0;
end;

function EntitySolidAt(const es: TEntitySet; cx, cy: LongInt): Boolean;
begin
  EntitySolidAt := (EntityMonsterAt(es, cx, cy) >= 0) or
                   (EntityTownsfolkAt(es, cx, cy) >= 0);
end;

procedure EntitiesClear(var es: TEntitySet);
begin
  es.Count := 0; es.Monsters := 0; es.Props := 0;
end;

procedure EntityAppend(var es: TEntitySet; const e: TEntity);
begin
  Append(es, e);
end;

end.
