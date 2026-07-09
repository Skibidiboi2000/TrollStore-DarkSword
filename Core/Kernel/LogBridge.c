#include <stdio.h>
#include <stdarg.h>

void utils_log(const char *message, const char *tag) {
    if (!tag || !*tag) tag = "C";
    fprintf(stderr, "[%s] %s\n", tag, message);
}
