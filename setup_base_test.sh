check_and_define_tp test_base_madv_simple_stress

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
