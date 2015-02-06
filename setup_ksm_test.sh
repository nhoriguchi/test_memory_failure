#!/bin/bash

check_and_define_tp tksm

prepare_ksm_test() {
    ksm_on
    show_ksm_params | tee -a ${OFILE}
    save_nr_corrupted_before
    get_kernel_message_before
}

cleanup_ksm_test() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    ksm_off
    show_ksm_params | tee -a ${OFILE}
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
}

control_ksm_test() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "waiting for injection from outside")
            local checkksm=$(${PAGETYPES} -p ${pid} -b ksm -rlN -a ${BASEVFN} | wc -l)
            ${PAGETYPES} -p ${pid} -b ksm -rlN -a ${BASEVFN}
            if [ "$checkksm" -le 1 ] ; then
                set_return_code "KSM_ALLOC_FAILURE"
                return 0
            fi
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 > ${TMPF}.pageflagcheck1
            sleep 1
            ${MCEINJECT} -p ${pid} -e ${ERROR_TYPE} -a ${BASEVFN} # 2>&1
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
        "tksm exit.")
            ${PAGETYPES} -p ${pid} -rlN -a ${BASEVFN}+1310720 > ${TMPF}.pageflagcheck2
            kill -SIGUSR1 ${pid}
            set_return_code "EXIT"
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_ksm() {
    check_kernel_message_nobug
    check_return_code "$EXPECTED_RETURN_CODE"
    check_nr_hwcorrupted
}

check_ksm_hard_offline() {
    check_ksm
    FALSENEGATIVE=true
    check_console_output -v "give up"
    FALSENEGATIVE=false
}

check_ksm_soft_offline() {
    check_ksm
    FALSENEGATIVE=true
    check_console_output -v "migration failed"
    # check_ksm_migrated
    FALSENEGATIVE=false
}
