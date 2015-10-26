check_and_define_tp memeater
check_and_define_tp thugetlb
check_and_define_tp test_soft_offline_unpoison_stress
check_and_define_tp test_zero_page

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


prepare_base_zero_page() {
	prepare_system_default
}

cleanup_base_zero_page() {
	cleanup_system_default
}

control_base_zero_page() {
    local pid="$1"
    local line="$2"

    local injpfn="$[BASEVFN + ERROR_OFFSET]"

    echo "$line" | tee -a $OFILE
    case "$line" in
        "zero page allocated.")
            echo "$PAGETYPES -p $pid -b zero -l" | tee -a $OFILE
            $PAGETYPES -p $pid -b zero -a 0x700000000+10 -Nl | tee -a $OFILE | grep -v voffset > $TMPF.zero
			zero_pfn=0x$(grep ^700000000 $TMPF.zero | awk '{print $2}')
			if [ "$zero_pfn" == 0x ] ; then
				set_return_code FAILED_ZEROPAGE_ALLOCATION
			else
				set_return_code PASSED_ZEROPAGE_ALLOCATION
				$MCEINJECT -p $pid -e $ERROR_TYPE -a 0x700000000
				$PAGETYPES -p $pid -b zero -a 0x700000000+10 -Nl | tee -a $OFILE
			fi
            kill -SIGUSR1 $pid
            ;;
        "test_zero_page exit.")
            kill -SIGUSR1 $pid
            set_return_code "EXIT"
            return 0
            ;;
        "PROCESS_KILLED")
            set_return_code "KILLED"
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_base_zero_page() {
	check_system_default
}

DEFAULT_THP=
prepare_base_huge_zero_page() {
	DEFAULT_THP=$(get_thp)
	set_thp_always
	prepare_system_default
}

cleanup_base_huge_zero_page() {
	cleanup_system_default
	echo "$DEFAULT_THP" > $THPDIR/enabled
}

control_base_huge_zero_page() {
    local pid="$1"
    local line="$2"

    local injpfn="$[BASEVFN + ERROR_OFFSET]"

    echo "$line" | tee -a $OFILE
    case "$line" in
        "zero page allocated.")
            echo "$PAGETYPES -p $pid -b zero -l" | tee -a $OFILE
            $PAGETYPES -p $pid -b zero,thp=zero,thp -a 0x700000000+512 -l | tee -a $OFILE | grep -v voffset > $TMPF.zero
			zero_pfn=0x$(grep ^700000000 $TMPF.zero | awk '{print $2}')
			if [ "$zero_pfn" == 0x ] ; then
				set_return_code FAILED_ZEROPAGE_ALLOCATION
			else
				set_return_code PASSED_ZEROPAGE_ALLOCATION
				$MCEINJECT -p $pid -e $ERROR_TYPE -a 0x700000000
				$PAGETYPES -p $pid -b zero -a 0x700000000+512 -l | tee -a $OFILE
			fi
            kill -SIGUSR1 $pid
            ;;
        "test_zero_page exit.")
            kill -SIGUSR1 $pid
            set_return_code "EXIT"
            return 0
            ;;
        "PROCESS_KILLED")
            set_return_code "KILLED"
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_base_huge_zero_page() {
	check_system_default
}
