#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>

#define MADV_SOFT_OFFLINE 101

int main(int argc, char *argv[])
{
	int count = 1000;
	size_t len = 4096;
	char *p;

	if (argc > 1 && !strcmp(argv[1], "hugetlb")) {
		p = mmap(NULL, 0x200000, PROT_READ|PROT_WRITE,
			 MAP_PRIVATE|MAP_ANONYMOUS|MAP_HUGETLB, -1, 0);
		if (p == MAP_FAILED)
			perror("mmap");
		printf("use hugetlb %p\n", p);
		memset(p, 'c', 0x200000);
	} else {
		p = malloc(len);
		if (!p)
			perror("malloc");
	}

	while (1) {
		madvise(p, len, MADV_SOFT_OFFLINE);
		usleep(100000);
	}
}
