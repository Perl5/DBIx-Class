# vim: filetype=perl

sub run_tests {

    plan tests => 5;
    my $schema = shift;

    my $employees = $schema->resultset('Employee::AdjacencyList');
    $employees->delete();

    my $grandma = $employees->create({ name=>'grandma', parent_id=>0 });
    foreach (1..15) {
        $employees->create({ name=>'temp', parent_id=>$grandma->id() });
    }
    ok( ($grandma->children->count()==15), 'grandma children' );

    my $mom = ($grandma->children->search(undef,{rows=>1})->all())[0];
    foreach (1..5) {
        ($grandma->children->search(undef,{rows=>1})->all())[0]->parent( $mom );
    }
    ok( ($mom->children->count()==5), 'mom children' );
    ok( ($grandma->children->count()==10), 'grandma children' );

    $mom = ($grandma->children->search(undef,{rows=>2})->all())[0];
    foreach (1..4) {
        ($grandma->children->search(undef,{rows=>1})->all())[0]->parent( $mom );
    }
    ok( ($mom->children->count()==4), 'mom children' );
    ok( ($grandma->children->count()==6), 'grandma children' );

    ok( check_rs( scalar $grandma->children() ), 'correct positions' );
}

sub check_rs {
    my( $rs ) = @_;
    $rs->reset();
    my $position_column = $rs->result_class->position_column();
    my $expected_position = 0;
    while (my $row = $rs->next()) {
        $expected_position ++;
        if ($row->get_column($position_column)!=$expected_position) {
            return 0;
        }
        my $children = $row->children();
        while (my $child = $children->next()) {
            return 0 if (!check_rs( scalar $child->children() ));
        }
    }
    return 1;
}

1;
