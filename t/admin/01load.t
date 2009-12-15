#
#===============================================================================
#
#         FILE:  01load.t
#
#  DESCRIPTION:  
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Gordon Irving (), <goraxe@cpan.org>
#      VERSION:  1.0
#      CREATED:  28/11/09 13:54:30 GMT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Test::More;                      # last test to print

use FindBin qw($Bin);
use Path::Class;


use lib dir($Bin,'..', '..','lib')->stringify;
use lib dir($Bin,'..', 'lib')->stringify;



BEGIN {
    eval "use DBIx::Class::Admin";
    plan skip_all => "Deps not installed: $@" if $@;
}

use_ok 'DBIx::Class::Admin';


done_testing;
