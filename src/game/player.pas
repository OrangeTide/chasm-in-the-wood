unit player;

{** The player's position on the grid.

  The player occupies one cell and moves a cell at a time, staying inside the grid.
  This is deliberately small for now; facing, stats, and inventory arrive with the
  gameplay releases. }

{$mode objfpc}{$H+}

interface

uses
  grid;

type
  TPlayer = record
    cx, cy: longint;
  end;

procedure PlayerInit(out p: TPlayer; const g: TGrid);
procedure PlayerMove(var p: TPlayer; dx, dy: longint; const g: TGrid);

implementation

procedure PlayerInit(out p: TPlayer; const g: TGrid);
begin
  p.cx := g.w div 2;
  p.cy := g.h div 2;
end;

procedure PlayerMove(var p: TPlayer; dx, dy: longint; const g: TGrid);
begin
  if GridInBounds(g, p.cx + dx, p.cy + dy) then begin
    p.cx := p.cx + dx;
    p.cy := p.cy + dy;
  end;
end;

end.
