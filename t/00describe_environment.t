###
### This version is rather 5.8-centric, because DBIC itself is 5.8
### It certainly can be rewritten to degrade well on 5.6
###

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

# Explicitly add 'lib' to the front of INC - this way we will
# know without ambiguity what was loaded from the local untar
# and what came from elsewhere
use lib qw(lib t/lib);

use strict;
use warnings;

use Test::More 'no_plan';
use Config;
use File::Find 'find';
use Module::Runtime 'module_notional_filename';
use List::Util qw(max min);
use ExtUtils::MakeMaker;
use DBICTest::Util 'visit_namespaces';

# load these two to pull in the t/lib armada
use DBICTest;
use DBICTest::Schema;


my $known_libpaths = {
  SA => {
    config_key => 'sitearch',
  },
  SL => {
    config_key => 'sitelib',
  },
  VA => {
    config_key => 'vendorarch',
  },
  VL => {
    config_key => 'vendorlib',
  },
  PA => {
    config_key => 'archlib',
  },
  PL => {
    config_key => 'privlib',
  },
  INC => {
    relpath => './inc',
  },
  LIB => {
    relpath => './lib',
  },
  HOME => {
    relpath => '~',
    full_path => full_path (
      eval { require File::HomeDir and File::HomeDir->my_home }
        ||
      $ENV{HOME}
        ||
      glob('~')
    ),
  },
};

for my $k (keys %$known_libpaths) {
  my $v = $known_libpaths->{$k};

  # never use home as a found-in-dir marker - it is too broad
  # HOME is only used by the shortener
  $v->{abbrev} = $k unless $k eq 'HOME';

  unless ( $v->{full_path} ) {
    if ( $v->{relpath} ) {
      $v->{full_path} = full_path( $v->{relpath} );
    }
    elsif ( $Config{ $v->{config_key} || '' } ) {
      $v->{full_path} = full_path (
        $Config{"$v->{config_key}exp"} || $Config{$v->{config_key}}
      );
    }
  }

  delete $known_libpaths->{$k} unless $v->{full_path} and -d $v->{full_path};
}


# first run through lib/ and *try* to load anything we can find
# within our own project
find({
  wanted => sub {
    -f $_ or return;

    # can't just `require $fn`, as we need %INC to be
    # populated properly
    my ($mod) = $_ =~ /^ lib [\/\\] (.+) \.pm $/x
      or return;

    try_module_require(join ('::', File::Spec->splitdir($mod)) )
  },
  no_chdir => 1,
}, 'lib' );



# now run through OptDeps and attempt loading everything else
#
# some things needs to be sorted before other things
# positive - load first
# negative - load last
my $load_weights = {
  # Make sure oracle is tried last - some clients (e.g. 10.2) have symbol
  # clashes with libssl, and will segfault everything coming after them
  "DBD::Oracle" => -999,
};
try_module_require($_) for sort
  { ($load_weights->{$b}||0) <=> ($load_weights->{$a}||0) }
  keys %{
    DBIx::Class::Optional::Dependencies->req_list_for([
      grep
        # some DBDs are notoriously problematic to load
        # hence only show stuff based on test_rdbms which will
        # take into account necessary ENVs
        { $_ !~ /^ (?: rdbms | dist )_ /x }
        keys %{DBIx::Class::Optional::Dependencies->req_group_list}
    ])
  }
;


# at this point we've loaded everything we ever could, let's drill through
# the *ENTIRE* symtable and build a map of versions
my $has_versionpm = eval { require version };
my $versioned_modules = {
  perl => { version => $], full_path => $^X }
};
my $seen_known_libs;
visit_namespaces( action => sub {
  no strict 'refs';
  my $pkg = shift;

  # keep going, but nothing to see here
  return 1 if $pkg eq 'main';

  # private - not interested, including no further descent
  return 0 if $pkg =~ / (?: ^ | :: ) _ /x;

  # not interested in no-VERSION-containing modules, nor synthetic classes
  return 1 if (
    ! defined ${"${pkg}::VERSION"}
      or
    ${"${pkg}::VERSION"} =~ /\Qset by base.pm/
  );

  # make sure a version can be extracted, be noisy when it doesn't work
  # do this even if we are throwing away the result below in lieu of EUMM
  my $mod_ver = eval { $pkg->VERSION };
  if (my $err = $@) {
    $err =~ s/^/  /mg;
    say_err (
      "Calling `$pkg->VERSION` resulted in an exception, which should never "
    . "happen - please file a bug with the distribution containing $pkg. "
    . "Complete exception text below:\n\n$err"
    );
  }
  elsif( ! defined $mod_ver or ! length $mod_ver ) {
    my $ret = defined $mod_ver
      ? "the empty string ''"
      : "'undef'"
    ;

    say_err (
      "Calling `$pkg->VERSION` returned $ret, even though \$${pkg}::VERSION "
    . "is defined, which should never happen - please file a bug with the "
    . "distribution containing $pkg."
    );

    undef $mod_ver;
  }

  # if this is a real file - extract the version via EUMM whenever possible
  my $fn = $INC{module_notional_filename($pkg)};

  my $full_path;

  my $eumm_ver = (
    $fn
      and
    -f $fn
      and
    -r $fn
      and
    $full_path = full_path($fn)
      and
    eval { MM->parse_version( $fn ) }
  ) || undef;

  if (
    $has_versionpm
      and
    defined $eumm_ver
      and
    defined $mod_ver
      and
    $eumm_ver ne $mod_ver
      and
    (
      ( eval { version->parse( do { (my $v = $eumm_ver) =~ s/_//g; $v } ) } || 0 )
        !=
      ( eval { version->parse( do { (my $v = $mod_ver) =~ s/_//g; $v } ) } || 0 )
    )
  ) {
    say_err (
      "Mismatch of versions '$mod_ver' and '$eumm_ver', obtained respectively "
    . "via `$pkg->VERSION` and parsing the version out of @{[ shorten_fn( $full_path ) ]} "
    . "with ExtUtils::MakeMaker\@@{[ ExtUtils::MakeMaker->VERSION ]}. "
    . "This should never happen - please check whether this is still present "
    . "in the latest version, and then file a bug with the distribution "
    . "containing $pkg."
    );
  }

  if( defined $eumm_ver ) {
    $versioned_modules->{$pkg} = { version => $eumm_ver };
  }
  elsif( defined $mod_ver ) {
    $versioned_modules->{$pkg} = { version => $mod_ver };
  }

  # add the path and a "where-from" marker if any
  if ( $full_path and my $slot = $versioned_modules->{$pkg} ) {
    $slot->{full_path} = $full_path;

    if ( my $abbr = ( matching_known_lib( $full_path ) || {} )->{abbrev} ) {
      $slot->{from_known_lib} = $abbr;
      $seen_known_libs->{$abbr} = 1;
    }
  }

  1;
});

# compress identical versions sourced from ./lib as close to the root as we can
for my $mod ( sort { length($b) <=> length($a) } keys %$versioned_modules ) {
  ($versioned_modules->{$mod}{from_known_lib}||'') eq 'LIB'
    or next;

  my $parent = $mod;

  while ( $parent =~ s/ :: (?: . (?! :: ) )+ $ //x ) {
    $versioned_modules->{$parent}
      and
    $versioned_modules->{$parent}{version} eq $versioned_modules->{$mod}{version}
      and
    ($versioned_modules->{$parent}{from_known_lib}||'') eq 'LIB'
      and
    delete $versioned_modules->{$mod}
      and
    last
  }
}

ok 1, (scalar keys %$versioned_modules) . " distinctly versioned modules found";

# do not announce anything under ci - we are watching for STDERR silence
exit if DBICTest::RunMode->is_ci;


# diag the result out
my $max_ver_len = max map
  { length "$_" }
  ( 'xxx.yyyzzz_bbb', map { $_->{version} } values %$versioned_modules )
;
my $max_mod_len = max map { length $_ } keys %$versioned_modules;
my $max_marker_len = max map { length $_ } keys %{ $seen_known_libs || {} };

my $discl = <<'EOD';

List of loadable modules specifying a version within both the core and *OPTIONAL* dependency chains present on this system
Note that *MANY* of these modules will *NEVER* be loaded during normal operation of DBIx::Class
(modules sourced from ./lib with versions identical to their parent namespace were omitted for brevity)
EOD

diag "\n$discl\n";

if ($seen_known_libs) {
  diag "Sourcing markers:\n";

  diag $_ for
    map
      {
        sprintf "  %*s: %s",
          $max_marker_len => $_->{abbrev},
          ($_->{config_key} ? "\$Config{$_->{config_key}}" : $_->{relpath} )
      }
      @{$known_libpaths}{ sort keys %$seen_known_libs }
  ;

  diag "\n";
}

diag "=============================\n";

diag sprintf (
  "%*s  %*s  %*s%s\n",
  $max_marker_len+2 => $versioned_modules->{$_}{from_known_lib} || '',
  $max_ver_len => $versioned_modules->{$_}{version},
  -$max_mod_len => $_,
  ($versioned_modules->{$_}{full_path}
    ? ' ' x (80 - min(78, $max_mod_len)) . "[ MD5: @{[ get_md5( $versioned_modules->{$_}{full_path} ) ]} ]"
    : ''
  ),
) for sort { lc($a) cmp lc($b) } keys %$versioned_modules;

diag "=============================\n$discl\n";

exit 0;



sub say_err { print STDERR "\n", @_, "\n" };

# do !!!NOT!!! use Module::Runtime's require_module - it breaks CORE::require
sub try_module_require {
  # trap deprecation warnings and whatnot
  local $SIG{__WARN__} = sub {};
  local $@;
  eval "require $_[0]";
}

sub full_path {
  return '' unless ( defined $_[0] and -e $_[0] );

  my $fn = Cwd::abs_path($_[0]);

  if ( $^O eq 'MSWin32' and $fn ) {

    # sometimes we can get a short/longname mix, normalize everything to longnames
    $fn = Win32::GetLongPathName($fn);

    # Fixup (native) slashes in Config not matching (unixy) slashes in INC
    $fn =~ s|\\|/|g;
  }

  $fn;
}

sub shorten_fn {
  my $fn = shift;

  my $l = matching_known_lib( $fn )
    or return $fn;

  if ($l->{relpath}) {
    $fn =~ s/\Q$l->{full_path}\E/$l->{relpath}/;
  }
  elsif ($l->{config_key}) {
    $fn =~ s/\Q$l->{full_path}\E/<<$l->{config_key}>>/;
  }

  $fn;
}

sub matching_known_lib {
  my $fn = full_path( $_[0] )
    or return '';

  for my $l (
    sort { length( $b->{full_path} ) <=> length( $a->{full_path} ) }
    values %$known_libpaths
  ) {
    return { %$l } if 0 == index( $fn, $l->{full_path} );
  }
}

sub get_md5 {
  # we already checked for -r/-f, just bail if can't open
  open my $fh, '<:raw', $_[0] or return '';
  require Digest::MD5;
  Digest::MD5->new->addfile($fh)->hexdigest;
}
