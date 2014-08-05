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
#include <pthread.h>
#include "test_core/lib/include.h"

#define ALLOCPAGE   256
#define ALLOCBYTE   ALLOCPAGE*PSIZE
#define VADDR       0x700000000000
#define VADDRINT    0x001000000000

#define SEGNR	10
char *p[SEGNR];

void usage(char *str)
{
	printf(
"Usage: %s [-f file)]\n"
"  -f : give file path to pass the vma info\n"
, str);
	exit(EXIT_SUCCESS);
}

void sig_handle(int signo) {
	int i, j;
	for (i = 0; i < SEGNR; i++)
		for (j = 0; j < ALLOCPAGE; j++)
			p[i][j * PSIZE] = 1;
}

void *access_memory(void *arg) {
	int i;
	char c;
	while (1) {
		usleep(1000000);
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
	}
}

int main(int argc, char **argv) {
	int fd[4];
	int i, j;
	char c;
	char fname[256];
	char buf[PSIZE];
	char *foutpath = 0;
	int threads = 1;
	time_t t;
	pthread_t *pthreadsp;
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

        while ((c = getopt(argc, argv, "p:vf:t:")) != -1) {
                switch(c) {
                case 'p':
                        testpipe = optarg;
                        {
                                struct stat stat;
                                lstat(testpipe, &stat);
                                if (!S_ISFIFO(stat.st_mode))
                                        errmsg("Given file is not fifo.\n");
                        }
                        break;
                case 'v':
                        verbose = 1;
                        break;
		case 'f' :
			foutpath = optarg;
			break;
                case 't':
                        threads = strtoul(optarg, NULL, 10);
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
        p[8] = mmap((void *)VADDR+VADDRINT*5, ALLOCBYTE, MMAP_PROT, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
        p[9] = mmap((void *)VADDR+VADDRINT*6, ALLOCBYTE, MMAP_PROT, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);

        set_mergeable(p[8], ALLOCBYTE);
        set_mergeable(p[9], ALLOCBYTE);
        memset(p[8], 'a', ALLOCBYTE);
        memset(p[9], 'a', ALLOCBYTE);
	Dprintf("p[8] %p, p[9] %p\n", p[8], p[9]);

	for (i = 0; i < SEGNR; i++)
		for (j = 0; j < ALLOCPAGE; j++)
			c = p[i][j * PSIZE];

	if (foutpath) {
		int fdout = open(foutpath, O_RDWR|O_TRUNC|O_CREAT, 0666);
		char addr[32];
		for (i = 0; i < SEGNR; i++) {
			sprintf(addr, "%p\n", p[i]);
			write(fdout, addr, strlen(addr));
		}
		close(fdout);
	}

	signal(SIGUSR1, sig_handle);

	pthreadsp = checked_malloc(threads * sizeof(pthread_t));

	for (i = 0; i < threads; i++) {
		Dprintf("Thread %i start\n", i);
		pthread_create(&pthreadsp[i], NULL, access_memory, NULL);
	}

	for (i = 0; i < threads; i++)
		pthread_join(pthreadsp[i], NULL);
	Dprintf("Pthreads joined.\n");
}
