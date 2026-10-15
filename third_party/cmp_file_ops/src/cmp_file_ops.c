#include <stdint.h>

#if defined(_WIN32)
#include <windows.h>
#define CMP_EXPORT __declspec(dllexport)
static int32_t cmp_error(void) {
  const DWORD code = GetLastError();
  return -(int32_t)(code ? code : ERROR_GEN_FAILURE);
}
CMP_EXPORT int32_t cmp_mkdir(const void* path) {
  if (CreateDirectoryW((const wchar_t*)path, NULL)) return 0;
  const int32_t error = cmp_error();
  return error == -ERROR_ALREADY_EXISTS ? 1 : error;
}
CMP_EXPORT int32_t cmp_lock(const void* path, int32_t seal, intptr_t* output) {
  HANDLE handle = CreateFileW((const wchar_t*)path,
    seal ? GENERIC_READ : GENERIC_READ | GENERIC_WRITE,
    seal ? FILE_SHARE_READ | FILE_SHARE_DELETE : 0, NULL, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (handle == INVALID_HANDLE_VALUE) return cmp_error();
  *output = (intptr_t)handle;
  return 0;
}
CMP_EXPORT int32_t cmp_close(intptr_t handle) {
  return CloseHandle((HANDLE)handle) ? 0 : cmp_error();
}
CMP_EXPORT int32_t cmp_move(const void* source, const void* target) {
  /* No REPLACE_EXISTING or COPY_ALLOWED. */
  return MoveFileExW((const wchar_t*)source, (const wchar_t*)target,
    MOVEFILE_WRITE_THROUGH) ? 0 : cmp_error();
}
#else
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#define CMP_EXPORT __attribute__((visibility("default")))
static int32_t cmp_error(void) { return -(errno ? errno : EIO); }
CMP_EXPORT int32_t cmp_mkdir(const void* path) {
  if (mkdir((const char*)path, 0700) == 0) return 0;
  const int32_t error = cmp_error();
  return error == -EEXIST ? 1 : error;
}
CMP_EXPORT int32_t cmp_lock(const void* path, int32_t seal, intptr_t* output) {
  int fd = open((const char*)path, (seal ? O_RDONLY : O_RDWR) | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return cmp_error();
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
    const int32_t error = cmp_error();
    close(fd);
    return error;
  }
  *output = fd;
  return 0;
}
CMP_EXPORT int32_t cmp_close(intptr_t handle) {
  /* Never retry close on EINTR: the descriptor may have been released. */
  return close((int)handle) == 0 ? 0 : cmp_error();
}
CMP_EXPORT int32_t cmp_move(const void* source, const void* target) {
  if (link((const char*)source, (const char*)target) != 0) return cmp_error();
  /* Crash here leaves two names for one inode; reconciliation checks identical. */
  return unlink((const char*)source) == 0 ? 0 : cmp_error();
}
#endif
