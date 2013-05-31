package # Hide from PAUSE
  DBIx::Class::SQLMaker::MSSQL;

use warnings;
use strict;

use base qw( DBIx::Class::SQLMaker );

#
# MSSQL does not support ... OVER() ... RNO limits
#
sub _rno_default_order {
  return \ '(SELECT(1))';
}

# more or less copy pasted directly from ::SQLMaker
sub insert {
  my $self    = shift;
  my $table   = $self->_table(shift);
  my $data    = shift || return;
  my $options = shift;

  if (! $data or (ref $data eq 'HASH' and !keys %{$data} ) ) {
    my @bind;
    my $sql = sprintf(
      'INSERT INTO %s DEFAULT VALUES', $_[0]->_quote($table)
    );

    if ( ($options||{})->{returning} ) {
      my $s;
      ($s, @bind) = $self->_insert_returning ($options);
      $sql .= $s;
    }

    return ($sql, @bind);
  }

  my $method = $self->_METHOD_FOR_refkind("_insert", $data);
  my ($sql, @bind) = $self->$method($data);

  $sql = join " ", $self->_sqlcase('insert into'), $table, $sql;

  if ($options->{returning}) {
    my ($s, @b) = $self->_insert_returning ($options);
    $sql =~ s/\bVALUES\b/$s VALUES/;
    @bind = (@b, @bind);
  }

  return wantarray ? ($sql, @bind) : $sql;
}


# insert returning docs at
# http://msdn.microsoft.com/en-us/library/ms177564.aspx

sub _insert_returning {
  my ($self, $options) = @_;

  my $f = $options->{returning};

  my @f_list = do {
    if (! ref $f) {
      ($f)
    }
    elsif (ref $f eq 'ARRAY') {
      @$f
    }
    elsif (ref $f eq 'SCALAR') {
      (
        ($$f)
      )
    }
    else {
      $self->throw_exception("Unsupported INSERT RETURNING option $f");
    }
  };

  return (
    join ' ',
    $self->_sqlcase(' output'),
    join ', ',
    map $self->_quote("INSERTED.$_"), @f_list,
  );
}

1
