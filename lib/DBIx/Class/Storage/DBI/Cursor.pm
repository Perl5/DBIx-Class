package # hide from PAUSE 
    DBIx::Class::Storage::DBI::Cursor;

use base qw/DBIx::Class::Cursor/;

use strict;
use warnings;

sub new {
  my ($class, $storage, $args, $attrs) = @_;
  #use Data::Dumper; warn Dumper(@_);
  $class = ref $class if ref $class;
  my $new = {
    storage => $storage,
    args => $args,
    pos => 0,
    attrs => $attrs,
    pid => $$,
  };

  $new->{tid} = threads->tid if $INC{'threads.pm'};
  
  return bless ($new, $class);
}

sub next {
  my ($self) = @_;

  $self->_check_forks_threads;
  if ($self->{attrs}{rows} && $self->{pos} >= $self->{attrs}{rows}) {
    $self->{sth}->finish if $self->{sth}->{Active};
    delete $self->{sth};
    $self->{done} = 1;
  }
  return if $self->{done};
  unless ($self->{sth}) {
    $self->{sth} = ($self->{storage}->_select(@{$self->{args}}))[1];
    if ($self->{attrs}{software_limit}) {
      if (my $offset = $self->{attrs}{offset}) {
        $self->{sth}->fetch for 1 .. $offset;
      }
    }
  }
  my @row = $self->{sth}->fetchrow_array;
  if (@row) {
    $self->{pos}++;
  } else {
    delete $self->{sth};
    $self->{done} = 1;
  }
  return @row;
}

sub all {
  my ($self) = @_;

  $self->_check_forks_threads;
  return $self->SUPER::all if $self->{attrs}{rows};
  $self->{sth}->finish if $self->{sth}->{Active};
  delete $self->{sth};
  my ($rv, $sth) = $self->{storage}->_select(@{$self->{args}});
  return @{$sth->fetchall_arrayref};
}

sub reset {
  my ($self) = @_;

  $self->_check_forks_threads;
  $self->{sth}->finish if $self->{sth}->{Active};
  $self->_soft_reset;
}

sub _soft_reset {
  my ($self) = @_;

  delete $self->{sth};
  $self->{pos} = 0;
  delete $self->{done};
  return $self;
}

sub _check_forks_threads {
  my ($self) = @_;

  if($INC{'threads.pm'} && $self->{tid} != threads->tid) {
      $self->_soft_reset;
      $self->{tid} = threads->tid;
  }

  if($self->{pid} != $$) {
      $self->_soft_reset;
      $self->{pid} = $$;
  }
}

sub DESTROY {
  my ($self) = @_;

  $self->_check_forks_threads;
  $self->{sth}->finish if $self->{sth}->{Active};
}

1;
