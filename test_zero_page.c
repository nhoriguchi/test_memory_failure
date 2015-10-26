#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>

#include "test_core/lib/include.h"

#define ADDR_INPUT 0x700000000000

void sig_handle(int signo) { ; }

int main(int argc, char *argv[])
{
	int count = 1000;
	size_t len = 4096;
	char *p;
	char c;
	int i;
	int nr = 10;

	while ((c = getopt(argc, argv, "vp:n:")) != -1) {
		switch (c) {
		case 'v':
			verbose = 1;
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
		case 'n':
			nr = strtol(optarg, NULL, 10);
			break;
		}
	}

	signal(SIGUSR1, sig_handle);

	p = checked_mmap((void *)ADDR_INPUT, nr * PS, PROT_READ|PROT_WRITE,
			 MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
	/* fault in */
	for (i = 0; i < nr; i++)
		c = p[i*PS];
	pprintf("zero page allocated.\n");
	pause();

	pprintf("test_zero_page exit.\n");
	pause();
	return 0;
}
