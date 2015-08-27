#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

[ ! "$VM" ] && echo "You must give VM name in recipe file" && exit 1
[ ! "$VMIP" ] && echo "You must give VM IP address in recipe file" && exit 1
[ ! "$PASSWD" ] && echo "You must give VM root password in recipe file" && exit 1

MEMEATER=$(dirname $(readlink -f $BASH_SOURCE))/memeater
GPA2HPA=$(dirname $(readlink -f $BASH_SOURCE))/gpa2hpa.rb
[ ! -x "$MEMEATER" ] && echo "memeater not found." >&2 && exit 1
GUESTMEMEATER=/usr/local/bin/memeater
GUESTMEMEATERPID=0
TARGETGVA=""
TARGETGPA=""
TARGETHPA=""
GUESTSERIALMONITORPID=""

# check VM RAM size is not greater than 2GB
memsize=$(virsh dominfo $VM | grep "Used memory:" | tr -s ' ' | cut -f3 -d' ')
if [ "$memsize" -gt 2097152 ] ; then
    echo "Too much VM RAM size. (> 2GB)"
    exit 1
fi

vm_restart_if_unconnectable

# send helper tools to guest
send_helper_to_guest() {
    scp $MEMEATER $VMIP:$GUESTMEMEATER > /dev/null
    scp $PAGETYPES $VMIP:$GUESTPAGETYPES > /dev/null
}

# define helper functions below

stop_guest_memeater() {
    ssh $VMIP "pkill -f $GUESTMEMEATER > /dev/null 2>&1 </dev/null"
}

run_guest_memeater() {
    stop_guest_memeater
    ssh $VMIP "$GUESTMEMEATER -f /tmp/mapping > /dev/null 2>&1 </dev/null &"
    GUESTMEMEATERPID=`ssh $VMIP "pgrep -f $GUESTMEMEATER"`
    [ ! "$GUESTMEMEATERPID" ] && echo "$usemem not running. Test aborts." >&2 && return 1
    return 0
}

get_gpa_guest_memeater() {
    local flagtype=$1
    scp $VMIP:/tmp/mapping /tmp/mapping > /dev/null 2>&1
    local start=$(printf "0x%lx" $[$(sort /tmp/mapping | sort | head -n1)/4096])
    local end=$(printf "0x%lx" $[$(sort /tmp/mapping | sort | tail -n1)/4096 + 256])
    local cmd="$GUESTPAGETYPES -p ${GUESTMEMEATERPID} -b ${flagtype} -rNL"
    local line=
    while read line ; do
        cmd="$cmd -a $[line/4096]+256"
    done < /tmp/mapping
    echo $cmd
    ssh $VMIP $cmd | grep -v offset | tr '\t' ' ' | tr -s ' ' > ${TMPF}.guest-page-types
    local lines=`wc -l ${TMPF}.guest-page-types | cut -f1 -d' '`
    [ "$lines" -eq 0 ] && echo "Page on pid:$GUESTMEMEATERPID not found." >&2 && return 1
    [ "$lines" -gt 2 ] && lines=`ruby -e "p rand($lines) + 1"`
    TARGETGVA=0x`cat ${TMPF}.guest-page-types | sed -n ${lines}p | cut -f1 -d ' '`
    TARGETGPA=0x`cat ${TMPF}.guest-page-types | sed -n ${lines}p | cut -f2 -d ' '`
    return 0
}

get_hpa() {
    local flagtype="$1"
    get_gpa_guest_memeater "$flagtype" || return 1
    [ ! "$TARGETGPA" ] && echo "Failed to get GPA. Test skipped." && return 1
    TARGETHPA=`ruby ${GPA2HPA} $VM $TARGETGPA`
    echo "GVA:$TARGETGVA - GPA:$TARGETGPA - HPA:[$TARGETHPA]" | tee -a ${OFILE}
    [ ! "$TARGETHPA" ] && echo "Failed to get HPA. Test skipped." && return 1
    if [ ! "$TARGETHPA" ] || [ "$TARGETHPA" == "0x" ] || [ "$TARGETHPA" == "0x0" ] ; then
        echo "Failed to get HPA. Test skipped." && return 1
    fi
    echo -n "HPA status: " ; $PAGETYPES -a $TARGETHPA -Nlr | grep -v offset | tee -a ${OFILE}
    echo -n "GPA status: " ; ssh $VMIP $GUESTPAGETYPES -a $TARGETGPA -Nlr | grep -v offset | tee -a ${OFILE}
}

guest_process_running() {
    ssh -o ConnectTimeout=5 $VMIP "pgrep -f $GUESTMEMEATER" > /dev/null 2>&1 </dev/null
}

prepare_test() {
    TARGETGVA=""
    TARGETGPA=""
    TARGETHPA=""

    if [ "$ERROR_TYPE" = mce-srao ] ; then
        check_mce_capability || return 1 # MCE SRAO not supported
    fi

    vm_restart_if_unconnectable
    vmdirty && vm_restart_wait || sleep 1
    rm -f /tmp/mapping
    stop_guest_memeater
    send_helper_to_guest

    save_nr_corrupted_before
    get_kernel_message_before
    get_guest_kernel_message_before
    run_vm_serial_monitor
}

cleanup_test() {
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    rm -f /tmp/mapping
    stop_guest_memeater
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
    vm_ssh_connectable && get_guest_kernel_message_after
    get_guest_kernel_message | tee -a ${OFILE}
    stop_vm_serial_monitor
}

check_guest_state() {
    if vm_ssh_connectable ; then
        echo "Guest OS still alive." | tee -a ${OFILE}
        set_return_code "GUEST_ALIVE"
        if guest_process_running ; then
            echo "And $GUESTMEMEATER still running." | tee -a ${OFILE}
            set_return_code "GUEST_PROC_ALIVE"
            echo "let $GUESTMEMEATER access to error page" | tee -a ${OFILE}

            access_error
            if vm_ssh_connectable ; then
                if guest_process_running ; then
                    echo "$GUESTMEMEATER was still alive" | tee -a ${OFILE}
                    set_return_code "GUEST_PROC_ALIVE_LATER_ACCESS"
                else
                    echo "$GUESTMEMEATER was killed" | tee -a ${OFILE}
                    set_return_code "GUEST_PROC_KILLED_LATER_ACCESS"
                fi
            else
                echo "Guest OS panicked." | tee -a ${OFILE}
                set_return_code "GUEST_PANICKED_LATER_ACCESS"
            fi
            return
        else
            echo "But $GUESTMEMEATER was killed." | tee -a ${OFILE}
            set_return_code "GUEST_PROC_KILLED"
            return
        fi
    else
        echo "Guest OS panicked." | tee -a ${OFILE}
        set_return_code "GUEST_PANICKED"
    fi
    # Force shutdown if VM is not connected (then maybe it stalls.)
    echo "Wait all kernel messages are output on serial console" | tee -a ${OFILE}
    sleep 5
    virsh destroy $VM
    set_vmdirty
}

access_error() {
    ssh $VMIP "kill -SIGUSR1 ${GUESTMEMEATERPID}"
}

check_page_migrated() {
    local gpa="$1"
    local oldhpa="$2"

    count_testcount
    currenthpa=$(ruby ${GPA2HPA} $VM $gpa)
    # echo "[$TARGETGPA] [$TARGETHPA] [$currenthpa]"
    if [ ! "$currenthpa" ] ; then
        count_failure "Fail to get HPA after migration."
    elif [ "$oldhpa" = "$currenthpa" ] ; then
        count_failure "page migration failed or not triggered."
    else
        count_success "page $oldhpa was migrated to $currenthpa."
    fi
}

control_kvm() {
    run_guest_memeater || return 1
    sleep 0.2
    get_hpa "$TARGET_PAGETYPES" || return 1
    set_return_code "GOT_HPA"
    ${MCEINJECT} -e "$ERROR_TYPE" -a "${TARGETHPA}"
    check_guest_state
}

control_kvm_panic() {
    run_guest_memeater || return 1
    get_hpa "$TARGET_PAGETYPES" || return 1
    set_return_code "GOT_HPA"
    echo "echo 0 > /proc/sys/vm/memory_failure_recovery" | tee -a ${OFILE}
    ssh $VMIP "echo 0 > /proc/sys/vm/memory_failure_recovery"
    ${MCEINJECT} -e "$ERROR_TYPE" -a "${TARGETHPA}"
    if vm_connectable ; then
        ssh $VMIP "echo 1 > /proc/sys/vm/memory_failure_recovery"
    fi
    check_guest_state
}

check_kvm() {
    check_kernel_message "${TARGETHPA}"
    check_kernel_message_nobug
    check_guest_kernel_message "${TARGETGPA}"
    check_return_code "$EXPECTED_RETURN_CODE"
    check_nr_hwcorrupted
}

check_kvm_panic() {
    check_kernel_message "${TARGETHPA}"
    check_guest_kernel_message "Kernel panic"
    check_return_code "$EXPECTED_RETURN_CODE"
    check_nr_hwcorrupted
}

check_kvm_soft_offline() {
    check_kernel_message "${TARGETHPA}"
    check_kernel_message_nobug
    check_guest_kernel_message -v "${TARGETGPA}"
    check_return_code "$EXPECTED_RETURN_CODE"
    check_page_migrated "$TARGETGPA" "$TARGETHPA"
    check_nr_hwcorrupted
}

control_kvm_inject_mce_on_qemu_page() {
    local pid=$(cat /varun/libvirt/qemu/$VM.pid)
    $PAGETYPES -p $pid -l
}

check_kvm_inject_mce_on_qemu_page() {
    check_kernel_message "${TARGETHPA}"
    check_kernel_message_nobug
}
