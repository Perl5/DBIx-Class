use warnings;
use strict;

use Test::More;
use lib 't/lib';
use DBICTest;

unless ( DBIx::Class::Optional::Dependencies->req_ok_for ('test_strictures') ) {
  my $missing = DBIx::Class::Optional::Dependencies->req_missing_for ('test_strictures');
  $ENV{RELEASE_TESTING}
    ? die ("Failed to load release-testing module requirements: $missing")
    : plan skip_all => "Test needs: $missing"
}


use File::Find;

find({
  wanted => sub {
    -f $_ or return;
    m/\.(?: pm | pl | t )$ /ix or return;

    return if m{^(?:
      maint/Makefile.PL.inc/.+                        # all the maint inc snippets are auto-strictured
        |
      t/lib/DBICTest/Util/OverrideRequire.pm          # no stictures by design (load order sensitive)
    )$}x;

    my $f = $_;

    Test::Strict::strict_ok($f);
    Test::Strict::warnings_ok($f);

    #Test::Strict::syntax_ok($f) if $f =~ /^ (?: lib  )/x;
  },
  no_chdir => 1,
}, (qw(lib t examples maint)) );

done_testing;
