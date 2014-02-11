#!/bin/bash

DISTRO=""
THPDIR=""
KHPDDIR=""

# if grep "Red Hat Enterprise Linux.*release 6" /etc/system-release > /dev/null ; then
if uname -r  | grep "\.el6" > /dev/null ; then
    DISTRO="RHEL6"
    THPDIR="/sys/kernel/mm/redhat_transparent_hugepage"
    KHPDDIR="/sys/kernel/mm/redhat_transparent_hugepage/khugepaged"
elif uname -r  | grep "\.el7" > /dev/null ; then
    DISTRO="RHEL7"
    THPDIR="/sys/kernel/mm/transparent_hugepage"
    KHPDDIR="/sys/kernel/mm/transparent_hugepage/khugepaged"
elif uname -r  | grep "\.fc[12][0-9]" > /dev/null ; then
    DISTRO="Fedora"
    THPDIR="/sys/kernel/mm/transparent_hugepage"
    KHPDDIR="/sys/kernel/mm/transparent_hugepage/khugepaged"
else
    DISTRO="upstream"
    THPDIR="/sys/kernel/mm/transparent_hugepage"
    KHPDDIR="/sys/kernel/mm/transparent_hugepage/khugepaged"
fi

RHELOPT="" ; [ "$DISTRO" = "RHEL6" ] && RHELOPT="-R"

[ ! -d "$THPDIR" ] && echo "Kernel not support thp." >&2 && exit 1

TTHP=$(dirname $(readlink -f $BASH_SOURCE))/tthp
[ ! -x "$TTHP" ] && echo "tthp not found." >&2 && exit 1

ulimit -s unlimited

## routines

get_thp()         { cat $THPDIR/enabled; }
set_thp_always()  { echo "always" > $THPDIR/enabled; }
set_thp_madvise() {
    if [ "$DISTRO" == "Fedora" ] || [ "$DISTRO" == "upstream" ] ; then
        echo "madvise" > $THPDIR/enabled;
    fi
}
set_thp_never()   { echo "never" > $THPDIR/enabled; }
get_thp_defrag()  { cat $THPDIR/defrag; }
set_thp_defrag_always()  { echo "always" > $THPDIR/defrag; }
set_thp_defrag_madvise() { echo "madvise" > $THPDIR/defrag; }
set_thp_defrag_never()   { echo "never" > $THPDIR/defrag; }
khpd_on()  { echo 1 > $KHPDDIR/defrag; }
khpd_off() { echo 0 > $KHPDDIR/defrag; }
compact_memory() { echo 1 > /proc/sys/vm/compact_memory; }

get_khpd_alloc_sleep_millisecs() { cat $KHPDDIR/alloc_sleep_millisecs; }
get_khpd_defrag()                { cat $KHPDDIR/defrag; }
get_khpd_max_ptes_none()         { cat $KHPDDIR/max_ptes_none; }
get_khpd_pages_to_scan()         { cat $KHPDDIR/pages_to_scan; }
get_khpd_scan_sleep_millisecs()  { cat $KHPDDIR/scan_sleep_millisecs; }
get_khpd_full_scans()            { cat $KHPDDIR/full_scans; }
get_khpd_pages_collapsed()       { cat $KHPDDIR/pages_collapsed; }
set_khpd_alloc_sleep_millisecs() { echo $1 > $KHPDDIR/alloc_sleep_millisecs; }
set_khpd_defrag()                {
    local val=$1
    if [ "$DISTRO" = "RHEL6" ] ; then
        [ "$val" -eq 0 ] && val="no" || val="yes"
    fi
    echo $val > $KHPDDIR/defrag;
}
set_khpd_max_ptes_none()         { echo $1 > $KHPDDIR/max_ptes_none; }
set_khpd_pages_to_scan()         { echo $1 > $KHPDDIR/pages_to_scan; }
set_khpd_scan_sleep_millisecs()  { echo $1 > $KHPDDIR/scan_sleep_millisecs; }
default_khpd_alloc_sleep_millisecs=60000
default_khpd_defrag=1
default_khpd_max_ptes_none=511
default_khpd_pages_to_scan=4096
default_khpd_scan_sleep_millisecs=10000
default_tuning_parameters() {
    set_khpd_alloc_sleep_millisecs $default_khpd_alloc_sleep_millisecs
    set_khpd_defrag                $default_khpd_defrag
    set_khpd_max_ptes_none         $default_khpd_max_ptes_none
    set_khpd_pages_to_scan         $default_khpd_pages_to_scan
    set_khpd_scan_sleep_millisecs  $default_khpd_scan_sleep_millisecs
}
set_thp_params_for_testing() {
    set_khpd_alloc_sleep_millisecs 100
    set_khpd_scan_sleep_millisecs  100
    set_khpd_pages_to_scan         $[4096*10]
}
show_current_tuning_parameters() {
    echo "thp                     : `get_thp`"
    echo "deflag                  : `get_thp_defrag`"
    echo "alloc_sleep_millices    : `get_khpd_alloc_sleep_millisecs`"
    echo "defrag (in khpd)        : `get_khpd_defrag               `"
    echo "max_ptes_none           : `get_khpd_max_ptes_none        `"
    echo "pages_to_scan           : `get_khpd_pages_to_scan        `"
    echo "scan_sleep_millisecs    : `get_khpd_scan_sleep_millisecs `"
}

thp_fault_alloc=0
thp_fault_fallback=0
thp_collapse_alloc=0
thp_collapse_alloc_failed=0
thp_split=0
get_vmstat_thp() {
    thp_fault_alloc=`grep thp_fault_alloc /proc/vmstat | cut -f2 -d' '`
    thp_fault_fallback=`grep thp_fault_fallback /proc/vmstat | cut -f2 -d' '`
    thp_collapse_alloc=`grep "thp_collapse_alloc " /proc/vmstat | cut -f2 -d' '`
    thp_collapse_alloc_failed=`grep thp_collapse_alloc_failed /proc/vmstat | cut -f2 -d' '`
    thp_split=`grep thp_split /proc/vmstat | cut -f2 -d' '`
}
show_stat_thp() {
    get_vmstat_thp
    echo   "        clpsd, fscan, fltal, fltfb, clpal, clpaf, split"
    printf "Result  %5s, %5s, %5s, %5s, %5s, %5s, %5s\n" `get_khpd_pages_collapsed` `get_khpd_full_scans` $thp_fault_alloc $thp_fault_fallback $thp_collapse_alloc $thp_collapse_alloc_failed $thp_split
}

prepare_test() {
    echo 1 > /proc/sys/vm/drop_caches
    # echo 1 > /proc/sys/vm/compact_memory
    set_thp_params_for_testing
    # show_current_tuning_parameters

    # echo $TTHP
    # ps awf

    set_thp_never
    set_thp_always
    # For RHEL6, we have no madvise(MADV_HUGEPAGE) interface and thp is already on,
    # so this switch does nothing.
    # -> RHEL6.5 starts to support madvise(MADV_HUGEPAGE) so no more need this.
    # set_thp_madvise

    pkill -9 -f ${TTHP}

    show_stat_thp | tee -a ${OFILE}
    save_nr_corrupted_before
    get_kernel_message_before
}

cleanup_test() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    default_tuning_parameters
    # show_current_tuning_parameters
    show_stat_thp | tee -a ${OFILE}
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
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

check_thp() {
    check_kernel_message -v diff "failed"
    check_kernel_message_nobug diff
    check_return_code "$EXPECTED_RETURN_CODE"
    check_nr_hwcorrupted
}

check_thp_soft_offline() {
    check_thp
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
            count_success "tail page migrated"
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
