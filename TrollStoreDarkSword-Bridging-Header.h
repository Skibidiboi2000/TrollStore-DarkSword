@import UIKit;
#import <Foundation/Foundation.h>

// LARA kernel exploit
#import "darksword.h"
#import "utils.h"
#import "offsets.h"
#import "sbx.h"

// TaskRop / RemoteCall
#import "RemoteCall.h"

// ChOma code signing
#import "CSBlob.h"
#import "CodeDirectory.h"
#import "MachO.h"
#import "Fat.h"

// XPF library
#import "xpf.h"

// Trust cache scanning (XPF-based)
#import "choma_helpers.h"
#import "choma_trustcache.h"

// RemoteCall system() helper
int rc_run_system(RemoteCall *rc, const char *cmd);

// Swift 6 concurrency-safe offset accessors
uint32_t get_off_proc_p_flag(void);
