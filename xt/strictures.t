use warnings;
use strict;

use DBIx::Class::Optional::Dependencies -skip_all_without => 'test_strictures';

use Test::More;
use File::Find;
use lib 't/lib';
use DBICTest;

# The rationale is - if we can load all our optdeps
# that are related to lib/ - then we should be able to run
# perl -c checks (via syntax_ok), and all should just work
my $missing_groupdeps_present = grep
  { DBIx::Class::Optional::Dependencies->req_ok_for($_) }
  grep
    { $_ !~ /^ (?: test | rdbms | dist ) _ /x }
    keys %{DBIx::Class::Optional::Dependencies->req_group_list}
;

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

    Test::Strict::syntax_ok($f)
      if ! $missing_groupdeps_present and $f =~ /^ (?: lib  )/x;
  },
  no_chdir => 1,
}, (qw(lib t examples maint)) );

done_testing;
