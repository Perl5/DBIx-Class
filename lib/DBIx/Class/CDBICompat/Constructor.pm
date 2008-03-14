package # hide from PAUSE
    DBIx::Class::CDBICompat::Constructor;

use strict;
use warnings;

sub add_constructor {
  my ($class, $meth, $sql) = @_;
  $class = ref $class if ref $class;
  no strict 'refs';
  
  my %attrs;
  $attrs{rows}     = $1 if $sql =~ s/LIMIT\s+(.*)\s+$//i;
  $attrs{order_by} = $1 if $sql =~ s/ORDER BY\s+(.*)//i;
  
  *{"${class}::${meth}"} =
    sub {
      my ($class, @args) = @_;
      return $class->search_literal($sql, @args, \%attrs);
    };
}

1;
