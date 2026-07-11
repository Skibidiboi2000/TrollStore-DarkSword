#import "IPAParser.h"
#import <zlib.h>
#import "ChoMAWrapper.h"
#import "Logger.h"

typedef struct __attribute__((packed)) {
    uint32_t signature;
    uint16_t versionNeeded;
    uint16_t flags;
    uint16_t compression;
    uint16_t modTime;
    uint16_t modDate;
    uint32_t crc32;
    uint32_t compressedSize;
    uint32_t uncompressedSize;
    uint16_t fileNameLen;
    uint16_t extraFieldLen;
} ZIPLocalHeader;

typedef struct __attribute__((packed)) {
    uint32_t signature;
    uint16_t versionMade;
    uint16_t versionNeeded;
    uint16_t flags;
    uint16_t compression;
    uint16_t modTime;
    uint16_t modDate;
    uint32_t crc32;
    uint32_t compressedSize;
    uint32_t uncompressedSize;
    uint16_t fileNameLen;
    uint16_t extraFieldLen;
    uint16_t commentLen;
    uint16_t diskStart;
    uint16_t internalAttrs;
    uint32_t externalAttrs;
    uint32_t localOffset;
} ZIPCentralDir;

static const NSUInteger CHUNK_SIZE = 4 * 1024 * 1024; // 4MB streaming chunks

@implementation IPAParser

+ (NSData *)extractCDHashFromIPAAt:(NSURL *)ipaPath error:(NSError **)error {
    NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    tmpDir = [tmpDir URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];

    if (![self unzipIPAAt:ipaPath to:tmpDir error:error]) {
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return nil;
    }

    NSURL *payloadDir = [tmpDir URLByAppendingPathComponent:@"Payload"];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir.path error:nil];
    NSString *appDir = nil;
    for (NSString *name in contents) {
        if ([name hasSuffix:@".app"]) { appDir = name; break; }
    }
    if (!appDir) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Missing .app in Payload"}];
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return nil;
    }

    NSURL *appPath = [payloadDir URLByAppendingPathComponent:appDir];
    NSURL *infoPlistURL = [appPath URLByAppendingPathComponent:@"Info.plist"];
    NSData *infoData = [NSData dataWithContentsOfURL:infoPlistURL];
    if (!infoData) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Missing Info.plist"}];
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return nil;
    }
    NSDictionary *info = [NSPropertyListSerialization propertyListWithData:infoData options:0 format:nil error:error];
    if (!info) {
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return nil;
    }
    NSString *execName = info[@"CFBundleExecutable"];
    if (!execName) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"No CFBundleExecutable"}];
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return nil;
    }

    NSString *execPath = [[appPath URLByAppendingPathComponent:execName] path];
    NSData *cdhash = [ChoMAWrapper extractCDHash:execPath];
    [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];

    if (!cdhash) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CDHash extraction failed"}];
    }
    return cdhash;
}

+ (BOOL)unzipIPAAt:(NSURL *)source to:(NSURL *)dest error:(NSError **)error {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:source error:error];
    if (!fh) return NO;

    // Read EOCD from tail — stream-safe: only need last 64KB
    uint64_t fileSize = [fh seekToEndOfFile];
    if (fileSize < 22) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"File too small"}];
        [fh closeFile];
        return NO;
    }

    NSUInteger searchLen = (NSUInteger)MIN(fileSize, 65557);
    uint64_t searchStart = fileSize - searchLen;
    [fh seekToFileOffset:searchStart];
    NSData *tail = [fh readDataOfLength:searchLen];
    if (tail.length != searchLen) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Cannot read EOCD region"}];
        [fh closeFile];
        return NO;
    }

    NSInteger eocdOffset = -1;
    for (NSInteger i = 0; i < (NSInteger)searchLen - 3; i++) {
        uint32_t sig;
        [tail getBytes:&sig range:NSMakeRange(i, 4)];
        if (sig == 0x06054b50) { eocdOffset = (NSInteger)searchStart + i; break; }
    }
    if (eocdOffset < 0) {
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid ZIP: no EOCD"}];
        [fh closeFile];
        return NO;
    }

    // Read central directory from EOCD
    uint16_t numEntries;
    uint32_t cdOffset;
    [tail getBytes:&numEntries range:NSMakeRange((NSUInteger)(eocdOffset - (NSInteger)searchStart) + 10, 2)];
    [tail getBytes:&cdOffset range:NSMakeRange((NSUInteger)(eocdOffset - (NSInteger)searchStart) + 16, 4)];

    // Read central directory into memory (typically < 64KB)
    [fh seekToFileOffset:cdOffset];
    NSUInteger cdBytes = (NSUInteger)(eocdOffset - (NSInteger)cdOffset);
    NSData *centralDir = [fh readDataOfLength:cdBytes];
    if (centralDir.length != cdBytes) {
        [fh closeFile];
        if (error) *error = [NSError errorWithDomain:@"IPA" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Cannot read central directory"}];
        return NO;
    }

    NSInteger pos = 0;
    for (uint16_t i = 0; i < numEntries; i++) {
        if ((NSUInteger)pos + sizeof(ZIPCentralDir) > centralDir.length) break;
        ZIPCentralDir cd;
        [centralDir getBytes:&cd range:NSMakeRange(pos, sizeof(ZIPCentralDir))];
        if (cd.signature != 0x02014b50) break;

        NSString *name = [[NSString alloc] initWithData:[centralDir subdataWithRange:NSMakeRange(pos + 46, cd.fileNameLen)] encoding:NSUTF8StringEncoding];
        if (!name) { pos += 46 + cd.fileNameLen + cd.extraFieldLen + cd.commentLen; continue; }
        pos += 46 + cd.fileNameLen + cd.extraFieldLen + cd.commentLen;

        // Zip slip guard
        if ([name containsString:@".."] || [name hasPrefix:@"/"]) continue;

        NSURL *destPath = [dest URLByAppendingPathComponent:name];
        if ([name hasSuffix:@"/"]) {
            [[NSFileManager defaultManager] createDirectoryAtURL:destPath withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }
        [[NSFileManager defaultManager] createDirectoryAtURL:[destPath URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];

        // Read local header via stream
        [fh seekToFileOffset:cd.localOffset];
        ZIPLocalHeader lh;
        NSData *lhData = [fh readDataOfLength:sizeof(ZIPLocalHeader)];
        if (lhData.length != sizeof(ZIPLocalHeader)) continue;
        [lhData getBytes:&lh length:sizeof(ZIPLocalHeader)];
        if (lh.signature != 0x04034b50) continue;

        uint64_t dataOff = cd.localOffset + 30 + lh.fileNameLen + lh.extraFieldLen;
        [fh seekToFileOffset:dataOff];

        // Stream file data to disk — never hold entire compressed entry in RAM
        if (cd.compression == 0) {
            [[NSFileManager defaultManager] createFileAtPath:destPath.path contents:nil attributes:nil];
            NSFileHandle *outFH = [NSFileHandle fileHandleForWritingAtPath:destPath.path];
            if (!outFH) continue;

            uint64_t remaining = cd.compressedSize;
            while (remaining > 0) {
                NSUInteger toRead = (NSUInteger)MIN(remaining, CHUNK_SIZE);
                NSData *chunk = [fh readDataOfLength:toRead];
                if (chunk.length == 0) break;
                [outFH writeData:chunk];
                remaining -= chunk.length;
            }
            [outFH closeFile];
        } else if (cd.compression == 8) {
            // For deflate, buffer entire entry + decompress to file
            NSMutableData *compBuf = [NSMutableData dataWithCapacity:(NSUInteger)cd.compressedSize];
            uint64_t remaining = cd.compressedSize;
            while (remaining > 0) {
                NSUInteger toRead = (NSUInteger)MIN(remaining, CHUNK_SIZE);
                NSData *chunk = [fh readDataOfLength:toRead];
                if (chunk.length == 0) break;
                [compBuf appendData:chunk];
                remaining -= chunk.length;
            }

            if (compBuf.length == cd.compressedSize) {
                NSData *decompressed = [self decompressDeflate:compBuf uncompressedSize:cd.uncompressedSize];
                if (decompressed) [decompressed writeToURL:destPath atomically:YES];
            }
        }
    }

    [fh closeFile];
    return YES;
}

+ (NSData *)decompressDeflate:(NSData *)compressed uncompressedSize:(uint32_t)uncompressedSize {
    if (uncompressedSize == 0) return nil;
    NSMutableData *result = [NSMutableData dataWithLength:uncompressedSize];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    int ret = inflateInit2_(&stream, -15, ZLIB_VERSION, sizeof(stream));
    if (ret != Z_OK) return nil;

    stream.next_in = (Bytef *)compressed.bytes;
    stream.avail_in = (uInt)compressed.length;
    stream.next_out = (Bytef *)result.mutableBytes;
    stream.avail_out = (uInt)uncompressedSize;
    ret = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);

    return (ret == Z_STREAM_END) ? result : nil;
}

@end
