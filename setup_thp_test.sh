#!/bin/bash

check_and_define_tp tthp

ulimit -s unlimited

prepare_thp() {
    echo 1 > /proc/sys/vm/drop_caches
    # echo 1 > /proc/sys/vm/compact_memory
    set_thp_params_for_testing
    # show_current_tuning_parameters

    # echo $tthp
    # ps awf

    set_thp_never
    set_thp_always
    # For RHEL6, we have no madvise(MADV_HUGEPAGE) interface and thp is already on,
    # so this switch does nothing.
    # -> RHEL6.5 starts to support madvise(MADV_HUGEPAGE) so no more need this.
    # set_thp_madvise

    pkill -9 -f $tthp

    show_stat_thp | tee -a ${OFILE}
    save_nr_corrupted_before
    prepare_system_default
}

cleanup_thp() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    default_tuning_parameters
    # show_current_tuning_parameters
    show_stat_thp | tee -a ${OFILE}
    cleanup_system_default
}

control_thp() {
    local pid="$1"
    local line="$2"
    local injpfn="$[BASEVFN + ERROR_OFFSET]"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "waiting for page fault")
            ${PAGETYPES} -p ${pid} -Nl -a ${BASEVFN}+0x200
            kill -SIGUSR1 ${pid}
            ;;
        "waiting for signal")
            ${PAGETYPES} -p ${pid} -a ${BASEVFN} | grep thp > /dev/null 2>&1
            if [ $? -ne 0 ] ; then
                echo "Target address is NOT thp." | tee -a /dev/kmsg
            fi
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 > ${TMPF}.pageflagcheck1
            kill -SIGUSR1 ${pid}
            ;;
        "waiting for injection from outside")
            echo ${MCEINJECT} -p ${pid} -e ${ERROR_TYPE} -a ${injpfn} # 2>&1
            ${MCEINJECT} -p ${pid} -e ${ERROR_TYPE} -a ${injpfn} # 2>&1
            kill -SIGUSR1 ${pid}
            ;;
        "waiting for memory compaction")
            echo 1 > /proc/sys/vm/drop_caches
            kill -SIGUSR1 ${pid}
            return 0
            ;;
        "splitting thp")
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
        "tthp exit.")
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 > ${TMPF}.pageflagcheck2
            kill -SIGUSR1 ${pid}
            set_return_code "EXIT"
            return 0
            ;;
        "OK, target memory is backed by THP.")
            set_return_code "THP_ALLOC_SUCCEED"
            ;;
        "NG, target memory is NOT backed by THP.")
            set_return_code "THP_ALLOC_FAIL"
            kill -9 ${pid}
            ;;
        *)
            ;;
    esac
    return 1
}

check_thp_hard_offline() {
    check_system_default
    check_nr_hwcorrupted
}

check_thp_soft_offline() {
    if [ "$ERROR_OFFSET" == 0 ] ; then
        check_page_migrated head
    else
        check_page_migrated tail
    fi
}

check_page_migrated() {
    local headtail=$1
    local before=($(sed -ne '2,$p' ${TMPF}.pageflagcheck1 | cut -f2 | tr '\n' ' '))
    local after=($(sed -ne '2,$p' ${TMPF}.pageflagcheck2 | cut -f2 | tr '\n' ' '))
    # echo "${before[0]}, ${before[1]}, ${after[0]}, ${after[1]}"

    if [ "$headtail" = head ] ; then
        count_testcount "raw page migration?"
        if [ "${before[0]}" = "${after[0]}" ] ; then
            count_failure "head page not migrated"
        else
            count_success "head page migrated"
        fi

        FALSENEGATIVE=true
        count_testcount "thp migration?"
        if [ "${before[1]}" = "${after[1]}" ] ; then
            count_failure "only raw page migrated"
        else
            count_success "thp migrated"
        fi
        FALSENEGATIVE=false
    else
        count_testcount "raw page migration?"
        if [ "${before[1]}" = "${after[1]}" ] ; then
            count_failure "tail page not migrated"
        else
            count_success "tail page migrated ${before[1]} => ${after[1]}"
            ${PAGETYPES} -rl -a 0x${before[1]}
        fi

        FALSENEGATIVE=true
        count_testcount "thp migration?"
        if [ "${before[0]}" = "${after[0]}" ] ; then
            count_failure "only raw page migrated"
        else
            count_success "thp migrated"
        fi
        FALSENEGATIVE=false
    fi
}
