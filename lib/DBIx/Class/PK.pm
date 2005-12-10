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

This class contains methods for handling primary keys and methods 
depending on them.

=head1 METHODS

=cut

sub _ident_cond {
  my ($class) = @_;
  return join(" AND ", map { "$_ = ?" } keys %{$class->_primaries});
}

sub _ident_values {
  my ($self) = @_;
  return (map { $self->{_column_data}{$_} } keys %{$self->_primaries});
}

=head2 set_primary_key(@cols)

Defines one or more columns as primary key for this class. Should be
called after C<columns>.

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

=head2 find(@colvalues), find(\%cols)

Finds a row based on its primary key(s).

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

=head2 discard_changes

Re-selects the row from the database, losing any changes that had
been made.

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

=head2 primary_columns

Read-only accessor which returns the list of primary keys for a class
(in scalar context, only returns the first primary key).

=cut

sub primary_columns {
  return keys %{shift->_primaries};
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

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

