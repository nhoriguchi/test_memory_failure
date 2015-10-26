#!/bin/bash

check_and_define_tp tthp
check_and_define_tp tthp_on_pcplist
check_and_define_tp tthp_small
check_and_define_tp memeater_thp

ulimit -s unlimited

prepare_thp() {
    if [ "$ERROR_TYPE" = mce-srao ] ; then
        check_mce_capability || return 1 # MCE SRAO not supported
    fi

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
    pkill -9 -f $tthp
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


background_thp_allocator() {
    while true ; do
        $tthp_on_pcplist
    done
}

STAPPID=
# Not intended to be used on RHEL6, only for RHEL7/upstream
prepare_thp_on_pcplist() {
    if [ ! -e filter_memory_error_event.ko ] ; then
        stap -p4 -g -m filter_memory_error_event.ko filter_memory_error_event.stp
        if [ $? -ne 0 ] ; then
            echo "Failed to build stap script" >&2
            return 1
        fi
    fi
    STAPPID="$(staprun -o $TMPF.stapout -D filter_memory_error_event.ko)"
    echo "STAPPID: $STAPPID"
    [ ! "$STAPPID" ] && return 1
    echo 1 > /proc/sys/vm/drop_caches
    set_thp_params_for_testing
    set_thp_never
    set_thp_always
    pkill -9 -f $tthp_on_pcplist 2> /dev/null
    pkill -9 -f background_thp_allocator 2>&1 > /dev/null
    show_stat_thp | tee -a $OFILE
    save_nr_corrupted_before
    prepare_system_default
}

cleanup_thp_on_pcplist() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    default_tuning_parameters
    # show_current_tuning_parameters
    pkill -9 -f $tthp_on_pcplist 2> /dev/null
    pkill -9 -f background_thp_allocator 2>&1 > /dev/null
    show_stat_thp | tee -a $OFILE
    cleanup_system_default
    kill -9 $STAPPID
    rmmod filter_memory_error_event
}

control_thp_on_pcplist() {
    background_thp_allocator &
    local backpid=$!
    local TARGET_PAGEFLAG="thp,compound_head=thp,compound_head"
    for i in $(seq 10) ; do
        echo "[$i] $PAGETYPES -p $(pgrep -f tthp_on_pcplist) -b $TARGET_PAGEFLAG -rNl"
        $PAGETYPES -p $(pgrep -f tthp_on_pcplist) -b $TARGET_PAGEFLAG -rNl | \
            grep -v offset | cut -f2 | \
            while read line ; do
                local thp=0x$line
                $MCEINJECT -e $ERROR_TYPE -a $[$thp + 1]
            done
    done

    kill -9 $backpid
    set_return_code EXIT
}

check_thp_on_pcplist() {
    check_system_default
    check_kernel_message -v "huge page recovery"
    check_nr_hwcorrupted
}

prepare_race_between_error_handling_and_process_exit() {
    echo 1 > /proc/sys/vm/drop_caches
    pkill -9 -f $tthp_small 2> /dev/null
    set_thp_params_for_testing
    set_thp_never
    set_thp_always
    save_nr_corrupted_before
    all_unpoison
    prepare_system_default
}

cleanup_race_between_error_handling_and_process_exit() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    default_tuning_parameters
    pkill -9 -f $tthp_small 2> /dev/null
    cleanup_system_default
}

RACE_ITERATIONS=10
control_race_between_error_handling_and_process_exit() {
    local pid=

    for i in $(seq $RACE_ITERATIONS) ; do
        $tthp_small &
        pid=$!
        echo "[$i] $PAGETYPES -p $(pgrep -f tthp_small) -b $TARGET_PAGEFLAG -rNl"
        $PAGETYPES -p $(pgrep -f tthp_small) -b $TARGET_PAGEFLAG -rNl | \
            grep -v offset | cut -f2 | \
            while read line ; do
                local thp=0x$line
                printf "$MCEINJECT -e $ERROR_TYPE -a 0x%lx\n" $[$thp + 1]
                $MCEINJECT -e $ERROR_TYPE -a $[$thp + 1]
                # $PAGETYPES -a $[$thp + 1] -X -N
            done
        kill -9 $pid
    done
    set_return_code EXIT
}

check_race_between_error_handling_and_process_exit() {
    check_system_default
    check_nr_hwcorrupted
}

control_race_between_munmap_and_thp_split() {
    local pid=

    for i in $(seq 100) ; do
        $tthp_small &
        pid=$!
        sleep 0.3
        migratepages $pid 0 1
        migratepages $pid 1 0
        kill -9 $pid
    done
    set_return_code EXIT
}

prepare_multiple_injection_thp() {
    echo 1 > /proc/sys/vm/drop_caches
    set_thp_params_for_testing
    set_thp_never
    set_thp_always
    pkill -9 -f $tthp_small
    pkill -9 -f $memeater_thp
	$tthp_small &
	$memeater_thp -n 200 &
	prepare_multiple_injection_race
}

cleanup_multiple_injection_thp() {
    pkill -9 -f $tthp_small
    pkill -9 -f $memeater_thp
	cleanup_multiple_injection_race
}

run_kernel_build_background() {
	pushd $KERNEL_SRC
	make mrproper > /dev/null
	make defconfig > /dev/null
	make -j $(nproc) > /dev/null
	popd
}

__run_kernel_build_background_pid=

prepare_multiple_injection_thp_background() {
    echo 1 > /proc/sys/vm/drop_caches
    set_thp_params_for_testing
    set_thp_never
    set_thp_always
    pkill -9 -f run_kernel_build_background
	run_kernel_build_background &
	__run_kernel_build_background_pid=$!
	prepare_multiple_injection_race
}

cleanup_multiple_injection_thp_background() {
    kill -9 $__run_kernel_build_background_pid
	pkill -9 make
	cleanup_multiple_injection_race
}
