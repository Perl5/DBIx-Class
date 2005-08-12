package DBIx::Class::Storage::DBI;

use strict;
use warnings;
use DBI;
use SQL::Abstract::Limit;
use DBIx::Class::Storage::DBI::Cursor;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/Exception AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/connect_info _dbh _sql_maker debug cursor/);

sub new {
  my $new = bless({}, ref $_[0] || $_[0]);
  $new->cursor("DBIx::Class::Storage::DBI::Cursor");
  $new->debug(1) if $ENV{DBIX_CLASS_STORAGE_DBI_DEBUG};
  return $new;
}

sub get_simple {
  my ($self, $get) = @_;
  return $self->{$get};
}

sub set_simple {
  my ($self, $set, $val) = @_;
  return $self->{$set} = $val;
}

=head1 NAME 

DBIx::Class::Storage::DBI - DBI storage handler

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the connection to the database

=head1 METHODS

=over 4

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
  my $maker;
  unless ($maker = $self->_sql_maker) {
    $self->_sql_maker(new SQL::Abstract::Limit( limit_dialect => $self->dbh ));
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

=item commit

  $class->commit;

Issues a commit again the current dbh

=cut

sub commit { $_[0]->dbh->commit; }

=item rollback

  $class->rollback;

Issues a rollback again the current dbh

=cut

sub rollback { $_[0]->dbh->rollback; }

sub _execute {
  my ($self, $op, $extra_bind, $ident, @args) = @_;
  my ($sql, @bind) = $self->sql_maker->$op($ident, @args);
  unshift(@bind, @$extra_bind) if $extra_bind;
  warn "$sql: @bind" if $self->debug;
  my $sth = $self->sth($sql);
  @bind = map { ref $_ ? ''.$_ : $_ } @bind; # stringify args
  my $rv = $sth->execute(@bind);
  return (wantarray ? ($rv, $sth, @bind) : $rv);
}

sub insert {
  my ($self, $ident, $to_insert) = @_;
  $self->throw( "Couldn't insert ".join(', ', map "$_ => $to_insert->{$_}", keys %$to_insert)." into ${ident}" )
    unless ($self->_execute('insert' => [], $ident, $to_insert) > 0);
  return $to_insert;
}

sub update {
  return shift->_execute('update' => [], @_);
}

sub delete {
  return shift->_execute('delete' => [], @_);
}

sub select {
  my ($self, $ident, $select, $condition, $attrs) = @_;
  my $order = $attrs->{order_by};
  if (ref $condition eq 'SCALAR') {
    $order = $1 if $$condition =~ s/ORDER BY (.*)$//i;
  }
  my ($rv, $sth, @bind) = $self->_execute('select', $attrs->{bind}, $ident, $select, $condition, $order, $attrs->{rows}, $attrs->{offset});
  return $self->cursor->new($sth, \@bind, $attrs);
}

sub select_single {
  my ($self, $ident, $select, $condition, $attrs) = @_;
  my $order = $attrs->{order_by};
  if (ref $condition eq 'SCALAR') {
    $order = $1 if $$condition =~ s/ORDER BY (.*)$//i;
  }
  my ($rv, $sth, @bind) = $self->_execute('select', $attrs->{bind}, $ident, $select, $condition, $order, 1, $attrs->{offset});
  return $sth->fetchrow_array;
}

sub sth {
  shift->dbh->prepare(@_);
}

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

