unit sfx;

{** A thin indirection for sound effects.

  Gameplay fires effects by naming a file, through this unit, without depending on the
  audio backend (and so without pulling SDL and the vorbis decoder into the GL-free unit
  tests). The main program points SfxHook at the audio unit; when nothing is wired, as in
  the tests, the calls are silent. }

{$mode objfpc}{$H+}

interface

type
  TSfxProc = procedure(const path: String);

var
  { Set by the main program to the audio backend; left nil elsewhere. }
  SfxHook: TSfxProc = nil;

{ Play the sound effect at path, if a backend is wired. }
procedure PlaySfx(const path: String);

implementation

procedure PlaySfx(const path: String);
begin
  if Assigned(SfxHook) then SfxHook(path);
end;

end.
