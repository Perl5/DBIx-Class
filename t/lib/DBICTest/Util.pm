package DBICTest::Util;

use warnings;
use strict;

use ANFANG;

use DBICTest::RunMode;

use constant {

  DEBUG_TEST_CONCURRENCY_LOCKS => (
    ( ($ENV{DBICTEST_DEBUG_CONCURRENCY_LOCKS}||'') =~ /^(\d+)$/ )[0]
      ||
    0
  ),

  # During 5.13 dev cycle HELEMs started to leak on copy
  # add an escape for these perls ON SMOKERS - a user/CI will still get death
  # constname a homage to http://theoatmeal.com/comics/working_home
  PEEPEENESS => (
    DBICTest::RunMode->is_smoker
      and
    ! DBICTest::RunMode->is_ci
      and
    ( "$]" >= 5.013005 and "$]" <= 5.013006)
  ),
};

use Config;
use Carp qw(cluck confess croak);
use Fcntl qw( :DEFAULT :flock );
use Scalar::Util qw( blessed refaddr openhandle );
use DBIx::Class::_Util qw( scope_guard parent_dir mkdir_p );

use base 'Exporter';
our @EXPORT_OK = qw(
  dbg stacktrace
  local_umask slurp_bytes tmpdir find_co_root rm_rf
  visit_namespaces PEEPEENESS
  check_customcond_args
  await_flock DEBUG_TEST_CONCURRENCY_LOCKS
);

if (DEBUG_TEST_CONCURRENCY_LOCKS) {
  require DBI;
  my $oc = DBI->can('connect');
  no warnings 'redefine';
  *DBI::connect = sub {
    DBICTest::Util::dbg("Connecting to $_[1]");
    goto $oc;
  }
}

sub dbg ($) {
  require Time::HiRes;
  printf STDERR "\n%.06f  %5s %-78s %s\n",
    scalar Time::HiRes::time(),
    $$,
    $_[0],
    $0,
  ;
}

# File locking is hard. Really hard. By far the best lock implementation
# I've seen is part of the guts of File::Temp. However it is sadly not
# reusable. Since I am not aware of folks doing NFS parallel testing,
# nor are we known to work on VMS, I am just going to punt this and
# use the portable-ish flock() provided by perl itself. If this does
# not work for you - patches more than welcome.
#
# This figure esentially means "how long can a single test hold a
# resource before everyone else gives up waiting and aborts" or
# in other words "how long does the longest test-group legitimally run?"
my $lock_timeout_minutes = 15;  # yes, that's long, I know
my $wait_step_seconds = 0.25;

sub await_flock ($$) {
  my ($fh, $locktype) = @_;

  my ($res, $tries);
  while(
    ! ( $res = flock( $fh, $locktype | LOCK_NB ) )
      and
    ++$tries <= $lock_timeout_minutes * 60 / $wait_step_seconds
  ) {
    select( undef, undef, undef, $wait_step_seconds );

    # "say something" every 10 cycles to work around RT#108390
    # jesus christ our tooling is such a crock of shit :(
    print "#\n" if not $tries % 10;
  }

  return $res;
}


sub local_umask ($) {
  return unless defined $Config{d_umask};

  croak 'Calling local_umask() in void context makes no sense'
    if ! defined wantarray;

  my $old_umask = umask($_[0]);
  croak "Setting umask failed: $!" unless defined $old_umask;

  scope_guard(sub {
    local ($@, $!, $?);

    eval {
      defined(umask $old_umask) or die "nope";
      1;
    } or cluck (
      "Unable to reset old umask '$old_umask': " . ($! || 'Unknown error')
    );
  });
}

# Try to determine the root of a checkout/untar if possible
# OR throws an exception
my $co_root;
sub find_co_root () {

  $co_root ||= do {

    my @mod_parts = split /::/, (__PACKAGE__ . '.pm');
    my $inc_key = join ('/', @mod_parts);  # %INC stores paths with / regardless of OS

    # a bit convoluted, but what we do here essentially is:
    #  - get the file name of this particular module
    #  - do 'cd ..' as many times as necessary to get to t/lib/../..

    my $root = $INC{$inc_key}
      or croak "\$INC{'$inc_key'} seems to be missing, this can't happen...";

    $root = parent_dir $root
      for 1 .. @mod_parts + 2;

    # do the check twice so that the exception is more informative in the
    # very unlikely case of realpath returning garbage
    # (Paththools are in really bad shape - handholding all the way down)
    for my $call_realpath (0,1) {

      require Cwd and $root = ( Cwd::realpath($root) . '/' )
        if $call_realpath;

      croak "Unable to find root of DBIC checkout/untar: '${root}Makefile.PL' does not exist"
        unless -f "${root}Makefile.PL";
    }

    # at this point we are pretty sure this is the right thing - detaint
    ($root =~ /(.+)/)[0];
  }
}

my $tempdir;
sub tmpdir () {
  $tempdir ||= do {

    require File::Spec;
    my $dir = File::Spec->tmpdir;
    $dir .= '/' unless $dir =~ / [\/\\] $ /x;

    # the above works but not always, test it to bits
    my $reason_dir_unusable;

    # PathTools has a bug where on MSWin32 it will often return / as a tmpdir.
    # This is *really* stupid and the result of having our lockfiles all over
    # the place is also rather obnoxious. So we use our own heuristics instead
    # https://rt.cpan.org/Ticket/Display.html?id=76663
    my @parts = File::Spec->splitdir($dir);

    # deal with how 'C:\\\\\\\\\\\\\\' decomposes
    pop @parts while @parts and ! length $parts[-1];

    if (
      @parts < 2
        or
      ( @parts == 2 and $parts[1] =~ /^ [\/\\] $/x )
    ) {
      $reason_dir_unusable =
        'File::Spec->tmpdir returned a root directory instead of a designated '
      . 'tempdir (possibly https://rt.cpan.org/Ticket/Display.html?id=76663)';
    }
    else {
      # make sure we can actually create and sysopen a file in this dir

      my $fn = $dir . "_dbictest_writability_test_$$";

      my $u = local_umask(0); # match the umask we use in DBICTest(::Schema)
      my $g = scope_guard { unlink $fn };

      eval {

        if (-e $fn) {
          unlink $fn or die "Unable to unlink pre-existing $fn: $!\n";
        }

        sysopen (my $tmpfh, $fn, O_RDWR|O_CREAT) or die "Opening $fn failed: $!\n";

        print $tmpfh 'deadbeef' x 1024 or die "Writing to $fn failed: $!\n";

        close $tmpfh or die "Closing $fn failed: $!\n";

        1;
      }
        or
      do {
        chomp( my $err = $@ );

        my @x_tests = map
          { (defined $_) ? ( $_ ? 1 : 0 ) : 'U' }
          map
            { (-e, -d, -f, -r, -w, -x, -o)}
            ($dir, $fn)
        ;

        $reason_dir_unusable = sprintf <<"EOE", $fn, $err, scalar $>, scalar $), umask(), (stat($dir))[4,5,2], @x_tests;
File::Spec->tmpdir returned a directory which appears to be non-writeable:

Error encountered while testing '%s': %s
Process EUID/EGID: %s / %s
Effective umask:   %o
TmpDir UID/GID:    %s / %s
TmpDir StatMode:   %o
TmpDir X-tests:    -e:%s -d:%s -f:%s -r:%s -w:%s -x:%s -o:%s
TmpFile X-tests:   -e:%s -d:%s -f:%s -r:%s -w:%s -x:%s -o:%s
EOE
      };
    }

    if ($reason_dir_unusable) {
      # Replace with our local project tmpdir. This will make multiple tests
      # from different runs conflict with each other, but is much better than
      # polluting the root dir with random crap or failing outright
      my $local_dir = find_co_root . 't/var/';

      mkdir_p $local_dir;

      warn "\n\nUsing '$local_dir' as test scratch-dir instead of '$dir': $reason_dir_unusable\n\n";
      $dir = $local_dir;
    }

    $dir;
  };
}


sub slurp_bytes ($) {
  croak "Expecting a file name, not a filehandle" if openhandle $_[0];
  croak "'$_[0]' is not a readable filename" unless -f $_[0] && -r $_[0];
  open my $fh, '<:raw', $_[0] or croak "Unable to open '$_[0]': $!";
  local $/ unless wantarray;
  <$fh>;
}


sub rm_rf ($) {
  croak "No valid argument supplied to rm_rf()" unless length "$_[0]";

  return unless -e $_[0];

### I do not trust myself - check for subsuming ( the right way )
### Avoid things like https://rt.cpan.org/Ticket/Display.html?id=111637
  require Cwd;

  my ($target, $tmp, $co_tmp) = map {

    my $abs_fn = Cwd::abs_path("$_");

    if ( $^O eq 'MSWin32' and length $abs_fn ) {

      # sometimes we can get a short/longname mix, normalize everything to longnames
      $abs_fn = Win32::GetLongPathName($abs_fn);

      # Fixup for unixy (as opposed to native) slashes
      $abs_fn =~ s|\\|/|g;
    }

    $abs_fn =~ s| (?<! / ) $ |/|x
      if -d $abs_fn;

    ( $abs_fn =~ /(.+)/s )[0]

  } ( $_[0], tmpdir, find_co_root . 't/var' );

  croak(
    "Path supplied to rm_rf() '$target' is neither within the local nor the "
  . "global scratch dirs ( '$co_tmp' and '$tmp' ): REFUSING TO `rm -rf` "
  . 'at random'
  ) unless (
    ( index($target, $co_tmp) == 0 and $target ne $co_tmp )
      or
    ( index($target, $tmp) == 0    and $target ne $tmp )
  );
###

  require File::Path;

  # do not ask for a recent version, use 1.x API calls
  File::Path::rmtree([ $target ]);
}


sub stacktrace {
  my $frame = shift;
  $frame++;
  my (@stack, @frame);

  while (@frame = CORE::caller($frame++)) {
    push @stack, [@frame[3,1,2]];
  }

  return undef unless @stack;

  $stack[0][0] = '';
  return join "\tinvoked as ", map { sprintf ("%s at %s line %d\n", @$_ ) } @stack;
}

sub check_customcond_args ($) {
  my $args = shift;

  confess "Expecting a hashref"
    unless ref $args eq 'HASH';

  for (qw(rel_name foreign_relname self_alias foreign_alias)) {
    confess "Custom condition argument '$_' must be a plain string"
      if length ref $args->{$_} or ! length $args->{$_};
  }

  confess "Current and legacy rel_name arguments do not match"
    if $args->{rel_name} ne $args->{foreign_relname};

  confess "Custom condition argument 'self_resultsource' must be a rsrc instance"
    unless defined blessed $args->{self_resultsource} and $args->{self_resultsource}->isa('DBIx::Class::ResultSource');

  confess "Passed resultsource has no record of the supplied rel_name - likely wrong \$rsrc"
    unless ref $args->{self_resultsource}->relationship_info($args->{rel_name});

  my $struct_cnt = 0;

  if (defined $args->{self_result_object} or defined $args->{self_rowobj} ) {
    $struct_cnt++;
    for (qw(self_result_object self_rowobj)) {
      confess "Custom condition argument '$_' must be a result instance"
        unless defined blessed $args->{$_} and $args->{$_}->isa('DBIx::Class::Row');
    }

    confess "Current and legacy self_result_object arguments do not match"
      if refaddr($args->{self_result_object}) != refaddr($args->{self_rowobj});
  }

  if (defined $args->{foreign_values}) {
    $struct_cnt++;

    confess "Custom condition argument 'foreign_values' must be a hash reference"
      unless ref $args->{foreign_values} eq 'HASH';
  }

  confess "Data structures supplied on both ends of a relationship"
    if $struct_cnt == 2;

  $args;
}

sub visit_namespaces {
  my $args = { (ref $_[0]) ? %{$_[0]} : @_ };

  my $visited_count = 1;

  # A package and a namespace are subtly different things
  $args->{package} ||= 'main';
  $args->{package} = 'main' if $args->{package} =~ /^ :: (?: main )? $/x;
  $args->{package} =~ s/^:://;

  if ( $args->{action}->($args->{package}) ) {
    my $ns =
      ( ($args->{package} eq 'main') ? '' :  $args->{package} )
        .
      '::'
    ;

    $visited_count += visit_namespaces( %$args, package => $_ ) for
      grep
        # this happens sometimes on %:: traversal
        { $_ ne '::main' }
        map
          { $_ =~ /^(.+?)::$/ ? "$ns$1" : () }
          do { no strict 'refs'; keys %$ns }
    ;
  }

  return $visited_count;
}

1;
