package DBIx::Class::Bundled;

use strict;
use warnings;
use File::Spec;

our $HERE = File::Spec->catdir(
              File::Spec->rel2abs(
                join '', (File::Spec->splitpath(__FILE__))[0,1]
              ),
              'Bundled'
            );

($HERE) = ($HERE =~ /^(.*)$/); # screw you, taint mode

unshift @INC, $HERE;

1;
