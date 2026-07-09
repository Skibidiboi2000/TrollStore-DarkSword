#include <dlfcn.h>
#include <string.h>
#include "RemoteCall.h"

int rc_run_system(RemoteCall *rc, const char *cmd) {
    if (!rc || !cmd) return -1;

    // Allocate command string in remote process's trojanMem
    if (![rc remote_write:rc.trojanMem string:cmd]) {
        return -1;
    }

    // Get system() address — shared cache maps at same VA across processes
    void *systemAddr = dlsym(RTLD_DEFAULT, "system");
    if (!systemAddr) return -1;

    uint64_t args[] = { rc.trojanMem };
    NSUInteger result = [rc doRemoteCallStableWithTimeout:30
                                            functionName:"system"
                                         functionPointer:systemAddr
                                                    args:args
                                               argCount:1];
    return result == 0 ? 0 : -1;
}
