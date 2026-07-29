/*
 * KSU Toast - su wrapper
 *
 * Replaces /system/bin/su. When an app calls su:
 * 1. Extracts the caller's UID and process name from /proc
 * 2. Connects to ksu-toastd via Unix socket
 * 3. Sends a CHECK request
 * 4. Blocks for response with timeout
 * 5. If ALLOWED: exec's the real ksud (which grants root normally)
 * 6. If DENIED/timed out: exits with error
 *
 * Uses only POSIX APIs — no Android-specific headers needed.
 * Compile with: aarch64-linux-android-clang -static -Os -s -o su su-wrapper.c
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>

#define DAEMON_SOCKET "/data/adb/ksu-toast/daemon.sock"
#define REAL_KSUD     "/data/adb/ksud"
#define TIMEOUT_SEC   10
#define BUF_SIZE      4096

/* Read /proc/self/status to get the real UID (before ksud changes it).
 * The kernel hasn't granted root yet at this point, so our UID is still
 * the calling app's UID. */
static int get_caller_uid(void) {
    FILE *f = fopen("/proc/self/status", "re");
    if (!f) return -1;

    char line[256];
    int uid = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "Uid:", 4) == 0) {
            /* Format: Uid:  <real>  <effective>  <saved>  <fs> */
            sscanf(line + 4, "%d", &uid);
            break;
        }
    }
    fclose(f);
    return uid;
}

/* Get the calling process's command name (not full path). */
static int get_caller_name(char *out, size_t out_size) {
    /* /proc/self/cmdline has the truncated comm name from the app */
    int fd = open("/proc/self/cmdline", O_RDONLY);
    if (fd < 0) return -1;

    ssize_t n = read(fd, out, out_size - 1);
    close(fd);

    if (n <= 0) return -1;
    out[n] = '\0';

    /* cmdline is NUL-separated; we only want the first entry */
    char *first_nul = memchr(out, '\0', n);
    if (first_nul) *first_nul = '\0';

    return 0;
}

/* Connect to the daemon's Unix socket with a timeout.
 * Returns fd on success, -1 on failure. */
static int connect_daemon(void) {
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, DAEMON_SOCKET, sizeof(addr.sun_path) - 1);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    /* Set non-blocking for connect with timeout */
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    int ret = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (ret < 0 && errno != EINPROGRESS) {
        close(fd);
        return -1;
    }

    /* Wait for connection with poll */
    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    fd_set wfds;
    FD_ZERO(&wfds);
    FD_SET(fd, &wfds);

    ret = select(fd + 1, NULL, &wfds, NULL, &tv);
    if (ret <= 0) {
        close(fd);
        return -1;
    }

    /* Check for socket error */
    int so_error = 0;
    socklen_t len = sizeof(so_error);
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_error, &len);
    if (so_error != 0) {
        close(fd);
        return -1;
    }

    /* Restore blocking for read */
    fcntl(fd, F_SETFL, flags);
    return fd;
}

static int send_request(int fd, const char *msg) {
    size_t len = strlen(msg);
    return write(fd, msg, len) == (ssize_t)len ? 0 : -1;
}

/* Read response with timeout. Returns 0 on success, -1 on timeout/error. */
static int read_response(int fd, char *buf, size_t buf_size) {
    struct timeval tv = { .tv_sec = TIMEOUT_SEC, .tv_usec = 0 };
    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);

    int ret = select(fd + 1, &rfds, NULL, NULL, &tv);
    if (ret <= 0) return -1;

    ssize_t n = read(fd, buf, buf_size - 1);
    if (n <= 0) return -1;

    buf[n] = '\0';
    return 0;
}

int main(int argc, char *argv[]) {
    (void)argc; /* unused — we get caller info from /proc */
    /* Get caller info */
    int uid = get_caller_uid();
    if (uid < 0) {
        /* Can't determine UID — fall through to real ksud */
        goto exec_ksud;
    }

    char caller_name[256] = "unknown";
    get_caller_name(caller_name, sizeof(caller_name));

    /* If UID is 0 (already root), no need to check — just pass through */
    if (uid == 0) {
        goto exec_ksud;
    }

    /* Connect to daemon */
    int sock = connect_daemon();
    if (sock < 0) {
        /* Daemon not running — fall through to default KSU behavior */
        goto exec_ksud;
    }

    /* Send CHECK request */
    char req[BUF_SIZE];
    snprintf(req, sizeof(req), "CHECK %d %s\n", uid, caller_name);
    if (send_request(sock, req) < 0) {
        close(sock);
        goto exec_ksud;
    }

    /* Wait for response */
    char resp[BUF_SIZE] = {0};
    if (read_response(sock, resp, sizeof(resp)) < 0) {
        /* Timeout or error — deny */
        close(sock);
        fprintf(stderr, "su: request timed out\n");
        return 1;
    }
    close(sock);

    /* Parse response */
    if (strncmp(resp, "ALLOWED", 7) == 0) {
        goto exec_ksud;
    }

    /* DENIED or anything else */
    fprintf(stderr, "su: permission denied\n");
    return 1;

exec_ksud:
    /* Execute the real KernelSU su daemon */
    execv(REAL_KSUD, argv);

    /* If exec fails, print error and exit — don't fall back to sh
     * (that would run as app's UID, not root, misleading the user) */
    fprintf(stderr, "su: failed to execute %s: %s\n", REAL_KSUD, strerror(errno));
    return 1;
}
