check_and_define_tp test_base_madv_simple_stress
check_and_define_tp memeater
check_and_define_tp thugetlb

prepare_madv_simple_stress() {
    prepare_system_default
}

cleanup_madv_simple_stress() {
    cleanup_system_default
}

control_madv_simple_stress() {
    local i=
    for i in $(seq 10) ; do
        $test_base_madv_simple_stress | tee -a $OFILE
        all_unpoison
    done
    set_return_code EXIT
}

check_madv_simple_stress() {
    check_system_default
}

prepare_poison_unpoison_stress() {
    pkill -SIGKILL -f $memeater
    prepare_system_default
}

cleanup_poison_unpoison_stress() {
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

control_poison_unpoison_stress() {
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

check_poison_unpoison_stress() {
    check_system_default
}

prepare_poison_unpoison_stress_hugetlb() {
    pkill -SIGKILL -f $thugetlb
    set_and_check_hugetlb_pool 200
    prepare_system_default
}

cleanup_poison_unpoison_stress_hugetlb() {
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

control_poison_unpoison_stress_hugetlb() {
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

check_poison_unpoison_stress_hugetlb() {
    check_system_default
}
