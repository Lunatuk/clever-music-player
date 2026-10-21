/* Compile with the Android NDK, including cmp_file_ops.c from its source dir.
   A static x86_64 Android executable can run on a Linux kernel (e.g. WSL).
   This checks Android's C branch with real syscalls, not its SELinux domain. */
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include "cmp_file_ops.c"

static void require(int condition, const char* message) {
  if (!condition) { fprintf(stderr, "FAIL %s (errno=%d)\n", message, errno); exit(1); }
}
static void put(const char* name, const char* text) {
  int fd = open(name, O_CREAT | O_EXCL | O_WRONLY, 0600);
  require(fd >= 0, "fixture create");
  require(write(fd, text, strlen(text)) == (ssize_t)strlen(text), "fixture write");
  require(close(fd) == 0, "fixture close");
}
static int has(const char* name, const char* text) {
  char bytes[32] = {0};
  int fd = open(name, O_RDONLY);
  if (fd < 0) return 0;
  ssize_t count = read(fd, bytes, sizeof(bytes));
  close(fd);
  return count == (ssize_t)strlen(text) && !memcmp(bytes, text, (size_t)count);
}
static void restrict_calls(int rename_error) {
  struct sock_filter filter[] = {
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
#ifdef __NR_link
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_link, 0, 1),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_linkat, 0, 1),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_renameat2, 0, 1),
    BPF_STMT(BPF_RET | BPF_K, rename_error
      ? SECCOMP_RET_ERRNO | (unsigned)rename_error : SECCOMP_RET_ALLOW),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
  };
  struct sock_fprog program = {sizeof(filter) / sizeof(filter[0]), filter};
  require(prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == 0, "no new privileges");
  require(prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) == 0, "seccomp filter");
}
static void cases(int rename_error) {
  restrict_calls(rename_error);
  require(link("source", "forbidden") == -1 && errno == EPERM,
    "hard links really prohibited");
  if (rename_error) {
    require(cmp_move("source", "free") == -rename_error, "rename failure preserved");
    require(has("source", "new") && access("free", F_OK) != 0, "failure retains source");
    return;
  }
  intptr_t first, second;
  require(cmp_lock("lock", 0, &first) == 0, "owner lock");
  require(cmp_lock("lock", 0, &second) == -EWOULDBLOCK, "second owner excluded");
  require(cmp_close(first) == 0, "owner close");
  int result = cmp_move("source", "target");
  if (result != -EEXIST) fprintf(stderr, "collision result=%d\n", result);
  require(result == -EEXIST && has("source", "new") && has("target", "old"),
    "collision retains both files");
  require(cmp_move("source", "target_link") == -EEXIST &&
    has("target", "old") && has("source", "new"), "symlink target not replaced");
  require(cmp_move("missing", "free") == -ENOENT, "missing source");
  struct stat before, after;
  require(stat("source", &before) == 0, "source inode");
  require(cmp_move("source", "free") == 0 && access("source", F_OK) != 0 &&
    has("free", "new"), "successful no-replace move");
  require(stat("free", &after) == 0 && before.st_ino == after.st_ino,
    "move retains inode without copying");
  int gate[2]; require(pipe(gate) == 0, "race gate");
  pid_t children[2];
  for (int i = 0; i < 2; ++i) {
    children[i] = fork(); require(children[i] >= 0, "race fork");
    if (!children[i]) {
      char token; close(gate[1]); require(read(gate[0], &token, 1) == 1, "race start");
      int value = cmp_move(i ? "race_b" : "race_a", "race_target");
      _exit(value == 0 ? 0 : value == -EEXIST ? 2 : 3);
    }
  }
  close(gate[0]); require(write(gate[1], "xx", 2) == 2, "release race"); close(gate[1]);
  int wins = 0, collisions = 0;
  for (int i = 0; i < 2; ++i) {
    int status; require(waitpid(children[i], &status, 0) == children[i] && WIFEXITED(status), "race wait");
    wins += WEXITSTATUS(status) == 0; collisions += WEXITSTATUS(status) == 2;
  }
  require(wins == 1 && collisions == 1, "exactly one writer wins");
  require((has("race_target", "a") && has("race_b", "b")) ||
    (has("race_target", "b") && has("race_a", "a")), "loser bytes retained");
}
int main(void) {
  char directory[] = "/tmp/cmp_android_ops_XXXXXX";
  require(mkdtemp(directory) != NULL && chdir(directory) == 0, "fresh temporary root");
  put("source", "new"); put("target", "old"); put("lock", "");
  put("race_a", "a"); put("race_b", "b");
  require(symlink("target", "target_link") == 0, "symlink fixture");
  int errors[] = {ENOSYS, EPERM, EINVAL, 0};
  int passed = 1;
  for (unsigned i = 0; i < sizeof(errors) / sizeof(errors[0]); ++i) {
    pid_t child = fork(); require(child >= 0, "case fork");
    if (!child) { cases(errors[i]); _exit(0); }
    int status; require(waitpid(child, &status, 0) == child, "case wait");
    if (!WIFEXITED(status) || WEXITSTATUS(status)) { passed = 0; break; }
  }
  /* Only known children of this invocation's fresh root are removed. */
  const char* names[] = {"source", "target", "lock", "race_a", "race_b",
    "target_link", "free", "forbidden", "race_target"};
  for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); ++i) unlink(names[i]);
  require(chdir("/") == 0 && rmdir(directory) == 0, "temporary cleanup");
  if (!passed) return 1;
  puts("PASS Android native moves: hard-link denial, collision, symlink, inode, race, ENOSYS/EPERM/EINVAL");
  return 0;
}
