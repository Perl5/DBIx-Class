# Test is sufficiently involved to *want* to run with "maximum paranoia"
BEGIN { $ENV{DBICTEST_OLD_MRO_SANITY_CHECK_ASSERTIONS} = 1 }

BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use strict;
use warnings;

use Test::More;
use Test::Warn;
use Test::Exception;

use List::Util 'shuffle';
use DBIx::Class::_Util 'sigwarn_silencer';


use DBICTest;

# Test txn_scope_guard
{
  my $schema = DBICTest->init_schema();

  is($schema->storage->transaction_depth, 0, "Correct transaction depth");
  my $artist_rs = $schema->resultset('Artist');

  my $fn = __FILE__;
  throws_ok {
   my $guard = $schema->txn_scope_guard;

    $artist_rs->create({
      name => 'Death Cab for Cutie',
      made_up_column => 1,
    });

   $guard->commit;
  } qr/No such column 'made_up_column' .*? at .*?\Q$fn\E line \d+/s, "Error propogated okay";

  ok(!$artist_rs->find({name => 'Death Cab for Cutie'}), "Artist not created");

  my $inner_exception = '';  # set in inner() below
  throws_ok (sub {
    outer($schema, 1);
  }, qr/$inner_exception/, "Nested exceptions propogated");

  ok(!$artist_rs->find({name => 'Death Cab for Cutie'}), "Artist not created");

  lives_ok (sub {

    # this weird assignment is to stop perl <= 5.8.9 leaking $schema on nested sub{}s
    my $s = $schema;

    warnings_exist ( sub {
      # The 0 arg says don't die, just let the scope guard go out of scope
      # forcing a txn_rollback to happen
      outer($s, 0);
    }, qr/A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or error. Rolling back./, 'Out of scope warning detected');

    ok(!$artist_rs->find({name => 'Death Cab for Cutie'}), "Artist not created");

  }, 'rollback successful withot exception');

  sub outer {
    my ($schema, $fatal) = @_;

    my $guard = $schema->txn_scope_guard;
    $schema->resultset('Artist')->create({
      name => 'Death Cab for Cutie',
    });
    inner($schema, $fatal);
  }

  sub inner {
    my ($schema, $fatal) = @_;

    my $inner_guard = $schema->txn_scope_guard;
    is($schema->storage->transaction_depth, 2, "Correct transaction depth");

    my $artist = $schema->resultset('Artist')->find({ name => 'Death Cab for Cutie' });

    eval {
      $artist->cds->create({
        title => 'Plans',
        year => 2005,
        $fatal ? ( foo => 'bar' ) : ()
      });
    };
    if ($@) {
      # Record what got thrown so we can test it propgates out properly.
      $inner_exception = $@;
      die $@;
    }

    # inner guard should commit without consequences
    $inner_guard->commit;
  }
}

# make sure the guard does not eat exceptions
{
  my $schema = DBICTest->init_schema;

  no warnings 'redefine';
  local *DBIx::Class::Storage::DBI::txn_rollback = sub { die 'die die my darling' };
  Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;

  throws_ok (sub {
    my $guard = $schema->txn_scope_guard;
    $schema->resultset ('Artist')->create ({ name => 'bohhoo'});

    # this should freak out the guard rollback
    # but it won't work because DBD::SQLite is buggy
    # instead just install a toxic rollback above
    #$schema->storage->_dbh( $schema->storage->_dbh->clone );

    die 'Deliberate exception';
  }, ( "$]" >= 5.013008 )
    ? qr/Deliberate exception/s # temporary until we get the generic exception wrapper rolling
    : qr/Deliberate exception.+Rollback failed/s
  );

  # just to mask off warning since we could not disconnect above
  $schema->storage->_dbh->disconnect;
}

# make sure it warns *big* on failed rollbacks
# test with and without a poisoned $@
require DBICTest::AntiPattern::TrueZeroLen;
require DBICTest::AntiPattern::NullObject;
{
  my @want = (
    qr/A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or error. Rolling back./,
    qr/\*+ ROLLBACK FAILED\!\!\! \*+/,
  );

  my @w;
  local $SIG{__WARN__} = sub {
    if (grep {$_[0] =~ $_} (@want)) {
      push @w, $_[0];
    }
    else {
      warn $_[0];
    }
  };


  # we are driving manually here, do not allow interference
  local $SIG{__DIE__} if $SIG{__DIE__};


  no warnings 'redefine';
  local *DBIx::Class::Storage::DBI::txn_rollback = sub { die 'die die my darling' };
  Class::C3->reinitialize() if DBIx::Class::_ENV_::OLD_MRO;

  my @poisons = shuffle (
    undef,
    DBICTest::AntiPattern::TrueZeroLen->new,
    DBICTest::AntiPattern::NullObject->new,
    'GIFT!',
  );

  for my $pre_poison (@poisons) {
    for my $post_poison (@poisons) {

      @w = ();

      my $schema = DBICTest->init_schema(no_populate => 1);

      # the actual scope where the guard is created/freed
      {
        # in this particular case these are not the warnings we are looking for
        local $SIG{__WARN__} = sigwarn_silencer qr/implementing the so called null-object-pattern/;

        # if is inside the eval, to clear $@ in the undef case
        eval { die $pre_poison if defined $pre_poison };

        my $guard = $schema->txn_scope_guard;

        eval { die $post_poison if defined $post_poison };

        $schema->resultset ('Artist')->create ({ name => "bohhoo, too bad we'll roll you back"});
      }

      local $TODO = 'Do not know how to deal with trapped exceptions occuring after guard instantiation...'
        if ( defined $post_poison and (
          # take no chances on installation
          DBICTest::RunMode->is_plain
            or
          # I do not understand why but on <= 5.8.8 and on 5.10.0
          # "$pre_poison == $post_poison == string" passes...
          # so todoify 5.8.9 and 5.10.1+, and deal with the rest below
          ( ( "$]" > 5.008008 and "$]" < 5.010000 ) or "$]" > 5.010000 )
            or
          ! defined $pre_poison
            or
          length ref $pre_poison
            or
          length ref $post_poison
        ));

      is (@w, 2, sprintf 'Both expected warnings found - $@ poisonstate:   pre-poison:%s   post-poison:%s',
        map {
          ! defined $_      ? 'UNDEF'
        : ! length ref $_   ? $_
                            : ref $_

        } ($pre_poison, $post_poison)
      );

      # just to mask off warning since we could not disconnect above
      $schema->storage->_dbh->disconnect;
    }
  }
}

# add a TODO to catch when Text::Balanced is finally fixed
# https://rt.cpan.org/Public/Bug/Display.html?id=74994
#
# while it doesn't matter much for DBIC itself, this particular bug
# is a *BANE*, and DBIC is to bump its dep as soon as possible
{

  require Text::Balanced;

  my @w;
  local $SIG{__WARN__} = sub {
    $_[0] =~ /External exception class .+? \Qimplements partial (broken) overloading/
      ? push @w, @_
      : warn @_
  };

  lives_ok {
    # this is what poisons $@
    Text::Balanced::extract_bracketed( '(foo', '()' );
    DBIx::Class::_Util::is_exception($@);

    my $s = DBICTest::Schema->connect('dbi:SQLite::memory:');
    my $g = $s->txn_scope_guard;
    $g->commit;
  } 'Broken Text::Balanced is not screwing up txn_guard';

  local $TODO = 'RT#74994 *STILL* not fixed';
  is(scalar @w, 0, 'no warnings \o/');
}

done_testing;
