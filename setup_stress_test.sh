check_and_define_tp memeater_hugetlb
check_and_define_tp test_base_madv_simple_stress
check_and_define_tp memeater

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

prepare_stress_poison_unpoison_pfn () {
    set_and_check_hugetlb_pool 100
	$memeater_hugetlb -n 30 &
	prepare_multiple_injection_race
}

cleanup_stress_poison_unpoison_pfn () {
	pkill -f $memeater_hugetlb
	cleanup_multiple_injection_race
    set_and_check_hugetlb_pool 0
}

STRESS_TEST_TIME=100
control_stress_poison_unpoison_pfn () {
	local target=0x100
	local injtype=$INJECT_TYPE
	local maxpfn=0x$($PAGETYPES -NL | tail -n1 | cut -f1)

	(
		while true ; do
			echo "$MCEINJECT -e $injtype -a $target"
			$MCEINJECT -e $injtype -a $target
			target=$[(target + $RANDOM) % $maxpfn]
		done
	) &
	local poison_pid=$!

	(
		while true ; do
			all_unpoison
			sleep 0.1
		done
	) &
	local unpoison_pid=$!

	sleep $STRESS_TEST_TIME
	set_return_code EXIT
	kill -9 $poison_pid $unpoison_pid
}

check_stress_poison_unpoison_pfn () {
	check_system_default
	# not check about HWCorrupted value, because there are "ununpoisonable"
	# pages.
}

prepare_stress_soft_offline_unpoison() {
    pkill -SIGKILL -f $test_soft_offline_unpoison_stress
	all_unpoison
	prepare_system_default
}

cleanup_stress_soft_offline_unpoison() {
    pkill -SIGKILL -f $test_soft_offline_unpoison_stress
	all_unpoison
	cleanup_system_default
}

control_stress_soft_offline_unpoison() {
	$test_soft_offline_unpoison_stress &
	local pid=$!
	local count=1000

	while true ; do
		$PAGETYPES -b hwpoison -x -N
		count=$[count-1]
		[ "$count" -eq 0 ] && break
	done

	kill -9 $pid
	set_return_code EXIT
}

check_stress_soft_offline_unpoison() {
	check_system_default
}

prepare_stress_soft_offline_unpoison_hugetlb() {
    pkill -SIGKILL -f $test_soft_offline_unpoison_stress
	all_unpoison
    set_and_check_hugetlb_pool 200
	prepare_system_default
}

cleanup_stress_soft_offline_unpoison_hugetlb() {
    pkill -SIGKILL -f $test_soft_offline_unpoison_stress
    set_and_check_hugetlb_pool 0
	all_unpoison
	cleanup_system_default
}

control_stress_soft_offline_unpoison_hugetlb() {
	$test_soft_offline_unpoison_stress hugetlb &
	local pid=$!
	local count=1000

	while true ; do
		$PAGETYPES -b hwpoison -x -N
		count=$[count-1]
		[ "$count" -eq 0 ] && break
	done

	kill -9 $pid
	set_return_code EXIT
}

check_stress_soft_offline_unpoison_hugetlb() {
	check_system_default
}
