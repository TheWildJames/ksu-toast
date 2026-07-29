/*
 * KSU Toast - ksu-toastd daemon
 *
 * A root daemon that intercepts root requests from the su-wrapper,
 * manages the allowlist via KSU kernel ioctls, and communicates
 * with the companion APK for user-facing notifications.
 *
 * Compile with: aarch64-linux-android-clang -static -Os -s -o ksu-toastd ksu-toastd.c
 *
 * Contains techniques inspired by backslashxx/ksu_toolkit
 * ( https://github.com/backslashxx/ksu_toolkit ) — specifically the
 * KSU_IOCTL_GET_MANAGER_UID ioctl approach for querying the manager
 * app UID from the kernel, replacing fragile filesystem parsing.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <pthread.h>
#include <time.h>

/* ── Configuration ──────────────────────────────────────── */
#define DAEMON_SOCKET   "/data/adb/ksu-toast/daemon.sock"
/* Abstract socket — avoids SELinux file context issues with /data/adb/ */
#define APK_SOCKET      "/data/adb/ksu-toast/apk.sock"
#define DENY_LIST       "/data/adb/ksu-toast/deny.list"
#define ALLOW_CACHE     "/data/adb/ksu-toast/allow.cache"
#define PID_FILE        "/data/adb/ksu-toast/daemon.pid"
#define MODULE_DIR      "/data/adb/modules/ksu_toast"

#define SOCKET_BACKLOG  16
/* Use a guard since NDK already defines LINE_MAX */
#ifndef LINE_MAX
#define LINE_MAX 4096
#endif
#define REQ_TIMEOUT_SEC_DEFAULT 10
#define PKG_NAME_MAX    256

/* ── KSU UAPI constants (from KernelSU Next) ───────────── */
#define KSU_INSTALL_MAGIC1  0xDEADBEEF
#define KSU_INSTALL_MAGIC2  0xCAFEBABE
#define KSU_PER_USER_RANGE  100000
#define KSU_APP_PROFILE_VER 4
#define KSU_MAX_PACKAGE_NAME 256
#define KSU_MAX_GROUPS      32
#define KSU_SELINUX_DOMAIN  64

/* Compute ioctl numbers matching KSU's uapi/supercall.h */
#define KSU_IOCTL_SET_APP_PROFILE   _IOC(_IOC_WRITE, 'K', 12, 0)
#define KSU_IOCTL_GET_MANAGER_UID   _IOC(_IOC_READ,  'K', 10, 0)
#define CHANGE_MANAGER_UID          10006

struct ksu_get_manager_uid_cmd {
    __u32 uid;
};

/* ── Structs matching KSU UAPI (must match kernel layout exactly) ── */
struct root_profile {
    __s32 uid;
    __s32 gid;
    __u32 groups_count;
    __s32 groups[KSU_MAX_GROUPS];
    struct { __u64 effective; __u64 permitted; __u64 inheritable; } capabilities;
    char selinux_domain[KSU_SELINUX_DOMAIN];
    __s32 namespaces;
    __u64 flags;
};

struct non_root_profile {
    __u8 umount_modules;
};

/* Must match kernel's struct app_profile exactly, including union layout.
 * The union adds padding after allow_su for alignment. */
struct app_profile {
    __u32 version;
    char key[KSU_MAX_PACKAGE_NAME];
    __s32 curr_uid;
    __u8 allow_su;
    /* 7 bytes implicit padding before union */
    union {
        struct {
            __u8 use_default;
            /* 3 bytes implicit padding before template_name */
            char template_name[KSU_MAX_PACKAGE_NAME];
            struct root_profile profile;
        } rp_config;
        struct {
            __u8 use_default;
            struct non_root_profile profile;
        } nrp_config;
    };
};

struct set_app_profile_cmd {
    struct app_profile profile;
};

/* ── Globals ────────────────────────────────────────────── */
static int daemon_sock_fd = -1;
static int apk_listen_fd = -1;
static volatile int running = 1;
static int manager_uid = -1;
static int g_timeout_sec = REQ_TIMEOUT_SEC_DEFAULT;

/* Configurable paths (parsed from argv, defaults from defines) */
static const char *g_deny_path = DENY_LIST;
static const char *g_cache_path = ALLOW_CACHE;

/* ── Helpers ────────────────────────────────────────────── */

/* Write a line to a file (used for deny.list and allow.cache updates) */
static int file_contains(const char *path, int uid) {
    FILE *f = fopen(path, "re");
    if (!f) return 0;
    char line[64];
    while (fgets(line, sizeof(line), f)) {
        int u;
        if (sscanf(line, "%d", &u) == 1 && u == uid) {
            fclose(f);
            return 1;
        }
    }
    fclose(f);
    return 0;
}

static int file_append(const char *path, int uid) {
    FILE *f = fopen(path, "ae");
    if (!f) return -1;
    fprintf(f, "%d\n", uid);
    fclose(f);
    return 0;
}

/* Resolve the KSU Next manager app's UID via the kernel module.
 * Uses KSU_IOCTL_GET_MANAGER_UID first, falls back to parsing
 * /data/system/packages.list if the ioctl fails.
 *
 * Technique from backslashxx/ksu_toolkit. */
static int resolve_manager_uid_via_ioctl(void) {
    int ksu_fd = -1;
    long ret = syscall(SYS_reboot, KSU_INSTALL_MAGIC1, KSU_INSTALL_MAGIC2, 0, &ksu_fd);
    if (ret != 0 || ksu_fd < 0) return -1;

    struct ksu_get_manager_uid_cmd cmd = {0};
    ret = ioctl(ksu_fd, KSU_IOCTL_GET_MANAGER_UID, &cmd);
    close(ksu_fd);
    if (ret != 0 || cmd.uid == 0) return -1;
    return (int)cmd.uid;
}

/* Fallback: parse /data/system/packages.list for known manager packages */
static int resolve_manager_uid_fallback(void) {
    FILE *f = fopen("/data/system/packages.list", "re");
    if (!f) return -1;

    const char *managers[] = {
        "com.rifsxd.ksunext",
        "me.weishu.kernelsu",
        "com.rifsxd.kernelsunext",
        NULL
    };

    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        for (int i = 0; managers[i]; i++) {
            size_t plen = strlen(managers[i]);
            if (strncmp(line, managers[i], plen) == 0 && line[plen] == ' ') {
                int uid;
                if (sscanf(line + plen + 1, "%d", &uid) == 1) {
                    fclose(f);
                    return uid;
                }
            }
        }
    }
    fclose(f);
    return -1;
}

static int resolve_manager_uid(void) {
    int uid = resolve_manager_uid_via_ioctl();
    if (uid > 0) return uid;
    return resolve_manager_uid_fallback();
}

/* Remove socket file and create a listening Unix socket */
static int create_socket(const char *path) {
    unlink(path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr = { .sun_family = AF_UNIX };

    /* Abstract socket if path starts with '@' (no filesystem file, no SELinux) */
    socklen_t addr_len = sizeof(addr);
    if (path[0] == '@') {
        addr.sun_path[0] = '\0';
        size_t name_len = strlen(path + 1);
        memcpy(addr.sun_path + 1, path + 1, name_len);
        /* MUST pass exact length — kernel compares full abstract name up to addr_len */
        addr_len = offsetof(struct sockaddr_un, sun_path) + 1 + name_len;
    } else {
        unlink(path);
        strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    }

    if (bind(fd, (struct sockaddr *)&addr, addr_len) < 0) {
        close(fd);
        return -1;
    }

    /* Filesystem sockets need world-rw for APK; abstract sockets don't */
    if (path[0] != '@') {
        chmod(path, 0777);
    }

    if (listen(fd, SOCKET_BACKLOG) < 0) {
        close(fd);
        if (path[0] != '@') unlink(path);
        return -1;
    }
    return fd;
}

/* Read a line from a socketfd (up to newline or maxlen) */
static int read_line(int fd, char *buf, size_t maxlen) {
    size_t i = 0;
    while (i < maxlen - 1) {
        char c;
        ssize_t n = read(fd, &c, 1);
        if (n <= 0) return -1;
        if (c == '\n') break;
        buf[i++] = c;
    }
    buf[i] = '\0';
    return (int)i;
}

/* ── Grant root to an app via KSU ioctl ───────────────────
 *
 * Uses the CHANGE_MANAGER_UID technique from ksu_toolkit:
 * temporarily set the kernel's manager appid to root (UID 0),
 * call SET_APP_PROFILE as root (passes only_manager()), then
 * restore the original manager appid.
 *
 * Avoids fork/setuid/struct-inheritance issues entirely. */
static int grant_app_root(int target_uid, const char *pkg_name) {
    if (manager_uid < 0) {
        fprintf(stderr, "[ksu-toast] grant_root: manager UID not resolved\n");
        return -1;
    }

    /* Open ksu driver fd */
    int ksu_fd = -1;
    long ret = syscall(SYS_reboot, KSU_INSTALL_MAGIC1, KSU_INSTALL_MAGIC2, 0, &ksu_fd);
    if (ret != 0 || ksu_fd < 0) {
        fprintf(stderr, "[ksu-toast] grant_root: failed to open ksu fd\n");
        return -1;
    }

    /* Step 1: Change manager appid to root so our ioctl passes only_manager() */
    int orig_mgr = manager_uid;
    fprintf(stderr, "[ksu-toast] grant_root: setting manager UID to 0 (was %d)\n", orig_mgr);
    syscall(SYS_reboot, KSU_INSTALL_MAGIC1, CHANGE_MANAGER_UID, 0, 0, 0, 0);

    /* Step 2: Prepare and call SET_APP_PROFILE (now running as root = manager) */
    struct app_profile profile = {0};
    profile.version = KSU_APP_PROFILE_VER;
    profile.curr_uid = target_uid;
    profile.allow_su = 1;
    profile.rp_config.use_default = 1;
    strcpy(profile.rp_config.profile.selinux_domain, "u:r:ksu:s0");

    if (pkg_name) {
        strncpy(profile.key, pkg_name, sizeof(profile.key) - 1);
    } else {
        snprintf(profile.key, sizeof(profile.key), "uid_%d", target_uid);
    }

    struct set_app_profile_cmd cmd;
    memset(&cmd, 0, sizeof(cmd));
    memcpy(&cmd.profile, &profile, sizeof(profile));

    int ioctl_ret = ioctl(ksu_fd, KSU_IOCTL_SET_APP_PROFILE, &cmd);
    int ioctl_err = errno;
    fprintf(stderr, "[ksu-toast] grant_root: ioctl returned %d, errno=%d\n",
            ioctl_ret, ioctl_err);

    /* Step 3: Restore original manager appid */
    syscall(SYS_reboot, KSU_INSTALL_MAGIC1, CHANGE_MANAGER_UID, orig_mgr, 0, 0, 0);
    fprintf(stderr, "[ksu-toast] grant_root: restored manager UID to %d\n", orig_mgr);

    close(ksu_fd);
    return (ioctl_ret == 0) ? 0 : -1;
}

/* ── Notify APK about a root request ──────────────────────
 *
 * Format: REQUEST <req_id> <uid> <app_name>\n
 * Response: GRANT|DENY|IGNORE <req_id>\n
 * Returns: 1=grant, 0=deny, -1=timeout/error */
static int ask_apk(int uid, const char *app_name) {
    if (apk_listen_fd < 0) return -1;

    /* Accept a connection from the APK (or fail if no APK connected) */
    struct sockaddr_un client_addr;
    socklen_t client_len = sizeof(client_addr);

    /* Wait up to REQ_TIMEOUT_SEC_DEFAULT for APK to connect */
    struct timeval accept_tv = { .tv_sec = g_timeout_sec, .tv_usec = 0 };
    fd_set accept_fds;
    FD_ZERO(&accept_fds);
    FD_SET(apk_listen_fd, &accept_fds);
    int sel_ret = select(apk_listen_fd + 1, &accept_fds, NULL, NULL, &accept_tv);
    if (sel_ret <= 0) {
        fprintf(stderr, "[ksu-toast] APK connection timed out\n");
        /* Fallback: post Android notification directly via cmd notification.
         * This works without the companion APK. On Android 14+, the
         * APK cannot connect to our socket due to SELinux restrictions,
         * so this is the primary notification path. */
        char notif_cmd[1024];
        snprintf(notif_cmd, sizeof(notif_cmd),
            "cmd notification post -t \"Root request\" "
            "--importance 4 "
            "\"ksu_toast_req_%d\" "
            "\"%s wants root\" "
            ">/dev/null 2>&1",
            uid, app_name ? app_name : "App");
        int nret = system(notif_cmd);
        fprintf(stderr, "[ksu-toast] cmd notification post: ret=%d\n", nret);
        return -1;
    }

    int apk_fd = accept(apk_listen_fd, (struct sockaddr *)&client_addr, &client_len);
    if (apk_fd < 0) return -1;

    /* Generate a request ID */
    int req_id = (int)(time(NULL) % 100000) + (uid % 1000);

    /* Send request to APK */
    char req[LINE_MAX];
    int n = snprintf(req, sizeof(req),
                     "REQUEST %d %d %s\n", req_id, uid, app_name ? app_name : "unknown");
    write(apk_fd, req, n);

    /* Wait for response with timeout */
    struct timeval tv = { .tv_sec = g_timeout_sec, .tv_usec = 0 };
    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(apk_fd, &rfds);

    int result = -1;
    if (select(apk_fd + 1, &rfds, NULL, NULL, &tv) > 0) {
        char resp[LINE_MAX] = {0};
        if (read_line(apk_fd, resp, sizeof(resp)) > 0) {
            int resp_req_id = 0;
            char action[16] = {0};
            if (sscanf(resp, "%15s %d", action, &resp_req_id) >= 1) {
                if (strcmp(action, "GRANT") == 0) result = 1;
                else if (strcmp(action, "DENY") == 0) result = 0;
                /* IGNORE also returns 0 (deny, no cache) */
            }
        }
    }

    close(apk_fd);
    return result;
}

/* ── Handle an su-wrapper CHECK request ────────────────── */
static void handle_check(int client_fd, int uid, const char *app_name) {
    /* 1. Already in allow.cache → ALLOWED immediately */
    if (file_contains(g_cache_path, uid)) {
        write(client_fd, "ALLOWED\n", 8);
        return;
    }

    /* 2. In deny.list → DENIED immediately */
    if (file_contains(g_deny_path, uid)) {
        write(client_fd, "DENIED\n", 7);
        return;
    }

    /* 3. Unknown — ask the user via APK notification */
    fprintf(stderr, "[ksu-toast] Request: uid=%d app=%s\n", uid, app_name);

    int apk_result = ask_apk(uid, app_name);

    if (apk_result == 1) {
        /* User chose GRANT — add to allowlist via ioctl */
        if (grant_app_root(uid, app_name) == 0) {
            /* Cache it so we don't ask again in this session */
            file_append(g_cache_path, uid);
            write(client_fd, "ALLOWED\n", 8);
            fprintf(stderr, "[ksu-toast] Granted root for uid=%d (%s)\n", uid, app_name);
        } else {
            fprintf(stderr, "[ksu-toast] Failed to grant root for uid=%d\n", uid);
            write(client_fd, "DENIED\n", 7);
        }
    } else if (apk_result == 0) {
        /* User chose DENY — add to deny list */
        file_append(g_deny_path, uid);
        write(client_fd, "DENIED\n", 7);
        fprintf(stderr, "[ksu-toast] Denied root for uid=%d (%s)\n", uid, app_name);
    } else {
        /* Timeout or no APK — default deny */
        write(client_fd, "DENIED\n", 7);
        fprintf(stderr, "[ksu-toast] Request timed out for uid=%d (%s)\n", uid, app_name);
    }
}

/* ── Daemon client handler (one thread per connection) ──── */
static void *client_handler(void *arg) {
    int client_fd = (int)(intptr_t)arg;
    char buf[LINE_MAX] = {0};

    if (read_line(client_fd, buf, sizeof(buf)) <= 0) {
        close(client_fd);
        return NULL;
    }

    /* Parse: CHECK <uid> <app_name> */
    char cmd[32] = {0};
    int uid = -1;
    char app_name[PKG_NAME_MAX] = "unknown";

    int parsed = sscanf(buf, "%31s %d %255s", cmd, &uid, app_name);
    if (parsed >= 2 && strcmp(cmd, "CHECK") == 0) {
        handle_check(client_fd, uid, parsed >= 3 ? app_name : "unknown");
    } else {
        write(client_fd, "ERROR unrecognized\n", 19);
    }

    close(client_fd);
    return NULL;
}

/* ── Signal handler for clean shutdown ──────────────────── */
static void handle_signal(int sig) {
    (void)sig;
    running = 0;
}

/* ── Main ───────────────────────────────────────────────── */
int main(int argc, char *argv[]) {
    /* Ignore SIGPIPE so write() to dead sockets returns EPIPE */
    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    /* Default paths (can be overridden by env or args) */
    const char *sock_path = DAEMON_SOCKET;
    const char *apk_path = APK_SOCKET;
    /* g_deny_path and g_cache_path initialized at file scope */

    /* Parse args (for testing / manual launch) */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--socket") == 0 && i + 1 < argc)
            sock_path = argv[++i];
        else if (strcmp(argv[i], "--apk-socket") == 0 && i + 1 < argc)
            apk_path = argv[++i];
        else if (strcmp(argv[i], "--deny-list") == 0 && i + 1 < argc)
            g_deny_path = argv[++i];
        else if (strcmp(argv[i], "--cache") == 0 && i + 1 < argc)
            g_cache_path = argv[++i];
    }

    /* Resolve manager UID */
    manager_uid = resolve_manager_uid();
    if (manager_uid < 0) {
        fprintf(stderr, "[ksu-toast] WARNING: Could not find KSU Next manager app.\n");
        fprintf(stderr, "[ksu-toast] Setuid to manager UID will not work.\n");
        fprintf(stderr, "[ksu-toast] Granting root via ioctl may fail.\n");
    } else {
        fprintf(stderr, "[ksu-toast] Manager UID: %d\n", manager_uid);
    }

    /* Read config file — /data/adb/ksu-toast/config/timeout overrides default */
    FILE *timeout_file = fopen("/data/adb/ksu-toast/config/timeout", "re");
    if (timeout_file) {
        char buf[16] = {0};
        if (fgets(buf, sizeof(buf), timeout_file)) {
            int val = atoi(buf);
            if (val >= 5 && val <= 60) {
                g_timeout_sec = val;
                fprintf(stderr, "[ksu-toast] Read timeout from config: %ds\n", g_timeout_sec);
            }
        }
        fclose(timeout_file);
    }

    /* Ensure /data/adb/ksu-toast/ exists */
    mkdir("/data/adb/ksu-toast", 0755);

    /* Create daemon socket */
    daemon_sock_fd = create_socket(sock_path);
    if (daemon_sock_fd < 0) {
        fprintf(stderr, "[ksu-toast] Failed to create socket: %s\n", sock_path);
        return 1;
    }

    /* Create APK communication socket */
    apk_listen_fd = create_socket(apk_path);
    if (apk_listen_fd < 0) {
        fprintf(stderr, "[ksu-toast] WARNING: Failed to create APK socket: %s\n", apk_path);
        fprintf(stderr, "[ksu-toast] Companion APK notifications will not work.\n");
        /* Non-fatal — daemon can still serve cached/denied responses */
    }

    fprintf(stderr, "[ksu-toast] daemon started. Socket: %s\n", sock_path);

    /* Main accept loop */
    while (running) {
        struct sockaddr_un client_addr;
        socklen_t client_len = sizeof(client_addr);

        /* Use select with a 1s timeout so we can check 'running' flag */
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(daemon_sock_fd, &rfds);
        struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };

        int ret = select(daemon_sock_fd + 1, &rfds, NULL, NULL, &tv);
        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (ret == 0) continue;

        int client_fd = accept(daemon_sock_fd,
                               (struct sockaddr *)&client_addr, &client_len);
        if (client_fd < 0) continue;

        /* Spawn a detached thread to handle this client */
        pthread_t thread;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

        pthread_create(&thread, &attr, client_handler, (void *)(intptr_t)client_fd);
        pthread_attr_destroy(&attr);
    }

    /* Cleanup */
    if (daemon_sock_fd >= 0) {
        close(daemon_sock_fd);
        unlink(sock_path);
    }
    if (apk_listen_fd >= 0) {
        close(apk_listen_fd);
        /* Abstract socket — no filesystem file to unlink */
        if (apk_path[0] != '@') unlink(apk_path);
    }
    unlink(PID_FILE);

    return 0;
}
