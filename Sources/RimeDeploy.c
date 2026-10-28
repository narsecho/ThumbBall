#include "RimeBridge.h"
#include <stdio.h>
int main(int argc, char **argv) {
 if (argc != 3 || !tb_rime_start(argv[1], argv[2], 1)) { fprintf(stderr,"Rime dictionary deployment failed\n");return 1; }
 tb_rime_stop();puts("PASS: Rime T9 dictionary precompiled");return 0;
}
