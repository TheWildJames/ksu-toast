/*
 * sock-test.c — tiny Unix socket helper
 * Sends a line to a Unix socket and prints the response.
 * Compiled alongside ksu-toastd, no external dependencies.
 *
 * Usage: sock-test <socket-path> <message>
 * Example: sock-test /data/adb/ksu-toast/daemon.sock "CHECK 99999 TestApp"
 */

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: sock-test <socket-path> <message>\n");
        return 1;
    }

    const char *path = argv[1];
    const char *msg = argv[2];
    size_t msg_len = strlen(msg);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        return 1;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("connect");
        close(fd);
        return 1;
    }

    /* Set 12-second receive timeout (daemon waits 10s for APK) */
    struct timeval rcv_tv = { .tv_sec = 12, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rcv_tv, sizeof(rcv_tv));

    /* Send message + newline */
    write(fd, msg, msg_len);
    write(fd, "\n", 1);

    /* Shutdown write side so daemon knows we're done sending */
    shutdown(fd, SHUT_WR);

    /* Read response */
    char buf[4096];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
        buf[n] = '\0';
        printf("%s", buf);
    }

    close(fd);
    return 0;
}
