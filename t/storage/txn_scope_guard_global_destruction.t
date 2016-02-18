use strict;
use warnings;
use Test::More;

sub run_snippet {
  my $output = `$^X -Mlib=t/lib -MDBICTest -e '$_[0]' 2>&1`;
  chomp $output;
  return $output;
}

{
  my $output = run_snippet('
    my $s = DBICTest->init_schema;
    eval {
      my $g = $s->txn_scope_guard;
      die "normal destruction";
    };
  ');
  unlike $output,
    qr/A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or error\. Rolling back\./,
    'Out of scope warning not detected';
  is $output, "", "No other output";
}

{
  my $output = run_snippet('
    my $s = DBICTest->init_schema;
    my $g = $s->txn_scope_guard;
    die "global destruction";
  ');
  unlike $output,
    qr/A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or error\. Rolling back\./,
    'Out of scope warning not detected';
  like $output,
    qr/global destruction/,
    'Fatal exception detected';
}

{
  my $output = run_snippet('
    my $s = DBICTest->init_schema;
    my $g = $s->txn_scope_guard;
  ');
  like $output,
    qr/A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or error\. Rolling back\./,
    'Out of scope warning detected';
}

done_testing;
