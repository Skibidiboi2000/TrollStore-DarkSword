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
#include "choma_helpers.h"
#include "PatchFinder.h"
#include "PatchFinder_arm64.h"
#include "MemoryStream.h"
#include "MachO.h"
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>

// ---------------------------------------------------------------------------
// Diagnostic ring buffer — accumulates lines that Swift drains via
// choma_drain_diagnostics() and logs via LogManager with [CHOMA] tag.
// ---------------------------------------------------------------------------
#define DIAG_BUF_SIZE 131072
static char g_choma_diag_buf[DIAG_BUF_SIZE];
static size_t g_choma_diag_off = 0;

__attribute__((format(printf, 1, 2)))
static void diag(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    size_t space = DIAG_BUF_SIZE - g_choma_diag_off;
    int n = vsnprintf(g_choma_diag_buf + g_choma_diag_off, space, fmt, args);
    if (n > 0) {
        size_t written = (size_t)n;
        if (written >= space) written = space - 1;
        g_choma_diag_off += written;
        if (g_choma_diag_off > DIAG_BUF_SIZE - 1) g_choma_diag_off = DIAG_BUF_SIZE - 1;
    }
    g_choma_diag_buf[g_choma_diag_off] = '\0';
    va_end(args);
}

const char *choma_drain_diagnostics(void)
{
    const char *ret = g_choma_diag_buf;
    g_choma_diag_off = 0;
    return ret;
}

// ---------------------------------------------------------------------------
// Corrected PFSection creator for fileset entries.
//
// pfsec_init_from_macho() has a fileset-entry stream bug: it always clones
// macho->stream (the container's stream) even when a fileset entry is found.
// This wrapper uses the fileset entry's OWN stream so that section data is
// read from the correct in-cache slice.
// ---------------------------------------------------------------------------
PFSection *section_from_fileset_entry(MachO *container,
                                              const char *entryId,
                                              const char *segName,
                                              const char *sectName)
{
    // 1. Locate the fileset entry by entry_id
    FilesetMachO *target = NULL;
    for (uint32_t i = 0; i < container->filesetCount; i++) {
        FilesetMachO *entry = &container->filesetMachos[i];
        if (!entry->entry_id) continue;
        if (entry->underlyingMachO && entry->underlyingMachO->slicesCount == 1) {
            if (strcmp(entry->entry_id, entryId) == 0) {
                target = entry;
                break;
            }
        }
    }
    if (!target) { xpf_set_error("section_from_fileset_entry: entry '%s' not found among %u entries", entryId, container->filesetCount); return NULL; }

    // 2. Get the fileset entry's own MachO (which has the CORRECT stream)
    MachO *machoToUse = target->underlyingMachO->slices[0];
    if (!machoToUse) { xpf_set_error("section_from_fileset_entry: slices[0] is NULL for '%s'", entryId); return NULL; }
    xpf_set_error("section_from_fileset_entry: using entry '%s' (%u segments)", entryId, machoToUse->segmentCount);

    // 3. Locate the segment
    MachOSegment *segment = NULL;
    for (uint32_t i = 0; i < machoToUse->segmentCount; i++) {
        MachOSegment *seg = machoToUse->segments[i];
        if (!seg) continue;
        if (strncmp(seg->command.segname, segName, sizeof(seg->command.segname)) == 0) {
            segment = seg;
            break;
        }
    }
    if (!segment) { xpf_set_error("section_from_fileset_entry: segment '%s' not found in '%s' (%u segments)", segName, entryId, machoToUse->segmentCount); return NULL; }

    // 4. Allocate + populate the PFSection
    PFSection *pf = calloc(1, sizeof(PFSection));
    struct section_64 *section = NULL;

    if (sectName) {
        for (uint32_t i = 0; i < segment->command.nsects; i++) {
            struct section_64 *cand = &segment->sections[i];
            if (strncmp(cand->sectname, sectName, sizeof(cand->sectname)) == 0) {
                section = cand;
                break;
            }
        }
        if (!section) { free(pf); xpf_set_error("section_from_fileset_entry: sect '%s' not found in seg '%s' of '%s' (%u sections)", sectName, segName, entryId, segment->command.nsects); return NULL; }

        // Inline pfsec_info_populate_section (not exposed in public header)
        pf->info.fileoff  = section->offset;
        pf->info.vmaddr   = section->addr;
        pf->info.size     = section->size;
        pf->info.initprot = segment->command.initprot;
        pf->info.maxprot  = segment->command.maxprot;
        strncpy(pf->info.segname, segment->command.segname, sizeof(pf->info.segname) - 1);
        strncpy(pf->info.sectname, section->sectname, sizeof(pf->info.sectname) - 1);
    } else {
        pf->info.fileoff  = segment->command.fileoff;
        pf->info.vmaddr   = segment->command.vmaddr;
        pf->info.size     = segment->command.filesize;
        pf->info.initprot = segment->command.initprot;
        pf->info.maxprot  = segment->command.maxprot;
        strncpy(pf->info.segname, segment->command.segname, sizeof(pf->info.segname) - 1);
        pf->info.sectname[0] = '\0';
    }

    // 5. KEY FIX: clone the fileset entry's OWN stream, not the container's
    pf->cache   = NULL;
    if (!machoToUse->stream) {
        xpf_set_error("section_from_fileset_entry: stream is NULL for '%s'", entryId);
        free(pf);
        return NULL;
    }
    pf->stream  = memory_stream_softclone(machoToUse->stream);
    pf->macho   = machoToUse;

    // Trim the cloned stream to span just this section
    memory_stream_trim(pf->stream, pf->info.fileoff,
        memory_stream_get_size(pf->stream) - (pf->info.fileoff + pf->info.size));

    return pf;
}

// ---------------------------------------------------------------------------
// Helper: locate the AMFI fileset entry in the kernel container.
// Shared by choma_find_amfi_function_direct and choma_find_dev_mode_status.
// Returns the AMFI entry in *outEntry and its MachO in *outMacho.
// ---------------------------------------------------------------------------
static FilesetMachO *find_amfi_entry(MachO *kernel, MachO **outMacho)
{
    const char *amfiCandidates[] = {
        "com.apple.driver.AppleMobileFileIntegrity",
        "com.apple.security.AppleMobileFileIntegrity",
        "AppleMobileFileIntegrity",
        NULL
    };
    FilesetMachO *entry = NULL;
    for (int c = 0; amfiCandidates[c]; c++) {
        for (uint32_t i = 0; i < kernel->filesetCount; i++) {
            FilesetMachO *e = &kernel->filesetMachos[i];
            if (!e->entry_id) continue;
            if (!e->underlyingMachO) continue;
            if (e->underlyingMachO->slicesCount == 1) {
                if (strcmp(e->entry_id, amfiCandidates[c]) == 0) { entry = e; break; }
            }
        }
        if (entry) break;
    }
    if (!entry) {
        for (uint32_t i = 0; i < kernel->filesetCount; i++) {
            FilesetMachO *e = &kernel->filesetMachos[i];
            if (!e->entry_id) continue;
            if (e->underlyingMachO && e->underlyingMachO->slicesCount == 1) {
                if (strstr(e->entry_id, "MobileFileIntegrity") || strstr(e->entry_id, "AMFI")) {
                    entry = e; break;
                }
            }
        }
    }
    if (entry && outMacho) {
        *outMacho = entry->underlyingMachO->slices[0];
    }
    return entry;
}

// ---------------------------------------------------------------------------
// Helper: find the kernel fileset entry ("com.apple.kernel" or similar).
// ---------------------------------------------------------------------------
static char *find_kernel_entry_id(MachO *kernel)
{
    const char *kCandidates[] = {"com.apple.kernel", "com.apple.kernel.XNU", NULL};
    for (int c = 0; kCandidates[c]; c++) {
        for (uint32_t i = 0; i < kernel->filesetCount; i++) {
            const char *eid = kernel->filesetMachos[i].entry_id;
            if (!eid) continue;
            if (!strcmp(eid, kCandidates[c]))
                return eid;
        }
    }
    for (uint32_t i = 0; i < kernel->filesetCount; i++) {
        const char *eid = kernel->filesetMachos[i].entry_id;
        if (!eid) continue;
        if (strstr(eid, "kernel") &&
            !strstr(eid, "AMFI") &&
            !strstr(eid, "Sandbox"))
            return kernel->filesetMachos[i].entry_id;
    }
    return NULL;
}

// ---------------------------------------------------------------------------
// choma_get_amfi_data_range
//
// Returns the VM address and size of AMFI's primary __DATA_CONST,__data section.
// Swift can use this with kernel-r/w to scan runtime data (e.g. trust cache).
// Returns 0 if not found.
// ---------------------------------------------------------------------------
uint64_t choma_get_amfi_data_range(uint64_t *outSize)
{
    MachO *kernel = gXPF.kernel;
    if (!kernel || kernel->filesetCount == 0) return 0;

    FilesetMachO *entry = find_amfi_entry(kernel, NULL);
    if (!entry) return 0;

    PFSection *sec = section_from_fileset_entry(kernel, entry->entry_id,
                        "__DATA_CONST", "__data");
    if (!sec) sec = section_from_fileset_entry(kernel, entry->entry_id,
                        "__DATA", "__data");
    if (!sec) return 0;

    uint64_t vmaddr = sec->info.vmaddr;
    if (outSize) *outSize = sec->info.size;
    pfsec_free(sec);
    return vmaddr;
}

// ---------------------------------------------------------------------------
// Substring search in a section's cstrings.
//
// ChOma's PFStringMetric uses strcmp (exact match) which fails on
// release builds where cstrings are embedded in longer messages:
//   "AMFI: cannot allocate memory\0"  ← will NOT match "AMFI:" via strcmp
//
// This helper iterates all cstrings in a section and calls the matchBlock
// for every cstring that CONTAINS the given substring (strstr match).
// ---------------------------------------------------------------------------
void choma_search_substr(PFSection *section, const char *substr,
                                 void (^matchBlock)(uint64_t vmaddr, bool *stop))
{
    uint64_t scanAddr = section->info.vmaddr;
    uint64_t endAddr  = section->info.vmaddr + section->info.size;
    while (scanAddr < endAddr) {
        char *str = NULL;
        if (pfsec_read_string(section, scanAddr, &str) != 0) break;
        if (strstr(str, substr)) {
            bool stop = false;
            matchBlock(scanAddr, &stop);
            free(str);
            if (stop) return;
        } else {
            free(str);
        }
        scanAddr += strlen(str) + 1;
    }
}

// ---------------------------------------------------------------------------
// choma_find_amfi_function_direct
//
// Multi-strategy search for AMFIIsCDHashInTrustCache.
//
// Strategies (tried in order, returns first success):
//   A: Symbol-table enumeration on EVERY fileset entry
//   B: cstring scan for "AMFIIsCDHashInTrustCache" across all entries
//   C: macho_enumerate_function_starts on AMFI entry + BL-target heuristic
//   D: "AMFI:" anchor string -> xref -> pfsec_find_function_start
//   E: PACIBSP-based function enumeration + BL-count heuristic
//   F: cross-section string scan ("CDHash", "trustcache", ...) across all entries
// ---------------------------------------------------------------------------
uint64_t choma_find_amfi_function_direct(void)
{
    fprintf(stderr, "[CHOMA_D] choma_find_amfi_function_direct ENTERED\n");
    MachO *kernel = gXPF.kernel;
    if (!kernel) { xpf_set_error("choma_find_amfi: gXPF.kernel is NULL"); return 0; }
    if (kernel->filesetCount == 0) { xpf_set_error("choma_find_amfi: no fileset entries"); return 0; }

    diag("[CHOMA] choma_find_amfi: %u fileset entries\n", kernel->filesetCount);

    // ---- Find AMFI entry (needed by all strategies) ----
    MachO *amfiMacho = NULL;
    FilesetMachO *amfiEntry = find_amfi_entry(kernel, &amfiMacho);
    if (!amfiEntry) { xpf_set_error("choma_find_amfi: NO AMFI ENTRY FOUND"); return 0; }
    diag("[CHOMA] choma_find_amfi: entry='%s' vmaddr=0x%llx\n", amfiEntry->entry_id, amfiEntry->vmaddr);
    if (!amfiMacho) { xpf_set_error("choma_find_amfi: slices[0] is NULL"); return 0; }

    __block uint64_t result = 0;

    // ========================================================================
    // Strategy A: symbol table on ALL entries
    // ========================================================================
    fprintf(stderr, "[CHOMA_D] === STRATEGY A: symbol table ===\n");
    diag("[CHOMA] choma_find_amfi: === STRATEGY A: symbol table ===\n");
    for (uint32_t e = 0; e < kernel->filesetCount && !result; e++) {
        FilesetMachO *entry = &kernel->filesetMachos[e];
        if (!entry->underlyingMachO || entry->underlyingMachO->slicesCount != 1) continue;
        MachO *macho = entry->underlyingMachO->slices[0];
        if (!macho) continue;
        __block int symCount = 0;
        int ret = macho_enumerate_symbols(macho, ^(const char *name, uint8_t type, uint64_t vmaddr, bool *stop) {
            symCount++;
            if (strstr(name, "AMFIIsCDHashInTrustCache")) {
                diag("[CHOMA] choma_find_amfi: [A] FOUND in '%s' vmaddr=0x%llx type=0x%x\n", entry->entry_id, vmaddr, type);
                result = vmaddr;
                *stop = true;
            }
        });
        diag("[CHOMA] choma_find_amfi: [A] entry='%s' sym_count=%d ret=%d%s\n", entry->entry_id, symCount, ret, result ? " FOUND!" : "");
    }
    if (result) return result;
    diag("[CHOMA] choma_find_amfi: [A] FAILED (kernelcache fully stripped as expected)\n");

    // ========================================================================
    // Strategy B: cstring scan on ALL entries (exact + substring)
    // ========================================================================
    fprintf(stderr, "[CHOMA_D] === STRATEGY B: cstring scan ===\n");
    diag("[CHOMA] choma_find_amfi: === STRATEGY B: cstring scan ===\n");
    // B1: exact match (strcmp-based, original behavior)
    PFStringMetric *smB = pfmetric_string_init("AMFIIsCDHashInTrustCache");
    for (uint32_t e = 0; e < kernel->filesetCount && !result; e++) {
        FilesetMachO *entry = &kernel->filesetMachos[e];
        if (!entry->underlyingMachO || entry->underlyingMachO->slicesCount != 1) continue;
        PFSection *cstr = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT", "__cstring");
        if (!cstr) continue;
        __block uint64_t strAddr = 0;
        pfmetric_run(cstr, smB, ^(uint64_t vmaddr, bool *stop) { strAddr = vmaddr; *stop = true; });
        pfsec_free(cstr);
        if (strAddr) {
            PFSection *txt = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT_EXEC", "__text");
            if (!txt) txt = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT", "__text");
            if (txt) {
                PFXrefMetric *xm = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
                __block uint64_t xrefAddr = 0;
                pfmetric_run(txt, xm, ^(uint64_t va, bool *stop) { xrefAddr = va; *stop = true; });
                pfmetric_free(xm);
                if (xrefAddr) {
                    result = pfsec_find_function_start(txt, xrefAddr);
                    diag("[CHOMA] choma_find_amfi: [B1] xref=0x%llx func=0x%llx\n", xrefAddr, result);
                }
                pfsec_free(txt);
            }
            break;
        }
    }
    pfmetric_free(smB);
    if (result) return result;

    // B2: substring match (strstr-based, catches embedded function names)
    diag("[CHOMA] choma_find_amfi: === STRATEGY B2: cstring substrings ===\n");
    const char *bsubstrings[] = {"IsCDHash", "CDHashInTrust", "IsCDHash", NULL};
    for (int si = 0; bsubstrings[si] && !result; si++) {
        for (uint32_t e = 0; e < kernel->filesetCount && !result; e++) {
            FilesetMachO *entry = &kernel->filesetMachos[e];
            if (!entry->underlyingMachO || entry->underlyingMachO->slicesCount != 1) continue;
            if (entry != amfiEntry) continue;  // B2 must only search within AMFI entry
            PFSection *cstr = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT", "__cstring");
            if (!cstr) continue;
            __block uint64_t strAddr = 0;
            choma_search_substr(cstr, bsubstrings[si],
                ^(uint64_t va, bool *stop) { strAddr = va; *stop = true; });
            if (strAddr) {
                diag("[CHOMA] choma_find_amfi: [B2] '%s' FOUND in '%s' at 0x%llx\n",
                     bsubstrings[si], entry->entry_id, strAddr);
                PFSection *txt = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT_EXEC", "__text");
                if (!txt) txt = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT", "__text");
                if (txt) {
                    PFXrefMetric *xm = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
                    __block uint64_t xrefAddr = 0;
                    pfmetric_run(txt, xm, ^(uint64_t va, bool *stop) { xrefAddr = va; *stop = true; });
                    pfmetric_free(xm);
                    if (xrefAddr) {
                        result = pfsec_find_function_start(txt, xrefAddr);
                        diag("[CHOMA] choma_find_amfi: [B2] xref=0x%llx func=0x%llx\n", xrefAddr, result);
                    }
                    pfsec_free(txt);
                }
            }
            pfsec_free(cstr);
        }
    }
    if (result) return result;
    diag("[CHOMA] choma_find_amfi: [B] FAILED (func name not a cstring literal on RELEASE)\n");

    // ========================================================================
    // Strategy C: LC_FUNCTION_STARTS on AMFI entry
    // ========================================================================
    fprintf(stderr, "[CHOMA_D] === STRATEGY C: LC_FUNCTION_STARTS ===\n");
    diag("[CHOMA] choma_find_amfi: === STRATEGY C: LC_FUNCTION_STARTS ===\n");
    uint64_t *funcStarts = calloc(512, sizeof(uint64_t));
    __block int funcCount = 0;
    int fsRet = macho_enumerate_function_starts(amfiMacho, ^(uint64_t funcAddr, bool *stop) {
        if (funcCount < 512) funcStarts[funcCount++] = funcAddr;
    });
    if (fsRet == 0 && funcCount > 0) {
        diag("[CHOMA] choma_find_amfi: [C] %d function starts\n", funcCount);
        int logCount = (funcCount < 20) ? funcCount : 20;
        for (int i = 0; i < logCount; i++)
            diag("[CHOMA] choma_find_amfi: [C] func[%d] = 0x%llx\n", i, funcStarts[i]);
        if (funcCount > 20) diag("[CHOMA] choma_find_amfi: [C] ... and %d more\n", funcCount - 20);

        PFSection *amfiText = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT_EXEC", "__text");
        if (!amfiText) amfiText = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__text");
        if (amfiText) {
            uint64_t textStart = amfiText->info.vmaddr;
            uint64_t textEnd = textStart + amfiText->info.size;
            uint64_t *refCounts = calloc(funcCount, sizeof(uint64_t));
            uint64_t totalBLs = 0;

            for (uint64_t addr = textStart; addr < textEnd; addr += 4) {
                uint32_t inst = pfsec_read32(amfiText, addr);
                if ((inst & 0xFC000000) == 0x94000000) {
                    totalBLs++;
                    int32_t offset = (int32_t)(inst & 0x03FFFFFF);
                    if (offset & 0x02000000) offset |= 0xFC000000;
                    uint64_t target = addr + (offset * 4);
                    for (int f = 0; f < funcCount; f++) {
                        if (funcStarts[f] == target) { refCounts[f]++; break; }
                    }
                }
            }
            diag("[CHOMA] choma_find_amfi: [C] scanned 0x%llx bytes, %llu BL total\n", textEnd - textStart, totalBLs);

            int bestIdx = -1;
            uint64_t bestCount = 0;
            for (int f = 0; f < funcCount; f++) {
                if (refCounts[f] > bestCount) { bestCount = refCounts[f]; bestIdx = f; }
            }
            if (bestIdx >= 0) {
                diag("[CHOMA] choma_find_amfi: [C] heuristic picks func[%d] (0x%llx) with %llu BL refs\n", bestIdx, funcStarts[bestIdx], bestCount);
                result = funcStarts[bestIdx];
            } else {
                diag("[CHOMA] choma_find_amfi: [C] no BL refs hit any function start\n");
            }
            free(refCounts);
            pfsec_free(amfiText);
        } else {
            diag("[CHOMA] choma_find_amfi: [C] could not carve AMFI text section\n");
        }
    } else {
        diag("[CHOMA] choma_find_amfi: [C] FAILED (ret=%d, func_count=%d)\n", fsRet, funcCount);
    }
    free(funcStarts);
    if (result) return result;

    // ========================================================================
    // Strategy D: anchor substring -> xref -> pfsec_find_function_start
    //
    fprintf(stderr, "[CHOMA_D] === STRATEGY D: anchor substring -> xref ===\n");
    // Uses choma_search_substr (strstr) instead of PFStringMetric (strcmp)
    // because AMFI cstrings embed anchors in longer messages:
    //   "AMFI: cannot allocate memory\0" — strcmp("AMFI:") misses this
    //   strstr("AMFI: cannot allocate memory", "AMFI:") finds it.
    // ========================================================================
    diag("[CHOMA] choma_find_amfi: === STRATEGY D: anchor substring ===\n");
    PFSection *amfiCstr = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__cstring");
    PFSection *amfiTextD = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT_EXEC", "__text");
    if (!amfiTextD) amfiTextD = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__text");

    if (amfiCstr && amfiTextD) {
        // Broader anchor set — includes shorter substrings to catch more messages
        const char *anchorStrings[] = {
            "AMFI:", "AppleMobileFileIntegrity",
            "com.apple.security.exception.",
            "TrustCache", "trust_cache", "CDHash", "cdhash",
            "platform-application", "developer_mode",
            "MACF", "entitlement",
            NULL
        };
        for (int a = 0; anchorStrings[a] && !result; a++) {
            __block uint64_t anchorAddr = 0;
            choma_search_substr(amfiCstr, anchorStrings[a],
                ^(uint64_t va, bool *stop) { anchorAddr = va; *stop = true; });
            if (!anchorAddr) { diag("[CHOMA] choma_find_amfi: [D] '%s' NOT found\n", anchorStrings[a]); continue; }
            diag("[CHOMA] choma_find_amfi: [D] '%s' at 0x%llx\n", anchorStrings[a], anchorAddr);

            PFXrefMetric *xm = pfmetric_xref_init(anchorAddr, XREF_TYPE_MASK_REFERENCE);
            __block uint64_t refAddr = 0;
            __block int xrefCount = 0;
            pfmetric_run(amfiTextD, xm, ^(uint64_t va, bool *stop) {
                refAddr = va;
                xrefCount++;
                diag("[CHOMA] choma_find_amfi: [D] xref[%d]=0x%llx\n", xrefCount, va);
                *stop = false;
            });
            pfmetric_free(xm);
            diag("[CHOMA] choma_find_amfi: [D] '%s' has %d xrefs\n", anchorStrings[a], xrefCount);

            if (refAddr) {
                result = pfsec_find_function_start(amfiTextD, refAddr);
                diag("[CHOMA] choma_find_amfi: [D] func=0x%llx from '%s' xref=0x%llx\n", result, anchorStrings[a], refAddr);
            }
        }
    } else {
        diag("[CHOMA] choma_find_amfi: [D] FAILED (cstr=%p text=%p)\n", (void*)amfiCstr, (void*)amfiTextD);
    }
    pfsec_free(amfiCstr);
    pfsec_free(amfiTextD);

    // ========================================================================
    // Strategy E: PACIBSP-based function enumeration with size + loop filtering
    //
    fprintf(stderr, "[CHOMA_D] === STRATEGY E: PACIBSP function enum ===\n");
    // LC_FUNCTION_STARTS returns 0 entries on iOS 18.2+.  Instead, scan
    // __TEXT_EXEC directly for function prologues (PACIBSP on arm64e,
    // SUB sp on arm64).  Then:
    //   a) compute function sizes (distance to next prologue)
    //   b) filter out tiny stubs (< 20 B) and huge functions (> 1000 B)
    //   c) count backward branches (loops) within each function
    //   d) score = BL-refs*10 + callers + loops*50 + size_bonus
    //   e) return best candidate from filtered set
    // ========================================================================
    diag("[CHOMA] choma_find_amfi: === STRATEGY E: PACIBSP enumeration ===\n");
    {
        PFSection *txtE = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT_EXEC", "__text");
        if (!txtE) txtE = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__text");
        if (txtE) {
            uint64_t textStart = txtE->info.vmaddr;
            uint64_t textEnd   = textStart + txtE->info.size;
            uint64_t *funcStartsE = calloc(4096, sizeof(uint64_t));
            int funcCountE = 0;

            // Pass 1: find all function starts
            for (uint64_t addr = textStart; addr < textEnd && funcCountE < 4096; addr += 4) {
                uint32_t inst = pfsec_read32(txtE, addr);
                if (inst == 0xD503237F || inst == 0xD503227F) {
                    funcStartsE[funcCountE++] = addr;
                }
            }
            if (funcCountE == 0) {
                for (uint64_t addr = textStart; addr < textEnd && funcCountE < 4096; addr += 4) {
                    uint32_t inst = pfsec_read32(txtE, addr);
                    if ((inst & 0xFF8003FF) == 0xD10003FF) {
                        funcStartsE[funcCountE++] = addr;
                    }
                }
            }
            diag("[CHOMA] choma_find_amfi: [E] %d function starts\n", funcCountE);

            if (funcCountE > 0) {
                // Compute function sizes + count BL-refs + count loops
                uint64_t *sizesE  = calloc(funcCountE, sizeof(uint64_t));
                uint64_t *refsE   = calloc(funcCountE, sizeof(uint64_t));
                int *callersE     = calloc(funcCountE, sizeof(int));
                int *loopsE       = calloc(funcCountE, sizeof(int));

                for (int f = 0; f < funcCountE; f++) {
                    uint64_t start = funcStartsE[f];
                    uint64_t end   = (f + 1 < funcCountE) ? funcStartsE[f + 1] : textEnd;
                    sizesE[f] = end - start;
                }

                uint64_t totalBLsE = 0;
                for (uint64_t addr = textStart; addr < textEnd; addr += 4) {
                    uint32_t inst = pfsec_read32(txtE, addr);

                    if ((inst & 0xFC000000) == 0x94000000) { // BL
                        totalBLsE++;
                        int32_t offset = (int32_t)(inst & 0x03FFFFFF);
                        if (offset & 0x02000000) offset |= 0xFC000000;
                        uint64_t target = addr + (uint64_t)(offset * 4);

                        int fi;
                        for (fi = funcCountE - 1; fi >= 0; fi--) {
                            if (funcStartsE[fi] <= target) break;
                        }
                        if (fi >= 0 && (target - funcStartsE[fi]) < sizesE[fi]) {
                            refsE[fi]++;
                            int ci;
                            for (ci = funcCountE - 1; ci >= 0; ci--) {
                                if (funcStartsE[ci] <= addr) break;
                            }
                            if (ci >= 0 && ci != fi) callersE[fi]++;
                        }
                    }

                    // Detect backward branches (loops): B.cond, CBZ, CBNZ
                    if ((inst & 0xFF000010) == 0x54000000) { // B.cond
                        int32_t b_off = (int32_t)(inst & 0x00FFFFE0) >> 5;
                        uint64_t b_target = addr + (uint64_t)(b_off * 4);
                        if (b_target < addr) {  // backward = loop
                            int fi;
                            for (fi = funcCountE - 1; fi >= 0; fi--) {
                                if (funcStartsE[fi] <= addr) break;
                            }
                            if (fi >= 0 && b_target >= funcStartsE[fi]) loopsE[fi]++;
                        }
                    }
                    if ((inst & 0x7E000000) == 0x34000000 ||   // CBZ/CBNZ (32-bit)
                        (inst & 0x7E000000) == 0x35000000) {
                        int32_t cb_off = (int32_t)((inst & 0x00FFFFE0) >> 5);
                        uint64_t cb_target = addr + (uint64_t)(cb_off * 4);
                        if (cb_target < addr) {  // backward = loop
                            int fi;
                            for (fi = funcCountE - 1; fi >= 0; fi--) {
                                if (funcStartsE[fi] <= addr) break;
                            }
                            if (fi >= 0 && cb_target >= funcStartsE[fi]) loopsE[fi]++;
                        }
                    }
                }

                diag("[CHOMA] choma_find_amfi: [E] scanned 0x%llx bytes, %llu BL total\n",
                     textEnd - textStart, totalBLsE);

                // Pass 3: count data-section ADRP references per function
                PFSection *dataSecE = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA_CONST", "__data");
                if (!dataSecE) dataSecE = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA", "__data");

                uint64_t *dataRefsE = calloc(funcCountE, sizeof(uint64_t));
                if (dataSecE) {
                    for (int f = 0; f < funcCountE; f++) {
                        uint64_t end = (f + 1 < funcCountE) ? funcStartsE[f+1] : textEnd;
                        for (uint64_t a = funcStartsE[f]; a < end && a < funcStartsE[f] + 1600; a += 4) {
                            uint64_t r = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(txtE, a);
                            if (r && pfsec_contains_vmaddr(dataSecE, r)) {
                                dataRefsE[f]++;
                            }
                        }
                    }
                }

                // Score + rank.
                // FIX: prefer functions that reference AMFI data globals via ADRP.
                // This excludes utility functions (printf, IOMalloc, etc.) that don't
                // touch AMFI data structures but have many BL references.
                int bestIdx = -1;
                uint64_t bestScore = 0;
                int candidatesLogged = 0;

                for (int f = 0; f < funcCountE; f++) {
                    if (sizesE[f] < 40 || sizesE[f] > 1000) continue;
                    if (dataSecE && dataRefsE[f] == 0) continue;

                    uint64_t refScore = refsE[f] < 5 ? refsE[f] * 5 : 25 - (refsE[f] - 5) * 10;
                    if (refsE[f] > 15) refScore = 0;

                    uint64_t score = dataRefsE[f] * 30 + refScore + loopsE[f] * 50 + callersE[f];
                    if (sizesE[f] >= 80 && sizesE[f] <= 500) score += 30;
                    else if (sizesE[f] > 500) score += 10;

                    if (score > bestScore) {
                        bestScore = score;
                        bestIdx = f;
                    }

                    if (candidatesLogged < 15 || refsE[f] > 3 || loopsE[f] > 0 || dataRefsE[f] > 0) {
                        diag("[CHOMA] choma_find_amfi: [E] func[%d]=0x%llx size=%llu refs=%llu callers=%d loops=%d dataRefs=%llu score=%llu%s\n",
                             f, funcStartsE[f], sizesE[f], refsE[f], callersE[f], loopsE[f], dataRefsE[f], score,
                             f == bestIdx ? " [BEST]" : "");
                        candidatesLogged++;
                    }
                }

                int pickIdx = -1;
                if (bestIdx >= 0) {
                    pickIdx = bestIdx;
                    result = funcStartsE[pickIdx];
                    diag("[CHOMA] choma_find_amfi: [E] picks func[%d] (0x%llx) size=%llu refs=%llu dataRefs=%llu loops=%d score=%llu\n",
                         pickIdx, funcStartsE[pickIdx], sizesE[pickIdx], refsE[pickIdx], dataRefsE[pickIdx], loopsE[pickIdx], bestScore);
                } else {
                    diag("[CHOMA] choma_find_amfi: [E] no valid candidate after data-ref filter\n");
                }
                free(sizesE);
                free(refsE);
                free(callersE);
                free(loopsE);
                free(dataRefsE);
                if (dataSecE) pfsec_free(dataSecE);
            }
            pfsec_free(txtE);
            free(funcStartsE);
        } else {
            diag("[CHOMA] choma_find_amfi: [E] could not carve AMFI text section\n");
        }
    }
    if (result) {
        diag("[CHOMA] choma_find_amfi: [E] returned candidate — Strategy F will NOT run\n");
        return result;
    }
    diag("[CHOMA] choma_find_amfi: [E] FAILED — falling through to Strategy F\n");

    // ========================================================================
    // Strategy F: cross-section string scan across ALL entries
    fprintf(stderr, "[CHOMA_D] === STRATEGY F: cross-section string scan ===\n");
    //
    // Search every fileset entry's __cstring, __const, __objc_methname,
    // __objc_classname, etc. for AMFI-related strings that might be
    // cross-referenced from code.  Tries: "CDHash", "isCDHash",
    // "trustcache", "trust_cache", "AMFI".
    // ========================================================================
    diag("[CHOMA] choma_find_amfi: === STRATEGY F: cross-section string scan ===\n");
    {
        const char *searchStrings[] = {
            "CDHash", "isCDHash", "trustcache", "trust_cache",
            "AMFI", "MobileFileIntegrity", NULL
        };
        const char *searchSegments[] = {"__TEXT", "__DATA_CONST", "__DATA", NULL};
        const char *searchSections[] = {"__cstring", "__const", "__data", NULL};

        for (int si = 0; searchStrings[si] && !result; si++) {
            diag("[CHOMA] choma_find_amfi: [F] searching for '%s'\n", searchStrings[si]);
            for (uint32_t e = 0; e < kernel->filesetCount && !result; e++) {
                FilesetMachO *entry = &kernel->filesetMachos[e];
                if (!entry->underlyingMachO || entry->underlyingMachO->slicesCount != 1) continue;

                for (int sg = 0; searchSegments[sg] && !result; sg++) {
                    for (int sc = 0; searchSections[sc] && !result; sc++) {
                        PFSection *sec = section_from_fileset_entry(kernel, entry->entry_id,
                                        searchSegments[sg], searchSections[sc]);
                        if (!sec) continue;
                        __block uint64_t strAddr = 0;
                        choma_search_substr(sec, searchStrings[si],
                            ^(uint64_t va, bool *stop) { strAddr = va; *stop = true; });
                        if (strAddr) {
                            diag("[CHOMA] choma_find_amfi: [F] FOUND '%s' in '%s' %s,%s at 0x%llx\n",
                                 searchStrings[si], entry->entry_id,
                                 searchSegments[sg], searchSections[sc], strAddr);
                            // Xref → function start
                            PFSection *txtF = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT_EXEC", "__text");
                            if (!txtF) txtF = section_from_fileset_entry(kernel, entry->entry_id, "__TEXT", "__text");
                            if (txtF) {
                                PFXrefMetric *xmF = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
                                __block uint64_t refAddr = 0;
                                pfmetric_run(txtF, xmF, ^(uint64_t va, bool *stop) { refAddr = va; *stop = true; });
                                pfmetric_free(xmF);
                                if (refAddr) {
                                    result = pfsec_find_function_start(txtF, refAddr);
                                    diag("[CHOMA] choma_find_amfi: [F] xref=0x%llx func=0x%llx\n", refAddr, result);
                                }
                                pfsec_free(txtF);
                            }
                        }
                        pfsec_free(sec);
                    }
                }
            }
        }
    }
    if (result) return result;
    diag("[CHOMA] choma_find_amfi: [F] FAILED\n");

    if (!result) xpf_set_error("choma_find_amfi: ALL STRATEGIES FAILED");
    return result;
}

// ---------------------------------------------------------------------------
// choma_find_dev_mode_status_direct
//
// Multi-strategy search for the developer_mode_status global variable.
//
// Strategies:
//   A: Search "developer_mode_status" in AMFI entry's cstring / const
//   B: Anchor string ("DeveloperMode", "developer", "force enabled") in AMFI
//      cstring -> xref -> function -> ADRP scan for data section refs
//   C: Fallback: kernel entry cstring search (legacy approach)
// ---------------------------------------------------------------------------
uint64_t choma_find_dev_mode_status_direct(void)
{
    MachO *kernel = gXPF.kernel;
    if (!kernel) { xpf_set_error("choma_find_dev: gXPF.kernel is NULL"); return 0; }
    if (kernel->filesetCount == 0) { xpf_set_error("choma_find_dev: not a fileset"); return 0; }

    diag("[CHOMA] choma_find_dev: %u fileset entries\n", kernel->filesetCount);

    // Find AMFI entry (shared helper)
    MachO *amfiMacho_dev = NULL;
    FilesetMachO *amfiEntry = find_amfi_entry(kernel, &amfiMacho_dev);
    if (amfiEntry) {
        diag("[CHOMA] choma_find_dev: AMFI entry='%s'\n", amfiEntry->entry_id);
    }

    // Also find kernel entry (needed by strategy C)
    char *kernelEntryId = find_kernel_entry_id(kernel);
    diag("[CHOMA] choma_find_dev: kernel entry='%s' AMFI entry='%s'\n", kernelEntryId ? kernelEntryId : "(null)", amfiEntry ? amfiEntry->entry_id : "(null)");

    __block uint64_t result = 0;

    // ========================================================================
    // Strategy 0: unique panic string in kernel entry (XPF approach)
    // Uses: "Just like pineapple on pizza, this task/thread port doesn't
    //        belong here. @%s:%d" — a unique kernel panic cstring that
    //        is cross-referenced from a function that also references the
    //        developer_mode_status global variable.
    // ========================================================================
    if (!result) {
        diag("[CHOMA] choma_find_dev: === STRATEGY 0: pineapple panic string ===\n");
        const char *devPanicStr = "Just like pineapple on pizza, this task/thread port doesn't belong here. @%s:%d";

        if (kernelEntryId) {
            PFSection *kcstr = section_from_fileset_entry(kernel, kernelEntryId, "__TEXT", "__cstring");
            PFSection *ktxt = section_from_fileset_entry(kernel, kernelEntryId, "__TEXT_EXEC", "__text");
            if (!ktxt) ktxt = section_from_fileset_entry(kernel, kernelEntryId, "__TEXT", "__text");
            PFSection *kdata = section_from_fileset_entry(kernel, kernelEntryId, "__DATA_CONST", "__data");
            if (!kdata) kdata = section_from_fileset_entry(kernel, kernelEntryId, "__DATA", "__data");

            if (kcstr && ktxt && kdata) {
                __block uint64_t psAddr = 0;
                choma_search_substr(kcstr, devPanicStr,
                    ^(uint64_t va, bool *stop) { psAddr = va; *stop = true; });

                if (psAddr) {
                    diag("[CHOMA] choma_find_dev: [0] found pineapple string at 0x%llx\n", psAddr);
                    PFXrefMetric *xmp = pfmetric_xref_init(psAddr, XREF_TYPE_MASK_REFERENCE);
                    __block uint64_t xrAddr = 0;
                    pfmetric_run(ktxt, xmp, ^(uint64_t va, bool *stop) { xrAddr = va; *stop = true; });
                    pfmetric_free(xmp);

                    if (xrAddr) {
                        uint64_t func = pfsec_find_function_start(ktxt, xrAddr);
                        diag("[CHOMA] choma_find_dev: [0] xref=0x%llx func=0x%llx\n", xrAddr, func);
                        if (func) {
                            for (int d = 0; d < 200 && !result; d++) {
                                uint64_t a = func + (d * 4);
                                uint64_t r = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(ktxt, a);
                                if (r && pfsec_contains_vmaddr(kdata, r)) {
                                    diag("[CHOMA] choma_find_dev: [0] FUNC+%d ADRP -> data 0x%llx\n", d*4, r);
                                    result = r;
                                }
                            }
                        }
                    }
                } else {
                    diag("[CHOMA] choma_find_dev: [0] pineapple string NOT found in kernel cstring\n");
                }
            } else {
                diag("[CHOMA] choma_find_dev: [0] could not carve sections (cstr=%p txt=%p data=%p)\n",
                     (void*)kcstr, (void*)ktxt, (void*)kdata);
            }
            pfsec_free(kcstr);
            pfsec_free(ktxt);
            pfsec_free(kdata);
        } else {
            diag("[CHOMA] choma_find_dev: [0] no kernel entry found\n");
        }
    }
    if (result) return result;

    // ========================================================================
    // Strategy A: "developer_mode_status" in AMFI cstring / const
    // ========================================================================
    if (amfiEntry && !result) {
        diag("[CHOMA] choma_find_dev: === STRATEGY A: literal search in AMFI ===\n");
        const char *sections[] = {"__cstring", "__const"};
        for (int s = 0; s < 2 && !result; s++) {
            PFSection *sec = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", sections[s]);
            if (!sec) { diag("[CHOMA] choma_find_dev: [A] no __TEXT,%s in AMFI\n", sections[s]); continue; }
            diag("[CHOMA] choma_find_dev: [A] searching AMFI __TEXT,%s (size=0x%llx)\n", sections[s], sec->info.size);

            PFStringMetric *sm = pfmetric_string_init("developer_mode_status");
            __block uint64_t strAddr = 0;
            pfmetric_run(sec, sm, ^(uint64_t va, bool *stop) { strAddr = va; *stop = true; });
            pfmetric_free(sm);

            if (strAddr) {
                diag("[CHOMA] choma_find_dev: [A] FOUND 'developer_mode_status' in AMFI __TEXT,%s at 0x%llx\n", sections[s], strAddr);
                // Xref to find referencing code, then ADRP scan
                PFSection *txt = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT_EXEC", "__text");
                if (!txt) txt = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__text");
                if (txt) {
                    PFXrefMetric *xm = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
                    __block uint64_t xrefAddr = 0;
                    pfmetric_run(txt, xm, ^(uint64_t va, bool *stop) { xrefAddr = va; *stop = true; });
                    pfmetric_free(xm);
                    if (xrefAddr) {
                        uint64_t func = pfsec_find_function_start(txt, xrefAddr);
                        diag("[CHOMA] choma_find_dev: [A] xref=0x%llx func=0x%llx\n", xrefAddr, func);
                        if (func) {
                            // Scan function for ADRP pointing to data section
                            PFSection *dataSec = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA_CONST", "__data");
                            if (!dataSec) dataSec = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA", "__data");
                            if (!dataSec) dataSec = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA_CONST", "__const");
                            if (dataSec) {
                                diag("[CHOMA] choma_find_dev: [A] scanning func for ADRP to data (vmaddr=0x%llx size=0x%llx)\n", dataSec->info.vmaddr, dataSec->info.size);
                                for (int d = 0; d < 400 && !result; d++) {
                                    uint64_t a = func + (d * 4);
                                    uint64_t r = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(txt, a);
                                    if (r && pfsec_contains_vmaddr(dataSec, r)) {
                                        diag("[CHOMA] choma_find_dev: [A] FUNC+%d ADRP -> data VA 0x%llx\n", d*4, r);
                                        result = r;
                                    }
                                }
                                pfsec_free(dataSec);
                            } else { diag("[CHOMA] choma_find_dev: [A] no data section found in AMFI\n"); }
                        }
                    } else { diag("[CHOMA] choma_find_dev: [A] no xref to string in AMFI text\n"); }
                    pfsec_free(txt);
                }
            } else {
                diag("[CHOMA] choma_find_dev: [A] 'developer_mode_status' NOT in __TEXT,%s\n", sections[s]);
            }
            pfsec_free(sec);
        }
    } else if (!amfiEntry) {
        diag("[CHOMA] choma_find_dev: [A] skipped (no AMFI entry)\n");
    }
    if (result) return result;

    // ========================================================================
    // Strategy B: anchor substrings in AMFI cstring -> xref -> function -> ADRP
    // Uses choma_search_substr (strstr) to find embedded anchors in longer
    // cstrings — the old PFStringMetric (strcmp) missed everything.
    // ========================================================================
    if (amfiEntry && !result) {
        diag("[CHOMA] choma_find_dev: === STRATEGY B: anchor substrings ===\n");
        PFSection *cstr = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__cstring");
        PFSection *txt = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT_EXEC", "__text");
        if (!txt) txt = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__text");
        if (cstr && txt) {
            const char *anchors[] = {
                "DeveloperMode", "developer", "force enabled", "devmode",
                "developer_mode", "AMFI", "entitlement",
                "platform-application", "platform_application",
                NULL
            };
            for (int a = 0; anchors[a] && !result; a++) {
                __block uint64_t anchorAddr = 0;
                choma_search_substr(cstr, anchors[a],
                    ^(uint64_t va, bool *stop) { anchorAddr = va; *stop = true; });
                if (!anchorAddr) { diag("[CHOMA] choma_find_dev: [B] '%s' NOT found\n", anchors[a]); continue; }
                diag("[CHOMA] choma_find_dev: [B] '%s' at 0x%llx\n", anchors[a], anchorAddr);

                PFXrefMetric *xm = pfmetric_xref_init(anchorAddr, XREF_TYPE_MASK_REFERENCE);
                __block uint64_t xrefAddr = 0;
                pfmetric_run(txt, xm, ^(uint64_t va, bool *stop) { xrefAddr = va; *stop = true; });
                pfmetric_free(xm);
                if (!xrefAddr) { diag("[CHOMA] choma_find_dev: [B] no xref from '%s'\n", anchors[a]); continue; }

                uint64_t func = pfsec_find_function_start(txt, xrefAddr);
                diag("[CHOMA] choma_find_dev: [B] '%s' xref=0x%llx func=0x%llx\n", anchors[a], xrefAddr, func);
                if (!func) continue;

                PFSection *dataSec = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA_CONST", "__data");
                if (!dataSec) dataSec = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA", "__data");
                if (!dataSec) dataSec = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__DATA_CONST", "__const");
                if (!dataSec) { diag("[CHOMA] choma_find_dev: [B] no data section\n"); continue; }

                for (int d = 0; d < 400 && !result; d++) {
                    uint64_t addr = func + (d * 4);
                    uint64_t r = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(txt, addr);
                    if (r && pfsec_contains_vmaddr(dataSec, r)) {
                        diag("[CHOMA] choma_find_dev: [B] '%s' FUNC+%d ADRP -> 0x%llx\n", anchors[a], d*4, r);
                        result = r;
                    }
                }
                pfsec_free(dataSec);
            }
        } else {
            diag("[CHOMA] choma_find_dev: [B] cannot carve sections (cstr=%p text=%p)\n", (void*)cstr, (void*)txt);
        }
        pfsec_free(cstr);
        pfsec_free(txt);
    } else if (!amfiEntry) {
        diag("[CHOMA] choma_find_dev: [B] skipped (no AMFI entry)\n");
    }
    if (result) return result;

    // ========================================================================
    // Strategy C: fallback to kernel entry cstring (legacy approach)
    // ========================================================================
    if (kernelEntryId && !result) {
        diag("[CHOMA] choma_find_dev: === STRATEGY C: kernel entry fallback ===\n");
        PFSection *kText = section_from_fileset_entry(kernel, kernelEntryId, "__TEXT_EXEC", "__text");
        if (!kText) kText = section_from_fileset_entry(kernel, kernelEntryId, "__TEXT", "__text");
        PFSection *kCstr = section_from_fileset_entry(kernel, kernelEntryId, "__TEXT", "__cstring");
        PFSection *kData = section_from_fileset_entry(kernel, kernelEntryId, "__DATA_CONST", "__data");
        if (!kData) kData = section_from_fileset_entry(kernel, kernelEntryId, "__DATA", "__data");

        if (kText && kCstr) {
            diag("[CHOMA] choma_find_dev: [C] kernel cstring size=0x%llx\n", kCstr->info.size);
            PFStringMetric *sm = pfmetric_string_init("developer_mode_status");
            __block uint64_t strAddr = 0;
            pfmetric_run(kCstr, sm, ^(uint64_t va, bool *stop) { strAddr = va; *stop = true; });
            pfmetric_free(sm);

            if (strAddr) {
                diag("[CHOMA] choma_find_dev: [C] FOUND in kernel cstring at 0x%llx\n", strAddr);
                PFXrefMetric *xm = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
                __block uint64_t xrefAddr = 0;
                pfmetric_run(kText, xm, ^(uint64_t va, bool *stop) { xrefAddr = va; *stop = true; });
                pfmetric_free(xm);
                if (xrefAddr && kData) {
                    uint64_t func = pfsec_find_function_start(kText, xrefAddr);
                    diag("[CHOMA] choma_find_dev: [C] xref=0x%llx func=0x%llx\n", xrefAddr, func);
                    if (func) {
                        for (int d = 0; d < 100 && !result; d++) {
                            uint64_t addr = func + (d * 4);
                            uint64_t r = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(kText, addr);
                            if (r && pfsec_contains_vmaddr(kData, r)) {
                                diag("[CHOMA] choma_find_dev: [C] FUNC+%d ADRP -> 0x%llx\n", d*4, r);
                                result = r;
                            }
                        }
                    }
                } else {
                    diag("[CHOMA] choma_find_dev: [C] no xref or no data section\n");
                }
            } else {
                diag("[CHOMA] choma_find_dev: [C] 'developer_mode_status' NOT in kernel cstring\n");
            }
        } else {
            diag("[CHOMA] choma_find_dev: [C] cannot carve kernel sections\n");
        }
        pfsec_free(kText);
        pfsec_free(kCstr);
        pfsec_free(kData);
    } else if (!kernelEntryId) {
        diag("[CHOMA] choma_find_dev: [C] skipped (no kernel entry)\n");
    }

    // ========================================================================
    // Strategy D: data-section ADRP scan across ALL AMFI functions
    //
    // Enumerate every function start in AMFI (via PACIBSP prologue scan)
    // and scan the first 400 instructions for ADRP references into any
    // __DATA / __DATA_CONST section.  Every ADRP target is a candidate
    // global variable.  Return the one referenced by the MOST functions
    // (heuristic: developer_mode_status is accessed by many callers).
    // ========================================================================
    if (amfiEntry && !result) {
        diag("[CHOMA] choma_find_dev: === STRATEGY D: AMFI function ADRP scan ===\n");
        PFSection *txtD = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT_EXEC", "__text");
        if (!txtD) txtD = section_from_fileset_entry(kernel, amfiEntry->entry_id, "__TEXT", "__text");
        if (txtD) {
            uint64_t tStart = txtD->info.vmaddr;
            uint64_t tEnd   = tStart + txtD->info.size;

            // Find all AMFI function starts via PACIBSP / SUB-prologue scan
            uint64_t *funcStartsD = calloc(2048, sizeof(uint64_t));
            int funcCountD = 0;
            for (uint64_t addr = tStart; addr < tEnd && funcCountD < 2048; addr += 4) {
                uint32_t inst = pfsec_read32(txtD, addr);
                if (inst == 0xD503237F || inst == 0xD503227F ||
                    ((inst & 0xFF8003FF) == 0xD10003FF && funcCountD == 0)) {
                    funcStartsD[funcCountD++] = addr;
                }
            }

            diag("[CHOMA] choma_find_dev: [D] %d AMFI function starts\n", funcCountD);

            // Build list of data sections in AMFI
            PFSection *dataSectionsD[8];
            int dataCountD = 0;
            const char *dSegs[] = {"__DATA_CONST", "__DATA", "__DATA_DIRTY", NULL};
            const char *dSects[] = {"__data", "__const", "__common", NULL};
            for (int si = 0; dSegs[si] && dataCountD < 8; si++) {
                for (int sj = 0; dSects[sj] && dataCountD < 8; sj++) {
                    PFSection *ds = section_from_fileset_entry(kernel, amfiEntry->entry_id, dSegs[si], dSects[sj]);
                    if (ds) dataSectionsD[dataCountD++] = ds;
                }
            }
            diag("[CHOMA] choma_find_dev: [D] %d data sections in AMFI\n", dataCountD);

            if (dataCountD > 0 && funcCountD > 0) {
                // For each function, scan its first 400 instructions for ADRP
                // Count how many functions reference each data address
                typedef struct { uint64_t addr; int count; } DataRef;
                DataRef *refsD = calloc(4096, sizeof(DataRef));
                int refCountD = 0;

                for (int fi = 0; fi < funcCountD && fi < 200; fi++) {
                    uint64_t funcStart = funcStartsD[fi];
                    for (int di = 0; di < 400; di++) {
                        uint64_t insAddr = funcStart + (di * 4);
                        if (insAddr >= tEnd) break;
                        uint64_t r = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(txtD, insAddr);
                        if (!r) continue;
                        for (int ds = 0; ds < dataCountD; ds++) {
                            if (pfsec_contains_vmaddr(dataSectionsD[ds], r)) {
                                // Found an ADRP into data section — track it
                                int found = 0;
                                for (int ri = 0; ri < refCountD; ri++) {
                                    if (refsD[ri].addr == r) { refsD[ri].count++; found = 1; break; }
                                }
                                if (!found && refCountD < 4096) {
                                    refsD[refCountD].addr = r;
                                    refsD[refCountD].count = 1;
                                    refCountD++;
                                }
                                break;
                            }
                        }
                    }
                }

                diag("[CHOMA] choma_find_dev: [D] %d unique data refs found\n", refCountD);

                // Log top refs by caller-count
                for (int ri = 0; ri < refCountD && ri < 20; ri++) {
                    diag("[CHOMA] choma_find_dev: [D] data[%d] 0x%llx referenced by %d functions\n",
                         ri, refsD[ri].addr, refsD[ri].count);
                }

                // Sort by count descending, pick the most-referenced
                // developer_mode_status should be referenced by multiple functions
                int bestRef = -1;
                int bestCnt = 0;
                for (int ri = 0; ri < refCountD; ri++) {
                    if (refsD[ri].count > bestCnt && refsD[ri].count >= 2) {
                        bestCnt = refsD[ri].count;
                        bestRef = ri;
                    }
                }
                if (bestRef >= 0) {
                    result = refsD[bestRef].addr;
                    diag("[CHOMA] choma_find_dev: [D] PICKED 0x%llx (%d functions)\n", result, bestCnt);
                } else {
                    diag("[CHOMA] choma_find_dev: [D] no data ref with >=2 callers\n");
                }
                free(refsD);
            }
            for (int di = 0; di < dataCountD; di++) pfsec_free(dataSectionsD[di]);
            pfsec_free(txtD);
            free(funcStartsD);
        } else {
            diag("[CHOMA] choma_find_dev: [D] no AMFI text section\n");
        }
    }
    if (result) return result;
    diag("[CHOMA] choma_find_dev: [D] FAILED\n");

    // ========================================================================
    // Strategy E: all-sections dev mode string search across ALL entries
    //
    // Search every fileset entry's __cstring, __const, __objc_methname, etc.
    // for any dev-mode-related string.  If found, xref → function → ADRP
    // scan into data sections.
    // ========================================================================
    diag("[CHOMA] choma_find_dev: === STRATEGY E: all-sections scan ===\n");
    {
        const char *devStrings[] = {
            "developer", "Developer", "devmode", "DevMode", "DEVMODE",
            "force_enabled", "developer_mode", "development", NULL
        };
        const char *eSegs[] = {"__TEXT", "__DATA_CONST", "__DATA", NULL};
        const char *eSects[] = {"__cstring", "__const", "__data", "__objc_methname", NULL};

        for (int si = 0; devStrings[si] && !result; si++) {
            diag("[CHOMA] choma_find_dev: [E] searching '%s'\n", devStrings[si]);

            for (uint32_t e = 0; e < kernel->filesetCount && !result; e++) {
                FilesetMachO *entry = &kernel->filesetMachos[e];
                if (!entry->underlyingMachO || entry->underlyingMachO->slicesCount != 1) continue;

                for (int sg = 0; eSegs[sg] && !result; sg++) {
                    for (int sc = 0; eSects[sc] && !result; sc++) {
                        PFSection *sec = section_from_fileset_entry(kernel, entry->entry_id,
                                        eSegs[sg], eSects[sc]);
                        if (!sec) continue;
                        __block uint64_t strAddr = 0;
                        choma_search_substr(sec, devStrings[si],
                            ^(uint64_t va, bool *stop) { strAddr = va; *stop = true; });
                        if (strAddr) {
                            diag("[CHOMA] choma_find_dev: [E] FOUND '%s' in '%s' %s,%s at 0x%llx\n",
                                 devStrings[si], entry->entry_id, eSegs[sg], eSects[sc], strAddr);
                            // Xref → function → ADRP into data
                            PFSection *txtE2 = section_from_fileset_entry(kernel, entry->entry_id,
                                                     "__TEXT_EXEC", "__text");
                            if (!txtE2) txtE2 = section_from_fileset_entry(kernel, entry->entry_id,
                                                     "__TEXT", "__text");
                            PFSection *dataE2 = section_from_fileset_entry(kernel, entry->entry_id,
                                                        "__DATA_CONST", "__data");
                            if (!dataE2) dataE2 = section_from_fileset_entry(kernel, entry->entry_id,
                                                        "__DATA", "__data");
                            if (txtE2 && dataE2) {
                                PFXrefMetric *xmE = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
                                __block uint64_t refAddr = 0;
                                pfmetric_run(txtE2, xmE, ^(uint64_t va, bool *stop) { refAddr = va; *stop = true; });
                                pfmetric_free(xmE);
                                if (refAddr) {
                                    uint64_t funcE = pfsec_find_function_start(txtE2, refAddr);
                                    diag("[CHOMA] choma_find_dev: [E] xref=0x%llx func=0x%llx\n", refAddr, funcE);
                                    if (funcE) {
                                        for (int d = 0; d < 400 && !result; d++) {
                                            uint64_t a = funcE + (d * 4);
                                            uint64_t r = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(txtE2, a);
                                            if (r && pfsec_contains_vmaddr(dataE2, r)) {
                                                diag("[CHOMA] choma_find_dev: [E] FUNC+%d ADRP -> 0x%llx\n", d*4, r);
                                                result = r;
                                            }
                                        }
                                    }
                                }
                            }
                            pfsec_free(txtE2);
                            pfsec_free(dataE2);
                        }
                        pfsec_free(sec);
                    }
                }
            }
        }
    }
    if (result) return result;
    diag("[CHOMA] choma_find_dev: [E] FAILED\n");

    if (!result) xpf_set_error("choma_find_dev: ALL STRATEGIES FAILED");
    return result;
}


// ---------------------------------------------------------------------------
// Swift 6 concurrency-safe accessors for C globals set by offsets_init().
// Swift cannot directly access mutable C globals without concurrency warnings.
// These functions provide a non-isolated bridge.
// ---------------------------------------------------------------------------
extern uint32_t off_proc_p_pid;
extern uint32_t off_proc_p_list_le_next;
uint32_t get_off_proc_p_pid(void) { return off_proc_p_pid; }
uint32_t get_off_proc_p_list_le_next(void) { return off_proc_p_list_le_next; }
