unit datadir;

{** Resolve a content path against the game's data directory.

  Every data file the game loads lives under content/. The binary may run from
  three places, and the data sits differently in each:

    - the source tree, with content/ in the working directory (development);
    - a self-contained directory, with content/ beside the binary (a portable
      copy or the macOS bundle's Resources);
    - an install, with the binary in <prefix>/bin and the data in
      <prefix>/share/chasm/content.

  A menu launcher sets no useful working directory, so the game cannot assume it
  was started from its data. This unit finds the data root once, relative to the
  running executable, and resolves every content path against it.

  Search order, the first whose content/ exists wins:
    1. $CHASM_DATA, if set: a data root holding content/ (an explicit override).
    2. The directory holding the executable: content/ beside the binary.
    3. <exedir>/../share/chasm: the install layout.
    4. <exedir>/../Resources: the macOS bundle layout.
    5. The working directory: running from the source tree.

  If none of 1..4 has a content/, the path is returned unchanged, so the game
  behaves as before when run from the source tree and a loader still reports its
  own missing-file error against the working directory. }

{$mode objfpc}{$H+}

interface

{ Resolve a relative content path (for example 'content/strings.txt') to the
  path the game should open. The argument begins with 'content'. }
function DataPath(const rel: String): String;

implementation

uses SysUtils {$ifdef unix}, BaseUnix{$endif};

var
  { The chosen data root with a trailing path delimiter, or '' to mean the
    working directory (paths pass through unchanged). Resolved once. }
  gRoot: String;
  gResolved: Boolean = False;

{ The directory holding the running executable, with a trailing delimiter. On
  Linux /proc/self/exe is the real path even when launched by a bare name
  through PATH, which argv[0] is not. }
function ExeDir: String;
{$ifdef linux}
var
  link: String;
{$endif}
begin
{$ifdef linux}
  link := fpReadLink('/proc/self/exe');
  if link <> '' then
    Exit(IncludeTrailingPathDelimiter(ExtractFileDir(link)));
{$endif}
  ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))));
end;

{ True when base (trailing delimiter included) holds a content/ directory. }
function HasContent(const base: String): Boolean;
begin
  HasContent := DirectoryExists(base + 'content');
end;

procedure Resolve;
var
  env, exe, cand: String;
begin
  gResolved := True;
  gRoot := '';

  env := GetEnvironmentVariable('CHASM_DATA');
  if env <> '' then begin
    env := IncludeTrailingPathDelimiter(env);
    if HasContent(env) then begin gRoot := env; Exit; end;
  end;

  exe := ExeDir;
  if HasContent(exe) then begin gRoot := exe; Exit; end;

  cand := IncludeTrailingPathDelimiter(
            ExpandFileName(exe + '..' + PathDelim + 'share' + PathDelim + 'chasm'));
  if HasContent(cand) then begin gRoot := cand; Exit; end;

  cand := IncludeTrailingPathDelimiter(
            ExpandFileName(exe + '..' + PathDelim + 'Resources'));
  if HasContent(cand) then begin gRoot := cand; Exit; end;

  { None found: fall through with gRoot '' so paths resolve against the cwd. }
end;

function DataPath(const rel: String): String;
begin
  if not gResolved then Resolve;
  DataPath := gRoot + rel;
end;

end.
