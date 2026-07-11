#import "ChoMAWrapper.h"
#import "MachO.h"
#import "CSBlob.h"

@implementation ChoMAWrapper

+ (NSData *)extractCDHash:(NSString *)machOPath {
    if (![[NSFileManager defaultManager] isReadableFileAtPath:machOPath]) return nil;

    struct macho *macho = macho_init_for_writing(machOPath.UTF8String);
    if (!macho) return nil;

    CS_SuperBlob *superblob = macho_read_code_signature(macho);
    if (!superblob) { macho_free(macho); return nil; }

    struct csd_superblob *decoded = csd_superblob_decode(superblob);
    free(superblob);
    if (!decoded) { macho_free(macho); return nil; }

    uint8_t hash[20];
    int32_t hashType = 0;
    int ret = csd_superblob_calculate_best_cdhash(decoded, hash, &hashType);
    csd_superblob_free(decoded);
    macho_free(macho);

    if (ret != 0) return nil;
    return [NSData dataWithBytes:hash length:20];
}

@end
