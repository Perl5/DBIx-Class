# vim: filetype=perl

sub run_tests {

    plan tests => 96;
    my $schema = shift;

    foreach my $class ( 'Positioned', 'PositionedAdjacencyList', 'AdjacencyList' ) {

        my $employees = $schema->resultset('Employee::'.$class);

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
        if ($employees->result_class->can('parent_column')) {

            $employees->delete();
            my $mom = $employees->create({ name=>'temp' });
            foreach (1..14) {
                $employees->create({ name=>'temp', parent_id=>$mom->id() });
            }

            my $children = $mom->children();
            ok( ($children->count()==14), 'correct number of children' );

            my $grandma = $mom;
            my @children = $children->all();
            $mom = pop(@children);
            foreach my $child (@children) {
                $child->parent( $mom );
            }

            ok( ($mom->children->count() == 13), 'correct number of grandchildren' );

            if ($employees->result_class->can('position_column')) {
                # TODO: Test positioning within a tree.
            }
        }
    }

}

sub check_positions {
    my( $employees ) = @_;
    $employees->reset();
    my $expected_position = 0;
    my $is_ok = 1;
    while (my $employee = $employees->next()) {
        $expected_position ++;
        if ($employee->position()!=$expected_position) {
            $is_ok = 0;
            last;
        }
    }
    return $is_ok;
}

1;
