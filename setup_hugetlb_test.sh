#!/bin/bash

HUGETLBDIR=`grep hugetlbfs /proc/mounts | head -n1 | cut -f2 -d' '`
if [ ! -d "${HUGETLBDIR}" ] ; then
    mount -t hugetlbfs none /dev/hugepages
    if [ $? -ne 0 ] ; then
        echo "hugetlbfs not mounted." >&2 && exit 1
    fi
fi

check_and_define_tp thugetlb

hva2hpa() {
    $PAGETYPES -Nl -a $1 | grep -v offset | cut -f2
}

prepare_hugetlb() {
    # TODO: early kill knob?
    # TODO: kill exisiting programs?
    save_nr_corrupted_before
    set_and_check_hugetlb_pool 100
    prepare_system_default
}

cleanup_hugetlb() {
    save_nr_corrupted_inject
    all_unpoison
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
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 > ${TMPF}.pageflagcheck1
            ${PAGETYPES} -p ${pid} -a ${BASEVFN} | grep huge > /dev/null 2>&1
            if [ $? -ne 0 ] ; then
                echo "Target address is NOT hugepage." | tee -a $OFILE
                set_return_code "HUGEPAGE_ALLOC_FAILURE"
                kill -SIGKILL $pid
                return 0
            fi
            # cat /proc/${pid}/numa_maps | tee -a ${OFILE}
            printf "Inject MCE ($ERROR_TYPE) to %lx.\n" $injpfn | tee -a $OFILE
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
    if [ x"${before[0]}" != x"${after[0]}" ] && [ x"${before[1]}" != x"${after[1]}" ] ; then
        count_success "hugepage migrated (${before[0]} -> ${after[0]})"
    else
        count_failure "hugepage not migrated"
    fi
}

DEFAULT_MONARCH_TIMEOUT=1000000
SYSFS_MCHECK=/sys/devices/system/machinecheck
set_monarch_timeout() {
    local value=$1

    find $SYSFS_MCHECK/ -type f -name monarch_timeout | while read line ; do
        echo $value > $line
    done
}

prepare_hugetlb_race() {
    save_nr_corrupted_before
    set_and_check_hugetlb_pool 100
    prepare_system_default
    set_monarch_timeout $MONARCH_TIMEOUT
}

cleanup_hugetlb_race() {
    set_monarch_timeout $DEFAULT_MONARCH_TIMEOUT
    save_nr_corrupted_inject
    all_unpoison
    set_and_check_hugetlb_pool 0
    save_nr_corrupted_unpoison
    cleanup_system_default
}

# This test is not well defined because mce-inject tool could cause kernel
# panic which might be artifact of test infrastructure.
TARGET_PAGEFLAG="huge,compound_head,mmap=huge,compound_head"

control_multiple_inject_race() {
    local tgthpage="0x$($PAGETYPES -b $TARGET_PAGEFLAG -Nl | sed -n -e 2p | cut -f1)"
    local injtype=

    if [ ! "$tgthpage" ] ; then
        echo "no page with specified page flag"
        set_return_code FAILED_TO_GET_PFN
        return
    fi

    touch $TMPF.sync
    local i=
    for i in $(seq $NR_THREAD) ; do
        if [ "$INJECT_TYPE" == mce-srao ] || [ "$INJECT_TYPE" == hard-offline ] || [ "$INJECT_TYPE" == soft-offline ] ; then
            injtype=$INJECT_TYPE
        elif [ "$INJECT_TYPE" == hard-soft ] ; then
            if [ "$[$i % 2]" == "0" ] ; then
                injtype=hard-offline
            else
                injtype=soft-offline
            fi
        else
            echo "Invalid INJECT_TYPE"
            set_return_code INVALID_INJECT_TYPE
            return
        fi
        echo "$MCEINJECT -e $injtype -a $tgthpage" | tee -a $OFILE
        ( while [ -e $TMPF.sync ] ; do true ; done ; $MCEINJECT -e $injtype -a $tgthpage ) &
        echo $! | tee -a $OFILE
    done

    sleep 1
    rm $TMPF.sync
    sleep 1

    set_return_code EXIT
}

check_hugetlb_race() {
    check_system_default
    check_nr_hwcorrupted_consistent
}
