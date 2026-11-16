unit themes;

{** Zones and themes: the layer above region generation.

  The world is painted in zones, square blocks of regions, and each zone is assigned a
  theme from a small table. A theme sets how an area looks (floor, wall, door, and
  stair colours, and wall height) and how it is carved (room size and density). The
  assignment is a deterministic hash of the zone coordinates and the world seed, so a
  zone always has the same theme, and because the tile world folds the depth into its
  seed, a given zone differs from one depth to the next.

  Themes give the dungeon variety: catacombs give way to a flooded cistern, a tight
  warren, a tall cathedral, or the embers below. }

{$mode objfpc}{$H+}

interface

const
  ZONE_REGIONS = 3;   { a zone is this many regions on a side }
  NUM_THEMES   = 5;

type
  TThemeColor = record
    R, G, B: Byte;
  end;

  TTheme = record
    Name: String[16];
    Floor, Wall, Door, StairUp, StairDn: TThemeColor;
    WallHeight: LongInt;             { voxels }
    MinLeaf, MinRoom, MaxDepth: LongInt;   { carving parameters }
  end;

const
  ThemeTable: array[0..NUM_THEMES - 1] of TTheme = (
    (Name: 'Catacombs';
     Floor: (R: 66; G: 62; B: 56);   Wall: (R: 116; G: 112; B: 106);
     Door: (R: 120; G: 76; B: 40);   StairUp: (R: 164; G: 158; B: 150);
     StairDn: (R: 36; G: 34; B: 44); WallHeight: 6;
     MinLeaf: 9; MinRoom: 4; MaxDepth: 5),
    (Name: 'Warrens';
     Floor: (R: 72; G: 58; B: 44);   Wall: (R: 104; G: 84; B: 60);
     Door: (R: 120; G: 76; B: 40);   StairUp: (R: 150; G: 130; B: 100);
     StairDn: (R: 40; G: 30; B: 24); WallHeight: 4;
     MinLeaf: 7; MinRoom: 3; MaxDepth: 6),
    (Name: 'Cistern';
     Floor: (R: 54; G: 62; B: 70);   Wall: (R: 92; G: 108; B: 120);
     Door: (R: 110; G: 86; B: 54);   StairUp: (R: 150; G: 160; B: 170);
     StairDn: (R: 28; G: 34; B: 42); WallHeight: 8;
     MinLeaf: 11; MinRoom: 5; MaxDepth: 4),
    (Name: 'Cathedral';
     Floor: (R: 82; G: 80; B: 74);   Wall: (R: 150; G: 146; B: 136);
     Door: (R: 120; G: 90; B: 50);   StairUp: (R: 190; G: 186; B: 176);
     StairDn: (R: 44; G: 42; B: 48); WallHeight: 11;
     MinLeaf: 14; MinRoom: 6; MaxDepth: 4),
    (Name: 'Embers';
     Floor: (R: 58; G: 46; B: 44);   Wall: (R: 112; G: 70; B: 58);
     Door: (R: 120; G: 76; B: 40);   StairUp: (R: 162; G: 120; B: 100);
     StairDn: (R: 34; G: 26; B: 28); WallHeight: 6;
     MinLeaf: 9; MinRoom: 4; MaxDepth: 5)
  );

{ The theme index for the region at (rx, ry) under this world seed. }
function ThemeIndex(seed: QWord; rx, ry: LongInt): LongInt;

implementation

function FloorDiv(a, b: LongInt): LongInt;
begin
  if a >= 0 then FloorDiv := a div b
  else FloorDiv := -(((-a) + b - 1) div b);
end;

function ThemeIndex(seed: QWord; rx, ry: LongInt): LongInt;
var
  zx, zy: LongInt;
  h: QWord;
begin
  zx := FloorDiv(rx, ZONE_REGIONS);
  zy := FloorDiv(ry, ZONE_REGIONS);
  h := seed xor QWord($CBF29CE484222325);
  h := (h xor QWord(LongWord(zx))) * QWord($100000001B3);
  h := (h xor QWord(LongWord(zy))) * QWord($100000001B3);
  ThemeIndex := LongInt((h shr 33) mod QWord(NUM_THEMES));
end;

end.
