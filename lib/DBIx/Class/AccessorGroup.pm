package DBIx::Class::AccessorGroup;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;
use NEXT;

__PACKAGE__->mk_classdata('_accessor_group_deleted' => { });

sub mk_group_accessors {
    my($self, $group, @fields) = @_;

    $self->_mk_group_accessors('make_group_accessor', $group, @fields);
}


{
    no strict 'refs';
    no warnings 'redefine';

    sub _mk_group_accessors {
        my($self, $maker, $group, @fields) = @_;
        my $class = ref $self || $self;

        # So we don't have to do lots of lookups inside the loop.
        $maker = $self->can($maker) unless ref $maker;

        foreach my $field (@fields) {
            if( $field eq 'DESTROY' ) {
                require Carp;
                &Carp::carp("Having a data accessor named DESTROY  in ".
                             "'$class' is unwise.");
            }

            my $name = $field;

            ($name, $field) = @$field if ref $field;

            my $accessor = $self->$maker($group, $field);
            my $alias = "_${name}_accessor";

            #warn "$class $group $field $alias";

            *{$class."\:\:$name"}  = $accessor;
              #unless defined &{$class."\:\:$field"}

            *{$class."\:\:$alias"}  = $accessor;
              #unless defined &{$class."\:\:$alias"}
        }
    }
}

sub mk_group_ro_accessors {
    my($self, $group, @fields) = @_;

    $self->_mk_group_accessors('make_group_ro_accessor', $group, @fields);
}

sub mk_group_wo_accessors {
    my($self, $group, @fields) = @_;

    $self->_mk_group_accessors('make_group_wo_accessor', $group, @fields);
}

sub make_group_accessor {
    my ($class, $group, $field) = @_;

    my $set = "set_$group";
    my $get = "get_$group";

    # Build a closure around $field.
    return sub {
        my $self = shift;

        if(@_) {
            return $self->$set($field, @_);
        }
        else {
            return $self->$get($field);
        }
    };
}

sub make_group_ro_accessor {
    my($class, $group, $field) = @_;

    my $get = "get_$group";

    return sub {
        my $self = shift;

        if(@_) {
            my $caller = caller;
            require Carp;
            Carp::croak("'$caller' cannot alter the value of '$field' on ".
                        "objects of class '$class'");
        }
        else {
            return $self->$get($field);
        }
    };
}

sub make_group_wo_accessor {
    my($class, $group, $field) = @_;

    my $set = "set_$group";

    return sub {
        my $self = shift;

        unless (@_) {
            my $caller = caller;
            require Carp;
            Carp::croak("'$caller' cannot access the value of '$field' on ".
                        "objects of class '$class'");
        }
        else {
            return $self->$set($field, @_);
        }
    };
}

sub delete_accessor {
  my ($class, $accessor) = @_;
  $class = ref $class if ref $class;
  my $sym = "${class}::${accessor}";
  undef &$sym;
  delete $DB::sub{$sym};
  #$class->_accessor_group_deleted->{"${class}::${accessor}"} = 1;
}

1;
