# Changelog

All notable changes to Chasm in the Wood are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow semantic versioning. Each minor release gets a dated section and an
annotated git tag whose message is that release's changes.

## [Unreleased]

### Added
- SDL3 window with an OpenGL 3.3 core renderer, through hand-rolled minimal
  bindings loaded at runtime.
- MagicaVoxel `.vox` reader and writer.
- Greedy voxel mesher that merges same-colour faces into large quads.
- Diorama camera built as an orbit rig around a target point.
- `voxelize` tool: surface-voxelizes an OBJ mesh into a `.vox`, taking colours
  from the material's diffuse term.
- Asset pipeline that bakes the reference CC0 modular character (FBX) into a
  voxel model through assimp and the voxelizer.
- Modular Makefile split into `mk/*.mk` fragments by concern.
- Grid floor with a cell-to-world mapping, drawn as a two-tone checker.
- Player voxel model standing on the grid, moved a cell at a time with WASD or
  the arrow keys.
- Follow camera that eases its target toward the player each frame, with Q/E to
  orbit and `-`/`=` to zoom.

### Changed
- Split the renderer into a shared mesh shader and per-object GPU meshes, so the
  floor, the player, and later props draw through one program.

### Removed
- Stale tool stubs from the earlier software renderer that no longer compiled.
