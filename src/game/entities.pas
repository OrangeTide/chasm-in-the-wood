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
  TEntityKind = (enMonster, enProp);

  TEntity = record
    Kind:   TEntityKind;
    Cx, Cy: LongInt;          { global tile }
    DefIdx: LongInt;          { index into content Monsters or Items }
    R, G, B: Single;          { draw tint }
    Size:   TSizeClass;       { monster bulk (enMonster only) }
    { Stable identity, for the slain registry. }
    OrigRx, OrigRy, OrigIdx: LongInt;
    { Runtime combat state (enMonster only). }
    Hp, MaxHp: LongInt;
    Energy:    LongInt;       { turn-scheduling accumulator }
    Alive:     Boolean;
    Awake:     Boolean;       { has sighted the player and begun to chase }
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

{ The roaming area a zone theme maps to, for picking the local monsters. }
function ThemeArea(theme: LongInt): TArea;

{ Index of the live monster on tile (cx, cy), or -1. }
function EntityMonsterAt(const es: TEntitySet; cx, cy: LongInt): LongInt;

{ True when a live monster stands on tile (cx, cy). }
function EntityBlocked(const es: TEntitySet; cx, cy: LongInt): Boolean;

{ The slain registry: a kill is remembered by the monster's stable identity so a
  region that regenerates omits it. The registry lives for the session. }
procedure EntitiesSlay(depth, rx, ry, idx: LongInt);
function EntitiesIsSlain(depth, rx, ry, idx: LongInt): Boolean;
procedure EntitiesClearSlain;
function EntitiesSlainCount: LongInt;

implementation

{ ---- slain registry ---- }

type
  TSlainKey = record
    Depth, Rx, Ry, Idx: LongInt;
  end;

var
  gSlain: array of TSlainKey;
  gSlainN: LongInt = 0;

procedure EntitiesSlay(depth, rx, ry, idx: LongInt);
begin
  if EntitiesIsSlain(depth, rx, ry, idx) then exit;
  if gSlainN >= Length(gSlain) then
    SetLength(gSlain, (gSlainN + 1) * 2);
  gSlain[gSlainN].Depth := depth;
  gSlain[gSlainN].Rx := rx;
  gSlain[gSlainN].Ry := ry;
  gSlain[gSlainN].Idx := idx;
  Inc(gSlainN);
end;

function EntitiesIsSlain(depth, rx, ry, idx: LongInt): Boolean;
var
  i: LongInt;
begin
  for i := 0 to gSlainN - 1 do
    if (gSlain[i].Depth = depth) and (gSlain[i].Rx = rx) and
       (gSlain[i].Ry = ry) and (gSlain[i].Idx = idx) then
      exit(True);
  EntitiesIsSlain := False;
end;

procedure EntitiesClearSlain;
begin
  gSlainN := 0;
  SetLength(gSlain, 0);
end;

function EntitiesSlainCount: LongInt;
begin
  EntitiesSlainCount := gSlainN;
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
  HashRC := 2166136261;
  HashRC := (HashRC xor LongWord(a)) * 16777619;
  HashRC := (HashRC xor LongWord(b)) * 16777619;
  HashRC := (HashRC xor LongWord(c)) * 16777619;
  HashRC := (HashRC xor LongWord(d)) * 16777619;
end;

function StrHash(const s: String): LongWord;
var
  i: LongInt;
begin
  StrHash := 2166136261;
  for i := 1 to Length(s) do
    StrHash := (StrHash xor LongWord(Ord(s[i]))) * 16777619;
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
                (kind = 'light') or (kind = 'misc');
end;

procedure PropColor(const kind: String; out r, g, b: Single);
begin
  if kind = 'treasure' then begin r := 0.85; g := 0.70; b := 0.20; end
  else if kind = 'potion' then begin r := 0.30; g := 0.75; b := 0.40; end
  else if kind = 'light' then begin r := 0.95; g := 0.65; b := 0.25; end
  else begin r := 0.75; g := 0.70; b := 0.55; end;   { misc }
end;

procedure Append(var es: TEntitySet; const e: TEntity);
begin
  if es.Count >= Length(es.List) then
    SetLength(es.List, (es.Count + 1) * 2);
  es.List[es.Count] := e;
  Inc(es.Count);
end;

procedure AddMonster(var es: TEntitySet; const c: TContent; area: TArea;
  gx, gy, rx, ry, idx, depth: LongInt; h: LongWord);
var
  cand: array of LongInt;
  nc, i, pick: LongInt;
  e: TEntity;
begin
  if Length(c.Monsters) = 0 then exit;
  SetLength(cand, Length(c.Monsters));
  nc := 0;
  for i := 0 to High(c.Monsters) do
    if area in c.Monsters[i].Areas then begin cand[nc] := i; Inc(nc); end;
  { No local monster for this area: fall back to the whole roster. }
  if nc = 0 then
    for i := 0 to High(c.Monsters) do begin cand[nc] := i; Inc(nc); end;
  pick := cand[(h shr 8) mod LongWord(nc)];
  e.Kind := enMonster;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := pick;
  e.Size := c.Monsters[pick].Size;
  MonsterColor(c.Monsters[pick].Id, e.R, e.G, e.B);
  e.OrigRx := rx; e.OrigRy := ry; e.OrigIdx := idx;
  e.MaxHp := RollHp(c.Monsters[pick].HD, h);
  e.Hp := e.MaxHp;
  e.Energy := LongInt(h and 3);     { phase 0..3; the turn engine's cost is 4 }
  e.Alive := True;
  e.Awake := False;
  Append(es, e);
  Inc(es.Monsters);
end;

procedure AddProp(var es: TEntitySet; const c: TContent; gx, gy: LongInt;
  h: LongWord);
var
  cand: array of LongInt;
  nc, i, pick: LongInt;
  e: TEntity;
begin
  if Length(c.Items) = 0 then exit;
  SetLength(cand, Length(c.Items));
  nc := 0;
  for i := 0 to High(c.Items) do
    if IsPropKind(c.Items[i].Kind) then begin cand[nc] := i; Inc(nc); end;
  if nc = 0 then exit;
  pick := cand[(h shr 8) mod LongWord(nc)];
  e.Kind := enProp;
  e.Cx := gx; e.Cy := gy;
  e.DefIdx := pick;
  e.Size := szSmall;
  PropColor(c.Items[pick].Kind, e.R, e.G, e.B);
  e.OrigRx := 0; e.OrigRy := 0; e.OrigIdx := 0;
  e.MaxHp := 0; e.Hp := 0; e.Energy := 0;
  e.Alive := True;
  e.Awake := False;
  Append(es, e);
  Inc(es.Props);
end;

procedure EntitiesBuild(var es: TEntitySet; const c: TContent; var tw: TTileWorld;
  centerRx, centerRy, radius, avoidCx, avoidCy: LongInt);
var
  rx, ry, n, idx, depth, gx, gy: LongInt;
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
        if (h mod 6) > 2 then continue;
        { A slain monster leaves its room empty on regeneration. }
        if ((h mod 6) <= 1) and EntitiesIsSlain(depth, rx, ry, idx) then continue;
        ref.Rx := rx; ref.Ry := ry; ref.Idx := idx;
        if not TileWorldRoomCenter(tw, ref, gx, gy) then continue;
        if (gx = avoidCx) and (gy = avoidCy) then continue;
        if (h mod 6) <= 1 then AddMonster(es, c, area, gx, gy, rx, ry, idx, depth, h)
        else AddProp(es, c, gx, gy, h);
      end;
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

function EntityBlocked(const es: TEntitySet; cx, cy: LongInt): Boolean;
begin
  EntityBlocked := EntityMonsterAt(es, cx, cy) >= 0;
end;

end.
