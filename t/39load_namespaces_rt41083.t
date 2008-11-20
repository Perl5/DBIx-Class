#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

plan tests => 2;

my $warnings;
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
ok(
	$warnings !~
	qr/We found ResultSet class '([^']+)' for '([^']+)', but it seems that you had already set '([^']+)' to use '([^']+)' instead/,
	'Proxy sub class did not generate an error'
);
