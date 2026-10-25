#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>

extern char **environ;

#define ROOTLESS_PREFIX "/var/jb"
#define DAEMON_PATH_ROOTLESS "/var/jb/Library/LaunchDaemons"
#define DAEMON_PATH_ROOTFUL "/Library/LaunchDaemons"
#define BACKUP_DIR "/var/mobile/Library/SystemOptimizer/backup"

int is_rootless(void) {
    struct stat s;
    return (stat(ROOTLESS_PREFIX, &s) == 0);
}

const char* get_daemon_dir(void) {
    return is_rootless() ? DAEMON_PATH_ROOTLESS : DAEMON_PATH_ROOTFUL;
}

void ensure_dir(const char *path) {
    struct stat st = {0};
    if (stat(path, &st) == -1) {
        mkdir(path, 0755);
    }
}

int run_cmd(const char *cmd, char *const argv[]) {
    pid_t pid;
    int status;
    if (posix_spawn(&pid, cmd, NULL, NULL, argv, environ) != 0) {
        return -1;
    }
    waitpid(pid, &status, 0);
    return WEXITSTATUS(status);
}

int backup_daemon(const char *name) {
    ensure_dir("/var/mobile/Library/SystemOptimizer");
    ensure_dir(BACKUP_DIR);
    
    char src[512], dst[512];
    snprintf(src, sizeof(src), "%s/%s.plist", get_daemon_dir(), name);
    snprintf(dst, sizeof(dst), "%s/%s.plist", BACKUP_DIR, name);
    
    struct stat st;
    if (stat(src, &st) != 0) {
        return -1;
    }
    
    if (stat(dst, &st) != 0) {
        char *cp_args[] = {"/bin/cp", src, dst, NULL};
        return run_cmd("/bin/cp", cp_args);
    }
    return 0;
}

int disable_daemon(const char *name) {
    backup_daemon(name);
    
    char active_path[512], disabled_path[512];
    snprintf(active_path, sizeof(active_path), "%s/%s.plist", get_daemon_dir(), name);
    snprintf(disabled_path, sizeof(disabled_path), "%s/%s.plist.bak", get_daemon_dir(), name);

    char *unload_args[] = {"/bin/launchctl", "unload", "-w", active_path, NULL};
    run_cmd("/bin/launchctl", unload_args);

    if (rename(active_path, disabled_path) != 0) {
        return -1;
    }
    return 0;
}

int enable_daemon(const char *name) {
    char active_path[512], disabled_path[512];
    snprintf(active_path, sizeof(active_path), "%s/%s.plist", get_daemon_dir(), name);
    snprintf(disabled_path, sizeof(disabled_path), "%s/%s.plist.bak", get_daemon_dir(), name);

    if (rename(disabled_path, active_path) != 0) {
        return -1;
    }

    char *load_args[] = {"/bin/launchctl", "load", "-w", active_path, NULL};
    run_cmd("/bin/launchctl", load_args);
    return 0;
}

int restore_all(void) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "for f in %s/*.plist.bak; do [ -f \"$f\" ] && mv \"$f\" \"${f%%.bak}\"; done", get_daemon_dir());
    char *sh_args[] = {"/bin/sh", "-c", cmd, NULL};
    return run_cmd("/bin/sh", sh_args);
}

int get_status(const char *name) {
    char path[512];
    struct stat st;
    
    snprintf(path, sizeof(path), "%s/%s.plist", get_daemon_dir(), name);
    if (stat(path, &st) == 0) return 1;

    snprintf(path, sizeof(path), "%s/%s.plist.bak", get_daemon_dir(), name);
    if (stat(path, &st) == 0) return 0;

    return -1;
}

int main(int argc, char *argv[]) {
    setuid(0);
    setgid(0);

    if (argc < 2) {
        printf("Usage: %s <status|enable|disable|restore> [daemon_name]\n", argv[0]);
        return 1;
    }

    const char *action = argv[1];

    if (strcmp(action, "restore") == 0) {
        return restore_all();
    }

    if (argc < 3) {
        return 1;
    }

    const char *daemon = argv[2];

    if (strcmp(action, "status") == 0) {
        int st = get_status(daemon);
        printf("%d\n", st);
        return (st >= 0) ? 0 : 1;
    } else if (strcmp(action, "enable") == 0) {
        return enable_daemon(daemon);
    } else if (strcmp(action, "disable") == 0) {
        return disable_daemon(daemon);
    }

    return 1;
}
