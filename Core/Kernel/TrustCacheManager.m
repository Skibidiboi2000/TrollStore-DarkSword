#import "TrustCacheManager.h"
#import "darksword.h"
#import "choma_helpers.h"
#import "choma_trustcache.h"
#import "ChoMAWrapper.h"
#import "Logger.h"

@implementation TrustCacheManager

+ (BOOL)injectTrustCacheWithCdhash:(NSData *)cdhash error:(NSError **)error {
    if (!ds_is_ready()) {
        LOG_ERROR("'KRW not ready");
        if (error) *error = [NSError errorWithDomain:@"TC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"KRW not ready"}];
        return NO;
    }
    if (cdhash.length != 20) {
        LOG_ERROR("'Invalid CDHash length: %lu", (unsigned long)cdhash.length);
        if (error) *error = [NSError errorWithDomain:@"TC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid CDHash length"}];
        return NO;
    }

    uint64_t kernelSlide = ds_get_kernel_slide();
    LOG_DEBUG("Kernel slide = 0x%llx", kernelSlide);

    uint64_t tcUnslid = choma_find_trust_cache_by_data_scan();
    if (tcUnslid == 0) {
        LOG_ERROR("Trust cache not found via data scan");
        if (error) *error = [NSError errorWithDomain:@"TC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Trust cache not found"}];
        return NO;
    }
    uint64_t tcAddr = tcUnslid + kernelSlide;
    LOG_DEBUG("'TC addr (unslid=0x%llx, slid=0x%llx)", tcUnslid, tcAddr);

    uint32_t version = ds_kread32(tcAddr);
    if (version != 1 && version != 2) {
        LOG_ERROR("'Unknown TC version: %u", version);
        if (error) *error = [NSError errorWithDomain:@"TC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Unknown TC version"}];
        return NO;
    }
    uint32_t count = ds_kread32(tcAddr + 20);
    LOG_DEBUG("'TC version=%u, current entries=%u", version, count);

    uint64_t amfiDataSize = 0;
    uint64_t amfiDataStart = choma_get_amfi_data_range(&amfiDataSize);
    if (amfiDataStart == 0 || amfiDataSize == 0) {
        LOG_ERROR("'AMFI data range not found");
        if (error) *error = [NSError errorWithDomain:@"TC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"AMFI data range not found"}];
        return NO;
    }
    uint64_t dataEnd = amfiDataStart + kernelSlide + amfiDataSize;
    LOG_DEBUG("'AMFI data: start=0x%llx size=%llu end=0x%llx", amfiDataStart, amfiDataSize, dataEnd);

    uint64_t cdhashArray = tcAddr + 24;
    uint64_t newEntryOff = cdhashArray + (uint64_t)count * 20;
    LOG_DEBUG("'New entry would be at 0x%llx (data ends at 0x%llx)", newEntryOff, dataEnd);

    if (newEntryOff + 20 > dataEnd) {
        LOG_ERROR("'No slack space: entry 0x%llx + 20 > data end 0x%llx", newEntryOff, dataEnd);
        if (error) *error = [NSError errorWithDomain:@"TC" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"No slack space in TC data section"}];
        return NO;
    }

    // Dedup
    for (uint32_t i = 0; i < count; i++) {
        uint8_t buf[20];
        ds_kreadbuf(cdhashArray + (uint64_t)i * 20, buf, 20);
        NSData *existing = [NSData dataWithBytes:buf length:20];
        if ([existing isEqualToData:cdhash]) {
            LOG_INFO("CDHash already in trust cache (entry %u) — skipping", i);
            return YES;
        }
    }

    LOG_DEBUG("'Writing CDHash at 0x%llx and incrementing count...", newEntryOff);
    ds_kwritebuf(newEntryOff, cdhash.bytes, 20);
    ds_kwrite32(tcAddr + 20, count + 1);
    LOG_INFO("Trust cache injected — new entry count: %u", count + 1);

    return YES;
}

@end
