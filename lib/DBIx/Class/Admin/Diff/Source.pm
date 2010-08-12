package DBIx::Class::Schema::Diff::Source;

=head1 NAME

DBIx::Class::Schema::Diff::Source - Database schema sources

=head1 SYNOPSIS

    my $obj = DBIx::Class::Schema::Diff::Source->new(
        class => $str,
        sqltranslator => SQL::Translator->new(...),
    );

=cut

use Carp::Clan qw/^DBIx::Class/;
use SQL::Translator;
use Moose;

=head1 ATTRIBUTES

=head2 class

This attribute holds the classname of a L<DBIx::Class> schema.

=cut

has class => (
    is => 'ro',
    isa => 'Str', # Class?
    required => 1,
);

=head2 sqltranslator

Holds an L<SQL::Translator> object, either autobuilt or given when
constructing the object.

=cut

has sqltranslator => (
    is => 'ro',
    isa => 'SQL::Translator',
    lazy_build => 1,
    handles => {
        reset => 'reset',
        schema => 'schema',
    },
);

sub _build_sqltranslator {
    return SQL::Translator->new(
        add_drop_table => 1,
        ignore_constraint_names => 1,
        ignore_index_names => 1,
        parser => 'SQL::Translator::Parser::DBIx::Class',
        producer => $_[0]->producer,
        # more args...?
    );
}

=head2 version

Holds the database schema. Either generated from L</class> or
given in constructor.

=cut

has version => (
    is => 'ro',
    isa => 'Num',
    lazy_build => 1,
);

sub _build_version {
    my $class = shift->class;
    my $version;

    if($class->can('meta')) {
        return $class->meta->version || '0';
    }
    elsif($version = eval "no strict; \$$class\::VERSION") {
        return $version;
    }

    return 0;
}

=head2 producer

Alias for L<SQL::Translator::producer()>, but will always return the
producer as a string.

=cut

has producer => (
    is => 'rw',
    isa => 'Str',
    default => 'SQLite',
    trigger => sub { $_[0]->sqltranslator->producer($_[1]) },
);

=head2 schema

Proxy for L<SQL::Translator::schema()>.

=head1 METHODS

=head2 translate

    $text = $self->translate;

Will return generated SQL.

=cut

sub translate {
    my $self = shift;

    return $self->sqltranslator->translate({ data => $self->class });
}

=head2 filename

    $path = $self->filename($directory);
    $path = $self->filename($directory, $preversion);

Returns a filename relative to the given L<$directory>.

=cut

sub filename {
    my $self = shift;
    my $directory = shift;
    my $preversion = shift;
    my $class = $self->class;
    my $version = $self->version;
    my($obj, $filename);

    # ddl_filename() does ref($obj) to find filename
    $obj = bless {}, $class;

    $filename = $obj->ddl_filename($self->producer, $version, $directory);
    $filename =~ s/$version/$preversion\-$version/ if(defined $preversion);

    return $filename;
}

=head2 schema_to_file

    $bool = $self->schema_to_file($filename);
    $bool = $self->schema_to_file($directory);

Will dump schema as SQL to a given C<$filename> or use the L</filename>
attribute by default.

=cut

sub schema_to_file {
    my $self = shift;
    my $file = shift or return;
    my $text = $self->translate or return;
    my $OUT;

    if(ref $file eq '' and -d $file) {
        $file = $self->filename($file) or return;
    }

    open $OUT, '>', $file or croak "Cannot write to ($file): $!";
    print $OUT $text or croak "Cannot write to ($file) filehandle: $!";

    return 1;
}

=head2 reset

Proxy for L<SQL::Translator::reset()>.

=head1 BUGS

=head1 COPYRIGHT & LICENSE

=head1 AUTHOR

See L<DBIx::Class::Schema::Diff>.

=cut

1;
