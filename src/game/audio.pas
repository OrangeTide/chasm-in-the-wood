unit audio;

{** Background music and sound effects.

  Modelled on the clumplump player. The vendored public-domain stb_vorbis decodes a
  whole OGG track into interleaved 16-bit samples, which are copied into a Pascal buffer
  and streamed to the device through one SDL audio stream. The music buffer is the loop,
  so a track authored to loop plays seamlessly. Each frame AudioUpdate tops the music
  stream up from the buffer, wrapping at the end, so looping needs no audio-thread
  callback.

  Sound effects play through a small pool of extra streams bound to the same device, so
  SDL mixes them over the music. A one-shot clip is decoded once, cached by path, and
  pushed whole into the next free voice; the voices round-robin, so a few effects overlap
  before the oldest is cut. Effects have their own volume.

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

{ Play a one-shot sound effect from the OGG at path, mixed over the music. A no-op if
  audio is disabled or the file is missing or will not decode. The clip is cached after
  the first play, so repeated effects do not touch the disk again. }
procedure AudioSfx(const path: String);

{ Set the sound-effect volume, 0..1, applied to effects played after it. }
procedure AudioSetSfxVolume(v: Single);

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

const
  SFX_VOICES = 8;   { overlapping one-shot effects before the oldest is cut }

type
  { A decoded one-shot effect, kept in the cache after its first play. }
  TSfxClip = record
    Path:     String;
    Pcm:      array of cint16;
    Channels: LongInt;
    Rate:     LongInt;
  end;

var
  gStream:   PSDL_AudioStream = nil;
  gOn:       Boolean = False;
  gPcm:      array of cint16;   { interleaved S16, the current track and its loop }
  gChannels: LongInt = 0;
  gRate:     LongInt = 0;
  gCursor:   LongInt = 0;       { next interleaved sample index to push }
  gCurPath:  String = '';
  gVolume:   Single = 1.0;
  gSfx:      array[0 .. SFX_VOICES - 1] of PSDL_AudioStream;
  gSfxNext:  LongInt = 0;
  gSfxVol:   Single = 1.0;
  gClips:    array of TSfxClip;

procedure AudioInit;
var
  spec: TSDL_AudioSpec;
  i: LongInt;
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
  { A pool of effect voices bound to the same device; SDL mixes them with the music. }
  for i := 0 to SFX_VOICES - 1 do begin
    gSfx[i] := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @spec, nil, nil);
    if gSfx[i] <> nil then SDL_ResumeAudioStreamDevice(gSfx[i]);
  end;
  gOn := True;
end;

function DecodeClip(const path: String; out clip: TSfxClip): Boolean;
{ Decode a whole OGG into interleaved S16. The caller owns the result. }
var
  ch, rate: cint;
  outp: PInt16;
  n, total: LongInt;
begin
  DecodeClip := False;
  clip.Path := path;
  clip.Channels := 0; clip.Rate := 0;
  SetLength(clip.Pcm, 0);
  ch := 0; rate := 0; outp := nil;
  n := stb_vorbis_decode_filename(PAnsiChar(path), @ch, @rate, @outp);
  if (n <= 0) or (outp = nil) then begin
    writeln(StdErr, 'audio: cannot decode ', path);
    if outp <> nil then cfree(outp);
    exit;
  end;
  total := n * ch;
  SetLength(clip.Pcm, total);
  if total > 0 then Move(outp^, clip.Pcm[0], total * SizeOf(cint16));
  cfree(outp);
  clip.Channels := ch;
  clip.Rate := rate;
  DecodeClip := True;
end;

function DecodeTrack(const path: String): Boolean;
var
  clip: TSfxClip;
begin
  DecodeTrack := False;
  if not DecodeClip(path, clip) then exit;
  gPcm := clip.Pcm;
  gChannels := clip.Channels;
  gRate := clip.Rate;
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

procedure AudioSetSfxVolume(v: Single);
begin
  if v < 0 then v := 0;
  if v > 1 then v := 1;
  gSfxVol := v;
end;

function ClipIndex(const path: String): LongInt;
{ The cache slot for a clip, decoding and caching it on first use, or -1 on failure. }
var
  i: LongInt;
  clip: TSfxClip;
begin
  for i := 0 to High(gClips) do
    if gClips[i].Path = path then exit(i);
  if not DecodeClip(path, clip) then exit(-1);
  i := Length(gClips);
  SetLength(gClips, i + 1);
  gClips[i] := clip;
  ClipIndex := i;
end;

procedure AudioSfx(const path: String);
var
  ci, v, bytes: LongInt;
  src: TSDL_AudioSpec;
begin
  if not gOn then exit;
  if (path = '') or (not FileExists(path)) then exit;
  ci := ClipIndex(path);
  if ci < 0 then exit;
  if Length(gClips[ci].Pcm) = 0 then exit;
  v := gSfxNext;
  gSfxNext := (gSfxNext + 1) mod SFX_VOICES;
  if gSfx[v] = nil then exit;
  { Point the voice at this clip's format, flush whatever it was playing, and push the
    whole clip for the device to drain once. }
  src.Format := cint(SDL_AUDIO_S16LE);
  src.Channels := gClips[ci].Channels;
  src.Freq := gClips[ci].Rate;
  SDL_SetAudioStreamFormat(gSfx[v], @src, nil);
  SDL_ClearAudioStream(gSfx[v]);
  SDL_SetAudioStreamGain(gSfx[v], gSfxVol);
  bytes := Length(gClips[ci].Pcm) * SizeOf(cint16);
  SDL_PutAudioStreamData(gSfx[v], @gClips[ci].Pcm[0], bytes);
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
var
  i: LongInt;
begin
  if gStream <> nil then SDL_DestroyAudioStream(gStream);
  gStream := nil;
  for i := 0 to SFX_VOICES - 1 do begin
    if gSfx[i] <> nil then SDL_DestroyAudioStream(gSfx[i]);
    gSfx[i] := nil;
  end;
  gOn := False;
  gCurPath := '';
  SetLength(gPcm, 0);
  SetLength(gClips, 0);
end;

end.
