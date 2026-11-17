unit uitext;
{ A runtime table of the game's user-visible text, loaded from a plain file so the         }
{ wording of names, titles, menus, dialogue, and messages lives in content rather than     }
{ the sources. Each line is 'str <key> "<value>"'; blank and '#' lines are skipped. A       }
{ value may hold Format placeholders (%s, %d) for a caller to fill, and a '|' separates     }
{ the lines of a multi-line value. A missing key returns '[key]', so a gap shows up in      }
{ play rather than passing silently. This holds presentation text only; identifiers,        }
{ error output, and debug logging stay in the code.                                         }

{$mode objfpc}{$H+}

interface

uses
  sysutils;

type
  TUIStrArray = array of String;

{ Load the string table from path, replacing any table already held. False when the file
  is missing or unreadable; whatever loaded before a failure is kept. }
function UIStrLoad(const path: String): Boolean;

{ The value for key, or '[key]' when the table has no such entry. }
function UIStr(const key: String): String;

{ UIStr(key) with the Format placeholders filled from args. }
function UIStrFmt(const key: String; const args: array of const): String;

{ UIStr(key) split into its '|'-separated lines. }
function UIStrList(const key: String): TUIStrArray;

implementation

uses
  classes;

type
  TEntry = record
    Key, Val: String;
  end;

var
  gTab: array of TEntry;
  gN: LongInt;

function UIStr(const key: String): String;
var
  i: LongInt;
begin
  for i := 0 to gN - 1 do
    if gTab[i].Key = key then exit(gTab[i].Val);
  UIStr := '[' + key + ']';
end;

function UIStrFmt(const key: String; const args: array of const): String;
begin
  UIStrFmt := Format(UIStr(key), args);
end;

function UIStrList(const key: String): TUIStrArray;
var
  s: String;
  n, p: LongInt;
begin
  UIStrList := nil;
  s := UIStr(key);
  n := 0;
  { Split on '|' into successive lines, keeping empty ones so spacing is preserved. }
  repeat
    p := Pos('|', s);
    SetLength(UIStrList, n + 1);
    if p = 0 then begin
      UIStrList[n] := s;
      s := '';
    end else begin
      UIStrList[n] := Copy(s, 1, p - 1);
      s := Copy(s, p + 1, Length(s));
    end;
    Inc(n);
  until (p = 0);
end;

procedure Put(const key, val: String);
var
  i: LongInt;
begin
  for i := 0 to gN - 1 do
    if gTab[i].Key = key then begin gTab[i].Val := val; exit; end;
  if gN >= Length(gTab) then SetLength(gTab, (gN + 1) * 2);
  gTab[gN].Key := key; gTab[gN].Val := val;
  Inc(gN);
end;

function ParseLine(const line: String): Boolean;
{ A 'str <key> "<value>"' row. The value is whatever sits between the first and last
  double quote, so it may hold spaces, '%' placeholders, and '|' separators. }
var
  s, key: String;
  i, q1, q2: LongInt;
begin
  ParseLine := False;
  s := Trim(line);
  if (s = '') or (s[1] = '#') then exit;
  if Copy(s, 1, 4) <> 'str ' then exit;
  s := Trim(Copy(s, 5, Length(s)));
  { The key runs to the next space. }
  i := Pos(' ', s);
  if i = 0 then exit;
  key := Copy(s, 1, i - 1);
  q1 := Pos('"', s);
  if q1 = 0 then exit;
  q2 := Length(s);
  while (q2 > q1) and (s[q2] <> '"') do Dec(q2);
  if q2 <= q1 then exit;
  Put(key, Copy(s, q1 + 1, q2 - q1 - 1));
  ParseLine := True;
end;

function UIStrLoad(const path: String): Boolean;
var
  f: TextFile;
  line: String;
begin
  UIStrLoad := False;
  if not FileExists(path) then exit;
  AssignFile(f, path);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then exit;
  try
    while not Eof(f) do begin
      ReadLn(f, line);
      ParseLine(line);
    end;
  finally
    CloseFile(f);
  end;
  UIStrLoad := True;
end;

end.
