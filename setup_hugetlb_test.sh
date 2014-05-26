#!/bin/bash

HUGETLBDIR=`grep hugetlbfs /proc/mounts | head -n1 | cut -f2 -d' '`
if [ ! -d "${HUGETLBDIR}" ] ; then
    mount -t hugetlbfs none /dev/hugepages
    if [ $? -ne 0 ] ; then
        echo "hugetlbfs not mounted." >&2 && exit 1
    fi
fi
THUGETLB=`dirname $BASH_SOURCE`/thugetlb
[ ! -x "$THUGETLB" ] && echo "thugetlb not found." >&2 && exit 1

sysctl vm.nr_hugepages=100
NRHUGEPAGE=`cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages`
[ "${NRHUGEPAGE}" -ne 100 ] && echo "failed to allocate hugepage." >&2 && exit 1

hva2hpa() {
    $PAGETYPES -Nl -a $1 | grep -v offset | cut -f2
}

prepare_test() {
    save_nr_corrupted_before
    get_kernel_message_before
}

cleanup_test() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
}

control_hugetlb() {
    local pid="$1"
    local line="$2"
    local injpfn="$[BASEVFN + ERROR_OFFSET]"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "waiting for injection from outside")
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 > ${TMPF}.pageflagcheck1
            ${PAGETYPES} -p ${pid} -a ${BASEVFN} | grep huge > /dev/null 2>&1
            if [ $? -ne 0 ] ; then
                echo "Target address is NOT hugepage." | tee -a /dev/kmsg
                set_return_code "HUGEPAGE_ALLOC_FAILURE"
            fi
            # cat /proc/${pid}/numa_maps | tee -a ${OFILE}
            ${MCEINJECT} -p ${pid} -e ${ERROR_TYPE} -a ${injpfn} # 2>&1
            kill -SIGUSR1 ${pid}
            ;;
        "error injection with madvise")
            # tell cmd the page offset into which error is injected
            echo ${ERROR_OFFSET} > ${PIPE}
            kill -SIGUSR1 ${pid}
            ;;
        "after madvise injection")
            kill -SIGUSR1 ${pid}
            ;;
        "writing affected region")
            set_return_code "ACCESS"
            kill -SIGUSR1 ${pid}
            sleep 0.5
            ;;        
        "thugetlb exit.")
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 > ${TMPF}.pageflagcheck2
            kill -SIGUSR1 ${pid}
            set_return_code "EXIT"
            return 0
            ;;
        "PROCESS_KILLED")
            set_return_code "KILLED"
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_hugetlb() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "$EXPECTED_RETURN_CODE"
    check_nr_hwcorrupted
}

check_hugetlb_soft_offline() {
    check_hugetlb
    check_hugepage_migrated
}

check_hugepage_migrated() {
    local before=($(sed -ne '2,$p' ${TMPF}.pageflagcheck1 | cut -f2 | tr '\n' ' '))
    local after=($(sed -ne '2,$p' ${TMPF}.pageflagcheck2 | cut -f2 | tr '\n' ' '))

    count_testcount "hugepage migration?"
    if [ x"${before[0]}" != x"${after[0]}" ] && [ x"${before[1]}" != x"${after[1]}" ] ; then
        count_success "hugepage migrated (${before[0]} -> ${after[0]})"
    else
        count_failure "hugepage not migrated"
    fi
}

control_hugetlb_race() {
    local tgthpage=0x$(${PAGETYPES}  -b huge,compound_head,mmap=huge,compound_head -Nl | sed -n -e 4p | cut -f1)
    echo "echo target hugepage ${tgthpage}"
    local tgthpage2=$(printf "0x%x" $[${tgthpage} + 3])
    echo "echo target hugepage ${tgthpage2}"

    ( while true ; do ${PAGETYPES} -b hwpoison -x -N ; done ) &
    local pid1=$!
    ( while true ; do ${MCEINJECT} -e "mce-srao" -a $tgthpage ; done ) &
    local pid2=$!
    ( while true ; do ${MCEINJECT} -e "mce-srao" -a $tgthpage2 ; done ) &
    local pid3=$!
    sleep 1
    kill -9 $pid2
    kill -9 $pid3
    kill -9 $pid1
    set_return_code EXIT
}

check_hugetlb_race() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "$EXPECTED_RETURN_CODE"
    check_nr_hwcorrupted_consistent
}
