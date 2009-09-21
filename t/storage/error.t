use Class::C3;
use strict;
use Test::More;
use warnings;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 4 );
}

use lib qw(t/lib);

use_ok( 'DBICTest' );
use_ok( 'DBICTest::Schema' );
my $schema = DBICTest->init_schema;

{
       my $warnings;
       local $SIG{__WARN__} = sub { $warnings .= $_[0] };
       eval {
         $schema->resultset('CD')
                ->create({ title => 'vacation in antarctica' })
       };
       like $@, qr/NULL/;  # as opposed to some other error
       unlike( $warnings, qr/uninitialized value/, "No warning from Storage" );
}

