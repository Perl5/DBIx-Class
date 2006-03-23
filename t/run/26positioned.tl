# vim: filetype=perl

sub run_tests {

    plan tests => 96;
    my $schema = shift;

    my $employees = $schema->resultset('Employee::Positioned');

    if ($employees->result_class->can('position_column')) {

        $employees->delete();
        foreach (1..5) {
            $employees->create({ name=>'temp' });
        }

        $employees = $employees->search(undef,{order_by=>'position'});
        ok( check_positions($employees), "$class: intial positions" );

        my $employee;

        foreach my $position (1..$employees->count()) {

            $employee = $employees->find({ position=>$position });
            $employee->move_previous();
            ok( check_positions($employees), "$class: move_previous( $position )" );

            $employee = $employees->find({ position=>$position });
            $employee->move_next();
            ok( check_positions($employees), "$class: move_next( $position )" );

            $employee = $employees->find({ position=>$position });
            $employee->move_first();
            ok( check_positions($employees), "$class: move_first( $position )" );

            $employee = $employees->find({ position=>$position });
            $employee->move_last();
            ok( check_positions($employees), "$class: move_last( $position )" );

            foreach my $to_position (1..$employees->count()) {
                $employee = $employees->find({ position=>$position });
                $employee->move_to($to_position);
                ok( check_positions($employees), "$class: move_to( $position => $to_position )" );
            }

        }
    }
}

sub check_positions {
    my( $employees ) = @_;
    $employees->reset();
    my $expected_position = 0;
    while (my $employee = $employees->next()) {
        $expected_position ++;
        if ($employee->position()!=$expected_position) {
            return 0;
        }
    }
    return 1;
}

1;
