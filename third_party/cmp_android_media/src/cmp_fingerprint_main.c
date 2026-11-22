#include "cmp_media.h"
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <wchar.h>

int wmain(int argc, wchar_t **argv) {
    if (argc != 2 || !cmp_media_begin()) return 1;
    int fd = _wopen(argv[1], _O_RDONLY | _O_BINARY | _O_NOINHERIT);
    const char *response = cmp_media_fingerprint_fd(fd, -1);
    int status = puts(response) < 0;
    if (fd >= 0 && _close(fd) != 0) status = 1;
    cmp_media_end();
    return status;
}
