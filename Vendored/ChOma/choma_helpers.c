#include "choma_helpers.h"
#include "Entitlements.h"
#include "Fat.h"
#include "FileStream.h"
#include "MemoryStream.h"
#include "MachOByteOrder.h"
#include <mach-o/fat.h>
#include <sys/fcntl.h>

int choma_replace_entitlements_in_macho(MachO *macho, const char *entitlements_path)
{
    CS_DecodedBlob *entBlob = create_xml_entitlements_blob(entitlements_path);
    if (!entBlob) return -1;

    csd_blob_set_type(entBlob, CSSLOT_ENTITLEMENTS);

    CS_SuperBlob *superblob = macho_read_code_signature(macho);
    if (!superblob) {
        csd_blob_free(entBlob);
        return -1;
    }

    CS_DecodedSuperBlob *decoded = csd_superblob_decode(superblob);
    free(superblob);
    if (!decoded) {
        csd_blob_free(entBlob);
        return -1;
    }

    uint32_t index = 0;
    CS_DecodedBlob *existing = csd_superblob_find_blob(decoded, CSSLOT_ENTITLEMENTS, &index);
    if (existing) {
        csd_superblob_remove_blob(decoded, existing);
    }

    csd_superblob_append_blob(decoded, entBlob);

    CS_SuperBlob *newSuperblob = csd_superblob_encode(decoded);
    if (!newSuperblob) {
        csd_superblob_free(decoded);
        return -1;
    }

    int ret = macho_replace_code_signature(macho, newSuperblob);
    free(newSuperblob);
    csd_superblob_free(decoded);
    return ret;
}

int choma_replace_entitlements(const char *macho_path, const char *entitlements_path)
{
    if (!macho_path || !entitlements_path) return -1;

    // First try: thin Mach-O via macho_init_for_writing
    MachO *macho = macho_init_for_writing(macho_path);
    if (macho) {
        int ret = choma_replace_entitlements_in_macho(macho, entitlements_path);
        macho_free(macho);
        return ret;
    }

    // Second try: fat binary
    // Open the file as writable
    MemoryStream *stream = file_stream_init_from_path(macho_path, 0, FILE_STREAM_SIZE_AUTO,
        FILE_STREAM_FLAG_WRITABLE | FILE_STREAM_FLAG_AUTO_EXPAND);
    if (!stream) return -1;

    // Read fat header
    struct fat_header fh;
    memory_stream_read(stream, 0, sizeof(fh), &fh);
    uint32_t magic = BIG_TO_HOST(fh.magic);
    if (magic != FAT_MAGIC && magic != FAT_MAGIC_64) {
        memory_stream_free(stream);
        return -1;
    }

    bool is64 = (magic == FAT_MAGIC_64);
    uint32_t nfat_arch = BIG_TO_HOST(fh.nfat_arch);

    FileStreamContext *fsCtx = (FileStreamContext *)stream->context;
    int fd = fsCtx->fd;

    int ret = 0;
    for (uint32_t i = 0; i < nfat_arch && ret == 0; i++) {
        struct fat_arch_64 arch = {0};

        if (is64) {
            struct fat_arch_64 raw;
            memory_stream_read(stream, sizeof(struct fat_header) + i * sizeof(raw), sizeof(raw), &raw);
            arch.cputype = (cpu_type_t)BIG_TO_HOST(raw.cputype);
            arch.cpusubtype = (cpu_subtype_t)BIG_TO_HOST(raw.cpusubtype);
            arch.offset = BIG_TO_HOST(raw.offset);
            arch.size = BIG_TO_HOST(raw.size);
            arch.align = BIG_TO_HOST(raw.align);
            arch.reserved = BIG_TO_HOST(raw.reserved);
        } else {
            struct fat_arch raw;
            memory_stream_read(stream, sizeof(struct fat_header) + i * sizeof(raw), sizeof(raw), &raw);
            arch.cputype = (cpu_type_t)BIG_TO_HOST(raw.cputype);
            arch.cpusubtype = (cpu_subtype_t)BIG_TO_HOST(raw.cpusubtype);
            arch.offset = BIG_TO_HOST(raw.offset);
            arch.size = BIG_TO_HOST(raw.size);
            arch.align = BIG_TO_HOST(raw.align);
            arch.reserved = 0;
        }

        // Only process arm64 slices
        if (arch.cputype != CPU_TYPE_ARM64) continue;

        // Open a writable FileStream for this slice (dups the fd)
        MemoryStream *sliceStream = file_stream_init_from_file_descriptor(
            fd, (uint32_t)arch.offset, arch.size,
            FILE_STREAM_FLAG_WRITABLE | FILE_STREAM_FLAG_AUTO_EXPAND);
        if (!sliceStream) { ret = -1; break; }

        MachO *slice = macho_init(sliceStream, arch);
        if (!slice) {
            memory_stream_free(sliceStream);
            ret = -1;
            break;
        }

        ret = choma_replace_entitlements_in_macho(slice, entitlements_path);
        macho_free(slice);
    }

    memory_stream_free(stream);
    return ret;
}

const char *choma_xpf_version_string(void) {
    return gXPF.kernelVersionString;
}

uint64_t choma_xpf_kernel_base(void) {
    return gXPF.kernelBase;
}
