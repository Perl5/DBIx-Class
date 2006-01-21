package DBIx::Class::Storage::DBI;

use strict;
use warnings;
use DBI;
use SQL::Abstract::Limit;
use DBIx::Class::Storage::DBI::Cursor;

BEGIN {

package DBIC::SQL::Abstract; # Would merge upstream, but nate doesn't reply :(

use base qw/SQL::Abstract::Limit/;

sub select {
  my ($self, $table, $fields, $where, $order, @rest) = @_;
  @rest = (-1) unless defined $rest[0];
  $self->SUPER::select($table, $self->_recurse_fields($fields), 
                         $where, $order, @rest);
}

sub _emulate_limit {
  my $self = shift;
  if ($_[3] == -1) {
    return $_[1].$self->_order_by($_[2]);
  } else {
    return $self->SUPER::_emulate_limit(@_);
  }
}

sub _recurse_fields {
  my ($self, $fields) = @_;
  my $ref = ref $fields;
  return $self->_quote($fields) unless $ref;
  return $$fields if $ref eq 'SCALAR';

  if ($ref eq 'ARRAY') {
    return join(', ', map { $self->_recurse_fields($_) } @$fields);
  } elsif ($ref eq 'HASH') {
    foreach my $func (keys %$fields) {
      return $self->_sqlcase($func)
        .'( '.$self->_recurse_fields($fields->{$func}).' )';
    }
  }
}

sub _order_by {
  my $self = shift;
  my $ret = '';
  if (ref $_[0] eq 'HASH') {
    if (defined $_[0]->{group_by}) {
      $ret = $self->_sqlcase(' group by ')
               .$self->_recurse_fields($_[0]->{group_by});
    }
    if (defined $_[0]->{order_by}) {
      $ret .= $self->SUPER::_order_by($_[0]->{order_by});
    }
  } else {
    $ret = $self->SUPER::_order_by(@_);
  }
  return $ret;
}

sub _table {
  my ($self, $from) = @_;
  if (ref $from eq 'ARRAY') {
    return $self->_recurse_from(@$from);
  } elsif (ref $from eq 'HASH') {
    return $self->_make_as($from);
  } else {
    return $from;
  }
}

sub _recurse_from {
  my ($self, $from, @join) = @_;
  my @sqlf;
  push(@sqlf, $self->_make_as($from));
  foreach my $j (@join) {
    my ($to, $on) = @$j;

    # check whether a join type exists
    my $join_clause = '';
    if (ref($to) eq 'HASH' and exists($to->{-join_type})) {
      $join_clause = ' '.uc($to->{-join_type}).' JOIN ';
    } else {
      $join_clause = ' JOIN ';
    }
    push(@sqlf, $join_clause);

    if (ref $to eq 'ARRAY') {
      push(@sqlf, '(', $self->_recurse_from(@$to), ')');
    } else {
      push(@sqlf, $self->_make_as($to));
    }
    push(@sqlf, ' ON ', $self->_join_condition($on));
  }
  return join('', @sqlf);
}

sub _make_as {
  my ($self, $from) = @_;
  return join(' ', map { (ref $_ eq 'SCALAR' ? $$_ : $self->_quote($_)) }
                           reverse each %{$self->_skip_options($from)});
}

sub _skip_options {
  my ($self, $hash) = @_;
  my $clean_hash = {};
  $clean_hash->{$_} = $hash->{$_}
    for grep {!/^-/} keys %$hash;
  return $clean_hash;
}

sub _join_condition {
  my ($self, $cond) = @_;
  if (ref $cond eq 'HASH') {
    my %j;
    for (keys %$cond) { my $x = '= '.$self->_quote($cond->{$_}); $j{$_} = \$x; };
    return $self->_recurse_where(\%j);
  } elsif (ref $cond eq 'ARRAY') {
    return join(' OR ', map { $self->_join_condition($_) } @$cond);
  } else {
    die "Can't handle this yet!";
  }
}

sub _quote {
  my ($self, $label) = @_;
  return '' unless defined $label;
  return $self->SUPER::_quote($label);
}

} # End of BEGIN block

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/Exception AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/connect_info _dbh _sql_maker debug cursor/);

our $TRANSACTION = 0;

sub new {
  my $new = bless({}, ref $_[0] || $_[0]);
  $new->cursor("DBIx::Class::Storage::DBI::Cursor");
  $new->debug(1) if $ENV{DBIX_CLASS_STORAGE_DBI_DEBUG};
  return $new;
}

=head1 NAME 

DBIx::Class::Storage::DBI - DBI storage handler

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the connection to the database

=head1 METHODS

=cut

sub dbh {
  my ($self) = @_;
  my $dbh;
  unless (($dbh = $self->_dbh) && $dbh->FETCH('Active') && $dbh->ping) {
    $self->_populate_dbh;
  }
  return $self->_dbh;
}

sub sql_maker {
  my ($self) = @_;
  unless ($self->_sql_maker) {
    $self->_sql_maker(new DBIC::SQL::Abstract( limit_dialect => $self->dbh ));
  }
  return $self->_sql_maker;
}

sub _populate_dbh {
  my ($self) = @_;
  my @info = @{$self->connect_info || []};
  $self->_dbh($self->_connect(@info));
}

sub _connect {
  my ($self, @info) = @_;
  return DBI->connect(@info);
}

=head2 txn_begin

Calls begin_work on the current dbh.

=cut

sub txn_begin {
  $_[0]->dbh->begin_work if $TRANSACTION++ == 0 and $_[0]->dbh->{AutoCommit};
}

=head2 txn_commit

Issues a commit against the current dbh.

=cut

sub txn_commit {
  if ($TRANSACTION == 0) {
    $_[0]->dbh->commit;
  }
  else {
    $_[0]->dbh->commit if --$TRANSACTION == 0;    
  }
}

=head2 txn_rollback

Issues a rollback against the current dbh.

=cut

sub txn_rollback {
  if ($TRANSACTION == 0) {
    $_[0]->dbh->rollback;
  }
  else {
    --$TRANSACTION == 0 ? $_[0]->dbh->rollback : die $@;    
  }
}

sub _execute {
  my ($self, $op, $extra_bind, $ident, @args) = @_;
  my ($sql, @bind) = $self->sql_maker->$op($ident, @args);
  unshift(@bind, @$extra_bind) if $extra_bind;
  warn "$sql: @bind" if $self->debug;
  my $sth = $self->sth($sql,$op);
  @bind = map { ref $_ ? ''.$_ : $_ } @bind; # stringify args
  my $rv = $sth->execute(@bind);
  return (wantarray ? ($rv, $sth, @bind) : $rv);
}

sub insert {
  my ($self, $ident, $to_insert) = @_;
  $self->throw( "Couldn't insert ".join(', ', map "$_ => $to_insert->{$_}", keys %$to_insert)." into ${ident}" )
    unless ($self->_execute('insert' => [], $ident, $to_insert));
  return $to_insert;
}

sub update {
  return shift->_execute('update' => [], @_);
}

sub delete {
  return shift->_execute('delete' => [], @_);
}

sub _select {
  my ($self, $ident, $select, $condition, $attrs) = @_;
  my $order = $attrs->{order_by};
  if (ref $condition eq 'SCALAR') {
    $order = $1 if $$condition =~ s/ORDER BY (.*)$//i;
  }
  if (exists $attrs->{group_by}) {
    $order = { group_by => $attrs->{group_by},
               ($order ? (order_by => $order) : ()) };
  }
  my @args = ('select', $attrs->{bind}, $ident, $select, $condition, $order);
  if ($attrs->{software_limit} ||
      $self->sql_maker->_default_limit_syntax eq "GenericSubQ") {
        $attrs->{software_limit} = 1;
  } else {
    push @args, $attrs->{rows}, $attrs->{offset};
  }
  return $self->_execute(@args);
}

sub select {
  my $self = shift;
  my ($ident, $select, $condition, $attrs) = @_;
  return $self->cursor->new($self, \@_, $attrs);
}

sub select_single {
  my $self = shift;
  my ($rv, $sth, @bind) = $self->_select(@_);
  return $sth->fetchrow_array;
}

sub sth {
  my ($self, $sql) = @_;
  # 3 is the if_active parameter which avoids active sth re-use
  return $self->dbh->prepare_cached($sql, {}, 3);
}

=head2 columns_info_for

Returns database type info for a given table columns.

=cut

sub columns_info_for {
    my ($self, $table) = @_;
    my $sth = $self->dbh->prepare("SELECT * FROM $table WHERE 1=0");
    $sth->execute;
    my %result;
    my @columns = @{$sth->{NAME}};
    for my $i ( 0 .. $#columns ){
        my $type = $sth->{TYPE}->[$i];
        my $info = $self->dbh->type_info($type);
        my %column_info;
        if ( $info ){
            $column_info{data_type} = $info->{TYPE_NAME};
            $column_info{size} = $info->{COLUMN_SIZE};
            $column_info{is_nullable} = $info->{NULLABLE};
        }else{
            $column_info{data_type} = $type;
        }
        $result{$columns[$i]} = \%column_info;
    }
    return \%result;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

