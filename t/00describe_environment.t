###
### This version is rather 5.8-centric, because DBIC itself is 5.8
### It certainly can be rewritten to degrade well on 5.6
###

# Very important to grab the snapshot early, as we will be reporting
# the INC indices from the POV of whoever ran the script, *NOT* from
# the POV of the internals
my @initial_INC;
BEGIN {
  @initial_INC = @INC;
}

BEGIN {
  unshift @INC, 't/lib';

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

use Test::More 'no_plan';
use Config;
use File::Find 'find';
use Digest::MD5 ();
use Cwd 'abs_path';
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
  T => {
    relpath => './t',
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
  $v->{marker} = $k unless $k eq 'HOME';

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
my $seen_known_markers;

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

my @known_modules = sort
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

try_module_require($_) for @known_modules;

my $has_versionpm = eval { require version };


# At this point we've loaded everything we ever could, but some modules
# (understandably) crapped out. For an even more thorough report, note
# everthing present in @INC we excplicitly know about (via OptDeps)
# *even though* it didn't load
my $known_failed_loads;

for my $mod (@known_modules) {
  my $inc_key = module_notional_filename($mod);
  next if defined $INC{$inc_key};

  if (defined( my $idx = module_found_at_inc_index( $mod, \@INC ) ) ) {
    $known_failed_loads->{$mod} = full_path( "$INC[$idx]/$inc_key" );
  }

}

my $perl = 'perl';

# This is a cool idea, but the line is too long even with shortening :(
#
#for my $i ( 1 .. $Config{config_argc} ) {
#  my $conf_arg = $Config{"config_arg$i"};
#  $conf_arg =~ s!
#    \= (.+)
#  !
#    '=' . shorten_fn(full_path($1) )
#  !ex;
#
#  $perl .= " $conf_arg";
#}

my $interesting_modules = {
  # pseudo module
  $perl => {
    version => $],
    full_path => $^X,
  }
};


# drill through the *ENTIRE* symtable and build a map of intereseting modules
visit_namespaces( action => sub {
  no strict 'refs';
  my $pkg = shift;

  # keep going, but nothing to see here
  return 1 if $pkg eq 'main';

  # private - not interested, including no further descent
  return 0 if $pkg =~ / (?: ^ | :: ) _ /x;

  my $inc_key = module_notional_filename($pkg);

  my $full_path = (
    $INC{$inc_key}
      and
    -f $INC{$inc_key}
      and
    -r $INC{$inc_key}
      and
    full_path($INC{$inc_key})
  );

  # handle versions first (not interested in synthetic classes)
  if (
    defined ${"${pkg}::VERSION"}
      and
    ${"${pkg}::VERSION"} !~ /\Qset by base.pm/
  ) {

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

    if (
      $full_path
        and
      defined ( my $eumm_ver = eval { MM->parse_version( $full_path ) } )
    ) {

      # can only run the check reliably if v.pm is there
      if (
        $has_versionpm
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

      $interesting_modules->{$pkg}{version} = $eumm_ver;
    }
    elsif( defined $mod_ver ) {

      $interesting_modules->{$pkg}{version} = $mod_ver;
    }
  }
  elsif ( $full_path = $known_failed_loads->{$pkg} ) {
    $interesting_modules->{$pkg}{version} = '!! LOAD FAILED !!';
  }

  if ($full_path) {
    my $marker;
    if (my $m = ( matching_known_lib( $full_path ) || {} )->{marker} ) {
      $marker = $m;
    }
    elsif (defined ( my $idx = module_found_at_inc_index($pkg, \@initial_INC) ) ) {
      $marker = sprintf '$INC[%d]', $idx;
    }

    # we are only interested if there was a declared version already above
    # OR if the module came from somewhere other than T or LIB
    if (
      $marker
        and
      (
        $interesting_modules->{$pkg}
          or
        $marker !~ /^ (?: T | LIB ) $/x
      )
    ) {
      $interesting_modules->{$pkg}{source_marker} = $marker;
      $seen_known_markers->{$marker} = 1
        if $known_libpaths->{$marker};
    }

    # at this point only fill in the path (md5 calc) IFF it is interesting
    # in any respect
    $interesting_modules->{$pkg}{full_path} = $full_path
      if $interesting_modules->{$pkg};
  }

  1;
});

# compress identical versions sourced from ./lib and ./t as close to the root
# of a namespace as we can
purge_identically_versioned_submodules_with_markers([qw( LIB T )]);

ok 1, (scalar keys %$interesting_modules) . " distinctly versioned modules found";

# do not announce anything under ci - we are watching for STDERR silence
exit 0 if DBICTest::RunMode->is_ci;


# diag the result out
my $max_ver_len = max map
  { length "$_" }
  ( 'xxx.yyyzzz_bbb', map { $_->{version} || '' } values %$interesting_modules )
;
my $max_mod_len = max map { length $_ } keys %$interesting_modules;
my $max_marker_len = max map { length $_ } ( '$INC[99]', keys %{ $seen_known_markers || {} } );

my $discl = <<'EOD';

List of loadable modules within both the core and *OPTIONAL* dependency chains present on this system
Note that *MANY* of these modules will *NEVER* be loaded during normal operation of DBIx::Class
(modules sourced from ./lib and ./t with versions identical to their parent namespace were omitted for brevity)
EOD

# pre-assemble everything and print it in one shot
# makes it less likely for parallel test execution to insert bogus lines
my $final_out = "\n$discl\n";


if ($seen_known_markers) {

  $final_out .= join "\n", 'Sourcing markers:', (map
    {
      sprintf "%*s: %s",
        $max_marker_len => $_->{marker},
        ($_->{config_key} ? "\$Config{$_->{config_key}}" : "$_->{relpath}/*" )
    }
    sort
      {
        !!$b->{config_key} cmp !!$a->{config_key}
          or
        ( $a->{marker}||'') cmp ($b->{marker}||'')
      }
      @{$known_libpaths}{keys %$seen_known_markers}
  ), '', '';

}

$final_out .= "=============================\n";

$final_out .= join "\n", (map
  { sprintf (
    "%*s  %*s  %s%s",
    $max_marker_len => $interesting_modules->{$_}{source_marker} || '',
    $max_ver_len => ( defined $interesting_modules->{$_}{version}
      ? $interesting_modules->{$_}{version}
      : ''
    ),
    $_,
    ($interesting_modules->{$_}{full_path}
      ? ' ' x (80 - min( 78, length($_) )) . "[ MD5: @{[ get_md5( $interesting_modules->{$_}{full_path} ) ]} ]"
      : ''
    ),
  ) }
  sort { lc($a) cmp lc($b) } keys %$interesting_modules
), '';

$final_out .= "=============================\n$discl\n\n";

diag $final_out;

exit 0;



sub say_err { print STDERR @_, "\n\n" };

# do !!!NOT!!! use Module::Runtime's require_module - it breaks CORE::require
sub try_module_require {
  # trap deprecation warnings and whatnot
  local $SIG{__WARN__} = sub {};
  local $@;
  eval "require $_[0]";
}

sub full_path {
  return '' unless ( defined $_[0] and -e $_[0] );

  # File::Spec's rel2abs does not resolve symlinks
  # we *need* to look at the filesystem to be sure
  my $fn = abs_path($_[0]);

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
    $fn =~ s!\Q$l->{full_path}!$l->{relpath}!;
  }
  elsif ($l->{config_key}) {
    $fn =~ s!\Q$l->{full_path}!<<$l->{marker}>>!
      and
    $seen_known_markers->{$l->{marker}} = 1;
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
    # run through the matcher twice - first always append a /
    # then try without
    # important to avoid false positives
    for my $suff ( '/', '' ) {
      return { %$l } if 0 == index( $fn, "$l->{full_path}$suff" );
    }
  }
}

sub module_found_at_inc_index {
  my ($mod, $dirs) = @_;

  my $fn = module_notional_filename($mod);

  for my $i ( 0 .. $#$dirs ) {
    # searching from here on out won't mean anything
    return undef if length ref $dirs->[$i];

    if (
      -d $dirs->[$i]
        and
      -f "$dirs->[$i]/$fn"
        and
      -r "$dirs->[$i]/$fn"
    ) {
      return $i;
    }
  }

  return undef;
}

sub purge_identically_versioned_submodules_with_markers {
  my $markers = shift;

  return unless @$markers;

  for my $mod ( sort { length($b) <=> length($a) } keys %$interesting_modules ) {

    next unless defined $interesting_modules->{$mod}{version};

    my $marker = $interesting_modules->{$mod}{source_marker}
      or next;

    next unless grep { $marker eq $_ } @$markers;

    my $parent = $mod;

    while ( $parent =~ s/ :: (?: . (?! :: ) )+ $ //x ) {
      $interesting_modules->{$parent}
        and
      ($interesting_modules->{$parent}{version}||'') eq $interesting_modules->{$mod}{version}
        and
      ($interesting_modules->{$parent}{source_marker}||'') eq $interesting_modules->{$mod}{source_marker}
        and
    delete $interesting_modules->{$mod}
        and
      last
    }
  }
}

sub module_notional_filename {
  (my $fn = $_[0] . '.pm') =~ s|::|/|g;
  $fn;
}

sub get_md5 {
  # we already checked for -r/-f, just bail if can't open
  open my $fh, '<:raw', $_[0] or return '';
  Digest::MD5->new->addfile($fh)->hexdigest;
}
