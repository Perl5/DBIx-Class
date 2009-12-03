package # Hide from PAUSE
  DBIx::Class::SQLAHacks::MSSQL;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

sub _RowNumberOver {
   my $self = shift;
   my $sql  =  $self->SUPER::_RowNumberOver(@_);
   $sql =~ s/(\s*)SELECT\s Q1\.\*,\s ROW_NUMBER\(\)\s OVER\(\s \)\s AS\s ROW_NUM\s
             FROM\s \(\n(\s*.*)\n\s*(.*)\n\s*\)\s Q1
             /$1SELECT Q1.*, ROW_NUMBER() OVER($3) AS ROW_NUM FROM (\n$2\n) Q1/ixm;
   return $sql;
}

1;
