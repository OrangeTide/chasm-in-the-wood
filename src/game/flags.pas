unit flags;
{ A set of named game flags. Quests gate their stages on flags, dialogue sets and     }
{ reads them, and the save persists them. A flag name is a short upper-case id such    }
{ as QUEST_MAIN or SHARD_CRYPT. This holds state only; the quest layer gives the        }
{ flags meaning. The set never holds duplicates and its order is the order flags were   }
{ first set, which the save round-trips.                                                }

{$mode objfpc}{$H+}

interface

type
  TFlagSet = record
    Names: array of String;
  end;

{ Empty the set. }
procedure FlagClearAll(out fs: TFlagSet);

{ True when the flag is set. }
function FlagTest(const fs: TFlagSet; const name: String): Boolean;

{ Set the flag. Returns True when it was newly added, False when already set or empty. }
function FlagSet(var fs: TFlagSet; const name: String): Boolean;

{ The number of set flags, and the i-th flag name, for saving and restoring. }
function FlagCount(const fs: TFlagSet): LongInt;
function FlagName(const fs: TFlagSet; i: LongInt): String;

implementation

procedure FlagClearAll(out fs: TFlagSet);
begin
  SetLength(fs.Names, 0);
end;

function FlagTest(const fs: TFlagSet; const name: String): Boolean;
var
  i: LongInt;
begin
  for i := 0 to High(fs.Names) do
    if fs.Names[i] = name then exit(True);
  FlagTest := False;
end;

function FlagSet(var fs: TFlagSet; const name: String): Boolean;
var
  k: LongInt;
begin
  if (name = '') or FlagTest(fs, name) then exit(False);
  k := Length(fs.Names);
  SetLength(fs.Names, k + 1);
  fs.Names[k] := name;
  FlagSet := True;
end;

function FlagCount(const fs: TFlagSet): LongInt;
begin
  FlagCount := Length(fs.Names);
end;

function FlagName(const fs: TFlagSet; i: LongInt): String;
begin
  if (i >= 0) and (i <= High(fs.Names)) then
    FlagName := fs.Names[i]
  else
    FlagName := '';
end;

end.
