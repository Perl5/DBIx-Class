use warnings;
use strict;

use Test::More;
use Test::NoTabs;
use lib 't/lib';
use DBICTest;
unless ( DBICTest::AuthorCheck->is_author || $ENV{AUTOMATED_TESTING} || $ENV{RELEASE_TESTING} ) {
  plan( skip_all => "Author tests not required for installation" );
}
all_perl_files_ok();

done_testing;
