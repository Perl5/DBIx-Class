use DBIx::Class::Optional::Dependencies -skip_all_without => 'test_pod';

use warnings;
use strict;

use Test::More;
use lib qw(t/lib);
use DBICTest;

# this has already been required but leave it here for CPANTS static analysis
require Test::Pod;

my $generated_pod_dir = 'maint/.Generated_Pod';
Test::Pod::all_pod_files_ok( 'lib', -d $generated_pod_dir ? $generated_pod_dir : () );
