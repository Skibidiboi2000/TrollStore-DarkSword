#include "choma_trustcache.h"
#include "choma_helpers.h"
#include "PatchFinder.h"
#include "PatchFinder_arm64.h"
#include <string.h>
#include <stdlib.h>

#define TRUSTCACHE_ANCHOR_STRING "unexpected size for TrustCache property: %u != %zu @%s:%d"


// ---------------------------------------------------------------------------
// choma_find_trust_cache_by_data_scan
//
// Scans the AMFI entry's __DATA_CONST,__data (or __DATA,__data) section for
// a trust cache header: version(1|2) + UUID(16B, ≥1 non-zero dword) +
// num_entries(<65535).  Returns UNSLID VM address, or 0.
//
// Unlike choma_find_trust_cache_runtime(), this does NOT rely on any debug /
// panic string — it finds the trust cache by its on-disk data layout.
// ---------------------------------------------------------------------------
uint64_t choma_find_trust_cache_by_data_scan(void)
{
    MachO *kernel = gXPF.kernel;
    if (!kernel || kernel->filesetCount == 0) return 0;

    // Scan AMFI's data section — the trust cache lives there, not in the
    // kernel entry's data section (which is multiple MB and full of noise).
    char *amfiEntry = NULL;
    for (uint32_t i = 0; i < kernel->filesetCount; i++) {
        const char *eid = kernel->filesetMachos[i].entry_id;
        if (!eid) continue;
        if (strstr(eid, "com.apple.driver.AppleMobileFileIntegrity") ||
            strstr(eid, "AMFI")) {
            amfiEntry = strdup(eid);
            break;
        }
    }
    if (!amfiEntry) return 0;

    PFSection *data = section_from_fileset_entry(kernel, amfiEntry,
                                                  "__DATA_CONST", "__data");
    if (!data) data = section_from_fileset_entry(kernel, amfiEntry,
                                                  "__DATA", "__data");
    if (!data) { free(amfiEntry); return 0; }

    uint64_t dataStart = data->info.vmaddr;
    uint64_t dataSize  = data->info.size;

    uint64_t result = 0;

    // Walk at 4-byte stride looking for version(4B) + uuid(16B) + count(4B).
    // Count is typically 0 in the file (entries filled at boot), so we allow
    // 0 but require at least one non-zero UUID dword to reject noise.
    for (uint64_t off = 0; off + 24 <= dataSize; off += 4) {
        uint32_t version = pfsec_read32(data, dataStart + off);
        if (version != 1 && version != 2) continue;

        // UUID: at least one of the 4 dwords must be non-zero
        uint32_t u0 = pfsec_read32(data, dataStart + off + 4);
        uint32_t u1 = pfsec_read32(data, dataStart + off + 8);
        uint32_t u2 = pfsec_read32(data, dataStart + off + 12);
        uint32_t u3 = pfsec_read32(data, dataStart + off + 16);
        if ((u0 | u1 | u2 | u3) == 0) continue;

        uint32_t count = pfsec_read32(data, dataStart + off + 20);
        if (count >= 65535) continue;

        result = dataStart + off;
        break;
    }

    pfsec_free(data);
    free(amfiEntry);
    return result;
}

uint64_t choma_find_trust_cache_runtime(void)
{
    MachO *kernel = gXPF.kernel;
    if (!kernel || kernel->filesetCount == 0) return 0;

    char *kernelEntry = NULL;
    for (uint32_t i = 0; i < kernel->filesetCount; i++) {
        const char *eid = kernel->filesetMachos[i].entry_id;
        if (!eid) continue;
        if (strstr(eid, "com.apple.kernel") || strstr(eid, "kernel")) {
            if (!strstr(eid, "AMFI") && !strstr(eid, "Sandbox")) {
                kernelEntry = strdup(eid);
                break;
            }
        }
    }
    if (!kernelEntry) return 0;

    PFSection *kcstr = section_from_fileset_entry(kernel, kernelEntry, "__TEXT", "__cstring");
    if (!kcstr) { free(kernelEntry); return 0; }

    __block uint64_t strAddr = 0;
    choma_search_substr(kcstr, TRUSTCACHE_ANCHOR_STRING,
        ^(uint64_t va, bool *stop) { strAddr = va; *stop = true; });
    pfsec_free(kcstr);
    if (!strAddr) { free(kernelEntry); return 0; }

    PFSection *ktext = section_from_fileset_entry(kernel, kernelEntry, "__TEXT_EXEC", "__text");
    if (!ktext) ktext = section_from_fileset_entry(kernel, kernelEntry, "__TEXT", "__text");
    if (!ktext) { free(kernelEntry); return 0; }

    PFXrefMetric *xm = pfmetric_xref_init(strAddr, XREF_TYPE_MASK_REFERENCE);
    __block uint64_t xrefAddr = 0;
    pfmetric_run(ktext, xm, ^(uint64_t va, bool *stop) { xrefAddr = va; *stop = true; });
    pfmetric_free(xm);
    if (!xrefAddr) { pfsec_free(ktext); free(kernelEntry); return 0; }

    uint64_t funcStart = pfsec_find_function_start(ktext, xrefAddr);
    if (!funcStart) { pfsec_free(ktext); free(kernelEntry); return 0; }

    PFSection *kdata = section_from_fileset_entry(kernel, kernelEntry, "__DATA_CONST", "__data");
    if (!kdata) kdata = section_from_fileset_entry(kernel, kernelEntry, "__DATA", "__data");

    uint64_t result = 0;
    int adrpCount = 0;
    if (kdata) {
        for (int i = 0; i < 200; i++) {
            uint64_t insAddr = funcStart + (i * 4);
            uint64_t target = pfsec_arm64_resolve_adrp_ldr_str_add_reference_auto(ktext, insAddr);
            if (target && pfsec_contains_vmaddr(kdata, target)) {
                adrpCount++;
                if (adrpCount == 2) {
                    result = target;
                    break;
                }
            }
        }
        pfsec_free(kdata);
    }

    pfsec_free(ktext);
    free(kernelEntry);
    return result;
}
