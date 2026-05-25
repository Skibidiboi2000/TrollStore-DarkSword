#ifndef CHOMA_HELPERS_H
#define CHOMA_HELPERS_H

#include "CSBlob.h"
#include "MachO.h"
#include "xpf.h"

int choma_replace_entitlements_in_macho(MachO *macho, const char *entitlements_path);

int choma_replace_entitlements(const char *macho_path, const char *entitlements_path);

const char *choma_xpf_version_string(void);
uint64_t choma_xpf_kernel_base(void);

#endif
