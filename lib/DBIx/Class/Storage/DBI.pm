package DBIx::Class::Storage::DBI;

use DBI;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/SQL::Abstract SQL Exception AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' => qw/connect_info _dbh/);

sub new {
  bless({}, ref $_[0] || $_[0]);
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

sub insert {
  my ($self, $ident, $to_insert) = @_;
  my $sql = $self->create_sql('insert', [ keys %{$to_insert} ], $ident, undef);
  my $sth = $self->sth($sql);
  $sth->execute(values %{$to_insert});
  $self->throw( "Couldn't insert ".join(%to_insert)." into ${ident}" )
    unless $sth->rows;
  return $to_insert;
}

sub update {
  my ($self, $ident, $to_update, $condition) = @_;
  my $attrs = { };
  my $set_sql = $self->_cond_resolve($to_update, $attrs, ',');
  $set_sql =~ s/^\(//;
  $set_sql =~ s/\)$//;
  my $cond_sql = $self->_cond_resolve($condition, $attrs);
  my $sql = $self->create_sql('update', $set_sql, $ident, $cond_sql);
  my $sth = $self->sth($sql);
  my $rows = $sth->execute( @{$attrs->{bind}||[]} );
  return $rows;
}

sub delete {
  my ($self, $ident, $condition) = @_;
  my $attrs = { };
  my $cond_sql = $self->_cond_resolve($condition, $attrs);
  my $sql = $self->create_sql('delete', undef, $ident, $cond_sql);
  #warn "$sql ".join(', ',@{$attrs->{bind}||[]});
  my $sth = $self->sth($sql);
  return $sth->execute( @{$attrs->{bind}||[]} );
}

sub select {
  my ($self, $ident, $select, $condition, $attrs) = @_;
  $attrs ||= { };
  #my $select_sql = $self->_cond_resolve($select, $attrs, ',');
  my $cond_sql = $self->_cond_resolve($condition, $attrs);
  1 while $cond_sql =~ s/^\s*\(\s*(.*ORDER.*)\s*\)\s*$/$1/;
  my $sql = $self->create_sql('select', $select, $ident, $cond_sql);
  #warn $sql.' '.join(', ', @{$attrs->{bind}||[]});
  my $sth = $self->sth($sql);
  if (@{$attrs->{bind}||[]}) {
    $sth->execute( @{$attrs->{bind}||[]} );
  } else {
    $sth->execute;
  }
  return $sth;
}

sub sth {
  shift->dbh->prepare(@_);
}

1;

=back

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

