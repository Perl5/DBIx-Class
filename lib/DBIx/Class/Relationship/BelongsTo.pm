package DBIx::Class::Relationship::BelongsTo;

use strict;
use warnings;

sub belongs_to {
  my ($class, $rel, $f_class, $cond, $attrs) = @_;
  eval "require $f_class";
  my %f_primaries = eval { %{ $f_class->_primaries } };
  my $f_loaded = !$@;
  # single key relationship
  if (not defined $cond) {
    $class->throw("Can't infer join condition for ${rel} on ${class}; unable to load ${f_class}") unless $f_loaded;
    my ($pri, $too_many) = keys %f_primaries;
    $class->throw("Can't infer join condition for ${rel} on ${class}; ${f_class} has multiple primary key") if $too_many;
    my $acc_type = ($class->_columns->{$rel}) ? 'filter' : 'single';
    $class->add_relationship($rel, $f_class,
      { "foreign.${pri}" => "self.${rel}" },
      { accessor => $acc_type }
    );
  }
  # multiple key relationship
  else {
    my $cond_rel;
    for (keys %$cond) {
      if (m/\./) { # Explicit join condition
        $cond_rel = $cond;
        last;
      }
      $cond_rel->{"foreign.$_"} = "self.".$cond->{$_};
      # primary key usage checks
      if (exists $f_primaries{$_}) {
        delete $f_primaries{$_};
      } elsif ($f_loaded) {
        $class->throw("non primary key used in join condition: $_");
      }
    }
    $class->throw("Invalid belongs_to specification for ${rel} on ${class}; primary key columns ".join(', ', keys %f_primaries)." of ${f_class} not specified in join condition") if ($f_loaded && keys %f_primaries);
    $class->add_relationship($rel, $f_class,
      $cond_rel,
      { accessor => 'single', %{$attrs ||{}} }
    );
  }
  return 1;
}

=head1 AUTHORS

Alexander Hartmaier <Alexander.Hartmaier@t-systems.at>

Matt S. Trout <mst@shadowcatsystems.co.uk>

=cut

1;
