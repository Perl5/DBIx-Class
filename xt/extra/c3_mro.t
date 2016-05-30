BEGIN { do "./t/lib/ANFANG.pm" or die ( $@ || $! ) }

use warnings;
use strict;

use Test::More;
use DBICTest;
use DBIx::Class::Optional::Dependencies;

my @global_ISA_tail = qw(
  DBIx::Class
  DBIx::Class::Componentised
  Class::C3::Componentised
  DBIx::Class::AccessorGroup
  Class::Accessor::Grouped
);

is(
  mro::get_mro($_),
  'c3',
  "Correct mro on base class '$_'",
) for grep { $_ =~ /^DBIx::Class/ } @global_ISA_tail;

{
  package AAA;

  use base "DBIx::Class::Core";
}

{
  package BBB;

  use base 'AAA';

  #Injecting a direct parent.
  __PACKAGE__->inject_base( __PACKAGE__, 'AAA' );
}

{
  package CCC;

  use base 'AAA';

  #Injecting an indirect parent.
  __PACKAGE__->inject_base( __PACKAGE__, 'DBIx::Class::Core' );
}

eval { mro::get_linear_isa('BBB'); };
ok (! $@, "Correctly skipped injecting a direct parent of class BBB");

eval { mro::get_linear_isa('CCC'); };
ok (! $@, "Correctly skipped injecting an indirect parent of class BBB");


my $art = DBICTest->init_schema->resultset("Artist")->next;

check_ancestry($_) for (
  ref( $art ),
  ref( $art->result_source ),
  ref( $art->result_source->resultset ),
  ref( $art->result_source->schema ),
  ( map
    { ref $art->result_source->schema->source($_) }
    $art->result_source->schema->sources
  ),
  qw( AAA BBB CCC ),
  ((! DBIx::Class::Optional::Dependencies->req_ok_for('cdbicompat') ) ? () : do {
    unshift @INC, 't/cdbi/testlib';
    map { eval "require $_" or die $@; $_ } qw(
      Film Lazy Actor ActorAlias ImplicitInflate
    );
  }),
);

use DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server;

is_deeply (
  mro::get_linear_isa('DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server'),
  [qw/
    DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server
    DBIx::Class::Storage::DBI::Sybase
    DBIx::Class::Storage::DBI::MSSQL
    DBIx::Class::Storage::DBI::UniqueIdentifier
    DBIx::Class::Storage::DBI::IdentityInsert
    DBIx::Class::Storage::DBI
    DBIx::Class::Storage::DBIHacks
    DBIx::Class::Storage
  /, @global_ISA_tail],
  'Correctly ordered ISA of DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server'
);

my $storage = DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server->new;
$storage->connect_info(['dbi:SQLite::memory:']); # determine_driver's init() connects for this subclass
$storage->_determine_driver;
is (
  $storage->can('sql_limit_dialect'),
  'DBIx::Class::Storage::DBI::MSSQL'->can('sql_limit_dialect'),
  'Correct method picked'
);

if ( "$]" >= 5.010 ) {
  ok (! $INC{'Class/C3.pm'}, 'No Class::C3 loaded on perl 5.10+');

  # Class::C3::Componentised loads MRO::Compat unconditionally to satisfy
  # the assumption that once Class::C3::X is loaded, so is Class::C3
  #ok (! $INC{'MRO/Compat.pm'}, 'No MRO::Compat loaded on perl 5.10+');
}

sub check_ancestry {
  my $class = shift;

  die "Expecting classname" if length ref $class;

  my @linear_ISA = @{ mro::get_linear_isa($class) };

  # something is *VERY* wrong, the splice below won't make it
  unless (@linear_ISA > @global_ISA_tail) {
    fail(
      "Unexpectedly shallow \@ISA for class '$class': "
    . join ', ', map { "'$_'" } @linear_ISA
    );
    return;
  }

  is_deeply (
    [ splice @linear_ISA, ($#linear_ISA - $#global_ISA_tail) ],
    \@global_ISA_tail,
    "Correct end of \@ISA for '$class'"
  );

  # check the remainder
  for my $c (@linear_ISA) {
    # nothing to see there
    next if $c =~ /^DBICTest::/;

    next if mro::get_mro($c) eq 'c3';

    fail( "Incorrect mro '@{[ mro::get_mro($c) ]}' on '$c' (parent of '$class')" );
  }
}

done_testing;
