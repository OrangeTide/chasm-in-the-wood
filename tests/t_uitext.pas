program t_uitext;

{** Tests the runtime string table: it loads from the file, returns a value by key, marks
  a missing key visibly, fills Format placeholders, and splits a multi-line value on its
  '|' separators, keeping empty lines. GL-free. }

{$mode objfpc}{$H+}

uses
  uitext;

var
  fails: LongInt;

procedure Check(cond: Boolean; const msg: String);
begin
  if not cond then begin writeln('  FAIL: ', msg); Inc(fails); end;
end;

var
  body: TUIStrArray;
begin
  fails := 0;
  Check(UIStrLoad('content/strings.txt'), 'the string table loads');

  { A plain lookup returns the file's value. }
  Check(UIStr('win_status') = 'STATUS', 'a key returns its value');

  { A missing key is marked, not silently empty, so a gap shows in play. }
  Check(UIStr('no_such_key') = '[no_such_key]', 'a missing key is bracketed');

  { Format placeholders are filled from the arguments. }
  Check(UIStrFmt('msg_hit', ['Rat', 5]) = 'You hit Rat for 5.',
        'placeholders fill from args');
  Check(UIStrFmt('msg_quaff', [10]) = 'You drink a potion. (+10)',
        'a single number placeholder fills');

  { A '|' value splits into lines, and an empty run ('||') keeps a blank line. }
  body := UIStrList('menu_death_body');
  Check(Length(body) = 3, 'the death body is three lines');
  Check(body[0] = 'The dark takes you.', 'the first death line is intact');

  body := UIStrList('menu_title_body');
  Check(Length(body) = 5, 'the title body is five lines');
  Check(body[2] = '', 'a double separator keeps an empty line');

  { A value with no separator is a single line. }
  body := UIStrList('win_status');
  Check((Length(body) = 1) and (body[0] = 'STATUS'), 'a plain value is one line');

  if fails = 0 then writeln('  ok')
  else begin writeln('  ', fails, ' FAILURES'); Halt(1); end;
end.
