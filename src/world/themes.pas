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
    r, g, b: byte;
  end;

  TTheme = record
    name: string[16];
    floor, wall, door, stairUp, stairDn: TThemeColor;
    wallHeight: longint;             { voxels }
    minLeaf, minRoom, maxDepth: longint;   { carving parameters }
  end;

const
  ThemeTable: array[0..NUM_THEMES - 1] of TTheme = (
    (name: 'Catacombs';
     floor: (r: 66; g: 62; b: 56);   wall: (r: 116; g: 112; b: 106);
     door: (r: 120; g: 76; b: 40);   stairUp: (r: 164; g: 158; b: 150);
     stairDn: (r: 36; g: 34; b: 44); wallHeight: 6;
     minLeaf: 9; minRoom: 4; maxDepth: 5),
    (name: 'Warrens';
     floor: (r: 72; g: 58; b: 44);   wall: (r: 104; g: 84; b: 60);
     door: (r: 120; g: 76; b: 40);   stairUp: (r: 150; g: 130; b: 100);
     stairDn: (r: 40; g: 30; b: 24); wallHeight: 4;
     minLeaf: 7; minRoom: 3; maxDepth: 6),
    (name: 'Cistern';
     floor: (r: 54; g: 62; b: 70);   wall: (r: 92; g: 108; b: 120);
     door: (r: 110; g: 86; b: 54);   stairUp: (r: 150; g: 160; b: 170);
     stairDn: (r: 28; g: 34; b: 42); wallHeight: 8;
     minLeaf: 11; minRoom: 5; maxDepth: 4),
    (name: 'Cathedral';
     floor: (r: 82; g: 80; b: 74);   wall: (r: 150; g: 146; b: 136);
     door: (r: 120; g: 90; b: 50);   stairUp: (r: 190; g: 186; b: 176);
     stairDn: (r: 44; g: 42; b: 48); wallHeight: 11;
     minLeaf: 14; minRoom: 6; maxDepth: 4),
    (name: 'Embers';
     floor: (r: 58; g: 46; b: 44);   wall: (r: 112; g: 70; b: 58);
     door: (r: 120; g: 76; b: 40);   stairUp: (r: 162; g: 120; b: 100);
     stairDn: (r: 34; g: 26; b: 28); wallHeight: 6;
     minLeaf: 9; minRoom: 4; maxDepth: 5)
  );

{ The theme index for the region at (rx, ry) under this world seed. }
function ThemeIndex(seed: qword; rx, ry: longint): longint;

implementation

function FloorDiv(a, b: longint): longint;
begin
  if a >= 0 then FloorDiv := a div b
  else FloorDiv := -(((-a) + b - 1) div b);
end;

function ThemeIndex(seed: qword; rx, ry: longint): longint;
var
  zx, zy: longint;
  h: qword;
begin
  zx := FloorDiv(rx, ZONE_REGIONS);
  zy := FloorDiv(ry, ZONE_REGIONS);
  h := seed xor qword($CBF29CE484222325);
  h := (h xor qword(longword(zx))) * qword($100000001B3);
  h := (h xor qword(longword(zy))) * qword($100000001B3);
  ThemeIndex := longint((h shr 33) mod qword(NUM_THEMES));
end;

end.
