program t_content;

{** Tests the content-table loader: the four tables parse, a known monster carries
  its parsed size and area set, a known item its kind, and species and classes load.
  GL-free; reads the real tables under content/. }

{$mode objfpc}{$H+}

uses
  content;

var
  fails: LongInt;
  c: TContent;
  idx: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

begin
  fails := 0;

  Check(ContentLoad('content', c), 'ContentLoad reports success');
  writeln('  loaded ', Length(c.Monsters), ' monsters, ', Length(c.Items),
          ' items, ', Length(c.Species), ' species, ', Length(c.Classes),
          ' classes');

  Check(Length(c.Monsters) > 0, 'monsters present');
  Check(Length(c.Items) > 0, 'items present');
  Check(Length(c.Species) > 0, 'species present');
  Check(Length(c.Classes) > 0, 'classes present');

  { The giant rat: small, roams forest and cave, drawn name parsed from quotes. }
  idx := MonsterByIdx(c, 'RAT');
  Check(idx >= 0, 'RAT found');
  if idx >= 0 then begin
    Check(c.Monsters[idx].Size = szSmall, 'RAT size is small');
    Check(arForest in c.Monsters[idx].Areas, 'RAT roams forest');
    Check(arCave in c.Monsters[idx].Areas, 'RAT roams cave');
    Check(c.Monsters[idx].Name = 'Giant Rat', 'RAT name parsed');
  end;

  { A large monster parses its size tag too. }
  idx := MonsterByIdx(c, 'SPIDER');
  Check((idx >= 0) and (c.Monsters[idx].Size = szLarge), 'SPIDER size is large');

  { Gold is a treasure item. }
  idx := ItemByIdx(c, 'GOLD');
  Check(idx >= 0, 'GOLD found');
  if idx >= 0 then begin
    Check(c.Items[idx].Kind = 'treasure', 'GOLD kind is treasure');
    Check(c.Items[idx].Name = 'Gold', 'GOLD name parsed');
  end;

  { Encounter tables: the forest area points at a non-empty table, and a weighted pick
    from it yields a monster that roams the forest. }
  idx := EncTableFor(c, arForest);
  Check(idx >= 1, 'forest area has an encounter table');
  Check((idx < 0) or (c.EncTables[idx].Total > 0), 'the forest table has weight');
  idx := EncPick(c, EncTableFor(c, arForest), 0);
  Check(idx >= 0, 'a forest pick yields a monster');
  Check((idx < 0) or (arForest in c.Monsters[idx].Areas),
        'a forest pick roams the forest');
  { The newgame default was read. }
  Check(c.DefSpecies <> '', 'newgame default species loaded');
  Check(Length(c.Names) > 0, 'newgame name pool loaded');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
