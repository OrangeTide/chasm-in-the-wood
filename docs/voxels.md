# Voxels

Voxel models come from two places: MagicaVoxel `.vox` files, such as the player, and
geometry the engine authors directly, such as dungeon chunks. Both become triangle
meshes through the same greedy mesher.

## The .vox format

`src/voxel/voxfile.pas` reads and writes MagicaVoxel `.vox`. A model is stored as a
dense grid of palette indices, zero meaning empty, plus a 255-entry colour palette.
That is the shape the mesher wants.

The reader keeps the first model in a file and skips the scene-graph and material
chunks. The writer emits a single `SIZE`, `XYZI`, and `RGBA` model that MagicaVoxel
and this reader both accept. The format has one quirk the unit hides: a voxel's colour
index `c` in `1..255` maps to the `c-1`'th entry of the `RGBA` chunk. The reader and
writer apply that offset so the rest of the engine just reads `palette[c]`.

Remember that `.vox` is `z` up. See [Coordinate systems](coordinates.md).

## Greedy meshing

`src/voxel/voxmesh.pas` turns a voxel grid into a triangle mesh. A naive mesher emits
a quad for every exposed voxel face, which is correct but wasteful: a flat wall
becomes thousands of tiny quads. The greedy mesher merges them.

For each of the six face directions it sweeps the grid in slices. In each slice it
builds a mask of exposed faces, a face being exposed where a solid voxel meets an
empty neighbour, tagged with the voxel's colour. It then merges runs of same-colour
faces into the largest rectangles it can, widest first then tallest, and emits two
triangles per rectangle. A flat same-colour wall collapses to a handful of large
quads.

Each vertex carries position, face normal, and RGB colour from the palette. Geometry
stays in voxel space; the renderer centres, scales, and for `.vox` models rotates it.
For a measured example, the voxelized player is about two thousand voxels and meshes
to about two thousand triangles, a large reduction from the per-face count.

Faces at a chunk border are meshed as if the outside were empty. That emits a pair of
hidden faces at the seam between two solid border voxels. They are inside the solid
and not visible, so this is correct but slightly wasteful. Neighbour-aware meshing
that drops those seam faces is a later optimisation.

## The voxelizer

`tools/voxelize.pas` turns an OBJ mesh into a `.vox`. It reads the OBJ and its `.mtl`
for per-material diffuse colour, fits the mesh into a grid whose longest axis is the
requested resolution, and marks every voxel a triangle passes through by sampling each
triangle at roughly half-voxel spacing. Colours become a palette by find-or-add.

Because the source OBJ is `y` up and `.vox` is `z` up, the voxelizer maps object `y`
to voxel `z`, so the model stands up when the renderer applies its `z`-up to `y`-up
rotation.

The voxelizer is a build-time tool. It shares `voxfile` with the runtime, so the tool
and the engine agree on the format. See [Build and assets](build-and-assets.md) for
how it fits the asset pipeline.
