unit critters;
{ Procedural placeholder voxel models for the dungeon's inhabitants: a small blocky  }
{ biped for monsters and a cube for item props. Both are built in plain white, so the }
{ per-entity draw tint colours them. They stand in until authored creature art lands.  }

{$mode objfpc}{$H+}

interface

uses
  voxfile;

{ A blocky humanoid, 5 x 3 x 9 voxels (z up). }
procedure BuildCreatureModel(out m: TVoxModel);

{ A small cube prop, 3 x 3 x 3 voxels. }
procedure BuildPropModel(out m: TVoxModel);

implementation

procedure White(var m: TVoxModel);
begin
  m.Palette[1].R := 255;
  m.Palette[1].G := 255;
  m.Palette[1].B := 255;
  m.Palette[1].A := 255;
end;

procedure Fill(var m: TVoxModel; x0, x1, y0, y1, z0, z1: LongInt);
var
  x, y, z: LongInt;
begin
  for z := z0 to z1 do
    for y := y0 to y1 do
      for x := x0 to x1 do
        VoxSetCell(m, x, y, z, 1);
end;

procedure BuildCreatureModel(out m: TVoxModel);
begin
  VoxAlloc(m, 5, 3, 9);
  White(m);
  Fill(m, 0, 1, 0, 2, 0, 3);   { left leg }
  Fill(m, 3, 4, 0, 2, 0, 3);   { right leg }
  Fill(m, 0, 4, 0, 2, 4, 6);   { torso and arms }
  Fill(m, 1, 3, 0, 2, 7, 8);   { head }
end;

procedure BuildPropModel(out m: TVoxModel);
begin
  VoxAlloc(m, 3, 3, 3);
  White(m);
  Fill(m, 0, 2, 0, 2, 0, 2);
end;

end.
