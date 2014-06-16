use strict;
use warnings;
use Test::More;

INIT {
    use lib 't/cdbi/testlib';
    require Film;
}

sub Film::get_test {
    my $self = shift;
    my $key = shift;
    $self->{get_test}++;
    return $self->{$key};
}

sub Film::set_test {
    my($self, $key, $val) = @_;
    $self->{set_test}++;
    return $self->{$key} = $val;
}


my $film = Film->create({ Title => "No Wolf McQuade" });

# Test mk_group_accessors() with a list of fields.
{
    Film->mk_group_accessors(test => qw(foo bar));
    $film->foo(42);
    is $film->foo, 42;

    $film->bar(23);
    is $film->bar, 23;
}


# An explicit accessor passed to mk_group_accessors should
# ignore accessor/mutator_name_for.
sub Film::accessor_name_for {
    my($class, $col) = @_;
    return "hlaglagh" if $col eq "wibble";
    return $col;
}

sub Film::mutator_name_for {
    my($class, $col) = @_;
    return "hlaglagh" if $col eq "wibble";
    return $col;
}


# Test with a mix of fields and field specs
{
    Film->mk_group_accessors(test => ("baz", [wibble_thing => "wibble"]));
    $film->baz(42);
    is $film->baz, 42;

    $film->wibble_thing(23);
    is $film->wibble_thing, 23;
}

done_testing;
