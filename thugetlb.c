/*
 * Test program for memory error handling for hugepages
 * Author: Naoya Horiguchi <n-horiguchi@ah.jp.nec.com>
 */
#define _GNU_SOURCE 1
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/mman.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/types.h>
#include <sys/prctl.h>
#include <sys/wait.h>

#include "test_core/lib/include.h"
#include "test_core/lib/hugepage.h"

#define ADDR_INPUT 0x700000000000

void sig_handle(int signo) { ; }

int main(int argc, char *argv[])
{
	char *addr;
	int i;
	int ret;
	int fd = 0;
	int inject = 0;
	int avoidtouch = 0;
	int privateflag = 0;
	int cowflag = 0;
	char c;
	char filename[BUF_SIZE] = "/test";
	void *exp_addr = (void *)ADDR_INPUT;
	int corrupt_page = -1;
	int nr_hps = 2;
	int offset = 0;

	int hardoffline = 0;
	int softoffline = 0;
	int mceinject = 0;

	signal(SIGUSR1, sig_handle);

	while ((c = getopt(argc, argv, "avp:HScn:")) != -1) {
		switch (c) {
		case 'a':
			avoidtouch = 1;
			break;
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
		case 'H':
			hardoffline = 1;
			break;
		case 'S':
			softoffline = 1;
			break;
		case 'c':
			mceinject = 1;
			break;
		case 'n':
			nr_hps = strtol(optarg, NULL, 10);
			break;
		}
	}

	/* root path of hugetlbfs is set to global variable @filepath */
	/* get_hugetlbfs_filepath(filename); */

	addr = alloc_anonymous_hugepage(nr_hps * HPS, privateflag, exp_addr);

	/* load hugepages on memory */
	write_hugepage(addr, nr_hps, 0);

	if (hardoffline || softoffline) {
		char rbuf[256];
		pprintf("error injection with madvise\n");
		pause();
		pipe_read(rbuf);
		offset = strtol(rbuf, NULL, 0);
		Dprintf("madvise inject to addr %lx\n", addr + offset * PS);
		if (madvise(addr + offset*PS, PS,
			    hardoffline ? MADV_HWPOISON : MADV_SOFT_OFFLINE) != 0)
			perror("madvise");
		pprintf("after madvise injection\n");
		pause();
	} else if (mceinject == 1) {
		pprintf("waiting for injection from outside\n");
		pause();
	} else {
		printf("No memory error injection\n");
		pause();
	}

	if (!avoidtouch) {
		pprintf("writing affected region\n");
		pause();
		write_hugepage(addr, nr_hps, 0);
	}

	pprintf("thugetlb_exit\n");
	pause();
	free_anonymous_hugepage(addr, nr_hps * HPS);
	return 0;
}
