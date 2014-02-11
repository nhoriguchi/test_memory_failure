CC=gcc
CFLAGS=-g # -Wall -Wextra
TESTCASE_FILTER=

src=tthp.c tksm.c thugetlb.c memeater.c
exe=$(src:.c=)
srcdir=.
dstdir=/usr/local/bin
dstexe=$(addprefix $(dstdir)/,$(exe))

OPT=-DDEBUG
LIBOPT= #-lnuma # -lcgroup

all: get_test_core $(exe)
%: %.c
	$(CC) $(CFLAGS) -o $@ $^ $(OPT) $(LIBOPT)

get_test_core:
	git clone https://github.com/Naoya-Horiguchi/test_core || true
	@true

install: $(exe)
	for file in $? ; do \
	  mv $$file $(dstdir) ; \
	done

clean:
	@for file in $(exe) ; do \
	  rm $(dstdir)/$$file 2> /dev/null ; \
	  rm $(srcdir)/$$file 2> /dev/null ; \
	  true ; \
	done

hugetlbtest: all
	bash run-test.sh -v -r hugetlb_test.rc -n $@ $(TESTCASE_FILTER)

thptest: all
	bash run-test.sh -v -r thp_test.rc -n $@ $(TESTCASE_FILTER)

kvmtest: all
	bash run-test.sh -v -r kvm_test.rc -n $@ -S $(TESTCASE_FILTER)

ksmtest: all
	bash run-test.sh -v -r ksm_test.rc -n $@ $(TESTCASE_FILTER)

test: hugetlbtest thptest ksmtest

fulltest: kvmtest thptest kvmtest ksmtest
