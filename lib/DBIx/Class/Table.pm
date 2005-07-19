package DBIx::Class::Table;

use strict;
use warnings;

use base qw/Class::Data::Inheritable Class::Accessor DBIx::Class::SQL/;

__PACKAGE__->mk_classdata('_columns' => {});

__PACKAGE__->mk_classdata('_table_name');

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless({ _column_data => { } }, $class);
  if ($attrs) {
    die "attrs must be a hashref" unless ref($attrs) eq 'HASH';
    while (my ($k, $v) = each %{$attrs}) {
      $new->set($k => $v);
    }
  }
  $new->{_dirty_columns} = {};
  return $new;
}

sub insert {
  my ($self) = @_;
  return if $self->{_in_database};
  my $sth = $self->_get_sth('insert', [ keys %{$self->{_column_data}} ],
                              $self->_table_name, undef);
  $sth->execute(values %{$self->{_column_data}});
  $self->{_in_database} = 1;
  $self->{_dirty_columns} = {};
  return $self;
}

sub create {
  my ($class, $attrs) = @_;
  die "create needs a hashref" unless ref $attrs eq 'HASH';
  return $class->new($attrs)->insert;
}

sub update {
  my ($self) = @_;
  die "Not in database" unless $self->{_in_database};
  my @to_update = keys %{$self->{_dirty_columns} || {}};
  return -1 unless @to_update;
  my $sth = $self->_get_sth('update', \@to_update,
                              $self->_table_name, $self->_ident_cond);
  my $rows = $sth->execute( (map { $self->{_column_data}{$_} } @to_update),
                  $self->_ident_values );
  if ($rows == 0) {
    die "Can't update $self: row not found";
  } elsif ($rows > 1) {
    die "Can't update $self: updated more than one row";
  }
  $self->{_dirty_columns} = {};
  return $self;
}

sub delete {
  my $self = shift;
  if (ref $self) {
    my $sth = $self->_get_sth('delete', undef,
                                $self->_table_name, $self->_ident_cond);
    $sth->execute($self->_ident_values);
    $sth->finish;
    delete $self->{_in_database};
  } else {
    my $query = (ref $_[0] eq 'HASH' ? $_[0] : {@_});
    my ($cond, $param) = $self->_where_from_hash($query);
    my $sth = $self->_get_sth('delete', undef, $self->_table_name, $cond);
    $sth->execute(@$param);
    $sth->finish;
  }
  return $self;
}

sub discard_changes {
  my ($self) = @_;
  $_[0] = $self->retrieve($self->id);
}

sub get {
  my ($self, $column) = @_;
  die "Can't fetch data as class method" unless ref $self;
  #die "No such column '${column}'" unless $self->_columns->{$column};
  return $self->{_column_data}{$column} if $self->_columns->{$column};
  return shift->SUPER::get(@_);
}

sub set {
  my ($self, $column, $value) = @_;
  #die "No such column '${column}'" unless $self->_columns->{$column};
  #die "set_column called for ${column} without value" if @_ < 3;
  if ($self->_columns->{$column}) {
    $self->{_dirty_columns}{$column} = 1;
    return $self->{_column_data}{$column} = $value;
  }
  return shift->SUPER::set(@_);
}

sub _register_columns {
  my ($class, @cols) = @_;
  my $names = { %{$class->_columns} };
  $names->{$_} ||= {} for @cols;
  $class->_columns($names); 
}

sub _mk_column_accessors {
  my ($class, @cols) = @_;
  $class->mk_accessors(@cols);
}

sub set_columns {
  my ($class, @cols) = @_;
  $class->_register_columns(@cols);
  $class->_mk_column_accessors(@cols);
}

sub retrieve_from_sql {
  my ($class, $cond, @vals) = @_;
  $cond =~ s/^\s*WHERE//i;
  my @cols = $class->_select_columns;
  my $sth = $class->_get_sth( 'select', \@cols, $class->_table_name, $cond);
  $sth->execute(@vals);
  my @found;
  while (my @row = $sth->fetchrow_array) {
    my $new = $class->new;
    $new->set($_, shift @row) for @cols;
    $new->{_in_database} = 1;
    $new->{_dirty_columns} = {};
    push(@found, $new);
  }
  return @found;
}

sub search {
  my $class    = shift;
  my $where    = ref $_[0] eq "HASH" ? shift: {@_};
  my ($cond, $param)  = $class->_where_from_hash($where);
  return $class->retrieve_from_sql($cond, @{$param});
}

sub search_like {
  my $class    = shift;
  my $where    = ref $_[0] eq "HASH" ? shift: {@_};
  my ($cond, $param)  = $class->_where_from_hash($where, { cmp => 'like' });
  return $class->retrieve_from_sql($cond, @{$param});
}

sub _select_columns {
  return keys %{$_[0]->_columns};
}

sub copy {
  my ($self, $changes) = @_;
  my $new = bless({ _column_data => { %{$self->{_column_data}}} }, ref $self);
  $new->set($_ => $changes->{$_}) for keys %$changes;
  return $new->insert;
}

sub _where_from_hash {
  my ($self, $query, $opts) = @_;
  my $op = $opts->{'cmp'} || '=';
  my $cond = join(' AND ',
               map { (defined $query->{$_}
                       ? "$_ $op ?"
                       : (do { delete $query->{$_}; "$_ IS NULL"; }));
                   } keys %$query);
  return ($cond, [ values %$query ]);
}

1;
