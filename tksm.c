#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/mman.h>
#include <getopt.h>
#include <errno.h>
#include <sys/time.h>
#include "test_core/lib/include.h"

#define ADDR_INPUT 0x700000000000

void sig_handle(int signo) { ; }

int main(int argc, char *argv[])
{
	char c;
	char *p1, *p2;
	int nr_pages = 2;
	int avoidtouch = 0;
        struct timeval tv;
	int hardoffline = 0;
	int softoffline = 0;
	int mceinject = 0;

	while ((c = getopt(argc, argv, "n:p:avHSc")) != -1) {
		switch(c) {
		case 'n':
			nr_pages = strtol(optarg, NULL, 10);
			break;
                case 'p':
                        testpipe = optarg;
                        {
                                struct stat stat;
                                lstat(testpipe, &stat);
                                if (!S_ISFIFO(stat.st_mode))
                                        errmsg("Given file is not fifo.\n");
                        }
                        break;
		case 'a':
			avoidtouch = 1;
			break;
		case 'v':
			verbose = 1;
			break;
		case 'H':
			hardoffline = 1;
			break;
		case 'S':
			softoffline = 1;
			break;
		case 'c':
			mceinject = 1;
			break;
		}
	}

        gettimeofday(&tv, NULL);
	srandom(tv.tv_usec);
	signal(SIGUSR1, sig_handle);

	c = 'A' + random() % 60;
	Dprintf("written letter is %c\n", c);
	Dprintf("nr_pages = %d\n", nr_pages);

	p1 = checked_mmap((void *)ADDR_INPUT, nr_pages * PS, MMAP_PROT,
			  MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
	p2 = checked_mmap((void *)(ADDR_INPUT + 0x10000000), nr_pages * PS,
			  MMAP_PROT, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);

	set_mergeable(p1, nr_pages * PS);
	set_mergeable(p2, nr_pages * PS);
	
	memset(p1, c, nr_pages * PS);
	memset(p2, c, nr_pages * PS);

	if (hardoffline || softoffline) {
		int offset = 0;
		char rbuf[256];
		pprintf("error injection with madvise\n");
		pause();
		pipe_read(rbuf);
		offset = strtol(rbuf, NULL, 0);
		Dprintf("madvise inject to page offset %d\n", offset);
		if (madvise(p1 + offset*PS, PS,
			    hardoffline ? MADV_HWPOISON : MADV_SOFT_OFFLINE) != 0)
			perror("madvise");
		pprintf("after madvise injection\n");
		pause();
	} else if (mceinject == 1) {
		pprintf("waiting for injection from outside\n");
		pause();
	} else {
		printf("No memory error injection\n");
	}

	if (!avoidtouch) {
		pprintf("writing affected region\n");
		pause();
		memset(p1, c + 1, PS);
	}

	clear_mergeable(p1, nr_pages * PS);
	clear_mergeable(p2, nr_pages * PS);

	pprintf("tksm exit.\n");
	pause();
	exit(EXIT_SUCCESS);
}
