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
  local @INC = ( 't/lib', @INC );


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

  require DBICTest::RunMode;
  require DBICTest::Util;
}

use strict;
use warnings;

use Test::More 'no_plan';

# Things happen... unfortunately
$SIG{__DIE__} = sub {
  die $_[0] unless defined $^S and ! $^S;

  diag "Something horrible happened while assembling the diag data\n$_[0]";
  exit 0;
};

use Config;
use File::Find 'find';
use Digest::MD5 ();
use Cwd 'abs_path';
use File::Spec;
use List::Util 'max';
use ExtUtils::MakeMaker;

use DBIx::Class::Optional::Dependencies;

my $known_paths = {
  SA => {
    config_key => 'sitearch',
  },
  SL => {
    config_key => 'sitelib',
  },
  SS => {
    config_key => 'sitelib_stem',
    match_order => 1,
  },
  SP => {
    config_key => 'siteprefix',
    match_order => 2,
  },
  VA => {
    config_key => 'vendorarch',
  },
  VL => {
    config_key => 'vendorlib',
  },
  VS => {
    config_key => 'vendorlib_stem',
    match_order => 3,
  },
  VP => {
    config_key => 'vendorprefix',
    match_order => 4,
  },
  PA => {
    config_key => 'archlib',
  },
  PL => {
    config_key => 'privlib',
  },
  PP => {
    config_key => 'prefix',
    match_order => 5,
  },
  BLA => {
    rel_path => './blib/arch',
    skip_unversioned_modules => 1,
  },
  BLL => {
    rel_path => './blib/lib',
    skip_unversioned_modules => 1,
  },
  INC => {
    rel_path => './inc',
  },
  LIB => {
    rel_path => './lib',
    skip_unversioned_modules => 1,
  },
  T => {
    rel_path => './t',
    skip_unversioned_modules => 1,
  },
  XT => {
    rel_path => './xt',
    skip_unversioned_modules => 1,
  },
  CWD => {
    rel_path => '.',
  },
  HOME => {
    rel_path => '~',
    abs_unix_path => abs_unix_path (
      eval { require File::HomeDir and File::HomeDir->my_home }
        ||
      $ENV{USERPROFILE}
        ||
      $ENV{HOME}
        ||
      glob('~')
    ),
  },
};

for my $k (keys %$known_paths) {
  my $v = $known_paths->{$k};

  # never use home as a found-in-dir marker - it is too broad
  # HOME is only used by the shortener
  $v->{marker} = $k unless $k eq 'HOME';

  unless ( $v->{abs_unix_path} ) {
    if ( $v->{rel_path} ) {
      $v->{abs_unix_path} = abs_unix_path( $v->{rel_path} );
    }
    elsif ( $Config{ $v->{config_key} || '' } ) {
      $v->{abs_unix_path} = abs_unix_path (
        $Config{"$v->{config_key}exp"} || $Config{$v->{config_key}}
      );
    }
  }

  delete $known_paths->{$k} unless $v->{abs_unix_path} and -d $v->{abs_unix_path};
}
my $seen_markers = {};

# first run through lib/ and *try* to load anything we can find
# within our own project
find({
  wanted => sub {
    -f $_ or return;

    $_ =~ m|lib/DBIx/Class/_TempExtlib| and return;

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
  qw( Data::Dumper DBD::SQLite ),
  map
    { $_ => 1 }
    map
      { keys %{ DBIx::Class::Optional::Dependencies->req_list_for($_) } }
      grep
        # some DBDs are notoriously problematic to load
        # hence only show stuff based on test_rdbms which will
        # take into account necessary ENVs
        { $_ !~ /^ (?: rdbms | dist )_ /x }
        keys %{DBIx::Class::Optional::Dependencies->req_group_list}
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
    $known_failed_loads->{$mod} = abs_unix_path( "$INC[$idx]/$inc_key" );
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
#    '=' . shorten_fn($1)
#  !ex;
#
#  $perl .= " $conf_arg";
#}

my $interesting_modules = {
  # pseudo module
  $perl => {
    version => $],
    abs_unix_path => abs_unix_path($^X),
  }
};


# drill through the *ENTIRE* symtable and build a map of interesting modules
DBICTest::Util::visit_namespaces( action => sub {
  no strict 'refs';
  my $pkg = shift;

  # keep going, but nothing to see here
  return 1 if $pkg eq 'main';

  # private - not interested, including no further descent
  return 0 if $pkg =~ / (?: ^ | :: ) _ /x;

  my $inc_key = module_notional_filename($pkg);

  my $abs_unix_path = (
    $INC{$inc_key}
      and
    -f $INC{$inc_key}
      and
    -r $INC{$inc_key}
      and
    abs_unix_path($INC{$inc_key})
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
      $abs_unix_path
        and
      defined ( my $eumm_ver = eval { MM->parse_version( $abs_unix_path ) } )
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
        . "via `$pkg->VERSION` and parsing the version out of @{[ shorten_fn( $abs_unix_path ) ]} "
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
  elsif ( $known_failed_loads->{$pkg} ) {
    $abs_unix_path = $known_failed_loads->{$pkg};
    $interesting_modules->{$pkg}{version} = '!! LOAD FAIL !!';
  }

  if ($abs_unix_path) {
    my ($marker, $initial_inc_idx);

    my $current_inc_idx = module_found_at_inc_index($pkg, \@INC);
    my $p = subpath_of_known_path( $abs_unix_path );

    if (
      defined $current_inc_idx
        and
      $p->{marker}
        and
      abs_unix_path($INC[$current_inc_idx]) eq $p->{abs_unix_path}
    ) {
      $marker = $p->{marker};
    }
    elsif (defined ( $initial_inc_idx = module_found_at_inc_index($pkg, \@initial_INC) ) ) {
      $marker = "\$INC[$initial_inc_idx]";
    }

    # we are only interested if there was a declared version already above
    # OR if the module came from somewhere other than skip_unversioned_modules
    if (
      $marker
        and
      (
        $interesting_modules->{$pkg}
          or
        !$p->{skip_unversioned_modules}
      )
    ) {
      $interesting_modules->{$pkg}{source_marker} = $marker;
      $seen_markers->{$marker} = 1;
    }

    # at this point only fill in the path (md5 calc) IFF it is interesting
    # in any respect
    $interesting_modules->{$pkg}{abs_unix_path} = $abs_unix_path
      if $interesting_modules->{$pkg};
  }

  1;
});

# compress identical versions sourced from ./blib, ./lib, ./t and ./xt
# as close to the root of a namespace as we can
purge_identically_versioned_submodules_with_markers([ map {
  ( $_->{skip_unversioned_modules} && $_->{marker} ) || ()
} values %$known_paths ]);

ok 1, (scalar keys %$interesting_modules) . " distinctly versioned modules found";

# do not announce anything under ci - we are watching for STDERR silence
exit 0 if DBICTest::RunMode->is_ci;


# diag the result out
my $max_ver_len = max map
  { length "$_" }
  ( 'xxx.yyyzzz_bbb', map { $_->{version} || '' } values %$interesting_modules )
;
my $max_marker_len = max map { length $_ } ( '$INC[999]', keys %$seen_markers );

# Note - must be less than 76 chars wide to account for the diag() prefix
my $discl = <<'EOD';

List of loadable modules within both *OPTIONAL* and core dependency chains
present on this system (modules sourced from ./blib, ./lib, ./t, and ./xt
with versions identical to their parent namespace were omitted for brevity)

    *** Note that *MANY* of these modules will *NEVER* be loaded ***
            *** during normal operation of DBIx::Class ***
EOD

# pre-assemble everything and print it in one shot
# makes it less likely for parallel test execution to insert bogus lines
my $final_out = "\n$discl\n";

$final_out .= "\@INC at startup (does not reflect manipulation at runtime):\n";

my $in_inc_skip;
for (0.. $#initial_INC) {

  my $shortname = shorten_fn( $initial_INC[$_] );

  # when *to* print a line of INC
  if (
    ! $ENV{AUTOMATED_TESTING}
      or
    @initial_INC < 11
      or
    $seen_markers->{"\$INC[$_]"}
      or
    ! -e $shortname
      or
    ! File::Spec->file_name_is_absolute($shortname)
  ) {
    $in_inc_skip = 0;
    $final_out .= sprintf ( "% 3s: %s\n",
      $_,
      $shortname
    );
  }
  elsif(! $in_inc_skip++) {
    $final_out .= "  ...\n";
  }
}

$final_out .= "\n";

if (my @seen_known_paths = grep { $known_paths->{$_} } keys %$seen_markers) {

  $final_out .= join "\n", 'Sourcing markers:', (map
    {
      sprintf "%*s: %s",
        $max_marker_len => $_->{marker},
        ($_->{config_key} ? "\$Config{$_->{config_key}}" : "$_->{rel_path}/" )
    }
    sort
      {
        !!$b->{config_key} cmp !!$a->{config_key}
          or
        ( $a->{marker}||'') cmp ($b->{marker}||'')
      }
      @{$known_paths}{@seen_known_paths}
  ), '', '';

}

$final_out .= "=============================\n";

$final_out .= join "\n", (map
  { sprintf (
    "%*s  %*s  %*s%s",
    $max_marker_len => $interesting_modules->{$_}{source_marker} || '',
    $max_ver_len => ( defined $interesting_modules->{$_}{version}
      ? $interesting_modules->{$_}{version}
      : ''
    ),
    -78 => $_,
    ($interesting_modules->{$_}{abs_unix_path}
      ? "  [ MD5: @{[ get_md5( $interesting_modules->{$_}{abs_unix_path} ) ]} ]"
      : "! -f \$INC{'@{[ module_notional_filename($_) ]}'}"
    ),
  ) }
  sort { lc($a) cmp lc($b) } keys %$interesting_modules
), '';

$final_out .= "=============================\n$discl\n\n";

diag $final_out;

# *very* large printouts may not finish flushing before the test exits
# injecting a <testname> ... ok in the middle of the diag
# http://www.cpantesters.org/cpan/report/fbdac74c-35ca-11e6-ab41-c893a58a4b8c
select( undef, undef, undef, 0.2 );

exit 0;



sub say_err { print STDERR "\n", @_, "\n\n" };

# do !!!NOT!!! use Module::Runtime's require_module - it breaks CORE::require
sub try_module_require {
  # trap deprecation warnings and whatnot
  local $SIG{__WARN__} = sub {};
  local $@;
  eval "require $_[0]";
}

sub abs_unix_path {
  return '' unless (
    defined $_[0]
      and
    ( -e $_[0] or File::Spec->file_name_is_absolute($_[0]) )
  );

  # File::Spec's rel2abs does not resolve symlinks
  # we *need* to look at the filesystem to be sure
  #
  # But looking at the FS for non-existing basenames *may*
  # throw on some OSes so be extra paranoid:
  # http://www.cpantesters.org/cpan/report/26a6e42f-6c23-1014-b7dd-5cd275d8a230
  #
  my $abs_fn = eval { abs_path($_[0]) } || '';

  if ( $abs_fn and $^O eq 'MSWin32' ) {

    # sometimes we can get a short/longname mix, normalize everything to longnames
    $abs_fn = Win32::GetLongPathName($abs_fn)
      if -e $abs_fn;

    # Fixup (native) slashes in Config not matching (unixy) slashes in INC
    $abs_fn =~ s|\\|/|g;
  }

  $abs_fn;
}

sub shorten_fn {
  my $fn = shift;

  my $abs_fn = abs_unix_path($fn);

  if ($abs_fn and my $p = subpath_of_known_path( $fn ) ) {
    $abs_fn =~ s| (?<! / ) $|/|x
      if -d $abs_fn;

    if ($p->{rel_path}) {
      $abs_fn =~ s!\Q$p->{abs_unix_path}!$p->{rel_path}!
        and return $abs_fn;
    }
    elsif ($p->{config_key}) {
      $abs_fn =~ s!\Q$p->{abs_unix_path}!<<$p->{marker}>>!
        and
      $seen_markers->{$p->{marker}} = 1
        and
      return $abs_fn;
    }
  }

  # we got so far - not a known path
  # return the unixified version it if was absolute, leave as-is otherwise
  my $rv = ( $abs_fn and File::Spec->file_name_is_absolute( $fn ) )
    ? $abs_fn
    : $fn
  ;

  $rv = "( ! -e ) $rv" unless -e $rv;

  return $rv;
}

sub subpath_of_known_path {
  my $abs_fn = abs_unix_path( $_[0] )
    or return '';

  for my $p (
    sort {
      length( $b->{abs_unix_path} ) <=> length( $a->{abs_unix_path} )
        or
      ( $a->{match_order} || 0 ) <=> ( $b->{match_order} || 0 )
    }
    values %$known_paths
  ) {
    # run through the matcher twice - first always append a /
    # then try without
    # important to avoid false positives
    for my $suff ( '/', '' ) {
      return { %$p } if 0 == index( $abs_fn, "$p->{abs_unix_path}$suff" );
    }
  }
}

sub module_found_at_inc_index {
  my ($mod, $inc_dirs) = @_;

  return undef unless @$inc_dirs;

  my $fn = module_notional_filename($mod);

  # trust INC if it specifies an existing path
  if( -f ( my $existing_path = abs_unix_path( $INC{$fn} ) ) ) {
    for my $i ( 0 .. $#$inc_dirs ) {

      # searching from here on out won't mean anything
      # FIXME - there is actually a way to interrogate this safely, but
      # that's a fight for another day
      return undef if length ref $inc_dirs->[$i];

      return $i
        if 0 == index( $existing_path, abs_unix_path( $inc_dirs->[$i] ) . '/' );
    }
  }

  for my $i ( 0 .. $#$inc_dirs ) {

    if (
      -d $inc_dirs->[$i]
        and
      -f "$inc_dirs->[$i]/$fn"
        and
      -r "$inc_dirs->[$i]/$fn"
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
