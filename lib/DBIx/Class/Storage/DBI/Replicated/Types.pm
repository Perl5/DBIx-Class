package # hide from PAUSE
  DBIx::Class::Storage::DBI::Replicated::Types;

# DBIx::Class::Storage::DBI::Replicated::Types - Types used internally by
# L<DBIx::Class::Storage::DBI::Replicated>

use warnings;
use strict;

use Type::Library
  -base,
  -declare => qw/BalancerClassNamePart Weight DBICSchema DBICStorageDBI/;
use Type::Utils -all;
use Types::Standard qw/Str Num/;
use Types::LoadableClass qw/LoadableClass/;

class_type DBICSchema, { class => 'DBIx::Class::Schema' };
class_type DBICStorageDBI, { class => 'DBIx::Class::Storage::DBI' };

subtype BalancerClassNamePart,
  as LoadableClass;

coerce BalancerClassNamePart,
  from Str,
  via {
    my $type = $_;
    $type =~ s/\A::/DBIx::Class::Storage::DBI::Replicated::Balancer::/;
    $type;
  };

subtype Weight,
  as Num,
  where { $_ >= 0 },
  message { 'weight must be a decimal greater than 0' };

1;
