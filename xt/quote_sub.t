use warnings;
use strict;

use Test::More;
use Test::Warn;

use DBIx::Class::_Util 'quote_sub';

my $q = do {
  no strict 'vars';
  quote_sub '$x = $x . "buh"; $x += 42';
};

warnings_exist {
  is $q->(), 42, 'Expected result after uninit and string/num conversion'
} [
  qr/Use of uninitialized value/i,
  qr/isn't numeric in addition/,
], 'Expected warnings, strict did not leak inside the qsub'
  or do {
    require B::Deparse;
    diag( B::Deparse->new->coderef2text( Sub::Quote::unquote_sub($q) ) )
  }
;

my $no_nothing_q = do {
  no strict;
  no warnings;
  quote_sub <<'EOC';
    BEGIN { warn "-->${^WARNING_BITS}<--\n" };
    my $n = "Test::Warn::warnings_exist";
    warn "-->@{[ *{$n}{CODE} ]}<--\n";
EOC
};

my $we_cref = Test::Warn->can('warnings_exist');

warnings_exist { $no_nothing_q->() } [
  qr/^\-\-\>\0+\<\-\-$/m,
  qr/^\Q-->$we_cref<--\E$/m,
], 'Expected warnings, strict did not leak inside the qsub'
  or do {
    require B::Deparse;
    diag( B::Deparse->new->coderef2text( Sub::Quote::unquote_sub($no_nothing_q) ) )
  }
;

done_testing;
