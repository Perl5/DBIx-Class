package DBIx::Class::Storage::DBI::Replicated::Types;

use MooseX::Types
  -declare => [qw/BalancerClassNamePart/];
use MooseX::Types::Moose qw/ClassName Str/;

class_type 'DBIx::Class::Storage::DBI';

subtype BalancerClassNamePart,
  as ClassName;
    
coerce BalancerClassNamePart,
  from Str,
  via {
    my $type = $_;
    if($type=~m/^::/) {
      $type = 'DBIx::Class::Storage::DBI::Replicated::Balancer'.$type;
    }  
    Class::MOP::load_class($type);  
    $type;  	
  };

1;
