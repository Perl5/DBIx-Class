package DBICTest::Util::OverrideRequire;

# no use/require of any kind - work bare

BEGIN {
  # Neat STDERR require call tracer
  #
  # 0 - no trace
  # 1 - just requires and return values
  # 2 - neat stacktrace (assumes that the supplied $override_cref does *not* (ab)use goto)
  # 3 - full stacktrace
  *TRACE = sub () { 0 };
}

# Takes a single coderef and replaces CORE::GLOBAL::require with it.
#
# On subsequent require() calls, the coderef will be invoked with
# two arguments - ($next_require, $module_name_copy)
#
# $next_require is a coderef closing over the module name. It needs
# to be invoked at some point without arguments for the actual
# require to take place (this way your coderef in essence becomes an
# around modifier)
#
# $module_name_copy is a string-copy of what $next_require is closing
# over. The reason for the copy is that you may trigger a side effect
# on magical values, and subsequently abort the require (e.g.
# require v.5.8.8 magic)
#
# All of this almost verbatim copied from Lexical::SealRequireHints
# Zefram++
sub override_global_require (&) {
  my $override_cref = shift;

  our $next_require = defined(&CORE::GLOBAL::require)
    ? \&CORE::GLOBAL::require
    : sub {

      my ($arg) = @_;

      # The shenanigans with $CORE::GLOBAL::{require}
      # are required because if there's a
      # &CORE::GLOBAL::require when the eval is
      # executed then the CORE::require in there is
      # interpreted as plain require on some Perl
      # versions, leading to recursion.
      my $grequire = delete $CORE::GLOBAL::{require};

      my $res = eval sprintf '
        local $SIG{__DIE__};
        $CORE::GLOBAL::{require} = $grequire;
        package %s;
        CORE::require($arg);
      ', scalar caller(0);  # the caller already had its package replaced

      my $err = $@ if $@ ne '';

      if( TRACE ) {
        if (TRACE == 1) {
          printf STDERR "Require of '%s' (returned: '%s')\n",
            (my $m_copy = $arg),
            (my $r_copy = $res),
          ;
        }
        else {
          my ($fr_num, @fr, @tr, $excise);
          while (@fr = caller($fr_num++)) {

            # Package::Stash::XS is a cock and gets mightily confused if one
            # uses a regex in the require hook. Even though it happens only
            # on < 5.8.7 it's still rather embarassing (also wtf does P::S::XS
            # even need to regex its own module name?!). So we do not use re :)
            if (TRACE == 3 or (index($fr[1], '(eval ') != 0 and index($fr[1], __FILE__) != 0) ) {
              push @tr, [@fr]
            }

            # the caller before this would be the override site - kill it away
            # if the cref writer uses goto - well tough, tracer won't work
            if ($fr[3] eq 'DBICTest::Util::OverrideRequire::__ANON__') {
              $excise ||= $tr[-2]
                if TRACE == 2;
            }
          }

          my @stack =
            map { "$_->[1], line $_->[2]" }
            grep { ! $excise or $_->[1] ne $excise->[1] or $_->[2] ne $excise->[2] }
            @tr
          ;

          printf STDERR "Require of '%s' (returned: '%s')\n%s\n\n",
            (my $m_copy = $arg),
            (my $r_copy = $res||''),
            join "\n", (map { "    $_" } @stack)
          ;
        }
      }

      die $err if defined $err;

      return $res;
    }
  ;

  # Need to suppress the redefinition warning, without
  # invoking warnings.pm.
  BEGIN { ${^WARNING_BITS} = ""; }

  *CORE::GLOBAL::require = sub {
    die "wrong number of arguments to require\n"
      unless @_ == 1;

    # the copy is to prevent accidental overload firing (e.g. require v5.8.8)
    my ($arg_copy) = our ($arg) = @_;

    return $override_cref->(sub {
      die "The require delegate takes no arguments\n"
        if @_;

      my $res = eval sprintf '
        local $SIG{__DIE__};
        package %s;
        $next_require->($arg);
      ', scalar caller(2);  # 2 for the indirection of the $override_cref around

      die $@ if $@ ne '';

      return $res;

    }, $arg_copy);
  }
}

1;
