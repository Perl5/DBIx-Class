use strict;
use warnings;
use Config;

# there is talk of possible perl compilations where -T is fatal or just
# doesn't work. We don't want to have the user deal with that.
BEGIN { unless ($INC{'t/lib/DBICTest/WithTaint.pm'}) {

  # it is possible the test itself is initially invoked in taint mode
  # and with relative paths *and* with a relative $^X and some other
  # craziness... in short: just be proactive
  require File::Spec;

  if (length $ENV{PATH}) {
    ( $ENV{PATH} ) = join ( $Config{path_sep},
      map { length($_) ? File::Spec->rel2abs($_) : () }
        split /\Q$Config{path_sep}/, $ENV{PATH}
    ) =~ /\A(.+)\z/;
  }

  my ($perl) = $^X =~ /\A(.+)\z/;

  {
    local $ENV{PATH} = "/nosuchrootbindir";
    system( $perl => -T => -e => '
      use warnings;
      use strict;
      eval { my $x = $ENV{PATH} . (kill (0)); 1 } or exit 42;
      exit 0;
    ');
  }

  if ( ($? >> 8) != 42 ) {
    print "1..0 # SKIP Your perl does not seem to like/support -T...\n";
    exit 0;
  }

  exec( $perl, qw( -I. -Mt::lib::DBICTest::WithTaint -T ), __FILE__ );
}}

# When in taint mode, PERL5LIB is ignored (but *not* unset)
# Put it back in INC so that local-lib users can actually
# run this test. Use lib.pm instead of an @INC unshift as
# it will correctly add any arch subdirs encountered

use lib (
  grep { length }
    map { split /\Q$Config{path_sep}\E/, (/^(.*)$/)[0] }  # untainting regex
      grep { defined }
        @ENV{qw(PERL5LIB PERLLIB)}  # precedence preserved by lib
);

# We need to specify 'lib' here as well because even if it was already in
# @INC, the above will have put our local::lib in front of it, so now an
# installed DBIx::Class will take precedence over the one we're trying to test.
# In some cases, prove will have supplied ./lib as an absolute path so it
# doesn't seem worth trying to remove the second copy since it won't hurt
# anything.
use lib qw(t/lib lib);

use Test::More;
use Test::Exception;
use DBICTest;

throws_ok (
  sub { $ENV{PATH} . (kill (0)) },
  qr/Insecure dependency in kill/,
  'taint mode active'
) if length $ENV{PATH};

{
  package DBICTest::Taint::Classes;

  use Test::More;
  use Test::Exception;

  use base qw/DBIx::Class::Schema/;

  lives_ok (sub {
    __PACKAGE__->load_classes(qw/Manual/);
    ok( __PACKAGE__->source('Manual'), 'The Classes::Manual source has been registered' );
    __PACKAGE__->_unregister_source (qw/Manual/);
  }, 'Loading classes with explicit load_classes worked in taint mode' );

  lives_ok (sub {
    __PACKAGE__->load_classes();
    ok( __PACKAGE__->source('Auto'), 'The Classes::Auto source has been registered' );
      ok( __PACKAGE__->source('Auto'), 'The Classes::Manual source has been re-registered' );
  }, 'Loading classes with Module::Find/load_classes worked in taint mode' );
}

{
  package DBICTest::Taint::Namespaces;

  use Test::More;
  use Test::Exception;

  use base qw/DBIx::Class::Schema/;

  lives_ok (sub {
    __PACKAGE__->load_namespaces();
    ok( __PACKAGE__->source('Test'), 'The Namespaces::Test source has been registered' );
  }, 'Loading classes with Module::Find/load_namespaces worked in taint mode' );
}

# check that we can create a database and all
{
  my $s = DBICTest->init_schema( sqlite_use_file => 1 );
  my $art = $s->resultset('Artist')->search({}, {
    prefetch => 'cds', order_by => 'artistid',
  })->next;
  is ($art->artistid, 1, 'got artist');
}

done_testing;
