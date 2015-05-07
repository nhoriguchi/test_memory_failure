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
	char c;
	int protflag = PROT_READ|PROT_WRITE;

	char *thp_addr;
	char *normal_anon;
	int nr_hps = 511;
	int nr_anon = 1024 * 511;
	int length;
	int length_anon;
	/* int a = _SC_PHYS_PAGES; */
	unsigned long exp_addr = ADDR_INPUT;

	c = 'A' + random() % 60;
	length = nr_hps * THPS;
	length_anon = nr_anon * PS;

	thp_addr = checked_mmap((void *)exp_addr, length, MMAP_PROT, MAP_THP, -1, 0);
	normal_anon = checked_mmap(NULL, length_anon, MMAP_PROT, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
	set_hugepage(thp_addr, length);
	clear_hugepage(normal_anon, length_anon);
	memset(thp_addr, c, length);
	memset(normal_anon, c, length_anon);
	return 0;
}
