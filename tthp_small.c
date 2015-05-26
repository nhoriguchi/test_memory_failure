#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h>
#include "test_core/lib/include.h"

#define MAP_THP MAP_PRIVATE|MAP_ANONYMOUS
#define ADDR_INPUT 0x700000000000

int main(int argc, char *argv[]) {
	int i;
	int protflag = PROT_READ|PROT_WRITE;

	char *thp_addr;
	int nr_hps = 10;
	int length;
	unsigned long exp_addr = ADDR_INPUT;

	length = nr_hps * THPS;
	while (1) {
		thp_addr = checked_mmap((void *)exp_addr, length, MMAP_PROT, MAP_THP, -1, 0);
		set_hugepage(thp_addr, length);
		memset(thp_addr, 'a', length);
		checked_munmap(thp_addr, length);
	}
	return 0;
}
