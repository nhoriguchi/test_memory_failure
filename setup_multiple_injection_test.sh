# This test is not well defined because mce-inject tool could cause kernel
# panic which might be artifact of test infrastructure.
TARGET_PAGEFLAG="huge,compound_head,mmap=huge,compound_head"

DEFAULT_MONARCH_TIMEOUT=1000000
SYSFS_MCHECK=/sys/devices/system/machinecheck
set_monarch_timeout() {
    local value=$1

	[ ! "$value" ] && return

    find $SYSFS_MCHECK/ -type f -name monarch_timeout | while read line ; do
        echo $value > $line
    done
}

prepare_multiple_injection_race() {
    save_nr_corrupted_before
    prepare_system_default
    set_monarch_timeout $MONARCH_TIMEOUT
}

cleanup_multiple_injection_race() {
    set_monarch_timeout $DEFAULT_MONARCH_TIMEOUT
    save_nr_corrupted_inject
    all_unpoison
    save_nr_corrupted_unpoison
    cleanup_system_default
}

check_multiple_injection_race() {
	check_system_default
    check_nr_hwcorrupted_consistent
}

__control_multiple_injection_race() {
	$PAGETYPES -b $TARGET_PAGEFLAG -rNl | grep -v X | grep -v offset > $TMPF.page-types
	local nr_lines=$(cat $TMPF.page-types | wc -l)
	if [ "$nr_lines" -eq 0 ] ; then
        echo "no page with page flag $TARGET_PAGEFLAG found"
        set_return_code FAILED_TO_GET_PFN
        return 1
	fi
	# cat $TMPF.page-types
	echo "nr_lines: $nr_lines"
	local no_line=$[($RANDOM % $nr_lines) + 1]
    local tgthpage="0x$(sed -ne ${no_line}p $TMPF.page-types | cut -f1)"
    # local tgthpage="0x$($PAGETYPES -b $TARGET_PAGEFLAG -rNL | grep -v X | sed -n -e 2p | cut -f1)"
    local injtype=

    if [ "$tgthpage" == 0x ] ; then
        echo "no page with specified page flag"
		echo "$PAGETYPES -b $TARGET_PAGEFLAG -rNl"
		$PAGETYPES -b $TARGET_PAGEFLAG -rNl
        set_return_code FAILED_TO_GET_PFN
        return 1
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
            return 1
        fi
		if [ "$DIFFERENT_PFNS" == true ] ; then
			echo "$MCEINJECT -e $injtype -a $[tgthpage + i]" | tee -a $OFILE
			( while [ -e $TMPF.sync ] ; do true ; done ; $MCEINJECT -e $injtype -a $[tgthpage + i]) &
		else
			echo "$MCEINJECT -e $injtype -a $tgthpage" | tee -a $OFILE
			( while [ -e $TMPF.sync ] ; do true ; done ; $MCEINJECT -e $injtype -a $tgthpage ) &
		fi
        echo $! | tee -a $OFILE
    done

    rm $TMPF.sync
    sleep 1
	return 0
}

MULTIINJ_ITERATIONS=10
control_multiple_injection_race() {
	for i in $(seq $MULTIINJ_ITERATIONS) ; do
		__control_multiple_injection_race || break
	done

    set_return_code EXIT
}
