#import "Logger.h"
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <stdarg.h>
#include <string.h>

static FILE *logFile = NULL;
static pthread_mutex_t logMutex = PTHREAD_MUTEX_INITIALIZER;
static NSDateFormatter *logFormatter = nil;

void log_init(void) {
    if (logFile != NULL) return;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = paths.firstObject;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSString *timeString = [formatter stringFromDate:[NSDate date]];

    NSString *logPath = [docsDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"TrollStoreLog_%@.txt", timeString]];

    logFile = fopen([logPath UTF8String], "w");
    if (logFile) {
        fprintf(logFile, "=== TrollStore DarkSword Log ===\n");
        fprintf(logFile, "Device: %s\n", [[[UIDevice currentDevice] model] UTF8String]);
        fprintf(logFile, "iOS: %s\n", [[[UIDevice currentDevice] systemVersion] UTF8String]);
        fprintf(logFile, "===============================\n");
        fflush(logFile);
    }

    logFormatter = [[NSDateFormatter alloc] init];
    [logFormatter setDateFormat:@"HH:mm:ss.SSS"];
}

void log_write(const char *level, const char *file, int line, const char *format, ...) {
    if (!logFile) log_init();
    if (!logFile) return;

    pthread_mutex_lock(&logMutex);

    NSString *timeString = [logFormatter stringFromDate:[NSDate date]];

    const char *filename = strrchr(file, '/');
    if (filename) filename++; else filename = file;

    pthread_t threadID = pthread_self();

    fprintf(logFile, "[%s] [%-5s] [0x%lx] [%s:%d] ",
            [timeString UTF8String], level, (unsigned long)threadID, filename, line);

    va_list args;
    va_start(args, format);
    vfprintf(logFile, format, args);
    va_end(args);

    fprintf(logFile, "\n");
    fflush(logFile);

    pthread_mutex_unlock(&logMutex);
}
