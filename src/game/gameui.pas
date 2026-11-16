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

{ Toggle a floating panel: 0 inventory (with the equipment doll), 1 character
  sheet, 2 options. The same call shows a hidden panel and hides a shown one. }
procedure GameUITogglePanel(id: LongInt);

{ Feed a mouse event: kind 0 down, 1 up, 2 move, 3 wheel; button 0 left, 1 middle,
  2 right; wheel the signed scroll delta. }
procedure GameUIMouse(kind, x, y, button, wheel: LongInt);

{ Draw the desktop as an overlay. Call after the 3D scene, before the buffer swap. }
procedure GameUIRender;

procedure GameUIFree;

implementation

uses
  gui, guitheme, guigl, panels;

type
  { A panel that draws a list of text lines, the live game status. }
  THudPanel = class(TWidget)
  private
    FLines: array of String;
  public
    procedure SetLines(const lines: array of String);
    procedure Draw(cv: TCanvas; theme: TTheme); override;
  end;

  { Owns the toggle panels and routes the HUD button clicks to them. A plain
    object, not a widget: its methods are the buttons' OnClick handlers. }
  TUIController = class
  public
    Inv:  TInventoryWindow;
    Equ:  TEquipmentWindow;
    Chr:  TCharacterSheet;
    Opts: TOptionsWindow;
    procedure TogglePanel(id: LongInt);
    procedure OnInv(sender: TWidget);
    procedure OnChar(sender: TWidget);
    procedure OnOpts(sender: TWidget);
  end;

var
  gTheme:   TSystem7Theme;
  gDesktop: TDesktop;
  gCanvas:  TGLCanvas;
  gWin:     TWindow;
  gHud:     THudPanel;
  gCtl:     TUIController;

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

{ ---- TUIController ---- }

procedure TUIController.TogglePanel(id: LongInt);
var
  show: Boolean;
begin
  case id of
    0: begin
         show := not Inv.Visible;
         Inv.Visible := show;
         Equ.Visible := show;
         if show then begin
           gDesktop.BringToFront(Equ);
           gDesktop.BringToFront(Inv);
         end;
       end;
    1: begin
         show := not Chr.Visible;
         Chr.Visible := show;
         if show then gDesktop.BringToFront(Chr);
       end;
    2: begin
         show := not Opts.Visible;
         Opts.Visible := show;
         if show then gDesktop.BringToFront(Opts);
       end;
  end;
end;

procedure TUIController.OnInv(sender: TWidget);  begin TogglePanel(0); end;
procedure TUIController.OnChar(sender: TWidget); begin TogglePanel(1); end;
procedure TUIController.OnOpts(sender: TWidget); begin TogglePanel(2); end;

procedure GameUIInit(viewW, viewH: LongInt);
var
  b: TButton;
begin
  gTheme := TSystem7Theme.Create;
  gDesktop := TDesktop.Create(gTheme, viewW, viewH);
  gCanvas := TGLCanvas.Create(viewW, viewH);

  { status window: the live HUD lines, then a row of panel-toggle buttons }
  gWin := TWindow.Create(gDesktop, 'STATUS', [wfClose, wfDrag, wfZoom], 12, 12, 250, 240);
  gHud := THudPanel.Create(gWin.Content);
  gHud.SetBounds(0, 0, 250, 180);

  gCtl := TUIController.Create;
  b := TButton.Create(gWin.Content, 'INV',  6, 186, 72, 22);  b.OnClick := @gCtl.OnInv;
  b := TButton.Create(gWin.Content, 'CHAR', 86, 186, 72, 22); b.OnClick := @gCtl.OnChar;
  b := TButton.Create(gWin.Content, 'OPTS', 166, 186, 72, 22); b.OnClick := @gCtl.OnOpts;

  { the toggle panels, created hidden and shown on demand }
  gCtl.Inv  := TInventoryWindow.Create(gDesktop, 300, 40);
  gCtl.Equ  := TEquipmentWindow.Create(gDesktop, 580, 40);
  gCtl.Chr  := TCharacterSheet.Create(gDesktop, 300, 330);
  gCtl.Opts := TOptionsWindow.Create(gDesktop, 600, 330);
  gCtl.Inv.Visible := False;
  gCtl.Equ.Visible := False;
  gCtl.Chr.Visible := False;
  gCtl.Opts.Visible := False;
  PlacePlaceholders(gCtl.Inv, gCtl.Equ);

  gDesktop.BringToFront(gWin);
end;

procedure GameUITogglePanel(id: LongInt);
begin
  if gCtl <> nil then gCtl.TogglePanel(id);
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
  if gCtl <> nil then begin gCtl.Free; gCtl := nil; end;
  if gCanvas <> nil then begin gCanvas.Free; gCanvas := nil; end;
  if gTheme <> nil then begin gTheme.Free; gTheme := nil; end;
end;

end.
