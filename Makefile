CC=gcc
CFLAGS=-g # -Wall -Wextra
TESTCASE_FILTER=

src=tthp.c tksm.c thugetlb.c memeater.c memeater_multithread.c test_base_madv_simple_stress.c tthp_on_pcplist.c tthp_small.c
exe=$(src:.c=)
stapsrc=filter_memory_error_event.stp check_mce_capability.stp
stapexe=$(stapsrc:.stp=.ko)
srcdir=.
dstdir=/usr/local/bin
dstexe=$(addprefix $(dstdir)/,$(exe))

OPT=-DDEBUG
LIBOPT=-lpthread #-lnuma # -lcgroup

all: get_test_core $(exe)
%: %.c
	$(CC) $(CFLAGS) -o $@ $^ $(OPT) $(LIBOPT)

get_test_core:
	@test -d "test_core" || git clone https://github.com/Naoya-Horiguchi/test_core
	@true

install: $(exe)
	for file in $? ; do \
	  mv $$file $(dstdir) ; \
	done

clean:
	@for file in $(exe) $(stapexe) ; do \
	  rm $(dstdir)/$$file 2> /dev/null ; \
	  rm $(srcdir)/$$file 2> /dev/null ; \
	  true ; \
	done

basetest: all
	bash run-test.sh -v -r base_test.rc -n $@ $(TESTCASE_FILTER)

hugetlbtest: all
	bash run-test.sh -v -r hugetlb_test.rc -n $@ $(TESTCASE_FILTER)

thptest: all
	bash run-test.sh -v -r thp_test.rc -n $@ $(TESTCASE_FILTER)

kvmtest: all
	bash run-test.sh -v -r kvm_test.rc -n $@ -S $(TESTCASE_FILTER)

tmpkvmtest: all
	bash run-test.sh -v -r tmp_kvm_test.rc -n $@ -S $(TESTCASE_FILTER)

ksmtest: all
	bash run-test.sh -v -r ksm_test.rc -n $@ $(TESTCASE_FILTER)

test: basetest hugetlbtest thptest ksmtest

fulltest: basetest kvmtest thptest kvmtest ksmtest
