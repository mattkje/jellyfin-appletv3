// dltest <path>: dlopen a bundle on the Apple TV and report what happened.
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    printf("dltest running\n"); fflush(stdout);
    for (int i = 1; i < argc; i++) {
        void *h = dlopen(argv[i], RTLD_NOW);
        printf("%s: %s\n", argv[i], h ? "loaded OK" : dlerror());
        fflush(stdout);
    }
    return 0;
}
