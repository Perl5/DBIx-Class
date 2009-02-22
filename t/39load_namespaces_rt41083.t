#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

plan tests => 4;

sub _chk_warning {
	defined $_[0]? 
		$_[0] !~ qr/We found ResultSet class '([^']+)' for '([^']+)', but it seems that you had already set '([^']+)' to use '([^']+)' instead/ :
		1
}

my $warnings;
eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTest::RtBug41083;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->load_namespaces(
	result_namespace => 'Schema_A',
	resultset_namespace => 'ResultSet_A',
	default_resultset_class => 'ResultSet'
    );
};
ok(!$@) or diag $@;
ok(_chk_warning($warnings), 'expected no complaint');

eval {
    local $SIG{__WARN__} = sub { $warnings .= shift };
    package DBICNSTest::RtBug41083;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->load_namespaces(
	result_namespace => 'Schema',
	resultset_namespace => 'ResultSet',
	default_resultset_class => 'ResultSet'
    );
};
ok(!$@) or diag $@;
ok(_chk_warning($warnings), 'expected no complaint') or diag $warnings;
