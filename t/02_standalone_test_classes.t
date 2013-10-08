use warnings;
use strict;

use Test::More;
use File::Find;

use DBIx::Class::_Util 'sigwarn_silencer';

use lib 't/lib';

find({
  wanted => sub {

    return unless ( -f $_ and $_ =~ /\.pm$/ );

    my $pid = fork();
    if (! defined $pid) {
      die "fork failed: $!"
    }
    elsif (!$pid) {
      if (my @offenders = grep { $_ ne 'DBIx/Class/_Util.pm' } grep { $_ =~ /(^|\/)DBI/ } keys %INC) {
        die "Wtf - DBI* modules present in %INC: @offenders";
      }

      local $SIG{__WARN__} = sigwarn_silencer( qr/\bdeprecated\b/i );
      require( ( $_ =~ m| t/lib/ (.+) |x )[0] ); # untaint and strip lib-part (. is unavailable under -T)
      exit 0;
    }

    is ( waitpid($pid, 0), $pid, "Fork $pid terminated sucessfully");
    my $ex = $? >> 8;
    is ( $ex, 0, "Loading $_ ($pid) exitted with $ex" );
  },

  no_chdir => 1,
}, 't/lib/DBICTest/Schema/');

done_testing;
