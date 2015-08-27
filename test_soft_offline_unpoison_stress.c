#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#define MADV_SOFT_OFFLINE 101

int main(int argc, char *argv[])
{
	int count = 1000;
	size_t len = 4096;
	char *p = malloc(len);

	while (count--) {
		madvise(p, len, MADV_SOFT_OFFLINE);
		sleep(1000);
	}
}
