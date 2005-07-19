package DBIx::Class::CDBICompat::AutoUpdate;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('__AutoCommit');

sub set {
  my $self = shift;
  $self->NEXT::set(@_);
  $self->update if ($self->autoupdate && $self->{_in_database});
}

sub autoupdate {
        my $proto = shift;
        ref $proto
          ? $proto->_obj_autoupdate(@_)
          : $proto->_class_autoupdate(@_) ;
}

sub _obj_autoupdate {
        my ($self, $set) = @_;
        my $class = ref $self;
        $self->{__AutoCommit} = $set if defined $set;
        defined $self->{__AutoCommit}
                ? $self->{__AutoCommit}
                : $class->_class_autoupdate;
}

sub _class_autoupdate {
        my ($class, $set) = @_;
        $class->__AutoCommit($set) if defined $set;
        return $class->__AutoCommit;
}

1;
