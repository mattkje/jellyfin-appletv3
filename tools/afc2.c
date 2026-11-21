// afc2 ls <path> | info <path> | get <remote> <local> | put <local> <remote> | link <target> <path> | mkdir <path>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/afc.h>
int main(int c, char **v) {
    idevice_t d; afc_client_t a;
    if (c < 3 || idevice_new(&d, NULL)) { fprintf(stderr, "usage/no device\n"); return 1; }
    {
        // fall back via lockdown
        lockdownd_client_t l; lockdownd_service_descriptor_t s = NULL;
        if (lockdownd_client_new_with_handshake(d, &l, "afc2") || lockdownd_start_service(l, "com.apple.afc2", &s)) { fprintf(stderr, "no afc2\n"); return 2; }
        afc_client_new(d, s, &a); lockdownd_client_free(l);
    }
    if (!strcmp(v[1], "ls")) {
        char **list = NULL;
        if (afc_read_directory(a, v[2], &list)) { fprintf(stderr, "ls failed\n"); return 3; }
        for (int i = 0; list[i]; i++) if (strcmp(list[i], ".") && strcmp(list[i], "..")) puts(list[i]);
    } else if (!strcmp(v[1], "get") && c == 4) {
        uint64_t h; if (afc_file_open(a, v[2], AFC_FOPEN_RDONLY, &h)) { fprintf(stderr, "open failed\n"); return 3; }
        FILE *o = fopen(v[3], "wb"); char buf[65536]; uint32_t n;
        while (afc_file_read(a, h, buf, sizeof buf, &n) == AFC_E_SUCCESS && n) fwrite(buf, 1, n, o);
        fclose(o); afc_file_close(a, h);
    } else if (!strcmp(v[1], "put") && c == 4) {
        uint64_t h; if (afc_file_open(a, v[3], AFC_FOPEN_WRONLY, &h)) { fprintf(stderr, "open failed\n"); return 3; }
        FILE *i = fopen(v[2], "rb"); char buf[65536]; size_t r; uint32_t n;
        while ((r = fread(buf, 1, sizeof buf, i)) > 0) afc_file_write(a, h, buf, (uint32_t)r, &n);
        fclose(i); afc_file_close(a, h);
    } else if (!strcmp(v[1], "info")) {
        char **info = NULL;
        if (afc_get_file_info(a, v[2], &info)) { fprintf(stderr, "info failed\n"); return 3; }
        for (int i = 0; info[i]; i += 2) printf("%s=%s\n", info[i], info[i + 1]);
    } else if (!strcmp(v[1], "link") && c == 4) {      // link <target> <linkpath>
        { afc_error_t e = afc_make_link(a, AFC_SYMLINK, v[2], v[3]); if (e) fprintf(stderr, "link error %d\n", e); return e ? 3 : 0; }
    } else if (!strcmp(v[1], "mv") && c == 4) {
        return afc_rename_path(a, v[2], v[3]) ? 3 : 0;
    } else if (!strcmp(v[1], "rm")) {               // one file or empty folder
        return afc_remove_path(a, v[2]) ? 3 : 0;
    } else if (!strcmp(v[1], "mkdir")) {
        return afc_make_directory(a, v[2]) ? 3 : 0;
    }
    afc_client_free(a); idevice_free(d); return 0;
}
