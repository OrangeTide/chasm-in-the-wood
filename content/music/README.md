# Music

The game loops one OGG Vorbis track per place, by filename:

- `town.ogg` plays in the hamlet of Brackenridge.
- `forest.ogg` plays on the surface outside the hamlet, in the forest around it.
- `dungeon.ogg` plays below, in the chasm.

A track authored to loop seamlessly is best, since the whole file is the loop.
When a file is absent the game simply runs without music.

## No music ships yet

The project ships only audio it can redistribute. The tracks used earlier in
development came from a licensed pack whose terms did not clearly permit
redistributing the audio, so they were dropped. No music ships at present, and
the game runs silent until distributable tracks are placed here.

To add music, drop CC0 or otherwise redistributable loops into this directory
under the three names above. Record each source and its licence in
`PROVENANCE.md`, confirmed before a release distributes it, the same as every
other asset. Unlike the earlier pack these files are committed, since they are
ones the project may distribute.
