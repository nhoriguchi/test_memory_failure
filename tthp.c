#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <getopt.h>
#include "test_core/lib/include.h"
#include "test_core/lib/pfn.h"

#define MAP_THP MAP_PRIVATE|MAP_ANONYMOUS
#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

void split_thp(char *ptr, int size) {
	clear_hugepage(ptr, size);
	mlock(ptr, 4096);
	ptr[0] = 'a';
	munlock(ptr, 4096);
	set_hugepage(ptr, size);
}

int main(int argc, char *argv[]) {
	int i;
	int nr = 2;
	char c;
	char *p;
	int mapflag = MAP_ANONYMOUS|MAP_SHARED;
	int protflag = PROT_READ|PROT_WRITE;
	int reserveonly = 0;
	unsigned long memsize = 0;

	char *thp_addr;
	int nr_hps = 1;
	int length;
	int madviseflag = 0;
	unsigned long exp_addr = ADDR_INPUT;
	int hardoffline = 0;
	int softoffline = 0;
	int mceinject = 0;
	int tail = 0;
	int avoidtouch = 0;
	int split = 0;
	int rhelmode = 0;
	int waitms = 0;
	int busyloop = 0;
	char tmpbuf[256];
        struct timeval tv;
	struct pagestat ps;
	struct pagestat ps_tail;

	while ((c = getopt(argc, argv, "n:w:p:mMHSca:tAPRvb")) != -1) {
		switch(c) {
		case 'n':
			nr_hps = strtol(optarg, NULL, 10);
			break;
		case 'w':
			waitms = strtol(optarg, NULL, 10);
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
		case 'm':
			madviseflag++;
			break;
		case 'M':
			madviseflag++;
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
		case 'a':
			exp_addr = strtol(optarg, NULL, 0);
			break;
		case 't':
			tail = 1;
			break;
		case 'A':
			avoidtouch = 1;
			break;
		case 'P':
			split = 1;
			break;
		case 'R':
			rhelmode = 1;
			break;
		case 'v':
			verbose = 1;
			break;
		case 'b':
			busyloop = 1;
			break;
		}
	}

        gettimeofday(&tv, NULL);
	srandom(tv.tv_usec);
	signal(SIGUSR1, sig_handle);

	c = 'A' + random() % 60;
	length = nr_hps * THPS;

	Dprintf("written letter is %c\n", c);
	Dprintf("nr_hugepages = %d, length 0x%x\n", nr_hps, length);
	Dprintf("Expected virtual address 0x%lx\n", exp_addr);
	Dprintf("wait %d millisecs\n", waitms);

	thp_addr = checked_mmap((void *)exp_addr, length, MMAP_PROT, MAP_THP, -1, 0);

	if (madviseflag == 1)
		set_hugepage(thp_addr, length);

	memset(thp_addr, c, length);
	/* just after page fault */
	pprintf("waiting for page fault\n");
	pause();

	if (split) {
		split_thp(thp_addr, length);
		pprintf("splitting thp\n");
		pause();
	} else {
		Dprintf("No splitting\n");
	}

	if (split) {
		pprintf("waiting for memory compaction\n");
		pause();
	} else {
		Dprintf("no memory compaction\n");
	}

	if (waitms)
		usleep(1000*waitms);

	pprintf("waiting for signal\n");
	pause();

	/*
	 * RHEL6 don't have KPF_THP flags so we have no reliable means to know
	 * a given address is backed by thp. So we try the next best mean, where
	 * we have check over all pmd range (512 pages) are contiguous physically,
	 * and suspected "tail" pages should have zero refcount.
	 */
	if (rhelmode) {
		get_pagestat(thp_addr, &ps);
		get_pagestat(thp_addr + PSIZE, &ps_tail);
		/* some check */
	} else {
		get_pagestat(thp_addr, &ps);
		if (!(ps.pflags & 1 << KPF_THP)) {
			pprintf("NG, target memory is NOT backed by THP.\n");
			exit(EXIT_FAILURE);
		} else {
			pprintf("OK, target memory is backed by THP.\n");
		}
	}

	/*
	 * TODO: reading /proc/pid/pagemap cause splitting thp, so there is
	 * no way to know phyical address of thp, which means we cannot do
	 * right test for memory corruption on thp.
	 */
	if (hardoffline || softoffline) {
		int offset = 0;
		char rbuf[256];
		pprintf("error injection with madvise\n");
		pause();
		pipe_read(rbuf);
		offset = strtol(rbuf, NULL, 0);
		Dprintf("madvise inject to page offset %d\n", offset);
		if (madvise(thp_addr + offset*PS, PS,
			    hardoffline ? MADV_HWPOISON : MADV_SOFT_OFFLINE) != 0)
			perror("madvise");
		pprintf("after madvise injection\n");
		pause();
	} else if (mceinject == 1) {
		pprintf("waiting for injection from outside\n");
		pause();
	} else if (busyloop == 1) {
		signal(SIGUSR1, sig_handle_flag);
		pprintf("busyloop start\n");
		while (flag)
			for (i = 0; i < nr_hps; i++)
				thp_addr[i*THPS] = 'x';
		pprintf("busyloop done\n");
	} else {
		printf("No memory error injection\n");
	}

	if (!avoidtouch) {
		pprintf("writing affected region\n");
		pause();
		memset(thp_addr, c, length);
	}

	if (madviseflag)
		clear_hugepage(thp_addr, length);

	pprintf("tthp exit.\n");
	pause();
	return 0;
}
