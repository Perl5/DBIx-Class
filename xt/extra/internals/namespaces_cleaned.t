BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

BEGIN {
  if ( "$]" < 5.010) {

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

use Test::More;

use DBICTest;
use File::Find;
use File::Spec;
use DBIx::Class::_Util qw( get_subname describe_class_methods );

# makes sure we can load at least something
use DBIx::Class;
use DBIx::Class::Carp;

my @modules = map {
  # FIXME:  AS THIS IS CLEARLY A LACK OF DEFENSE IN describe_class_methods  :FIXME
  # FIXME !!! without this detaint I get the test into an infloop on 5.16.x
  # (maybe other versions): https://travis-ci.org/ribasushi/dbix-class/jobs/144738784#L26762
  #
  # or locally like:
  #
  # ~$ ulimit -v $(( 1024 * 256 )); perl -d:Confess -Ilib  -Tl xt/extra/internals/namespaces_cleaned.t
  #     ...
  #  DBIx::Class::MethodAttributes::_attr_cache("DBIx::Class::Storage::DBI::ODBC::Firebird") called at lib/DBIx/Class/MethodAttributes.pm line 166
  #  DBIx::Class::MethodAttributes::_attr_cache("DBIx::Class::Storage::DBI::ODBC::Firebird") called at lib/DBIx/Class/MethodAttributes.pm line 166
  #  DBIx::Class::MethodAttributes::_attr_cache("DBIx::Class::Storage::DBI::ODBC::Firebird") called at lib/DBIx/Class/MethodAttributes.pm line 166
  #  DBIx::Class::MethodAttributes::_attr_cache("DBIx::Class::Storage::DBI::ODBC::Firebird") called at lib/DBIx/Class/MethodAttributes.pm line 154
  #  DBIx::Class::MethodAttributes::FETCH_CODE_ATTRIBUTES("DBIx::Class::Storage::DBI::ODBC::Firebird", CODE(0x42ac2b0)) called at /home/rabbit/perl5/perlbrew/perls/5.16.2/lib/5.16.2/x86_64-linux-thread-multi-ld/attributes.pm line 101
  #  attributes::get(CODE(0x42ac2b0)) called at lib/DBIx/Class/_Util.pm line 885
  #  eval {...} called at lib/DBIx/Class/_Util.pm line 885
  #  DBIx::Class::_Util::describe_class_methods("DBIx::Class::Storage::DBI::ODBC::Firebird") called at xt/extra/internals/namespaces_cleaned.t line 129
  # Out of memory!
  # Out of memory!
  # Out of memory!
  #    ...
  # Segmentation fault
  #
  # FIXME:  AS THIS IS CLEARLY A LACK OF DEFENSE IN describe_class_methods  :FIXME
  # Sweeping it under the rug for now as this is an xt/ test,
  # but someone *must* find what is going on eventually
  # FIXME:  AS THIS IS CLEARLY A LACK OF DEFENSE IN describe_class_methods  :FIXME

  ( $_ =~ /(.+)/ )

} grep {
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
  'SQL::Translator::Producer::DBIx::Class::File', # too crufty to touch

  # not sure how to handle type libraries
  'DBIx::Class::Storage::DBI::Replicated::Types',
  'DBIx::Class::Admin::Types',

  # G::L::D is unclean, but we never inherit from it
  'DBIx::Class::Admin::Descriptive',
  'DBIx::Class::Admin::Usage',

  # this subclass is expected to inherit whatever crap comes
  # from the parent
  'DBIx::Class::ResultSet::Pager',

  # utility classes, not part of the inheritance chain
  'DBIx::Class::Optional::Dependencies',
  'DBIx::Class::ResultSource::RowParser::Util',
  'DBIx::Class::_Util',
) };

my $has_moose = eval { require Moose::Util };

my $seen; #inheritance means we will see the same method multiple times

for my $mod (@modules) {
  SKIP: {
    skip "$mod exempt from namespace checks",1 if $skip_idx->{$mod};

    my %all_method_like =
      map
        { $_->[0]{name} => $mod->can( $_->[0]{name} ) }
        grep
          { $_->[0]{via_class} ne 'UNIVERSAL' }
          values %{ describe_class_methods($mod)->{methods} }
    ;

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

      my ($origin, $cv_name) = get_subname($all_method_like{$name});

      is ($cv_name, $name, "Properly named $name method at $origin" . ($origin eq $mod
        ? ''
        : " (inherited by $mod)"
      ));

      next if $seen->{"${origin}::${name}"}++;

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
            or
          # jesus christ nobody had any idea how to design an interface back then
          ( $name =~ /_trigger/ and $via = 'Class::Trigger' )
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
      $_ =~ m|lib/DBIx/Class/_TempExtlib| and return;
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
