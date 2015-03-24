#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <getopt.h>
#include "test_core/lib/include.h"

#define ALLOCPAGE   256
#define ALLOCBYTE   ALLOCPAGE*PSIZE
#define VADDR       0x700000000000
#define VADDRINT    0x001000000000

#define SEGNR          8
char *p[SEGNR];

void usage(char *str)
{
	printf(
"Usage: %s [-f file)]\n"
"  -f : give file path to pass the vma info\n"
, str);
	exit(EXIT_SUCCESS);
}

void sig_handle(int signo) { ; }

int main(int argc, char **argv) {
	int fd[4];
	int i, j;
	char c;
	char fname[256];
	char buf[PSIZE];
	char *foutpath = 0;
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

	while (1) {
		char c;
		int option_index = 0;
		static struct option long_options[] = {
			{ "file"  , required_argument , 0, 'f' },
			{ 0       , 0                 , 0,  0  }
		};

		if ((c = getopt_long(argc, argv, "f:",
				     long_options, &option_index)) == -1)
			break;

		switch (c) {
		case 'f' :
			/* waitms = strtol(optarg, NULL, 10); */
			foutpath = optarg;
			break;
		default:
			usage(argv[0]);
		}
	}

	p[0] = malloc(ALLOCBYTE);
	p[1] = malloc(ALLOCBYTE);
	p[2] = mmap((void*)VADDR, ALLOCBYTE, MMAP_PROT, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	p[3] = mmap((void*)VADDR+VADDRINT, ALLOCBYTE, MMAP_PROT, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	p[4] = mmap((void*)VADDR+VADDRINT*2, ALLOCBYTE, MMAP_PROT, MAP_SHARED, fd[0], 0);
	p[5] = mmap((void*)VADDR+VADDRINT*3, ALLOCBYTE, MMAP_PROT, MAP_SHARED, fd[1], 0);
	p[6] = mmap((void*)VADDR+VADDRINT*4, ALLOCBYTE, MMAP_PROT, MAP_PRIVATE, fd[2], 0);
	p[7] = mmap((void*)VADDR+VADDRINT*5, ALLOCBYTE, MMAP_PROT, MAP_PRIVATE, fd[3], 0);

	/* Forbid readahead, which could kill TP with SIGBUS */
	for (i = 0; i < SEGNR; i++)
		madvise(p[i], ALLOCBYTE, MADV_RANDOM);

	/* create dirty/clean pattern */
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

	signal(SIGUSR1, sig_handle);
	if (foutpath) {
		int fdout = open(foutpath, O_RDWR|O_TRUNC|O_CREAT, 0666);
		char addr[32];
		for (i = 0; i < SEGNR; i++) {
			sprintf(addr, "%p\n", p[i]);
			write(fdout, addr, strlen(addr));
		}
		close(fdout);
	}
	pause();
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
	sleep(3);
	return 0;
}
