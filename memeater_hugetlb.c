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

int flag = 1;

void sig_handle(int signo) { flag = 0; }

int main(int argc, char *argv[])
{
	char *addr;
	int i;
	int ret;
	int fd = 0;
	int inject = 0;
	int privateflag = 0;
	char c;
	char filename[BUF_SIZE] = "/test";
	void *exp_addr = (void *)ADDR_INPUT;
	int nr_hps = 2;

	signal(SIGUSR1, sig_handle);

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
			nr_hps = strtol(optarg, NULL, 10);
			break;
		}
	}

	/* root path of hugetlbfs is set to global variable @filepath */
	/* get_hugetlbfs_filepath(filename); */

	addr = alloc_anonymous_hugepage(nr_hps * HPS, privateflag, exp_addr);

	/* load hugepages on memory */
	write_hugepage(addr, nr_hps, 0);
	while (flag)
		sleep(1);

	free_anonymous_hugepage(addr, nr_hps * HPS);
	pprintf("memeater_hugetlb exit.\n");
	return 0;
}
