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
#       AUTHOR:  Gordon Irving (), <Gordon.irving@sophos.com>
#      COMPANY:  Sophos
#      VERSION:  1.0
#      CREATED:  28/11/09 13:54:30 GMT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Test::More;                      # last test to print

use Path::Class;
use FindBin qw($Bin);
use lib dir($Bin,'..', '..','lib')->stringify;
use lib dir($Bin,'..', 'lib')->stringify;

use ok 'DBIx::Class::Admin';


done_testing;
