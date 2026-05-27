#ifndef CHOMA_HELPERS_H
#define CHOMA_HELPERS_H

#include "CSBlob.h"
#include "MachO.h"
#include "xpf.h"

int choma_replace_entitlements_in_macho(MachO *macho, const char *entitlements_path);

int choma_replace_entitlements(const char *macho_path, const char *entitlements_path);

const char *choma_xpf_version_string(void);
uint64_t choma_xpf_kernel_base(void);

// Direct AMFI + developer_mode_status resolvers using corrected fileset-entry streams.
// These bypass libxpf's broken fileset entry lookup (pfsec_init_from_macho uses
// the container's stream instead of the fileset entry's own stream).
// Returns 0 if resolution fails.
uint64_t choma_find_amfi_function_direct(void);
uint64_t choma_find_dev_mode_status_direct(void);

// Returns the VM address of AMFI's primary __DATA_CONST,__data section.
// Swift can use kernel-r/w to scan runtime data (trust cache entries, globals).
// *outSize receives the section size.  Returns 0 if not found.
uint64_t choma_get_amfi_data_range(uint64_t *outSize);

// Drain and clear the diagnostic ring buffer. Returns a NUL-terminated string
// containing all [CHOMA] diagnostic lines since the last drain.
const char *choma_drain_diagnostics(void);

// Shared helpers used by choma_trustcache.c
PFSection *section_from_fileset_entry(MachO *container, const char *entryId, const char *segName, const char *sectName);
void choma_search_substr(PFSection *section, const char *substr, void (^matchBlock)(uint64_t vmaddr, bool *stop));

#endif

// Swift 6 concurrency-safe accessors for offsets_init() globals
uint32_t get_off_proc_p_pid(void);
uint32_t get_off_proc_p_list_le_next(void);
