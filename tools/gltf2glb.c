/* gltf2glb.c : pack a .gltf plus its external .bin into a self-contained .glb.
 *
 * A minimal, dependency-free glTF -> GLB packer built on the vendored cgltf
 * reader and writer. It embeds the single external buffer as the GLB binary
 * chunk so the runtime loads one self-contained blob per model (memory parse,
 * no side files). This is the first, deliberately small, piece of the eventual
 * asset baker (doc/demon-engine.md 5.7); the baker will grow image embedding
 * and CAS-depot ingestion on top.
 *
 * Images referenced by URI stay external (a GLB may keep external image URIs);
 * only geometry, skin, and animation data are embedded. That is all the flat-
 * shaded first pass needs.
 *
 * Usage: gltf2glb <in.gltf> <out.glb>
 */
/* The cgltf reader implementation lives in the gamemodel library (model.c);
 * this TU only adds the writer implementation. Defining both in one TU would
 * compile cgltf's internals twice. */
#define CGLTF_WRITE_IMPLEMENTATION
#include "cgltf_write.h"

#include <stdio.h>

int
main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s <in.gltf> <out.glb>\n", argv[0]);
        return 2;
    }
    const char *in = argv[1];
    const char *out = argv[2];

    cgltf_options options = {0};
    cgltf_data *data = NULL;

    if (cgltf_parse_file(&options, in, &data) != cgltf_result_success) {
        fprintf(stderr, "gltf2glb: cannot parse %s\n", in);
        return 1;
    }
    if (cgltf_load_buffers(&options, data, in) != cgltf_result_success) {
        fprintf(stderr, "gltf2glb: cannot load buffers for %s\n", in);
        cgltf_free(data);
        return 1;
    }

    /* These exports carry exactly one external .bin buffer. Embed it as the
     * GLB binary chunk: point data->bin at the loaded bytes and drop the URI
     * so the JSON writer emits an embedded (uri-less) buffer. */
    if (data->buffers_count != 1) {
        fprintf(stderr, "gltf2glb: expected 1 buffer, got %zu (unsupported)\n",
            (size_t)data->buffers_count);
        cgltf_free(data);
        return 1;
    }
    data->bin = data->buffers[0].data;
    data->bin_size = data->buffers[0].size;
    data->buffers[0].uri = NULL;

    options.type = cgltf_file_type_glb;
    if (cgltf_write_file(&options, out, data) != cgltf_result_success) {
        fprintf(stderr, "gltf2glb: cannot write %s\n", out);
        cgltf_free(data);
        return 1;
    }

    printf("gltf2glb: %s -> %s (bin %zu bytes, %zu meshes, %zu skins, "
        "%zu animations)\n", in, out, (size_t)data->bin_size,
        (size_t)data->meshes_count, (size_t)data->skins_count,
        (size_t)data->animations_count);

    cgltf_free(data);
    return 0;
}
