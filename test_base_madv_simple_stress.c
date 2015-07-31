#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include "test_core/lib/include.h"

#define ALLOCPAGE   256
#define ALLOCBYTE   ALLOCPAGE*PSIZE
#define VADDR       0x700000000000
#define VADDRINT    0x001000000000

#define SEGNR          8
char *p[SEGNR];

int main(int argc, char **argv) {
	int fd[4];
	int i, j;
	int ret;
	int injtype;
	char c;
	char fname[256];
	char buf[PSIZE];
	time_t t;
	srand((unsigned) time(&t));

	for (i = 0; i < 4; i++) {
		sprintf(fname, "/root/testfile%d", i+1);
		fd[i] = open(fname, O_RDWR|O_CREAT, 0644);
		if (fd[i] == -1) err("open");
		memset(buf, rand(), PSIZE);
		for (j = 0; j < ALLOCPAGE; j++)
			write(fd[i], buf, PSIZE);
		fsync(fd[i]);
	}

	p[0] = malloc(ALLOCBYTE);
	p[1] = malloc(ALLOCBYTE);
	p[2] = mmap((void*)VADDR,          ALLOCBYTE, MMAP_PROT, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	p[3] = mmap((void*)VADDR+VADDRINT, ALLOCBYTE, MMAP_PROT, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	p[4] = mmap((void*)VADDR+VADDRINT*2, ALLOCBYTE, MMAP_PROT, MAP_SHARED, fd[0], 0);
	p[5] = mmap((void*)VADDR+VADDRINT*3, ALLOCBYTE, MMAP_PROT, MAP_SHARED, fd[1], 0);
	p[6] = mmap((void*)VADDR+VADDRINT*4, ALLOCBYTE, MMAP_PROT, MAP_PRIVATE, fd[2], 0);
	p[7] = mmap((void*)VADDR+VADDRINT*5, ALLOCBYTE, MMAP_PROT, MAP_PRIVATE, fd[3], 0);

	for (i = 0; i < SEGNR; i++)
		for (j = 0; j < ALLOCPAGE; j++)
			c = p[i][j * PSIZE];

	pprintf("write random\n");

	for (i = 0; i < ALLOCPAGE; i++) {
		c = p[0][i * PSIZE];
		p[1][i * PSIZE] = rand();
		c = p[2][i * PSIZE];
		p[3][i * PSIZE] = rand();
		c = p[4][i * PSIZE];
		p[5][i * PSIZE] = rand();
		c = p[6][i * PSIZE];
		p[7][i * PSIZE] = rand();
	}
	for (i = 0; i < ALLOCPAGE; i++) {
		for (j = 0; j < SEGNR; j++) {
			injtype = (i + j) % 2 ? MADV_HWPOISON : MADV_SOFT_OFFLINE;
			ret = madvise(p[j] + i * PS, PS, injtype);
			if (ret < 0)
				fprintf(stderr, "madvise(%d) to p[%d] + %d PS failed\n",
					injtype, j, i);
		}
	}
	pprintf("%s exit\n", argv[0]);
}
