package DBIx::Class::Relationship::BelongsTo;

use strict;
use warnings;

sub belongs_to {
  my ($class, $rel, $f_class, $cond, $attrs) = @_;
  eval "require $f_class";
  if ($@) {
    $class->throw_exception($@) unless $@ =~ /Can't locate/;
  }

  my %f_primaries;
  $f_primaries{$_} = 1 for eval { $f_class->primary_columns };
  my $f_loaded = !$@;
  
  # single key relationship
  if (!ref $cond) {
    $class->throw_exception("Can't infer join condition for ${rel} on ${class}; unable to load ${f_class}")
      unless $f_loaded;

    my ($pri, $too_many) = keys %f_primaries;
    $class->throw_exception("Can't infer join condition for ${rel} on ${class}; ${f_class} has no primary keys")
      unless defined $pri;      
    $class->throw_exception("Can't infer join condition for ${rel} on ${class}; ${f_class} has multiple primary key")
      if $too_many;      

    my $fk = defined $cond ? $cond : $rel;
    $class->throw_exception("Can't infer join condition for ${rel} on ${class}; $fk is not a column")
      unless $class->has_column($fk);

    my $acc_type = $class->has_column($rel) ? 'filter' : 'single';
    $class->add_relationship($rel, $f_class,
      { "foreign.${pri}" => "self.${fk}" },
      { accessor => $acc_type, %{$attrs || {}} }
    );
  }
  # multiple key relationship
  elsif (ref $cond eq 'HASH') {
    my $cond_rel;
    for (keys %$cond) {
      if (m/\./) { # Explicit join condition
        $cond_rel = $cond;
        last;
      }
      $cond_rel->{"foreign.$_"} = "self.".$cond->{$_};
    }
    my $acc_type = (keys %$cond_rel == 1 and $class->has_column($rel)) ? 'filter' : 'single';
    $class->add_relationship($rel, $f_class,
      $cond_rel,
      { accessor => $acc_type, %{$attrs || {}} }
    );
  }
  else {
    $class->throw_exception('third argument for belongs_to must be undef, a column name, or a join condition');
  }
  return 1;
}

=head1 AUTHORS

Alexander Hartmaier <Alexander.Hartmaier@t-systems.at>

Matt S. Trout <mst@shadowcatsystems.co.uk>

=cut

1;
