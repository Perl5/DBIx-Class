BEGIN {
  if ($] < 5.010) {

    # Pre-5.10 perls pollute %INC on unsuccesfull module
    # require, making it appear as if the module is already
    # loaded on subsequent require()s
    # Can't seem to find the exact RT/perldelta entry
    #
    # The reason we can't just use a sane, clean loader, is because
    # if a Module require()s another module the %INC will still
    # get filled with crap and we are back to square one. A global
    # fix is really the only way for this test, as we try to load
    # each available module separately, and have no control (nor
    # knowledge) over their common dependencies.
    #
    # we want to do this here, in the very beginning, before even
    # warnings/strict are loaded

    unshift @INC, 't/lib';
    require DBICTest::Util::OverrideRequire;

    DBICTest::Util::OverrideRequire::override_global_require( sub {
      my $res = eval { $_[0]->() };
      if ($@ ne '') {
        delete $INC{$_[1]};
        die $@;
      }
      return $res;
    } );
  }
}

use strict;
use warnings;

# FIXME This is a crock of shit, needs to go away
# currently here to work around https://rt.cpan.org/Ticket/Display.html?id=74151
# kill with fire when PS::XS / RT#74151 is *finally* fixed
BEGIN {
  my $PS_provider;

  if ( "$]" < 5.010 ) {
    require Package::Stash::PP;
    $PS_provider = 'Package::Stash::PP';
  }
  else {
    require Package::Stash;
    $PS_provider = 'Package::Stash';
  }
  eval <<"EOS" or die $@;

sub stash_for (\$) {
  $PS_provider->new(\$_[0]);
}
1;
EOS
}

use Test::More;

use lib 't/lib';

BEGIN {
  require DBICTest::RunMode;
  plan( skip_all => "Skipping test on plain module install" )
    if DBICTest::RunMode->is_plain;
}

use DBICTest;
use File::Find;
use File::Spec;
use B qw/svref_2object/;

# makes sure we can load at least something
use DBIx::Class;
use DBIx::Class::Carp;

my @modules = grep {
  my ($mod) = $_ =~ /(.+)/;

  # not all modules are loadable at all times
  do {
    # trap deprecation warnings and whatnot
    local $SIG{__WARN__} = sub {};
    eval "require $mod";
  } ? $mod : do {
    SKIP: { skip "Failed require of $mod: " . ($@ =~ /^(.+?)$/m)[0], 1 };
    (); # empty RV for @modules
  };

} find_modules();

# have an exception table for old and/or weird code we are not sure
# we *want* to clean in the first place
my $skip_idx = { map { $_ => 1 } (
  (grep { /^DBIx::Class::CDBICompat/ } @modules), # too crufty to touch
  'SQL::Translator::Producer::DBIx::Class::File', # ditto

  # not sure how to handle type libraries
  'DBIx::Class::Storage::DBI::Replicated::Types',
  'DBIx::Class::Admin::Types',

  # G::L::D is unclean, but we never inherit from it
  'DBIx::Class::Admin::Descriptive',
  'DBIx::Class::Admin::Usage',

  # utility classes, not part of the inheritance chain
  'DBIx::Class::ResultSource::RowParser::Util',
  'DBIx::Class::_Util',
) };

my $has_moose = eval { require Moose::Util };

# can't use Class::Inspector for the mundane parts as it does not
# distinguish imports from anything else, what a crock of...
# Moose is not always available either - hence just do it ourselves

my $seen; #inheritance means we will see the same method multiple times

for my $mod (@modules) {
  SKIP: {
    skip "$mod exempt from namespace checks",1 if $skip_idx->{$mod};

    my %all_method_like = (map
      { %{stash_for($_)->get_all_symbols('CODE')} }
      (reverse @{mro::get_linear_isa($mod)})
    );

    my %parents = map { $_ => 1 } @{mro::get_linear_isa($mod)};

    my %roles;
    if ($has_moose and my $mc = Moose::Util::find_meta($mod)) {
      if ($mc->can('calculate_all_roles_with_inheritance')) {
        $roles{$_->name} = 1 for ($mc->calculate_all_roles_with_inheritance);
      }
    }

    for my $name (keys %all_method_like) {

      # overload is a funky thing - it is not cleaned, and its imports are named funny
      next if $name =~ /^\(/;

      my $gv = svref_2object($all_method_like{$name})->GV;
      my $origin = $gv->STASH->NAME;

      is ($gv->NAME, $name, "Properly named $name method at $origin" . ($origin eq $mod
        ? ''
        : " (inherited by $mod)"
      ));

      next if $seen->{"${origin}:${name}"}++;

      if ($origin eq $mod) {
        pass ("$name is a native $mod method");
      }
      elsif ($roles{$origin}) {
        pass ("${mod}::${name} came from consumption of role $origin");
      }
      elsif ($parents{$origin}) {
        pass ("${mod}::${name} came from proper parent-class $origin");
      }
      else {
        my $via;
        for (reverse @{mro::get_linear_isa($mod)} ) {
          if ( ($_->can($name)||'') eq $all_method_like{$name} ) {
            $via = $_;
            last;
          }
        }

        # exception time
        if (
          ( $name eq 'import' and $via = 'Exporter' )
        ) {
          pass("${mod}::${name} is a valid uncleaned import from ${name}");
        }
        else {
          fail ("${mod}::${name} appears to have entered inheritance chain by import into "
              . ($via || 'UNKNOWN')
          );
        }
      }
    }

    # some common import names (these should never ever be methods)
    for my $f (qw/carp carp_once carp_unique croak confess cluck try catch finally/) {
      if ($mod->can($f)) {
        my $via;
        for (reverse @{mro::get_linear_isa($mod)} ) {
          if ( ($_->can($f)||'') eq $all_method_like{$f} ) {
            $via = $_;
            last;
          }
        }
        fail ("Import $f leaked into method list of ${mod}, appears to have entered inheritance chain at "
            . ($via || 'UNKNOWN')
        );
      }
      else {
        pass ("Import $f not leaked into method list of $mod");
      }
    }
  }
}

sub find_modules {
  my @modules;

  find( {
    wanted => sub {
      -f $_ or return;
      s/\.pm$// or return;
      s/^ (?: lib | blib . (?:lib|arch) ) . //x;
      push @modules, join ('::', File::Spec->splitdir($_));
    },
    no_chdir => 1,
  }, (
    # find them in both lib and blib, duplicates are fine, since
    # @INC is preadjusted for us by the harness
    'lib',
    ( -e 'blib' ? 'blib' : () ),
  ));

  return sort @modules;
}

done_testing;
