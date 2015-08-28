check_and_define_tp memeater_hugetlb

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
