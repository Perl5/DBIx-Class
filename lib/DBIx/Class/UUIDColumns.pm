package DBIx::Class::UUIDColumns;
use base qw/DBIx::Class/;

__PACKAGE__->mk_classdata( 'uuid_auto_columns' => [] );
__PACKAGE__->mk_classdata( 'uuid_maker' );
__PACKAGE__->uuid_class( __PACKAGE__->_find_uuid_module );

=head1 NAME

DBIx::Class::UUIDColumns - Implicit uuid columns

=head1 SYNOPSIS

  package Artist;
  __PACKAGE__->load_components(qw/UUIDColumns Core DB/);
  __PACKAGE__->uuid_columns( 'artist_id' );

=head1 DESCRIPTION

This L<DBIx::Class> component resembles the behaviour of
L<Class::DBI::UUID>, to make some columns implicitly created as uuid.

Note that the component needs to be loaded before Core.

=head1 METHODS

=head2 uuid_columns

=cut

# be compatible with Class::DBI::UUID
sub uuid_columns {
    my $self = shift;
    for (@_) {
	$self->throw_exception("column $_ doesn't exist") unless $self->has_column($_);
    }
    $self->uuid_auto_columns(\@_);
}

sub uuid_class {
    my ($self, $class) = @_;

    if ($class) {
        $class = "DBIx::Class::UUIDMaker$class" if $class =~ /^::/;

        if (!eval "require $class") {
            $self->throw_exception("$class could not be loaded: $@");
        } elsif (!$class->isa('DBIx::Class::UUIDMaker')) {
            $self->throw_exception("$class is not a UUIDMaker subclass");
        } else {
            $self->uuid_maker($class->new);
        };
    };

    return ref $self->uuid_maker;
};

sub insert {
    my $self = shift;
    for my $column (@{$self->uuid_auto_columns}) {
	$self->store_column( $column, $self->get_uuid )
	    unless defined $self->get_column( $column );
    }
    $self->next::method(@_);
}

sub get_uuid {
    return shift->uuid_maker->as_string;
}

sub _find_uuid_module {
    if ($^O ne 'openbsd' && eval{require APR::UUID}) {
        # APR::UUID on openbsd causes some as yet unfound nastyness for XS
        return '::APR::UUID';
    } elsif (eval{require UUID}) {
        return '::UUID';
    } elsif (eval{require Data::UUID}) {
        return '::Data::UUID';
    } elsif (eval{
            # squelch the 'too late for INIT' warning in Win32::API::Type
            local $^W = 0;
            require Win32::Guidgen;
        }) {
        return '::Win32::Guidgen';
    } elsif (eval{require Win32API::GUID}) {
        return '::Win32API::GUID';
    } else {
        shift->throw_exception('no suitable uuid module could be found')
    };
};

=head1 AUTHORS

Chia-liang Kao <clkao@clkao.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
