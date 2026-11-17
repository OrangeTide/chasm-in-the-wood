unit audio;

{** Background music: decode an OGG Vorbis track once and loop it.

  Modelled on the clumplump player. The vendored public-domain stb_vorbis decodes a
  whole track into interleaved 16-bit samples, which are copied into a Pascal buffer
  and streamed to the device through one SDL audio stream. The buffer is the loop, so a
  track authored to loop plays seamlessly. Each frame AudioUpdate tops the stream up
  from the buffer, wrapping at the end, so looping needs no audio-thread callback.

  Audio is optional: if the device or a track cannot be opened the unit goes quiet and
  every call is a no-op, so a headless or silent run is unaffected. }

{$mode objfpc}{$H+}

interface

{ Bring up the audio device. Safe to call once; a failure leaves audio disabled. }
procedure AudioInit;

{ Loop the OGG track at path as the background music. A no-op if it is already the
  current track, if audio is disabled, or if the file is missing or will not decode. }
procedure AudioPlay(const path: String);

{ Silence the music channel. }
procedure AudioStop;

{ Set the music volume, 0..1, applied live. }
procedure AudioSetVolume(v: Single);

{ Feed the stream from the loop buffer; call once per frame. }
procedure AudioUpdate;

{ Close the device and free the track. }
procedure AudioShutdown;

implementation

uses
  sdl3, ctypes, sysutils;

{$L stbvorbis.o}
{$LINKLIB m}
{$LINKLIB c}

type
  PInt16  = ^cint16;
  PPInt16 = ^PInt16;

{ int stb_vorbis_decode_filename(const char*, int* channels, int* rate, short** out);
  returns the number of sample frames, or <= 0 on failure. }
function stb_vorbis_decode_filename(filename: PAnsiChar;
  channels, sample_rate: pcint; output: PPInt16): cint; cdecl;
  external name 'stb_vorbis_decode_filename';
procedure cfree(p: Pointer); cdecl; external name 'free';

var
  gStream:   PSDL_AudioStream = nil;
  gOn:       Boolean = False;
  gPcm:      array of cint16;   { interleaved S16, the current track and its loop }
  gChannels: LongInt = 0;
  gRate:     LongInt = 0;
  gCursor:   LongInt = 0;       { next interleaved sample index to push }
  gCurPath:  String = '';
  gVolume:   Single = 1.0;

procedure AudioInit;
var
  spec: TSDL_AudioSpec;
begin
  if gOn then exit;
  if not SDL_InitSubSystem(SDL_INIT_AUDIO) then begin
    writeln(StdErr, 'audio: no audio subsystem: ', SDL_GetError);
    exit;
  end;
  spec.Format := cint(SDL_AUDIO_S16LE);
  spec.Channels := 2;
  spec.Freq := 44100;
  gStream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @spec, nil, nil);
  if gStream = nil then begin
    writeln(StdErr, 'audio: no device: ', SDL_GetError);
    exit;
  end;
  SDL_ResumeAudioStreamDevice(gStream);
  gOn := True;
end;

function DecodeTrack(const path: String): Boolean;
var
  ch, rate: cint;
  outp: PInt16;
  n, total: LongInt;
begin
  DecodeTrack := False;
  ch := 0; rate := 0; outp := nil;
  n := stb_vorbis_decode_filename(PAnsiChar(path), @ch, @rate, @outp);
  if (n <= 0) or (outp = nil) then begin
    writeln(StdErr, 'audio: cannot decode ', path);
    if outp <> nil then cfree(outp);
    exit;
  end;
  total := n * ch;
  SetLength(gPcm, total);
  if total > 0 then Move(outp^, gPcm[0], total * SizeOf(cint16));
  cfree(outp);
  gChannels := ch;
  gRate := rate;
  gCursor := 0;
  DecodeTrack := True;
end;

procedure AudioPlay(const path: String);
var
  src: TSDL_AudioSpec;
begin
  if not gOn then exit;
  if path = gCurPath then exit;
  if not FileExists(path) then begin AudioStop; exit; end;
  if not DecodeTrack(path) then begin AudioStop; exit; end;

  src.Format := cint(SDL_AUDIO_S16LE);
  src.Channels := gChannels;
  src.Freq := gRate;
  SDL_SetAudioStreamFormat(gStream, @src, nil);
  SDL_ClearAudioStream(gStream);
  gCurPath := path;
  SDL_SetAudioStreamGain(gStream, gVolume);
  AudioUpdate;
end;

procedure AudioStop;
begin
  gCurPath := '';
  SetLength(gPcm, 0);
  if gOn then SDL_ClearAudioStream(gStream);
end;

procedure AudioSetVolume(v: Single);
begin
  if v < 0 then v := 0;
  if v > 1 then v := 1;
  gVolume := v;
  if gOn then SDL_SetAudioStreamGain(gStream, gVolume);
end;

procedure AudioUpdate;
var
  target, pushN, bytes: LongInt;
begin
  if (not gOn) or (gCurPath = '') or (Length(gPcm) = 0) then exit;
  { Keep about half a second queued; push in chunks, wrapping to loop. }
  target := gRate * gChannels;   { one second of interleaved samples }
  if target < 1 then exit;
  while SDL_GetAudioStreamQueued(gStream) < (target * SizeOf(cint16)) div 2 do begin
    pushN := gRate div 10 * gChannels;   { a tenth of a second }
    if gCursor + pushN > Length(gPcm) then pushN := Length(gPcm) - gCursor;
    if pushN <= 0 then begin gCursor := 0; continue; end;
    bytes := pushN * SizeOf(cint16);
    SDL_PutAudioStreamData(gStream, @gPcm[gCursor], bytes);
    Inc(gCursor, pushN);
    if gCursor >= Length(gPcm) then gCursor := 0;
  end;
end;

procedure AudioShutdown;
begin
  if gStream <> nil then SDL_DestroyAudioStream(gStream);
  gStream := nil;
  gOn := False;
  gCurPath := '';
  SetLength(gPcm, 0);
end;

end.
