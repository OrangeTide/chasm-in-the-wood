# Rendering

The renderer targets OpenGL 3.3 core through SDL3, with hand-rolled bindings. It
draws lit voxel meshes: the streamed world chunks and the player, all through one
shader program.

## SDL3 and the GL context

`src/platform/sdl3.pas` is a minimal SDL3 binding. It declares only the entry points
the engine calls: init and quit, window and GL context creation, the event pump,
timing, and the GL proc-address loader. SDL3 is linked at build time from the path
in `mk/config.mk` (`/usr/local` by default). A full third-party binding was not
worth the surface area for this small set of calls.

Startup requests a 3.3 core profile with a depth buffer and double buffering, creates
the window with the `SDL_WINDOW_OPENGL` flag, makes the context current, and enables
vsync.

## Loading OpenGL

The modern GL functions are not exported by `libGL` in a portable link interface, so
`src/gfx/glcore.pas` resolves each one at runtime through `SDL_GL_GetProcAddress`
after the context exists. It declares only the subset the renderer uses: buffers and
vertex arrays, shaders and programs, a few state calls, `glDrawElements`, and
`glReadPixels` for the screenshot path. `LoadGL` binds them all and reports any that
are missing. No `libGL` link is needed.

## Matrices

`src/math/vecmath.pas` provides `TVec3` and a column-major `TMat4`, the layout
OpenGL expects, so a matrix passes straight to `glUniformMatrix4fv` with no
transpose. It has the usual builders: identity, translate, scale, rotate, multiply,
perspective, and look-at.

## The camera

`src/render/camera.pas` is an orbit rig around a target point. Yaw, pitch, and
distance place the eye, and the eye always looks at the target. The dungeon uses a
fixed three-quarter pitch. The follow behaviour is just moving the target: each frame
`chasm.lpr` eases the target toward the player, and the framing math does not change.
The elevated angle is why the player sees over low walls, which matters for culling.

## Meshes and the shader

The renderer separates the program from the geometry so many meshes share one
program:

- `src/render/meshshader.pas` owns the shader program and its uniforms. A frame binds
  it once with the view and projection matrices and the light direction.
- `src/render/gpumesh.pas` owns a vertex array and vertex and index buffers uploaded
  from a mesh. Each chunk and the player holds its own.

The shader is a single directional light plus ambient, enough to read voxel faces as
solid form. The vertex format is position, normal, and RGB colour, nine floats,
interleaved. To draw, the caller binds the program, then for each object sets the
model matrix and draws its GPU mesh.

## Frustum culling

`src/render/frustum.pas` extracts the six clip planes from the combined
projection-times-view matrix with the Gribb-Hartmann method, reading the rows of the
column-major matrix, and tests chunk bounding boxes with the positive-vertex test.

The choice of culler is deliberate. The diorama camera is elevated and angled, so the
player sees over the low walls into neighbouring rooms. A plain frustum test over
chunk bounds is correct for that. Strict room-portal culling, which draws only rooms
reachable through a visible doorway, would wrongly hide rooms the player can plainly
see over a wall. The room graph is still built, but it serves prefetch and future
occlusion, not the primary cull. See [World streaming](world-streaming.md).

## Depth and culling state

The renderer enables the depth test with `GL_LESS`, back-face culling with
counter-clockwise front faces, and clears colour and depth each frame. The mesher
emits faces with consistent winding so back-face culling drops the inside faces.
