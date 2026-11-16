unit guitheme;
{ The System 7 theme: all window and widget chrome.                         }
{ It draws only through the abstract TCanvas, so it is backend-neutral and  }
{ works with any canvas, the OpenGL one included.                           }

{$mode objfpc}{$H+}

interface

uses
  gui;

type
  TSystem7Theme = class(TTheme)
  public
    function  TitleBarHeight: LongInt; override;
    function  BorderWidth: LongInt; override;
    procedure DrawWindow(cv: TCanvas; w: TWindow); override;
    procedure DrawButton(cv: TCanvas; const r: TRect; const caption: string;
                         pressed, isDefault, enabled: Boolean); override;
    procedure DrawSlot(cv: TCanvas; const r: TRect; hot, filled: Boolean); override;
    procedure DrawTab(cv: TCanvas; const r: TRect; const caption: string; active: Boolean); override;
    procedure DrawPanel(cv: TCanvas; const r: TRect); override;
    procedure DrawScrollbar(cv: TCanvas; const bar, thumb: TRect); override;
  end;

implementation

function TSystem7Theme.TitleBarHeight: LongInt; begin TitleBarHeight := 24; end;
function TSystem7Theme.BorderWidth: LongInt; begin BorderWidth := 2; end;

procedure TSystem7Theme.DrawWindow(cv: TCanvas; w: TWindow);
var r, tb, kb, cb, gb: TRect; cx, tw, i, yy: LongInt;
begin
  r := w.AbsRect;
  { drop shadow }
  cv.FillRect(Rect(r.left + 3, r.top + 3, r.right + 3, r.bottom + 3), clDkGray);
  { body }
  cv.FillRect(r, clWhite);
  cv.FrameRect(r, clBlack);
  { title bar }
  tb := Rect(r.left, r.top, r.right, r.top + TitleBarHeight);
  cv.FillRect(tb, clWhite);
  cv.HLine(r.left, r.right, tb.bottom, clBlack);
  { racing stripes when active }
  if w.Active then begin
    i := 0; yy := tb.top + 5;
    while i < 6 do begin
      cv.HLine(tb.left + 22, tb.right - 22, yy, clBlack);
      yy := yy + 2; i := i + 1;
    end;
  end;
  { title text on a knockout }
  tw := cv.TextWidth(w.Title);
  cx := (tb.left + tb.right) div 2 - tw div 2;
  cv.FillRect(Rect(cx - 6, tb.top + 3, cx + tw + 6, tb.top + TitleBarHeight - 4), clWhite);
  cv.DrawText(cx, tb.top + (TitleBarHeight - cv.TextHeight) div 2, w.Title, clBlack);
  { close box }
  if wfClose in w.Flags then begin
    cb := Rect(tb.left + 6, tb.top + 6, tb.left + 18, tb.top + 18);
    cv.FillRect(cb, clWhite); cv.FrameRect(cb, clBlack);
  end;
  { zoom box }
  if wfZoom in w.Flags then begin
    kb := Rect(tb.right - 18, tb.top + 6, tb.right - 6, tb.top + 18);
    cv.FillRect(kb, clWhite); cv.FrameRect(kb, clBlack);
    cv.FrameRect(Rect(kb.left + 2, kb.top + 2, kb.left + 7, kb.top + 7), clBlack);
  end;
  { grow (resize) box in the bottom-right corner }
  if wfGrow in w.Flags then begin
    gb := Rect(r.right - 16, r.bottom - 16, r.right, r.bottom);
    cv.FillRect(gb, clWhite);
    cv.FrameRect(gb, clBlack);
    for i := 0 to 2 do
      cv.FillRect(Rect(gb.right - 5 - i * 4, gb.bottom - 5 - i * 4,
                       gb.right - 3 - i * 4, gb.bottom - 3 - i * 4), clDkGray);
  end;
end;

procedure TSystem7Theme.DrawButton(cv: TCanvas; const r: TRect; const caption: string;
  pressed, isDefault, enabled: Boolean);
var cx, cy: LongInt;
begin
  if isDefault then
    cv.FrameRect(Rect(r.left - 3, r.top - 3, r.right + 3, r.bottom + 3), clBlack);
  if pressed then cv.FillRect(r, clLtGray) else cv.FillRect(r, clWhite);
  cv.FrameRect(r, clBlack);
  cx := (r.left + r.right) div 2 - cv.TextWidth(caption) div 2;
  cy := (r.top + r.bottom) div 2 - cv.TextHeight div 2;
  cv.DrawText(cx, cy, caption, clBlack);
end;

procedure TSystem7Theme.DrawSlot(cv: TCanvas; const r: TRect; hot, filled: Boolean);
begin
  cv.FillRect(r, clParch);
  { engraved look: dark top/left, light bottom/right }
  cv.HLine(r.left, r.right - 1, r.top, clDkGray);
  cv.VLine(r.left, r.top, r.bottom - 1, clDkGray);
  cv.HLine(r.left, r.right - 1, r.bottom - 1, clGray);
  cv.VLine(r.right - 1, r.top, r.bottom - 1, clGray);
end;

procedure TSystem7Theme.DrawTab(cv: TCanvas; const r: TRect; const caption: string; active: Boolean);
var cx: LongInt;
begin
  if active then cv.FillRect(r, clWhite) else cv.FillRect(r, clLtGray);
  cv.FrameRect(r, clBlack);
  cx := (r.left + r.right) div 2 - cv.TextWidth(caption) div 2;
  cv.DrawText(cx, r.top + (RectH(r) - cv.TextHeight) div 2, caption, clBlack);
end;

procedure TSystem7Theme.DrawPanel(cv: TCanvas; const r: TRect);
begin
  cv.FillRect(r, clLtGray);
  cv.FrameRect(r, clBlack);
end;

procedure TSystem7Theme.DrawScrollbar(cv: TCanvas; const bar, thumb: TRect);
var up, dn: TRect;
begin
  cv.FillRect(bar, clLtGray);
  cv.FrameRect(bar, clBlack);
  up := Rect(bar.left, bar.top, bar.right, bar.top + 16);
  dn := Rect(bar.left, bar.bottom - 16, bar.right, bar.bottom);
  cv.FillRect(up, clWhite); cv.FrameRect(up, clBlack);
  cv.FillRect(dn, clWhite); cv.FrameRect(dn, clBlack);
  { arrow nubs }
  cv.FillRect(Rect(up.left + 5, up.top + 6, up.right - 5, up.top + 9), clDkGray);
  cv.FillRect(Rect(dn.left + 5, dn.bottom - 9, dn.right - 5, dn.bottom - 6), clDkGray);
  { thumb }
  cv.FillRect(thumb, clWhite);
  cv.FrameRect(thumb, clBlack);
end;

end.
