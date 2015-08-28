check_and_define_tp test_base_madv_simple_stress
check_and_define_tp memeater
check_and_define_tp thugetlb
check_and_define_tp test_soft_offline_unpoison_stress

prepare_stress_madvise() {
    prepare_system_default
}

cleanup_stress_madvise() {
    cleanup_system_default
}

control_stress_madvise() {
    local i=
    for i in $(seq 10) ; do
        $test_base_madv_simple_stress | tee -a $OFILE
        all_unpoison
    done
    set_return_code EXIT
}

check_stress_madvise() {
    check_system_default
}

prepare_stress_poison_unpoison_process() {
    pkill -SIGKILL -f $memeater
    prepare_system_default
}

cleanup_stress_poison_unpoison_process() {
    cleanup_system_default
    pkill -SIGKILL -f $memeater
}

POISON_ITERATION=100

random_poison() {
    local i=
    local j=
    local pos=
    local pid=$1
    local range=

    rm -f /tmp/pfnlist
    for i in $(cat /tmp/mapping) ; do
        for j in $(seq 0 255) ; do
            echo "$[$i/4096 + $j]" >> /tmp/pfnlist
        done
    done
    range=$(wc -l /tmp/pfnlist | cut -f1 -d' ')

    for i in $(seq $POISON_ITERATION) ; do
        pos=$(ruby -e "puts rand($range) + 1")
        $PAGETYPES -N -p $pid -a $(sed -ne ${pos}p /tmp/pfnlist) -X 2> /dev/null
    done
}

random_unpoison() {
    local i=
    local pid=$1
    for i in $(seq $POISON_ITERATION) ; do
        $PAGETYPES -N -p $pid -b hwpoison -x
    done
}

control_stress_poison_unpoison_process() {
    local pid=
    local pid_poison=
    local pid_unpoison=
    local i=

    $memeater -f /tmp/mapping &
    pid=$!
    sleep 1 # ensure that memeater reached internal pause()

    random_poison $pid &
    pid_poison=$!
    random_unpoison $pid &
    pid_unpoison=$!

    wait $pid_poison $pid_unpoison
    kill -SIGUSR1 $pid
    set_return_code EXIT
}

check_stress_poison_unpoison_process() {
    check_system_default
}

prepare_stress_poison_unpoison_hugetlb() {
    pkill -SIGKILL -f $thugetlb
    set_and_check_hugetlb_pool 200
    prepare_system_default
}

cleanup_stress_poison_unpoison_hugetlb() {
    # all_unpoison
    # set_and_check_hugetlb_pool 0
    cleanup_system_default
    # pkill -SIGKILL -f $thugetlb
}

STRESS_NR_HP=1

random_poison_hugetlb() {
    local i=
    local pos=
    local pid=$1

    for i in $(seq $POISON_ITERATION) ; do
        pos=$(ruby -e "puts rand($[256*$STRESS_NR_HP])")
        $PAGETYPES -N -p $pid -a $[0x700000000+$pos] -X 2> /dev/null
    done
}

random_unpoison_hugetlb() {
    local i=
    local pid=$1
    for i in $(seq $POISON_ITERATION) ; do
        $PAGETYPES -N -p $pid -b hwpoison,huge,compound_head=hwpoison,huge,compound_head -x
    done
}

control_stress_poison_unpoison_hugetlb() {
    local pid=
    local pid_poison=
    local pid_unpoison=
    local i=

    $thugetlb -a -n $STRESS_NR_HP &
    pid=$!
    sleep 0.1 # ensure that thugetlb reached internal pause()

    random_poison_hugetlb $pid &
    pid_poison=$!
    random_unpoison_hugetlb $pid &
    pid_unpoison=$!

    wait $pid_poison $pid_unpoison
    kill -SIGUSR1 $pid
    set_return_code EXIT
}

check_stress_poison_unpoison_hugetlb() {
    check_system_default
}

NUMNODE=$(numactl -H | grep available | cut -f2 -d' ')

reonline_memblocks() {
    local block=""
    local memblocks="$(find /sys/devices/system/memory/ -type d -maxdepth 1 | grep "memory/memory" | sed 's/.*memory//')"
    for mb in $memblocks ; do
        if [ "$(cat /sys/devices/system/memory/memory${mb}/state)" == "offline" ] ; then
            block="$block $mb"
        fi
    done
    echo "offlined memory blocks: $block"
    for mb in $block ; do
        echo "Re-online memory block $mb"
        echo online > /sys/devices/system/memory/memory${mb}/state
    done
}

prepare_base_memory_hotremove_pageblock_with_hwpoison() {
    prepare_system_default
}

cleanup_base_memory_hotremove_pageblock_with_hwpoison() {
	reonline_memblocks
    cleanup_system_default
}

control_base_memory_hotremove_pageblock_with_hwpoison() {
	bash $TRDIR/find_perferred_pageblock_for_hotremove.sh | tee $WDIR/preferred_pageblock
	local preferred_memblk=$(grep "^preferred memblk:" $WDIR/preferred_pageblock | awk '{print $3}')
	local preferred_memblk_pfn=$(grep "^preferred memblk start pfn:" $WDIR/preferred_pageblock | awk '{print $5}')

	$MCEINJECT -e hard-offline -a $preferred_memblk_pfn
	$PAGETYPES -b hwpoison

	echo offline > /sys/devices/system/memory/memory${preferred_memblk}/state
	if [ $? -eq 0 ] ; then
		echo "hot remove memblk $preferred_memblk succeeded."
		set_return_code HOTREMOVE_SUCCESS
	else
		echo "hot remove memblk $preferred_memblk failed."
		set_return_code HOTREMOVE_FAILURE
	fi

	set_return_code EXIT
}

check_base_memory_hotremove_pageblock_with_hwpoison() {
    check_system_default
}

prepare_base_soft_offline_unpoison_stress() {
    pkill -SIGKILL -f $test_soft_offline_unpoison_stress
	all_unpoison
	prepare_system_default
}

cleanup_base_soft_offline_unpoison_stress() {
    pkill -SIGKILL -f $test_soft_offline_unpoison_stress
	all_unpoison
	cleanup_system_default
}

control_base_soft_offline_unpoison_stress() {
	$test_soft_offline_unpoison_stress &
	local pid=$!
	local count=1000

	while true ; do
		echo "### $count ### $PAGETYPES -b hwpoison -x -N"
		$PAGETYPES -b hwpoison -x -N
		count=$[count-1]
		[ "$count" -eq 0 ] && break
	done

	kill -9 $pid
	set_return_code EXIT
}

check_base_soft_offline_unpoison_stress() {
	check_system_default
}
