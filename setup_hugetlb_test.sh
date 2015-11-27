#!/bin/bash

HUGETLBDIR=`grep hugetlbfs /proc/mounts | head -n1 | cut -f2 -d' '`
if [ ! -d "${HUGETLBDIR}" ] ; then
    mount -t hugetlbfs none /dev/hugepages
    if [ $? -ne 0 ] ; then
        echo "hugetlbfs not mounted." >&2 && exit 1
    fi
fi

check_and_define_tp thugetlb
check_and_define_tp memeater_hugetlb

hva2hpa() {
    $PAGETYPES -Nl -a $1 | grep -v offset | cut -f2
}

prepare_hugetlb() {
    # TODO: early kill knob?
    # TODO: kill exisiting programs?
    if [ "$ERROR_TYPE" = mce-srao ] ; then
        check_mce_capability || return 1 # MCE SRAO not supported
    fi
    pkill -9 -f $thugetlb
    save_nr_corrupted_before
    set_and_check_hugetlb_pool 100
    prepare_system_default
}

cleanup_hugetlb() {
    save_nr_corrupted_inject
    all_unpoison
    pkill -9 -f $thugetlb
    set_and_check_hugetlb_pool 0
    save_nr_corrupted_unpoison
    prepare_system_default
}

control_hugetlb() {
    local pid="$1"
    local line="$2"
    local injpfn="$[BASEVFN + ERROR_OFFSET]"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "waiting for injection from outside")
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 | tee ${TMPF}.pageflagcheck1
            ${PAGETYPES} -p ${pid} -a ${BASEVFN} | grep huge > /dev/null 2>&1
            if [ $? -ne 0 ] ; then
                echo "Target address is NOT hugepage." | tee -a $OFILE
                set_return_code "HUGEPAGE_ALLOC_FAILURE"
                kill -SIGKILL $pid
                return 0
            fi
            # cat /proc/${pid}/numa_maps | tee -a ${OFILE}
            printf "Inject MCE ($ERROR_TYPE) to %lx.\n" $injpfn | tee -a $OFILE >&2
            ${MCEINJECT} -p ${pid} -e ${ERROR_TYPE} -a ${injpfn} # 2>&1
            kill -SIGUSR1 ${pid}
            ;;
        "error injection with madvise")
            # tell cmd the page offset into which error is injected
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 | tee ${TMPF}.pageflagcheck1
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
        "thugetlb_exit")
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 | tee ${TMPF}.pageflagcheck2
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

check_hugetlb_hard_offline() {
    check_system_default
    check_nr_hwcorrupted
}

check_hugetlb_soft_offline() {
    check_hugetlb_hard_offline
    check_hugepage_migrated
}

check_hugepage_migrated() {
    local before=($(sed -ne '2,$p' ${TMPF}.pageflagcheck1 | cut -f2 | tr '\n' ' '))
    local after=($(sed -ne '2,$p' ${TMPF}.pageflagcheck2 | cut -f2 | tr '\n' ' '))

    count_testcount "hugepage migration?"
	echo "[${before[0]}]"
	echo "[${after[0]}]"
	if [ ! "${before[0]}" ] || [ ! "${after[0]}" ] ; then
        count_failure "failed to get pfn (before:${before[0]}, after:${after[0]})"
    elif [ x"${before[0]}" != x"${after[0]}" ] && [ x"${before[1]}" != x"${after[1]}" ] ; then
        count_success "hugepage migrated (${before[0]} -> ${after[0]})"
    else
        count_failure "hugepage not migrated (${before[0]} -> ${after[0]})"
    fi
}

prepare_hugetlb_race() {
    set_and_check_hugetlb_pool 100
	$memeater_hugetlb -n 30 &
	prepare_multiple_injection_race
}

cleanup_hugetlb_race() {
	pkill -f $memeater_hugetlb
	cleanup_multiple_injection_race
    set_and_check_hugetlb_pool 0
}

# prepare_hugetlb_race_between_injection_and_mmap_fault_munmap() {
# }
# cleanup_hugetlb_race_between_injection_and_mmap_fault_munmap() {
# }
# control_hugetlb_race_between_injection_and_mmap_fault_munmap() {
# }
# check_hugetlb_race_between_injection_and_mmap_fault_munmap() {
# }
