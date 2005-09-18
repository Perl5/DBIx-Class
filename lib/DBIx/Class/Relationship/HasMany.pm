package DBIx::Class::Relationship::HasMany;

use strict;
use warnings;

sub has_many {
  my ($class, $rel, $f_class, $cond, $attrs) = @_;
    
  eval "require $f_class";

  if (!ref $cond) {
    my $f_key;
    if (defined $cond && length $cond) {
      $f_key = $cond;
      $class->throw( "No such column ${f_key} on foreign class ${f_class}" )
        unless ($@ || $f_class->_columns->{$f_key});
    } else {
      $class =~ /([^\:]+)$/;
      $f_key = lc $1 if $f_class->_columns->{lc $1};
      $class->throw( "Unable to resolve foreign key for has_many from ${class} to ${f_class}" )
        unless $f_key;
    }
    my ($pri, $too_many) = keys %{ $class->_primaries };
    $class->throw( "has_many can only infer join for a single primary key; ${class} has more" )
      if $too_many;
    $cond = { "foreign.${f_key}" => "self.${pri}" },
  }

  $class->add_relationship($rel, $f_class, $cond,
                            { accessor => 'multi',
                              join_type => 'LEFT',
                              cascade_delete => 1,
                              %{$attrs||{}} } );
}

1;
