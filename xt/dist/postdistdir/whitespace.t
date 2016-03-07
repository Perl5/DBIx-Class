BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }
use DBIx::Class::Optional::Dependencies -skip_all_without => 'test_whitespace';

use warnings;
use strict;

use Test::More;
use File::Glob 'bsd_glob';

use DBICTest ':GlobalLock';

# FIXME - temporary workaround for RT#82032, RT#82033
# also add all scripts (no extension) and some extra extensions
# we want to check
{
  no warnings 'redefine';
  my $is_pm = sub {
    $_[0] !~ /\./ || $_[0] =~ /\.(?:pm|pod|skip|bash|sql|json|proto)$/i || $_[0] =~ /::/;
  };

  *Test::EOL::_is_perl_module = $is_pm;
  *Test::NoTabs::_is_perl_module = $is_pm;
}

my @pl_targets = qw/t xt lib script examples maint/;
Test::EOL::all_perl_files_ok({ trailing_whitespace => 1 }, @pl_targets);
Test::NoTabs::all_perl_files_ok(@pl_targets);

# check some non-"perl files" in the root separately
my @root_files = grep { -f $_ } bsd_glob('*');

# use .gitignore as a partial guide of what to skip
if (open(my $gi, '<', '.gitignore')) {
  my $skipnames;
  while (my $ln = <$gi>) {
    next if $ln =~ /^\s*$/;
    chomp $ln;
    $skipnames->{$_}++ for bsd_glob($ln);
  }

  # these we want to check no matter what the above says
  delete @{$skipnames}{qw(
    Changes
    LICENSE
    AUTHORS
    README
    MANIFEST
    META.yml
    META.json
  )};

  @root_files = grep { ! $skipnames->{$_} } @root_files;
}

for my $fn (@root_files) {
  Test::EOL::eol_unix_ok($fn, { trailing_whitespace => 1 });
  Test::NoTabs::notabs_ok($fn) unless $fn eq 'MANIFEST';  # it is always tab infested
}

# FIXME - Test::NoTabs and Test::EOL declare 'no_plan' which conflicts with done_testing
# https://github.com/schwern/test-more/issues/14
#done_testing;
