# Music

The game loops one OGG Vorbis track per place, by filename:

- `town.ogg` plays in the hamlet of Brackenridge.
- `forest.ogg` plays on the surface outside the hamlet, in the forest around it.
- `dungeon.ogg` plays below, in the chasm.

A track authored to loop seamlessly is best, since the whole file is the loop.
When a file is absent the game simply runs without music.

## The tracks do not ship with the source

The `.ogg` files here are kept out of the repository (see the project `.gitignore`)
and must be sourced locally. They are not CC0 like the rest of the assets: they come
from a licensed music pack whose terms do not clearly permit redistributing the audio
files on their own, so the repository does not carry them, the same way the clumplump
project keeps this music local. The build and the game read them from this directory
when present; a fresh checkout has no music until the files are placed here.

To restore the music used in development, copy these three loops from the ELVGames
"Cosy Melodies Music Pack" into this directory under the names above:

- `town.ogg`    = `OST 3 - Tea Party Tunes (Loopable).ogg`
- `forest.ogg`  = `OST 1 - Blissful Butterflies (Loopable).ogg`
- `dungeon.ogg` = `OST 2 - Seaside Retreat (Loopable).ogg`

Copy them verbatim (do not transcode or trim); the loopable OGG exports are already
the right format. See `PROVENANCE.md` for the source and licence.
