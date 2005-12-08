package DBIx::Class::PK;

use strict;
use warnings;
use Tie::IxHash;

use base qw/DBIx::Class::Row/;

__PACKAGE__->mk_classdata('_primaries' => {});

=head1 NAME 

DBIx::Class::PK - Primary Key class

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents methods handling primary keys
and depending on them.

=head1 METHODS

=over 4

=cut

sub _ident_cond {
  my ($class) = @_;
  return join(" AND ", map { "$_ = ?" } keys %{$class->_primaries});
}

sub _ident_values {
  my ($self) = @_;
  return (map { $self->{_column_data}{$_} } keys %{$self->_primaries});
}

=item set_primary_key <@cols>

define one or more columns as primary key for this class

=cut

sub set_primary_key {
  my ($class, @cols) = @_;
  # check if primary key columns are valid columns
  for (@cols) {
    $class->throw( "Column $_ can't be used as primary key because it isn't defined in $class" )
      unless $class->has_column($_);
  }
  my %pri;
  tie %pri, 'Tie::IxHash', map { $_ => {} } @cols;
  $class->_primaries(\%pri);
}

=item find

Finds columns based on the primary key(s).

=cut

sub find {
  my ($class, @vals) = @_;
  my $attrs = (@vals > 1 && ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});
  my @pk = keys %{$class->_primaries};
  $class->throw( "Can't find unless primary columns are defined" ) 
    unless @pk;
  my $query;
  if (ref $vals[0] eq 'HASH') {
    $query = $vals[0];
  } elsif (@pk == @vals) {
    $query = {};
    @{$query}{@pk} = @vals;
    #my $ret = ($class->search_literal($class->_ident_cond, @vals, $attrs))[0];
    #warn "$class: ".join(', ', %{$ret->{_column_data}});
    #return $ret;
  } else {
    $query = {@vals};
  }
  $class->throw( "Can't find unless all primary keys are specified" )
    unless (keys %$query >= @pk); # If we check 'em we run afoul of uc/lc
                                  # column names etc. Not sure what to do yet
  #return $class->search($query)->next;
  my @cols = $class->_select_columns;
  my @row = $class->storage->select_single($class->_table_name, \@cols, $query);
  return (@row ? $class->_row_to_object(\@cols, \@row) : ());
}

=item discard_changes

Roll back changes that hasn't been comitted to the database.

=cut

sub discard_changes {
  my ($self) = @_;
  delete $self->{_dirty_columns};
  return unless $self->in_storage; # Don't reload if we aren't real!
  my ($reload) = $self->find($self->id);
  unless ($reload) { # If we got deleted in the mean-time
    $self->in_storage(0);
    return $self;
  }
  delete @{$self}{keys %$self};
  @{$self}{keys %$reload} = values %$reload;
  return $self;
}

=item id

returns the primary key(s) for the current row. Can't be called as
a class method.

=cut

sub id {
  my ($self) = @_;
  $self->throw( "Can't call id() as a class method" ) unless ref $self;
  my @pk = $self->_ident_values;
  return (wantarray ? @pk : $pk[0]);
}

=item  primary_columns

read-only accessor which returns a list of primary keys.

=cut

sub primary_columns {
  return keys %{shift->_primaries};
}

sub ID {
  my ($self) = @_;
  $self->throw( "Can't call ID() as a class method" ) unless ref $self;
  return undef unless $self->in_storage;
  return $self->_create_ID(map { $_ => $self->{_column_data}{$_} } keys %{$self->_primaries});
}

sub _create_ID {
  my ($class,%vals) = @_;
  return undef unless 0 == grep { !defined } values %vals;
  $class = ref $class || $class;
  return join '|', $class, map { $_ . '=' . $vals{$_} } sort keys %vals;    
}

sub ident_condition {
  my ($self) = @_;
  my %cond;
  $cond{$_} = $self->get_column($_) for $self->primary_columns;
  return \%cond;
}

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

