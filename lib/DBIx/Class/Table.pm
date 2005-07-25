package DBIx::Class::Table;

use strict;
use warnings;

use base qw/Class::Data::Inheritable DBIx::Class::SQL/;

__PACKAGE__->mk_classdata('_columns' => {});

__PACKAGE__->mk_classdata('_table_name');

__PACKAGE__->mk_classdata('table_alias'); # FIXME XXX

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless({ _column_data => { } }, $class);
  if ($attrs) {
    die "attrs must be a hashref" unless ref($attrs) eq 'HASH';
    while (my ($k, $v) = each %{$attrs}) {
      $new->store_column($k => $v);
    }
  }
  return $new;
}

sub insert {
  my ($self) = @_;
  return if $self->{_in_database};
  my $sth = $self->_get_sth('insert', [ keys %{$self->{_column_data}} ],
                              $self->_table_name, undef);
  $sth->execute(values %{$self->{_column_data}});
  $sth->finish;
  $self->{_in_database} = 1;
  $self->{_dirty_columns} = {};
  return $self;
}

sub in_database {
  return $_[0]->{_in_database};
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
  $sth->finish;
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
    die "Not in database" unless $self->{_in_database};
    #warn $self->_ident_cond.' '.join(', ', $self->_ident_values);
    my $sth = $self->_get_sth('delete', undef,
                                $self->_table_name, $self->_ident_cond);
    $sth->execute($self->_ident_values);
    $sth->finish;
    delete $self->{_in_database};
  } else {
    my $attrs = { };
    if (@_ > 1 && ref $_[$#_] eq 'HASH') {
      $attrs = { %{ pop(@_) } };
    }
    my $query = (ref $_[0] eq 'HASH' ? $_[0] : {@_});
    my ($cond, @param) = $self->_cond_resolve($query, $attrs);
    my $sth = $self->_get_sth('delete', undef, $self->_table_name, $cond);
    $sth->execute(@param);
    $sth->finish;
  }
  return $self;
}

sub get_column {
  my ($self, $column) = @_;
  die "Can't fetch data as class method" unless ref $self;
  die "No such column '${column}'" unless $self->_columns->{$column};
  return $self->{_column_data}{$column} if $self->_columns->{$column};
}

sub set_column {
  my $self = shift;
  my ($column) = @_;
  my $ret = $self->store_column(@_);
  $self->{_dirty_columns}{$column} = 1;
  return $ret;
}

sub store_column {
  my ($self, $column, $value) = @_;
  die "No such column '${column}'" unless $self->_columns->{$column};
  die "set_column called for ${column} without value" if @_ < 3;
  return $self->{_column_data}{$column} = $value;
}

sub _register_columns {
  my ($class, @cols) = @_;
  my $names = { %{$class->_columns} };
  $names->{$_} ||= {} for @cols;
  $class->_columns($names); 
}

sub _mk_column_accessors {
  my ($class, @cols) = @_;
  $class->mk_group_accessors('column' => @cols);
}

sub add_columns {
  my ($class, @cols) = @_;
  $class->_register_columns(@cols);
  $class->_mk_column_accessors(@cols);
}

sub retrieve_from_sql {
  my ($class, $cond, @vals) = @_;
  $cond =~ s/^\s*WHERE//i;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});
  my @cols = $class->_select_columns($attrs);
  my $sth = $class->_get_sth( 'select', \@cols, $class->_table_name, $cond);
  #warn "$cond @vals";
  return $class->sth_to_objects($sth, \@vals, \@cols);
}

sub sth_to_objects {
  my ($class, $sth, $args, $cols) = @_;
  my @cols = ((ref $cols eq 'ARRAY') ? @$cols : @{$sth->{NAME_lc}} );
  $sth->execute(@$args);
  my @found;
  while (my @row = $sth->fetchrow_array) {
    my $new = $class->new;
    $new->store_column($_, shift @row) for @cols;
    $new->{_in_database} = 1;
    push(@found, $new);
  }
  $sth->finish;
  return @found;
}

sub search {
  my $class = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $query    = ref $_[0] eq "HASH" ? shift: {@_};
  my ($cond, @param)  = $class->_cond_resolve($query, $attrs);
  return $class->retrieve_from_sql($cond, @param);
}

sub search_like {
  my $class    = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = pop(@_);
  }
  return $class->search(@_, { %$attrs, cmp => 'LIKE' });
}

sub _select_columns {
  return keys %{$_[0]->_columns};
}

sub copy {
  my ($self, $changes) = @_;
  my $new = bless({ _column_data => { %{$self->{_column_data}}} }, ref $self);
  $new->set_column($_ => $changes->{$_}) for keys %$changes;
  return $new->insert;
}

sub _cond_resolve {
  my ($self, $query, $attrs) = @_;
  return '1 = 1' unless keys %$query;
  my $op = $attrs->{'cmp'} || '=';
  my $cond = join(' AND ',
               map { (defined $query->{$_}
                       ? "$_ $op ?"
                       : (do { delete $query->{$_}; "$_ IS NULL"; }));
                   } keys %$query);
  return ($cond, values %$query);
}

sub table {
  shift->_table_name(@_);
}

1;
