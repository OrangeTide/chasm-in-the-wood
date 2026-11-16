unit content;
{ Loads the content tables under content/ into plain Pascal records: monsters,    }
{ items, species, and classes. The tables are whitespace-separated text with '#'   }
{ comment lines and a double-quoted display name. Parsing stays tolerant: unknown   }
{ trailing tags are ignored, so a table can gain tags without breaking the loader.  }
{ This holds data only; the game layer decides how to use it.                       }

{$mode objfpc}{$H+}

interface

uses
  sysutils, classes;

type
  { Monster roaming areas, matched against a zone's area for spawning. }
  TArea = (arForest, arCoast, arDesert, arFrozen, arVolcanic, arCrypt,
           arCave, arInfernal);
  TAreaSet = set of TArea;

  { Body bulk, drives the drawn creature's scale. }
  TSizeClass = (szTiny, szSmall, szMedium, szLarge, szHuge, szColossal);

  TMonsterDef = record
    Id, Name, Model: String;
    HD, AC, Atk, Dmg, Morale, Speed, XP, Flags: LongInt;
    Areas: TAreaSet;
    Size: TSizeClass;
  end;

  TItemDef = record
    Id, Name, Kind: String;
    Dmg, AC, Slots, Value, Flags: LongInt;
  end;

  TSpeciesDef = record
    Id, Name: String;
    Str, Dex, Con, Int, Wis, Cha, Flags, XpPct: LongInt;
  end;

  TClassDef = record
    Id, Name, Track, Prime, Kit, Domain, School: String;
    HitDie: LongInt;
  end;

  { A quick-start character: a species and a class id. }
  TPregen = record
    Species, Klass: String;
  end;

  { One weighted monster in an encounter table. }
  TEncEntry = record
    MonIdx, Weight: LongInt;
  end;

  TEncTable = record
    Entries: array of TEncEntry;
    Total:   LongInt;                { sum of the weights }
  end;

  TContent = record
    Monsters: array of TMonsterDef;
    Items:    array of TItemDef;
    Species:  array of TSpeciesDef;
    Classes:  array of TClassDef;
    { New-game data (newgame.txt). }
    Names:       array of String;    { the random name pool }
    Pregens:     array of TPregen;   { quick-start archetypes }
    DefSpecies:  String;             { character-creation starting species id }
    DefKlass:    String;             { and class id }
    { Encounter tables (encounters.txt). }
    EncTables:   array of TEncTable;        { indexed by table number }
    AreaTable:   array[TArea] of LongInt;   { area to table number, -1 for none }
  end;

{ Load all four tables from baseDir (e.g. 'content'). Returns False if a file is
  missing or unreadable; partial data loaded before the failure is left in place. }
function ContentLoad(const baseDir: String; out c: TContent): Boolean;

{ Index of the monster/item/species/class with this id, or -1. }
function MonsterByIdx(const c: TContent; const id: String): LongInt;
function ItemByIdx(const c: TContent; const id: String): LongInt;
function SpeciesByIdx(const c: TContent; const id: String): LongInt;
function ClassByIdx(const c: TContent; const id: String): LongInt;

{ The encounter table assigned to an area, or -1 when none applies. }
function EncTableFor(const c: TContent; area: TArea): LongInt;

{ Weighted pick of a monster index from a table, driven by roll, or -1 when the table is
  empty or out of range. }
function EncPick(const c: TContent; table: LongInt; roll: LongWord): LongInt;

implementation

{ ---- tokenizer ---- }

procedure Tokenize(const line: String; out tok: array of String; out n: LongInt);
{ Split on whitespace, but keep a double-quoted run as one token without quotes. }
var
  i, len, cap: LongInt;
  inQuote: Boolean;
  cur: String;

  procedure Flush;
  begin
    if cur <> '' then begin
      if n < cap then tok[n] := cur;
      Inc(n);
      cur := '';
    end;
  end;

begin
  n := 0;
  cap := Length(tok);
  cur := '';
  inQuote := False;
  len := Length(line);
  i := 1;
  while i <= len do begin
    if line[i] = '"' then begin
      if inQuote then begin
        { close: emit even an empty quoted string }
        if n < cap then tok[n] := cur;
        Inc(n);
        cur := '';
        inQuote := False;
      end else
        inQuote := True;
    end else if inQuote then
      cur := cur + line[i]
    else if (line[i] = ' ') or (line[i] = #9) then
      Flush
    else
      cur := cur + line[i];
    Inc(i);
  end;
  Flush;
end;

function Skip(const line: String): Boolean;
{ A blank or comment line carries no record. }
var
  s: String;
begin
  s := Trim(line);
  Skip := (s = '') or (s[1] = '#');
end;

function ToInt(const s: String): LongInt;
begin
  ToInt := StrToIntDef(s, 0);
end;

{ ---- field parsers ---- }

function ParseArea(const s: String): TArea;
begin
  if s = 'coast' then ParseArea := arCoast
  else if s = 'desert' then ParseArea := arDesert
  else if s = 'frozen' then ParseArea := arFrozen
  else if s = 'volcanic' then ParseArea := arVolcanic
  else if s = 'crypt' then ParseArea := arCrypt
  else if s = 'cave' then ParseArea := arCave
  else if s = 'infernal' then ParseArea := arInfernal
  else ParseArea := arForest;
end;

function ParseAreaSet(const s: String): TAreaSet;
{ A '+'-joined list such as "forest+cave". }
var
  parts: TStringList;
  i: LongInt;
begin
  ParseAreaSet := [];
  parts := TStringList.Create;
  try
    parts.Delimiter := '+';
    parts.StrictDelimiter := True;
    parts.DelimitedText := s;
    for i := 0 to parts.Count - 1 do
      Include(ParseAreaSet, ParseArea(Trim(parts[i])));
  finally
    parts.Free;
  end;
end;

function ParseSize(const tag: String): TSizeClass;
{ The value of a "size:" tag. }
var
  v: String;
begin
  v := Copy(tag, Pos(':', tag) + 1, Length(tag));
  if v = 'tiny' then ParseSize := szTiny
  else if v = 'small' then ParseSize := szSmall
  else if v = 'large' then ParseSize := szLarge
  else if v = 'huge' then ParseSize := szHuge
  else if v = 'colossal' then ParseSize := szColossal
  else ParseSize := szMedium;
end;

{ ---- per-table row readers ---- }

procedure ReadMonster(const tok: array of String; n: LongInt; var c: TContent);
var
  m: TMonsterDef;
  i, k: LongInt;
begin
  if n < 12 then exit;                 { 'mon' + 11 fixed fields at least }
  m.Id := tok[1];
  m.HD := ToInt(tok[2]);  m.AC := ToInt(tok[3]);  m.Atk := ToInt(tok[4]);
  m.Dmg := ToInt(tok[5]); m.Morale := ToInt(tok[6]); m.Speed := ToInt(tok[7]);
  m.XP := ToInt(tok[8]);  m.Flags := ToInt(tok[9]);
  m.Model := tok[10];
  m.Areas := ParseAreaSet(tok[11]);
  m.Size := szMedium;
  m.Name := '';
  { Remaining tokens: 'key:value' tags, then the quoted name (no colon). }
  for i := 12 to n - 1 do begin
    if Pos(':', tok[i]) > 0 then begin
      if Copy(tok[i], 1, 5) = 'size:' then m.Size := ParseSize(tok[i]);
    end else
      m.Name := tok[i];
  end;
  k := Length(c.Monsters);
  SetLength(c.Monsters, k + 1);
  c.Monsters[k] := m;
end;

procedure ReadItem(const tok: array of String; n: LongInt; var c: TContent);
var
  it: TItemDef;
  i, k: LongInt;
begin
  if n < 8 then exit;                   { 'item' + 7 fixed fields }
  it.Id := tok[1];  it.Kind := tok[2];
  it.Dmg := ToInt(tok[3]); it.AC := ToInt(tok[4]); it.Slots := ToInt(tok[5]);
  it.Value := ToInt(tok[6]); it.Flags := ToInt(tok[7]);
  it.Name := '';
  for i := 8 to n - 1 do
    if Pos(':', tok[i]) = 0 then it.Name := tok[i];
  k := Length(c.Items);
  SetLength(c.Items, k + 1);
  c.Items[k] := it;
end;

procedure ReadSpecies(const tok: array of String; n: LongInt; var c: TContent);
var
  sp: TSpeciesDef;
  k: LongInt;
begin
  if n < 11 then exit;        { species ID "Name" 6 stats FLAGS XP% }
  sp.Id := tok[1];  sp.Name := tok[2];
  sp.Str := ToInt(tok[3]); sp.Dex := ToInt(tok[4]); sp.Con := ToInt(tok[5]);
  sp.Int := ToInt(tok[6]); sp.Wis := ToInt(tok[7]); sp.Cha := ToInt(tok[8]);
  sp.Flags := ToInt(tok[9]); sp.XpPct := ToInt(tok[10]);
  k := Length(c.Species);
  SetLength(c.Species, k + 1);
  c.Species[k] := sp;
end;

procedure ReadClass(const tok: array of String; n: LongInt; var c: TContent);
var
  cl: TClassDef;
  k: LongInt;
begin
  if n < 8 then exit;         { class ID "Name" TRACK HITDIE PRIME KIT DOMAIN }
  cl.Id := tok[1];  cl.Name := tok[2];  cl.Track := tok[3];
  cl.HitDie := ToInt(tok[4]); cl.Prime := tok[5]; cl.Kit := tok[6];
  cl.Domain := tok[7];
  if n >= 9 then cl.School := tok[8] else cl.School := '';
  k := Length(c.Classes);
  SetLength(c.Classes, k + 1);
  c.Classes[k] := cl;
end;

{ ---- file loop ---- }

type
  TRowProc = procedure(const tok: array of String; n: LongInt; var c: TContent);

function LoadTable(const path, keyword: String; row: TRowProc;
  var c: TContent): Boolean;
var
  f: TextFile;
  line: String;
  tok: array[0..63] of String;
  n: LongInt;
begin
  LoadTable := False;
  if not FileExists(path) then exit;
  AssignFile(f, path);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then exit;
  try
    while not Eof(f) do begin
      ReadLn(f, line);
      if Skip(line) then continue;
      Tokenize(line, tok, n);
      if (n > 0) and (tok[0] = keyword) then row(tok, n, c);
    end;
  finally
    CloseFile(f);
  end;
  LoadTable := True;
end;

function LoadNewgame(const path: String; var c: TContent): Boolean;
{ newgame.txt carries three kinds of row (name, pregen, default), so it is read with a
  small dispatch of its own rather than the single-keyword table loader. }
var
  f: TextFile;
  line: String;
  tok: array[0..63] of String;
  n, k: LongInt;
begin
  LoadNewgame := False;
  if not FileExists(path) then exit;
  AssignFile(f, path);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then exit;
  try
    while not Eof(f) do begin
      ReadLn(f, line);
      if Skip(line) then continue;
      Tokenize(line, tok, n);
      if n < 2 then continue;
      if tok[0] = 'name' then begin
        k := Length(c.Names);
        SetLength(c.Names, k + 1);
        c.Names[k] := tok[1];
      end else if (tok[0] = 'pregen') and (n >= 3) then begin
        k := Length(c.Pregens);
        SetLength(c.Pregens, k + 1);
        c.Pregens[k].Species := tok[1];
        c.Pregens[k].Klass := tok[2];
      end else if (tok[0] = 'default') and (n >= 3) then begin
        c.DefSpecies := tok[1];
        c.DefKlass := tok[2];
      end;
    end;
  finally
    CloseFile(f);
  end;
  LoadNewgame := True;
end;

function LoadEncounters(const path: String; var c: TContent): Boolean;
{ encounters.txt assigns each area a table number and fills the numbered tables with
  weighted monsters, so it is read with its own dispatch like newgame.txt. }
var
  f: TextFile;
  line: String;
  tok: array[0..63] of String;
  n, cur, num, mi, w, k: LongInt;
begin
  LoadEncounters := False;
  if not FileExists(path) then exit;
  AssignFile(f, path);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then exit;
  cur := -1;
  try
    while not Eof(f) do begin
      ReadLn(f, line);
      if Skip(line) then continue;
      Tokenize(line, tok, n);
      if n < 2 then continue;
      if (tok[0] = 'area') and (n >= 3) then
        c.AreaTable[ParseArea(tok[1])] := ToInt(tok[2])
      else if tok[0] = 'table' then begin
        cur := ToInt(tok[1]);
        if cur >= Length(c.EncTables) then SetLength(c.EncTables, cur + 1);
      end else if (tok[0] = 'mon') and (n >= 3) and (cur >= 0) then begin
        mi := MonsterByIdx(c, tok[1]);
        w := ToInt(tok[2]);
        if (mi >= 0) and (w > 0) then begin
          k := Length(c.EncTables[cur].Entries);
          SetLength(c.EncTables[cur].Entries, k + 1);
          c.EncTables[cur].Entries[k].MonIdx := mi;
          c.EncTables[cur].Entries[k].Weight := w;
          Inc(c.EncTables[cur].Total, w);
        end;
      end;
    end;
  finally
    CloseFile(f);
  end;
  LoadEncounters := True;
end;

function EncTableFor(const c: TContent; area: TArea): LongInt;
begin
  EncTableFor := c.AreaTable[area];
end;

function EncPick(const c: TContent; table: LongInt; roll: LongWord): LongInt;
var
  r, i: LongInt;
begin
  EncPick := -1;
  if (table < 0) or (table >= Length(c.EncTables)) then exit;
  if c.EncTables[table].Total <= 0 then exit;
  r := LongInt(roll mod LongWord(c.EncTables[table].Total));
  for i := 0 to High(c.EncTables[table].Entries) do begin
    Dec(r, c.EncTables[table].Entries[i].Weight);
    if r < 0 then exit(c.EncTables[table].Entries[i].MonIdx);
  end;
end;

function ContentLoad(const baseDir: String; out c: TContent): Boolean;
var
  ok: Boolean;
  a: TArea;
begin
  SetLength(c.Monsters, 0);
  SetLength(c.Items, 0);
  SetLength(c.Species, 0);
  SetLength(c.Classes, 0);
  SetLength(c.Names, 0);
  SetLength(c.Pregens, 0);
  SetLength(c.EncTables, 0);
  for a := Low(TArea) to High(TArea) do c.AreaTable[a] := -1;
  c.DefSpecies := '';
  c.DefKlass := '';
  ok := True;
  ok := LoadTable(baseDir + '/monsters.txt', 'mon',     @ReadMonster, c) and ok;
  ok := LoadTable(baseDir + '/items.txt',    'item',    @ReadItem,    c) and ok;
  ok := LoadTable(baseDir + '/species.txt',  'species', @ReadSpecies, c) and ok;
  ok := LoadTable(baseDir + '/classes.txt',  'class',   @ReadClass,   c) and ok;
  ok := LoadNewgame(baseDir + '/newgame.txt', c) and ok;
  ok := LoadEncounters(baseDir + '/encounters.txt', c) and ok;
  ContentLoad := ok;
end;

function MonsterByIdx(const c: TContent; const id: String): LongInt;
var
  i: LongInt;
begin
  for i := 0 to High(c.Monsters) do
    if c.Monsters[i].Id = id then exit(i);
  MonsterByIdx := -1;
end;

function ItemByIdx(const c: TContent; const id: String): LongInt;
var
  i: LongInt;
begin
  for i := 0 to High(c.Items) do
    if c.Items[i].Id = id then exit(i);
  ItemByIdx := -1;
end;

function SpeciesByIdx(const c: TContent; const id: String): LongInt;
var
  i: LongInt;
begin
  for i := 0 to High(c.Species) do
    if c.Species[i].Id = id then exit(i);
  SpeciesByIdx := -1;
end;

function ClassByIdx(const c: TContent; const id: String): LongInt;
var
  i: LongInt;
begin
  for i := 0 to High(c.Classes) do
    if c.Classes[i].Id = id then exit(i);
  ClassByIdx := -1;
end;

end.
