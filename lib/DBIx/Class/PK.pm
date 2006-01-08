package DBIx::Class::PK;

use strict;
use warnings;
use Tie::IxHash;

use base qw/DBIx::Class::Row/;

=head1 NAME 

DBIx::Class::PK - Primary Key class

=head1 SYNOPSIS

=head1 DESCRIPTION

This class contains methods for handling primary keys and methods 
depending on them.

=head1 METHODS

=cut

sub _ident_cond {
  my ($class) = @_;
  return join(" AND ", map { "$_ = ?" } $class->primary_columns);
}

sub _ident_values {
  my ($self) = @_;
  return (map { $self->{_column_data}{$_} } $self->primary_columns);
}

=head2 discard_changes

Re-selects the row from the database, losing any changes that had
been made.

=cut

sub discard_changes {
  my ($self) = @_;
  delete $self->{_dirty_columns};
  return unless $self->in_storage; # Don't reload if we aren't real!
  my ($reload) = $self->find(map { $self->$_ } $self->primary_columns);
  unless ($reload) { # If we got deleted in the mean-time
    $self->in_storage(0);
    return $self;
  }
  delete @{$self}{keys %$self};
  @{$self}{keys %$reload} = values %$reload;
  return $self;
}

=head2 id

Returns the primary key(s) for a row. Can't be called as
a class method.

=cut

sub id {
  my ($self) = @_;
  $self->throw( "Can't call id() as a class method" ) unless ref $self;
  my @pk = $self->_ident_values;
  return (wantarray ? @pk : $pk[0]);
}

=head2 ID

Returns a unique id string identifying a row object by primary key.
Used by L<DBIx::Class::CDBICompat::LiveObjectIndex> and 
L<DBIx::Class::ObjectCache>.

=cut

sub ID {
  my ($self) = @_;
  $self->throw( "Can't call ID() as a class method" ) unless ref $self;
  return undef unless $self->in_storage;
  return $self->_create_ID(map { $_ => $self->{_column_data}{$_} } $self->primary_columns);
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

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

