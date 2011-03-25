use strict;
use warnings;

use Test::More;

use File::Find;
use File::Spec;
use B qw/svref_2object/;

# makes sure we can load at least something
use DBIx::Class;

my @modules = grep {
  my $mod = $_;

  # trap deprecation warnings and whatnot
  local $SIG{__WARN__} = sub {};

  # not all modules are loadable at all times
  eval "require $mod" ? $mod : do {
    SKIP: { skip "Failed require of $mod: $@", 1 };
    ();
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
) };

my $has_cmop = eval { require Class::MOP };

# can't use Class::Inspector for the mundane parts as it does not
# distinguish imports from anything else, what a crock of...
# Class::MOP is not always available either - hence just do it ourselves

my $seen; #inheritance means we will see the same method multiple times

for my $mod (@modules) {
  SKIP: {
    skip "$mod exempt from namespace checks",1 if $skip_idx->{$mod};

    my %all_method_like = do {
      no strict 'refs';
      map {
        my $m = $_;
        map
          { *{"${m}::$_"}{CODE} ? ( $_ => *{"${m}::$_"}{CODE} ) : () }
          keys %{"${m}::"}
      } (reverse @{mro::get_linear_isa($mod)});
    };

    my %parents = map { $_ => 1 } @{mro::get_linear_isa($mod)};

    my %roles;
    if ($has_cmop and my $mc = Class::MOP::class_of($mod)) {
      if ($mc->can('calculate_all_roles_with_inheritance')) {
        $roles{$_->name} = 1 for ($mc->calculate_all_roles_with_inheritance);
      }
    }

    for my $name (keys %all_method_like) {

      # overload is a funky thing - it is neither cleaned, and its imports are named funny
      next if $name =~ /^\(/;

      my $gv = svref_2object($all_method_like{$name})->GV;
      my $origin = $gv->STASH->NAME;

      next if $seen->{"${origin}:${name}"}++;

      TODO: {
        local $TODO = 'CAG does not clean its BEGIN constants' if $name =~ /^__CAG_/;
        is ($gv->NAME, $name, "Properly named $name method at $origin");
      }

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
        fail ("${mod}::${name} appears to have entered inheritance chain by import into "
            . ($via || 'UNKNOWN')
        );
      }
    }
  }
}

sub find_modules {
  my @modules;

  find({
    wanted => sub {
      -f $_ or return;
      s/\.pm$// or return;
      s/^ (?: lib | blib . (?:lib|arch) ) . //x;
      push @modules, join ('::', File::Spec->splitdir($_));
    },
    no_chdir => 1,
  }, (-e 'blib' ? 'blib' : 'lib') );

  return sort @modules;
}


done_testing;
