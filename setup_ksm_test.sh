#!/bin/bash

KSMDIR="/sys/kernel/mm/ksm"
[ ! -d "$KSMDIR" ] && echo "Kernel not support ksm." >&2 && exit 1
TKSM=`dirname $BASH_SOURCE`/tksm
[ ! -x "$TKSM" ] && echo "tksm not found." >&2 && exit 1

ksm_on() {
    echo 1    > $KSMDIR/run
    echo 1000 > $KSMDIR/pages_to_scan
    echo 0    > $KSMDIR/sleep_millisecs
}
ksm_off() {
    echo 2    > $KSMDIR/run
    echo 100  > $KSMDIR/pages_to_scan
    echo 20   > $KSMDIR/sleep_millisecs
}
get_pages_run()      { cat $KSMDIR/run;            }
get_pages_shared()   { cat $KSMDIR/pages_shared;   }
get_pages_sharing()  { cat $KSMDIR/pages_sharing;  }
get_pages_unshared() { cat $KSMDIR/pages_unshared; }
get_pages_volatile() { cat $KSMDIR/pages_volatile; }
get_full_scans()     { cat $KSMDIR/full_scans;     }

show_ksm_params() {
    echo "KSM params: run:`get_pages_run`, shared:`get_pages_shared`, sharing:`get_pages_sharing`, unshared:`get_pages_unshared`, volatile:`get_pages_volatile`, scans:`get_full_scans`"
}

prepare_test() {
    ksm_on
    show_ksm_params | tee -a ${OFILE}
    save_nr_corrupted_before
    get_kernel_message_before
}

cleanup_test() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    ksm_off
    show_ksm_params | tee -a ${OFILE}
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
}

control_ksm() {
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
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "$EXPECTED_RETURN_CODE"
    check_nr_hwcorrupted
}

check_ksm_hard() {
    check_ksm
    FALSENEGATIVE=true
    check_console_output -v "give up"
    FALSENEGATIVE=false
}

check_ksm_soft() {
    check_ksm
    FALSENEGATIVE=true
    check_console_output -v "migration failed"
    # check_ksm_migrated
    FALSENEGATIVE=false
}

# check_ksm_srao() {
#     local result="$1"
#     check_ksm_pages
#     FALSENEGATIVE=true
#     check_result_ksm PASS "$result"
#     check_console_output "LRU page"
#     FALSENEGATIVE=false
#     check_nr_hwcorrupted
# }

# check_ksm_srao_killed() {
#     local result="$1"
#     check_ksm_pages
#     check_result_ksm TIMEOUT "$result"
#     FALSENEGATIVE=true
#     check_console_output "LRU page"
#     FALSENEGATIVE=false
#     check_nr_hwcorrupted
# }
