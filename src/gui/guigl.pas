unit guigl;
{ The OpenGL canvas: a concrete TCanvas for the toolkit, drawn as a 2D overlay. }
{ Every primitive, text included, is a solid-coloured screen-space rectangle, so }
{ the canvas batches rectangles into one orthographic, alpha-blended pass and     }
{ clips with the scissor box. It carries a small embedded bitmap font.            }

{$mode objfpc}{$H+}

interface

uses
  glcore, gui, cfnfont;

type
  TGLCanvas = class(TCanvas)
  private
    FProg: GLuint;
    FUViewport: GLint;
    FVao, FVbo: GLuint;
    FVerts: array of GLfloat;   { 6 floats per vertex: x, y, r, g, b, a }
    FNverts: LongInt;
    FVw, FVh: LongInt;
    FScale: LongInt;
    FFont: TCfnFont;   { the active font, built-in or loaded from a CFN file }
    procedure PushVertex(x, y: LongInt; r, g, b, a: GLfloat);
    procedure PushQuad(x0, y0, x1, y1: LongInt; c: TColor);
    procedure Flush;
    procedure UseBuiltinFont;
  public
    constructor Create(viewW, viewH: LongInt);
    destructor Destroy; override;
    procedure Resize(viewW, viewH: LongInt);
    procedure BeginFrame;    { set 2D GL state and start a batch }
    procedure EndFrame;      { draw the batch and restore 3D GL state }

    { Replace the active font from a CFN blob in memory. Returns False and keeps }
    { the current font if the blob is malformed. }
    function LoadFont(const data; len: LongInt): Boolean;

    procedure SetClip(const r: TRect); override;
    procedure ClearClip; override;
    procedure FillRect(const r: TRect; c: TColor); override;
    procedure FrameRect(const r: TRect; c: TColor); override;
    procedure HLine(x1, x2, y: LongInt; c: TColor); override;
    procedure VLine(x, y1, y2: LongInt; c: TColor); override;
    procedure DrawText(x, y: LongInt; const s: String; c: TColor); override;
    function  TextWidth(const s: String): LongInt; override;
    function  TextHeight: LongInt; override;
  end;

implementation

{ ---- Built-in Solid Frame proportional bitmap font, codes 32..126 ---- }
{ Baked from the Solid Frame TTF at pixel size 9. This is the default face   }
{ copied into the runtime font tables at construction; a CFN file loaded     }
{ through LoadFont replaces it. Each glyph is a cell of FontCellH rows;       }
{ FontAdv gives the per-glyph advance in font pixels, so the face is          }
{ proportional. In a FontBits row, bit 7 is the leftmost column.             }
const
  FontLo    = 32;
  FontHi    = 126;
  FontCellH = 9;   { pixel rows per glyph cell }
  FontAsc   = 7;   { baseline row from top of cell }

  FontAdv: array[FontLo..FontHi] of Byte = (
    8,  {  32 ' ' }
    3,  {  33 '!' }
    7,  {  34 '"' }
    8,  {  35 '#' }
    7,  {  36 '$' }
    7,  {  37 '%' }
    7,  {  38 '&' }
    4,  {  39  }
    4,  {  40 '(' }
    4,  {  41 ')' }
    7,  {  42 '*' }
    7,  {  43 '+' }
    4,  {  44 ',' }
    7,  {  45 '-' }
    3,  {  46 '.' }
    7,  {  47 '/' }
    7,  {  48 '0' }
    7,  {  49 '1' }
    7,  {  50 '2' }
    7,  {  51 '3' }
    7,  {  52 '4' }
    7,  {  53 '5' }
    7,  {  54 '6' }
    7,  {  55 '7' }
    7,  {  56 '8' }
    7,  {  57 '9' }
    3,  {  58 ':' }
    4,  {  59 ';' }
    5,  {  60 '<' }
    7,  {  61 '=' }
    5,  {  62 '>' }
    7,  {  63 '?' }
    7,  {  64 '@' }
    7,  {  65 'A' }
    7,  {  66 'B' }
    7,  {  67 'C' }
    7,  {  68 'D' }
    7,  {  69 'E' }
    7,  {  70 'F' }
    7,  {  71 'G' }
    7,  {  72 'H' }
    7,  {  73 'I' }
    7,  {  74 'J' }
    7,  {  75 'K' }
    7,  {  76 'L' }
    7,  {  77 'M' }
    7,  {  78 'N' }
    7,  {  79 'O' }
    7,  {  80 'P' }
    7,  {  81 'Q' }
    7,  {  82 'R' }
    7,  {  83 'S' }
    7,  {  84 'T' }
    7,  {  85 'U' }
    7,  {  86 'V' }
    7,  {  87 'W' }
    7,  {  88 'X' }
    7,  {  89 'Y' }
    7,  {  90 'Z' }
    7,  {  91 '[' }
    7,  {  92  }
    7,  {  93 ']' }
    7,  {  94 '^' }
    7,  {  95 '_' }
    4,  {  96 '`' }
    7,  {  97 'a' }
    7,  {  98 'b' }
    7,  {  99 'c' }
    7,  { 100 'd' }
    7,  { 101 'e' }
    7,  { 102 'f' }
    7,  { 103 'g' }
    7,  { 104 'h' }
    3,  { 105 'i' }
    4,  { 106 'j' }
    7,  { 107 'k' }
    3,  { 108 'l' }
    7,  { 109 'm' }
    7,  { 110 'n' }
    7,  { 111 'o' }
    7,  { 112 'p' }
    7,  { 113 'q' }
    7,  { 114 'r' }
    7,  { 115 's' }
    7,  { 116 't' }
    7,  { 117 'u' }
    7,  { 118 'v' }
    7,  { 119 'w' }
    7,  { 120 'x' }
    7,  { 121 'y' }
    7,  { 122 'z' }
    5,  { 123 lbrace }
    3,  { 124 bar }
    5,  { 125 rbrace }
    7   { 126 '~' }
  );

  { bit 7 = leftmost column; draw column j when (b and (128 shr j)) <> 0 }
  FontBits: array[FontLo..FontHi, 0..FontCellH-1] of Byte = (
    ($00,$00,$00,$00,$00,$00,$00,$00,$00),
    ($C0,$C0,$C0,$C0,$C0,$00,$C0,$00,$00),
    ($6C,$D8,$00,$00,$00,$00,$00,$00,$00),
    ($00,$6C,$FE,$6C,$FE,$6C,$00,$00,$00),
    ($30,$7C,$B0,$78,$34,$F8,$30,$00,$00),
    ($00,$E4,$A8,$D0,$2C,$54,$9C,$00,$00),
    ($70,$D8,$D8,$74,$D8,$DC,$74,$00,$00),
    ($60,$C0,$00,$00,$00,$00,$00,$00,$00),
    ($60,$C0,$C0,$C0,$C0,$C0,$60,$00,$00),
    ($C0,$60,$60,$60,$60,$60,$C0,$00,$00),
    ($00,$CC,$78,$FC,$78,$CC,$00,$00,$00),
    ($00,$30,$30,$FC,$30,$30,$00,$00,$00),
    ($00,$00,$00,$00,$00,$60,$C0,$00,$00),
    ($00,$00,$00,$FC,$00,$00,$00,$00,$00),
    ($00,$00,$00,$00,$00,$C0,$C0,$00,$00),
    ($18,$18,$30,$30,$30,$60,$60,$00,$00),
    ($78,$CC,$EC,$DC,$CC,$CC,$78,$00,$00),
    ($30,$F0,$30,$30,$30,$30,$FC,$00,$00),
    ($78,$CC,$0C,$18,$30,$60,$FC,$00,$00),
    ($78,$CC,$0C,$38,$0C,$CC,$78,$00,$00),
    ($1C,$3C,$6C,$CC,$FC,$0C,$0C,$00,$00),
    ($FC,$C0,$C0,$FC,$0C,$CC,$78,$00,$00),
    ($78,$CC,$C0,$F8,$CC,$CC,$78,$00,$00),
    ($FC,$0C,$18,$30,$30,$30,$30,$00,$00),
    ($78,$CC,$CC,$78,$CC,$CC,$78,$00,$00),
    ($78,$CC,$CC,$7C,$0C,$CC,$78,$00,$00),
    ($00,$00,$C0,$C0,$00,$C0,$C0,$00,$00),
    ($00,$00,$60,$60,$00,$60,$C0,$00,$00),
    ($10,$30,$60,$C0,$60,$30,$10,$00,$00),
    ($00,$00,$FC,$00,$FC,$00,$00,$00,$00),
    ($80,$C0,$60,$30,$60,$C0,$80,$00,$00),
    ($78,$CC,$0C,$18,$30,$00,$30,$00,$00),
    ($78,$84,$74,$DC,$D8,$D8,$6C,$00,$00),
    ($78,$CC,$FC,$CC,$CC,$CC,$CC,$00,$00),
    ($F8,$CC,$F8,$CC,$CC,$CC,$F8,$00,$00),
    ($78,$CC,$C0,$C0,$C0,$CC,$78,$00,$00),
    ($F8,$CC,$CC,$CC,$CC,$CC,$F8,$00,$00),
    ($FC,$C0,$FC,$C0,$C0,$C0,$FC,$00,$00),
    ($FC,$C0,$FC,$C0,$C0,$C0,$C0,$00,$00),
    ($78,$CC,$C0,$DC,$CC,$CC,$7C,$00,$00),
    ($CC,$CC,$FC,$CC,$CC,$CC,$CC,$00,$00),
    ($FC,$30,$30,$30,$30,$30,$FC,$00,$00),
    ($0C,$0C,$0C,$0C,$CC,$CC,$78,$00,$00),
    ($CC,$CC,$CC,$F8,$CC,$CC,$CC,$00,$00),
    ($C0,$C0,$C0,$C0,$C0,$C0,$FC,$00,$00),
    ($CC,$FC,$CC,$CC,$CC,$CC,$CC,$00,$00),
    ($CC,$CC,$EC,$DC,$CC,$CC,$CC,$00,$00),
    ($78,$CC,$CC,$CC,$CC,$CC,$78,$00,$00),
    ($F8,$CC,$F8,$C0,$C0,$C0,$C0,$00,$00),
    ($78,$CC,$CC,$CC,$CC,$C8,$74,$00,$00),
    ($F8,$CC,$F8,$CC,$CC,$CC,$CC,$00,$00),
    ($7C,$C0,$78,$0C,$CC,$CC,$78,$00,$00),
    ($FC,$30,$30,$30,$30,$30,$30,$00,$00),
    ($CC,$CC,$CC,$CC,$CC,$CC,$78,$00,$00),
    ($CC,$CC,$CC,$CC,$CC,$78,$30,$00,$00),
    ($CC,$CC,$CC,$CC,$CC,$FC,$CC,$00,$00),
    ($CC,$CC,$CC,$78,$CC,$CC,$CC,$00,$00),
    ($CC,$CC,$78,$30,$30,$30,$30,$00,$00),
    ($FC,$0C,$18,$30,$60,$C0,$FC,$00,$00),
    ($78,$60,$60,$60,$60,$60,$78,$00,$00),
    ($60,$60,$30,$30,$30,$18,$18,$00,$00),
    ($78,$18,$18,$18,$18,$18,$78,$00,$00),
    ($30,$78,$CC,$00,$00,$00,$00,$00,$00),
    ($00,$00,$00,$00,$00,$00,$FC,$00,$00),
    ($C0,$60,$00,$00,$00,$00,$00,$00,$00),
    ($00,$00,$F8,$0C,$7C,$CC,$7C,$00,$00),
    ($C0,$C0,$F8,$CC,$CC,$CC,$F8,$00,$00),
    ($00,$00,$78,$CC,$C0,$CC,$78,$00,$00),
    ($0C,$0C,$7C,$CC,$CC,$CC,$7C,$00,$00),
    ($00,$00,$78,$CC,$F8,$C0,$7C,$00,$00),
    ($3C,$60,$FC,$60,$60,$60,$60,$00,$00),
    ($00,$00,$7C,$CC,$CC,$CC,$7C,$0C,$F8),
    ($C0,$C0,$F8,$CC,$CC,$CC,$CC,$00,$00),
    ($C0,$00,$C0,$C0,$C0,$C0,$C0,$00,$00),
    ($60,$00,$60,$60,$60,$60,$60,$60,$C0),
    ($C0,$C0,$CC,$F8,$CC,$CC,$CC,$00,$00),
    ($C0,$C0,$C0,$C0,$C0,$C0,$C0,$00,$00),
    ($00,$00,$CC,$FC,$CC,$CC,$CC,$00,$00),
    ($00,$00,$F8,$CC,$CC,$CC,$CC,$00,$00),
    ($00,$00,$78,$CC,$CC,$CC,$78,$00,$00),
    ($00,$00,$F8,$CC,$CC,$CC,$F8,$C0,$C0),
    ($00,$00,$7C,$CC,$CC,$CC,$7C,$0C,$0C),
    ($00,$00,$F8,$CC,$CC,$C0,$C0,$00,$00),
    ($00,$00,$7C,$C0,$78,$0C,$F8,$00,$00),
    ($60,$60,$FC,$60,$60,$60,$3C,$00,$00),
    ($00,$00,$CC,$CC,$CC,$CC,$7C,$00,$00),
    ($00,$00,$CC,$CC,$CC,$48,$30,$00,$00),
    ($00,$00,$CC,$CC,$CC,$FC,$CC,$00,$00),
    ($00,$00,$CC,$CC,$78,$CC,$CC,$00,$00),
    ($00,$00,$CC,$CC,$CC,$CC,$7C,$0C,$F8),
    ($00,$00,$FC,$18,$30,$60,$FC,$00,$00),
    ($30,$60,$60,$C0,$60,$60,$30,$00,$00),
    ($C0,$C0,$C0,$C0,$C0,$C0,$C0,$00,$00),
    ($C0,$60,$60,$30,$60,$60,$C0,$00,$00),
    ($00,$00,$00,$64,$98,$00,$00,$00,$00)
  );

  VERT_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'layout(location=0) in vec2 aPos;'#10 +
    'layout(location=1) in vec4 aColor;'#10 +
    'uniform vec2 uViewport;'#10 +
    'out vec4 vColor;'#10 +
    'void main() {'#10 +
    '  float nx = aPos.x / uViewport.x * 2.0 - 1.0;'#10 +
    '  float ny = 1.0 - aPos.y / uViewport.y * 2.0;'#10 +
    '  gl_Position = vec4(nx, ny, 0.0, 1.0);'#10 +
    '  vColor = aColor;'#10 +
    '}'#10;

  FRAG_SRC: PAnsiChar =
    '#version 330 core'#10 +
    'in vec4 vColor;'#10 +
    'out vec4 FragColor;'#10 +
    'void main() { FragColor = vColor; }'#10;

function Compile(kind: GLenum; const src: PAnsiChar): GLuint;
var
  sh: GLuint;
  ok, logLen: GLint;
  logBuf: array[0..1023] of AnsiChar;
begin
  sh := glCreateShader(kind);
  glShaderSource(sh, 1, @src, nil);
  glCompileShader(sh);
  glGetShaderiv(sh, GL_COMPILE_STATUS, @ok);
  if ok = GL_FALSE then begin
    glGetShaderInfoLog(sh, SizeOf(logBuf), @logLen, @logBuf[0]);
    writeln(StdErr, 'guigl: shader compile failed: ', PAnsiChar(@logBuf[0]));
    glDeleteShader(sh);
    Compile := 0;
    exit;
  end;
  Compile := sh;
end;

constructor TGLCanvas.Create(viewW, viewH: LongInt);
var
  vs, fs: GLuint;
  stride: GLsizei;
begin
  inherited Create;
  FVw := viewW; FVh := viewH;
  FScale := 2;
  FNverts := 0;
  SetLength(FVerts, 6 * 6 * 256);   { room for 256 quads before a grow }
  UseBuiltinFont;

  vs := Compile(GL_VERTEX_SHADER, VERT_SRC);
  fs := Compile(GL_FRAGMENT_SHADER, FRAG_SRC);
  FProg := glCreateProgram();
  glAttachShader(FProg, vs);
  glAttachShader(FProg, fs);
  glLinkProgram(FProg);
  glDeleteShader(vs);
  glDeleteShader(fs);
  FUViewport := glGetUniformLocation(FProg, 'uViewport');

  glGenVertexArrays(1, @FVao);
  glGenBuffers(1, @FVbo);
  glBindVertexArray(FVao);
  glBindBuffer(GL_ARRAY_BUFFER, FVbo);
  glBufferData(GL_ARRAY_BUFFER, Length(FVerts) * SizeOf(GLfloat), nil, GL_DYNAMIC_DRAW);
  stride := 6 * SizeOf(GLfloat);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, Pointer(0));
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, stride, Pointer(2 * SizeOf(GLfloat)));
  glEnableVertexAttribArray(1);
  glBindVertexArray(0);
end;

destructor TGLCanvas.Destroy;
begin
  if FVbo <> 0 then glDeleteBuffers(1, @FVbo);
  if FVao <> 0 then glDeleteVertexArrays(1, @FVao);
  if FProg <> 0 then glDeleteProgram(FProg);
  inherited Destroy;
end;

procedure TGLCanvas.Resize(viewW, viewH: LongInt);
begin
  FVw := viewW; FVh := viewH;
end;

procedure TGLCanvas.PushVertex(x, y: LongInt; r, g, b, a: GLfloat);
var
  base: LongInt;
begin
  base := FNverts * 6;
  if base + 6 > Length(FVerts) then SetLength(FVerts, Length(FVerts) * 2);
  FVerts[base + 0] := x;
  FVerts[base + 1] := y;
  FVerts[base + 2] := r;
  FVerts[base + 3] := g;
  FVerts[base + 4] := b;
  FVerts[base + 5] := a;
  Inc(FNverts);
end;

procedure TGLCanvas.PushQuad(x0, y0, x1, y1: LongInt; c: TColor);
var
  r, g, b, a: GLfloat;
begin
  a := ((c shr 24) and $FF) / 255.0;
  r := ((c shr 16) and $FF) / 255.0;
  g := ((c shr 8) and $FF) / 255.0;
  b := (c and $FF) / 255.0;
  PushVertex(x0, y0, r, g, b, a);
  PushVertex(x1, y0, r, g, b, a);
  PushVertex(x1, y1, r, g, b, a);
  PushVertex(x0, y0, r, g, b, a);
  PushVertex(x1, y1, r, g, b, a);
  PushVertex(x0, y1, r, g, b, a);
end;

procedure TGLCanvas.Flush;
begin
  if FNverts = 0 then exit;
  glBindVertexArray(FVao);
  glBindBuffer(GL_ARRAY_BUFFER, FVbo);
  glBufferData(GL_ARRAY_BUFFER, FNverts * 6 * SizeOf(GLfloat), @FVerts[0], GL_DYNAMIC_DRAW);
  glDrawArrays(GL_TRIANGLES, 0, FNverts);
  glBindVertexArray(0);
  FNverts := 0;
end;

procedure TGLCanvas.BeginFrame;
begin
  FNverts := 0;
  glUseProgram(FProg);
  glUniform2f(FUViewport, FVw, FVh);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
end;

procedure TGLCanvas.EndFrame;
begin
  Flush;
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_DEPTH_TEST);
  glEnable(GL_CULL_FACE);
end;

procedure TGLCanvas.SetClip(const r: TRect);
begin
  Flush;   { queued quads belong to the previous clip region }
  glEnable(GL_SCISSOR_TEST);
  glScissor(r.Left, FVh - r.Bottom, RectW(r), RectH(r));
end;

procedure TGLCanvas.ClearClip;
begin
  Flush;
  glDisable(GL_SCISSOR_TEST);
end;

procedure TGLCanvas.FillRect(const r: TRect; c: TColor);
begin
  PushQuad(r.Left, r.Top, r.Right, r.Bottom, c);
end;

procedure TGLCanvas.FrameRect(const r: TRect; c: TColor);
begin
  PushQuad(r.Left, r.Top, r.Right, r.Top + 1, c);        { top }
  PushQuad(r.Left, r.Bottom - 1, r.Right, r.Bottom, c);  { bottom }
  PushQuad(r.Left, r.Top, r.Left + 1, r.Bottom, c);      { left }
  PushQuad(r.Right - 1, r.Top, r.Right, r.Bottom, c);    { right }
end;

procedure TGLCanvas.HLine(x1, x2, y: LongInt; c: TColor);
begin
  if x2 < x1 then PushQuad(x2, y, x1 + 1, y + 1, c)
  else PushQuad(x1, y, x2 + 1, y + 1, c);
end;

procedure TGLCanvas.VLine(x, y1, y2: LongInt; c: TColor);
begin
  if y2 < y1 then PushQuad(x, y2, x + 1, y1 + 1, c)
  else PushQuad(x, y1, x + 1, y2 + 1, c);
end;

{ Load the compiled-in Solid Frame face into the runtime font record. }
procedure TGLCanvas.UseBuiltinFont;
var
  c, row, n: LongInt;
begin
  FFont.Lo := FontLo; FFont.Hi := FontHi;
  FFont.CellH := FontCellH; FFont.Asc := FontAsc; FFont.RowBytes := 1;
  n := FFont.Hi - FFont.Lo + 1;
  SetLength(FFont.Adv, n);
  SetLength(FFont.Bits, n * FFont.CellH * FFont.RowBytes);
  for c := FFont.Lo to FFont.Hi do begin
    FFont.Adv[c - FFont.Lo] := FontAdv[c];
    for row := 0 to FFont.CellH - 1 do
      FFont.Bits[(c - FFont.Lo) * FFont.CellH + row] := FontBits[c][row];
  end;
end;

function TGLCanvas.LoadFont(const data; len: LongInt): Boolean;
var
  tmp: TCfnFont;
begin
  LoadFont := CfnDecode(data, len, tmp);
  if LoadFont then FFont := tmp;
end;

procedure TGLCanvas.DrawText(x, y: LongInt; const s: String; c: TColor);
var
  i, cb, k, col, row, cx, code, gi, base: LongInt;
  bits: Byte;
begin
  cx := x;
  for i := 1 to Length(s) do begin
    code := Ord(s[i]);
    if (code >= FFont.Lo) and (code <= FFont.Hi) then gi := code - FFont.Lo
    else gi := -1;
    if gi >= 0 then begin
      base := gi * FFont.CellH * FFont.RowBytes;
      for row := 0 to FFont.CellH - 1 do
        for cb := 0 to FFont.RowBytes - 1 do begin
          bits := FFont.Bits[base + row * FFont.RowBytes + cb];
          if bits <> 0 then
            for k := 0 to 7 do
              if (bits and (128 shr k)) <> 0 then begin
                col := cb * 8 + k;
                PushQuad(cx + col * FScale, y + row * FScale,
                         cx + col * FScale + FScale, y + row * FScale + FScale, c);
              end;
        end;
      cx := cx + FFont.Adv[gi] * FScale;
    end else
      cx := cx + FFont.Adv[0] * FScale;   { unknown glyph: advance one space }
  end;
end;

function TGLCanvas.TextWidth(const s: String): LongInt;
var
  i, w, code: LongInt;
begin
  w := 0;
  for i := 1 to Length(s) do begin
    code := Ord(s[i]);
    if (code >= FFont.Lo) and (code <= FFont.Hi) then
      w := w + FFont.Adv[code - FFont.Lo] * FScale
    else
      w := w + FFont.Adv[0] * FScale;
  end;
  TextWidth := w;
end;

function TGLCanvas.TextHeight: LongInt;
begin
  TextHeight := FFont.CellH * FScale;
end;

end.
