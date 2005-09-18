package DBIx::Class::Relationship::BelongsTo;

use strict;
use warnings;

sub belongs_to {
  my ($class, $rel, $f_class, $cond, $attrs) = @_;
  eval "require $f_class";
  # single key relationship
  if (not defined $cond) {
    my ($pri, $too_many) = keys %{ $f_class->_primaries };
    my $acc_type = ($class->_columns->{$rel}) ? 'filter' : 'single';
    $class->add_relationship($rel, $f_class,
      { "foreign.${pri}" => "self.${rel}" },
      { accessor => $acc_type }
    );
  }
  # multiple key relationship
  else {
    my %f_primaries = %{ $f_class->_primaries };
    my $cond_rel;
    for (keys %$cond) {
      $cond_rel->{"foreign.$_"} = "self.".$cond->{$_};
      # primary key usage checks
      if (exists $f_primaries{$_}) {
        delete $f_primaries{$_};
      }
      else
      {
        $class->throw("non primary key used in join condition: $_");
      }
    }
    $class->throw("not all primary keys used in multi key relationship!") if keys %f_primaries;
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
