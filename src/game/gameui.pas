unit gameui;
{ The game's interface layer: a desktop of floating windows over the diorama.    }
{ It wraps the gui toolkit behind a plain procedural API so the main program can  }
{ drive it with integers and strings, and never sees the toolkit's own types.    }

{$mode objfpc}{$H+}

interface

{ Build the desktop and the status window for a viewW x viewH framebuffer. }
procedure GameUIInit(viewW, viewH: LongInt);

{ Replace the status panel's text with these lines. }
procedure GameUISetStatus(const lines: array of String);

{ Feed a mouse event: kind 0 down, 1 up, 2 move, 3 wheel; button 0 left, 1 middle,
  2 right; wheel the signed scroll delta. }
procedure GameUIMouse(kind, x, y, button, wheel: LongInt);

{ Draw the desktop as an overlay. Call after the 3D scene, before the buffer swap. }
procedure GameUIRender;

procedure GameUIFree;

implementation

uses
  gui, guitheme, guigl;

type
  { A panel that draws a list of text lines, the live game status. }
  THudPanel = class(TWidget)
  private
    FLines: array of String;
  public
    procedure SetLines(const lines: array of String);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

var
  gTheme:   TSystem7Theme;
  gDesktop: TDesktop;
  gCanvas:  TGLCanvas;
  gWin:     TWindow;
  gHud:     THudPanel;

procedure THudPanel.SetLines(const lines: array of String);
var
  i: LongInt;
begin
  SetLength(FLines, Length(lines));
  for i := 0 to High(lines) do FLines[i] := lines[i];
end;

procedure THudPanel.Draw(cv: TCanvas; theme: TTheme);
var
  r: TRect;
  i, lh: LongInt;
begin
  r := AbsRect;
  lh := cv.TextHeight + 4;
  for i := 0 to High(FLines) do
    cv.DrawText(r.Left + 4, r.Top + 4 + i * lh, FLines[i], clBlack);
end;

procedure GameUIInit(viewW, viewH: LongInt);
begin
  gTheme := TSystem7Theme.Create;
  gDesktop := TDesktop.Create(gTheme, viewW, viewH);
  gCanvas := TGLCanvas.Create(viewW, viewH);
  gWin := TWindow.Create(gDesktop, 'STATUS', [wfClose, wfDrag, wfZoom], 12, 12, 250, 150);
  gHud := THudPanel.Create(gWin.Content);
  gHud.SetBounds(0, 0, 250, 150);
  gDesktop.BringToFront(gWin);
end;

procedure GameUISetStatus(const lines: array of String);
begin
  if gHud <> nil then gHud.SetLines(lines);
end;

procedure GameUIMouse(kind, x, y, button, wheel: LongInt);
var
  e: TUIEvent;
begin
  if gDesktop = nil then exit;
  FillChar(e, SizeOf(e), 0);
  e.Pos := Pt(x, y);
  e.Button := button;
  e.Wheel := wheel;
  case kind of
    0: e.Kind := ekMouseDown;
    1: e.Kind := ekMouseUp;
    2: e.Kind := ekMouseMove;
    3: e.Kind := ekMouseWheel;
  else exit;
  end;
  gDesktop.Dispatch(e);
end;

procedure GameUIRender;
begin
  if gCanvas = nil then exit;
  gCanvas.BeginFrame;
  gDesktop.PaintAll(gCanvas);
  gCanvas.EndFrame;
end;

procedure GameUIFree;
begin
  if gDesktop <> nil then begin gDesktop.Free; gDesktop := nil; end;
  if gCanvas <> nil then begin gCanvas.Free; gCanvas := nil; end;
  if gTheme <> nil then begin gTheme.Free; gTheme := nil; end;
end;

end.
