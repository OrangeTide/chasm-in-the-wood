unit sdl3;

{** Minimal SDL3 binding.

  Only the entry points the engine actually calls are declared here: window and
  GL-context creation, the event pump, timing, and the GL proc-address loader
  that feeds glcore. This keeps the surface small and avoids a large vendored
  binding. SDL3 is linked at build time; override the search path with -Fl if
  libSDL3 lives outside the linker's default path. }

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes;

type
  PSDL_Window  = Pointer;
  TSDL_GLContext = Pointer;
  PSDL_AudioStream = Pointer;

  TSDL_AudioSpec = record
    Format:   cint;    { an SDL_AudioFormat, e.g. SDL_AUDIO_S16LE }
    Channels: cint;
    Freq:     cint;
  end;
  PSDL_AudioSpec = ^TSDL_AudioSpec;

  { SDL_Event is a 128-Byte union. We read its leading type word, and for key
    presses the scancode, and ignore the rest. The record is laid out to match
    SDL_KeyboardEvent up to the scancode field. }
  TSDL_KeyboardEvent = packed record
    Etype:     cuint32;
    Reserved:  cuint32;
    Timestamp: cuint64;
    WindowID:  cuint32;
    Which:     cuint32;
    Scancode:  cuint32;
    Key:       cuint32;
  end;

  { SDL3 reports mouse positions as floats in window coordinates. The layouts match
    SDL_MouseButtonEvent, SDL_MouseMotionEvent, and SDL_MouseWheelEvent. }
  TSDL_MouseButtonEvent = packed record
    Etype:     cuint32;
    Reserved:  cuint32;
    Timestamp: cuint64;
    WindowID:  cuint32;
    Which:     cuint32;
    Button:    cuint8;
    Down:      cuint8;
    Clicks:    cuint8;
    Padding:   cuint8;
    X, Y:      cfloat;
  end;

  TSDL_MouseMotionEvent = packed record
    Etype:     cuint32;
    Reserved:  cuint32;
    Timestamp: cuint64;
    WindowID:  cuint32;
    Which:     cuint32;
    State:     cuint32;
    X, Y:      cfloat;
    Xrel, Yrel: cfloat;
  end;

  TSDL_MouseWheelEvent = packed record
    Etype:     cuint32;
    Reserved:  cuint32;
    Timestamp: cuint64;
    WindowID:  cuint32;
    Which:     cuint32;
    Direction: cuint32;
    X, Y:      cfloat;
    MouseX, MouseY: cfloat;
  end;

  TSDL_Event = record
    case LongInt of
      0: (Etype: cuint32);
      1: (Key: TSDL_KeyboardEvent);
      2: (Button: TSDL_MouseButtonEvent);
      3: (Motion: TSDL_MouseMotionEvent);
      4: (Wheel: TSDL_MouseWheelEvent);
      5: (Padding: array[0..127] of Byte);
  end;

  PSDL_Event = ^TSDL_Event;

  TGLGetProc = function(const proc: PAnsiChar): Pointer; cdecl;

const
  SDL_INIT_AUDIO = cuint32($00000010);
  SDL_INIT_VIDEO = cuint32($00000020);

  SDL_AUDIO_S16LE = cuint32($8010);   { signed 16-bit little-endian PCM }
  SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK = cuint32($FFFFFFFF);

  SDL_WINDOW_OPENGL    = cuint64($0000000000000002);
  SDL_WINDOW_RESIZABLE = cuint64($0000000000000020);

  { SDL_GLAttr values (0-based enum order from SDL_video.H). }
  SDL_GL_DOUBLEBUFFER         = 5;
  SDL_GL_DEPTH_SIZE           = 6;
  SDL_GL_CONTEXT_MAJOR_VERSION = 17;
  SDL_GL_CONTEXT_MINOR_VERSION = 18;
  SDL_GL_CONTEXT_PROFILE_MASK  = 20;
  SDL_GL_CONTEXT_PROFILE_CORE  = $0001;

  SDL_EVENT_QUIT     = $100;
  SDL_EVENT_KEY_DOWN = $300;
  SDL_EVENT_KEY_UP   = $301;

  SDL_EVENT_MOUSE_MOTION      = $400;
  SDL_EVENT_MOUSE_BUTTON_DOWN = $401;
  SDL_EVENT_MOUSE_BUTTON_UP   = $402;
  SDL_EVENT_MOUSE_WHEEL       = $403;

  SDL_BUTTON_LEFT   = 1;
  SDL_BUTTON_MIDDLE = 2;
  SDL_BUTTON_RIGHT  = 3;

  SDL_SCANCODE_RETURN = 40;
  SDL_SCANCODE_ESCAPE = 41;
  SDL_SCANCODE_SPACE  = 44;
  SDL_SCANCODE_A = 4;
  SDL_SCANCODE_C = 6;
  SDL_SCANCODE_D = 7;
  SDL_SCANCODE_E = 8;
  SDL_SCANCODE_I = 12;
  SDL_SCANCODE_O = 18;
  SDL_SCANCODE_Q = 20;
  SDL_SCANCODE_R = 21;
  SDL_SCANCODE_S = 22;
  SDL_SCANCODE_W = 26;
  SDL_SCANCODE_MINUS  = 45;
  SDL_SCANCODE_EQUALS = 46;
  SDL_SCANCODE_F5 = 62;
  SDL_SCANCODE_F9 = 66;
  SDL_SCANCODE_RIGHT = 79;
  SDL_SCANCODE_LEFT  = 80;
  SDL_SCANCODE_DOWN  = 81;
  SDL_SCANCODE_UP    = 82;

function SDL_Init(flags: cuint32): ByteBool; cdecl; external 'SDL3';
function SDL_InitSubSystem(flags: cuint32): ByteBool; cdecl; external 'SDL3';
procedure SDL_Quit; cdecl; external 'SDL3';
function SDL_GetError: PAnsiChar; cdecl; external 'SDL3';
function SDL_GetTicks: cuint64; cdecl; external 'SDL3';

function SDL_CreateWindow(const title: PAnsiChar; w, h: cint;
  flags: cuint64): PSDL_Window; cdecl; external 'SDL3';
procedure SDL_DestroyWindow(window: PSDL_Window); cdecl; external 'SDL3';

function SDL_PollEvent(event: PSDL_Event): ByteBool; cdecl; external 'SDL3';

function SDL_GL_SetAttribute(attr, value: cint): ByteBool; cdecl; external 'SDL3';
function SDL_GL_CreateContext(window: PSDL_Window): TSDL_GLContext; cdecl; external 'SDL3';
function SDL_GL_DestroyContext(context: TSDL_GLContext): ByteBool; cdecl; external 'SDL3';
function SDL_GL_MakeCurrent(window: PSDL_Window; context: TSDL_GLContext): ByteBool; cdecl; external 'SDL3';
function SDL_GL_SetSwapInterval(interval: cint): ByteBool; cdecl; external 'SDL3';
function SDL_GL_SwapWindow(window: PSDL_Window): ByteBool; cdecl; external 'SDL3';
function SDL_GL_GetProcAddress(const proc: PAnsiChar): Pointer; cdecl; external 'SDL3';

{ ---- audio ---- }
function SDL_OpenAudioDeviceStream(devid: cuint32; const spec: PSDL_AudioSpec;
  callback: Pointer; userdata: Pointer): PSDL_AudioStream; cdecl; external 'SDL3';
function SDL_ResumeAudioStreamDevice(stream: PSDL_AudioStream): ByteBool; cdecl; external 'SDL3';
function SDL_PauseAudioStreamDevice(stream: PSDL_AudioStream): ByteBool; cdecl; external 'SDL3';
function SDL_PutAudioStreamData(stream: PSDL_AudioStream; const buf: Pointer;
  len: cint): ByteBool; cdecl; external 'SDL3';
function SDL_GetAudioStreamQueued(stream: PSDL_AudioStream): cint; cdecl; external 'SDL3';
function SDL_SetAudioStreamFormat(stream: PSDL_AudioStream;
  const src_spec, dst_spec: PSDL_AudioSpec): ByteBool; cdecl; external 'SDL3';
function SDL_ClearAudioStream(stream: PSDL_AudioStream): ByteBool; cdecl; external 'SDL3';
function SDL_SetAudioStreamGain(stream: PSDL_AudioStream; gain: cfloat): ByteBool; cdecl; external 'SDL3';
procedure SDL_DestroyAudioStream(stream: PSDL_AudioStream); cdecl; external 'SDL3';

implementation

end.
