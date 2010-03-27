
use strict;
use warnings;
use Test::More;
use Test::Exception;
use Data::Dumper;
use lib qw(t/lib);
use DBIC::SqlMakerTest;
use DBIx::Class::SQLAHacks::Oracle;



# 
#  Offline test for connect_by 
#  ( without acitve database connection)
# 
my @handle_tests = (
    {
        connect_by  => { 'parentid' => { '-prior' => \'artistid' } },
        stmt        => "parentid = PRIOR( artistid )",
        bind        => [],
        msg         => 'Simple: parentid = PRIOR artistid',
    },
    {
        connect_by  => { 'parentid' => { '!=' => { '-prior' => \'artistid' } } },
        stmt        => "parentid != PRIOR( artistid )",
        bind        => [],
        msg         => 'Simple: parentid != PRIOR artistid',
    },
    # Examples from http://download.oracle.com/docs/cd/B19306_01/server.102/b14200/queries003.htm

    # CONNECT BY last_name != 'King' AND PRIOR employee_id = manager_id ...
    {
        connect_by  => [
            last_name => { '!=' => 'King' },
            manager_id => { '-prior' => \'employee_id' },
        ],
        stmt        => "( last_name != ? AND manager_id = PRIOR( employee_id ) )",
        bind        => ['King'],
        msg         => 'oracle.com example #1',
    },
    # CONNECT BY PRIOR employee_id = manager_id and 
    #            PRIOR account_mgr_id = customer_id ...
    {
        connect_by  => [
            manager_id => { '-prior' => \'employee_id' },
            customer_id => { '-prior' => \'account_mgr_id' },
        ],
        stmt        => "( manager_id = PRIOR( employee_id ) AND customer_id = PRIOR( account_mgr_id ) )",
        bind        => [],
        msg         => 'oracle.com example #2',
    },
    # CONNECT BY NOCYCLE PRIOR employee_id = manager_id AND LEVEL <= 4;
    # TODO: NOCYCLE parameter doesn't work
);

my $sqla_oracle = DBIx::Class::SQLAHacks::Oracle->new();
isa_ok($sqla_oracle, 'DBIx::Class::SQLAHacks::Oracle');


my $test_count = ( @handle_tests * 2 ) + 1;

for my $case (@handle_tests) {
    local $Data::Dumper::Terse = 1;
    my ( $stmt, @bind );
    my $msg = sprintf("Offline: %s",
        $case->{msg} || substr($case->{stmt},0,25),
    );
    lives_ok(
        sub {
            ( $stmt, @bind ) = $sqla_oracle->_recurse_where( $case->{connect_by}, 'and' );
            is_same_sql_bind( $stmt, \@bind, $case->{stmt}, $case->{bind},$msg )
              || diag "Search term:\n" . Dumper $case->{connect_by};
        }
    ,sprintf("lives is ok from '%s'",$msg));
}

# 
#   Online Tests?
# 
$test_count += 0;

done_testing( $test_count );
