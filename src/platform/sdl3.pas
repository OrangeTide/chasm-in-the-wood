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

  { SDL_Event is a 128-byte union. We read its leading type word, and for key
    presses the scancode, and ignore the rest. The record is laid out to match
    SDL_KeyboardEvent up to the scancode field. }
  TSDL_KeyboardEvent = packed record
    etype:     cuint32;
    reserved:  cuint32;
    timestamp: cuint64;
    windowID:  cuint32;
    which:     cuint32;
    scancode:  cuint32;
    key:       cuint32;
  end;

  TSDL_Event = record
    case longint of
      0: (etype: cuint32);
      1: (key: TSDL_KeyboardEvent);
      2: (padding: array[0..127] of byte);
  end;

  PSDL_Event = ^TSDL_Event;

  TGLGetProc = function(const proc: PAnsiChar): Pointer; cdecl;

const
  SDL_INIT_VIDEO = cuint32($00000020);

  SDL_WINDOW_OPENGL    = cuint64($0000000000000002);
  SDL_WINDOW_RESIZABLE = cuint64($0000000000000020);

  { SDL_GLAttr values (0-based enum order from SDL_video.h). }
  SDL_GL_DOUBLEBUFFER         = 5;
  SDL_GL_DEPTH_SIZE           = 6;
  SDL_GL_CONTEXT_MAJOR_VERSION = 17;
  SDL_GL_CONTEXT_MINOR_VERSION = 18;
  SDL_GL_CONTEXT_PROFILE_MASK  = 20;
  SDL_GL_CONTEXT_PROFILE_CORE  = $0001;

  SDL_EVENT_QUIT     = $100;
  SDL_EVENT_KEY_DOWN = $300;

  SDL_SCANCODE_RETURN = 40;
  SDL_SCANCODE_ESCAPE = 41;
  SDL_SCANCODE_A = 4;
  SDL_SCANCODE_D = 7;
  SDL_SCANCODE_E = 8;
  SDL_SCANCODE_Q = 20;
  SDL_SCANCODE_S = 22;
  SDL_SCANCODE_W = 26;
  SDL_SCANCODE_MINUS  = 45;
  SDL_SCANCODE_EQUALS = 46;
  SDL_SCANCODE_RIGHT = 79;
  SDL_SCANCODE_LEFT  = 80;
  SDL_SCANCODE_DOWN  = 81;
  SDL_SCANCODE_UP    = 82;

function SDL_Init(flags: cuint32): bytebool; cdecl; external 'SDL3';
procedure SDL_Quit; cdecl; external 'SDL3';
function SDL_GetError: PAnsiChar; cdecl; external 'SDL3';
function SDL_GetTicks: cuint64; cdecl; external 'SDL3';

function SDL_CreateWindow(const title: PAnsiChar; w, h: cint;
  flags: cuint64): PSDL_Window; cdecl; external 'SDL3';
procedure SDL_DestroyWindow(window: PSDL_Window); cdecl; external 'SDL3';

function SDL_PollEvent(event: PSDL_Event): bytebool; cdecl; external 'SDL3';

function SDL_GL_SetAttribute(attr, value: cint): bytebool; cdecl; external 'SDL3';
function SDL_GL_CreateContext(window: PSDL_Window): TSDL_GLContext; cdecl; external 'SDL3';
function SDL_GL_DestroyContext(context: TSDL_GLContext): bytebool; cdecl; external 'SDL3';
function SDL_GL_MakeCurrent(window: PSDL_Window; context: TSDL_GLContext): bytebool; cdecl; external 'SDL3';
function SDL_GL_SetSwapInterval(interval: cint): bytebool; cdecl; external 'SDL3';
function SDL_GL_SwapWindow(window: PSDL_Window): bytebool; cdecl; external 'SDL3';
function SDL_GL_GetProcAddress(const proc: PAnsiChar): Pointer; cdecl; external 'SDL3';

implementation

end.
