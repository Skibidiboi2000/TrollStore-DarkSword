#ifndef Logger_h
#define Logger_h

#include <stdio.h>

void log_init(void);
void log_write(const char *level, const char *file, int line, const char *format, ...);

// Uses C vfprintf — does NOT handle ObjC %@ specifiers.
// Pass ObjC objects via .UTF8String + %s instead.
#define LOG_INFO(fmt, ...)  log_write("INFO",  __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define LOG_WARN(fmt, ...)  log_write("WARN",  __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) log_write("ERROR", __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define LOG_DEBUG(fmt, ...) log_write("DEBUG", __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#endif
