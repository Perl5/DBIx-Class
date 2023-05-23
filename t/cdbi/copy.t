use strict;
use warnings;
use Test::More;

INIT {
    use lib 't/cdbi/testlib';
}

{
    package # hide from PAUSE
        MyFilm;

    use base 'DBIC::Test::SQLite';
    use strict;

    __PACKAGE__->set_table('Movies');
    __PACKAGE__->columns(All => qw(id title));

    # Disables the implicit autoinc-on-non-supplied-pk behavior
    # (and the warning that goes with it)
    # This is the same behavior as it was pre 0.082900
    __PACKAGE__->column_info('id')->{is_auto_increment} = 0;

    sub create_sql {
        return qq{
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                title           VARCHAR(255)
        }
    }
}

my $film = MyFilm->create({ title => "For Your Eyes Only" });
ok $film->id;

my $new_film = $film->copy;
ok $new_film->id;
isnt $new_film->id, $film->id, "copy() gets new primary key";

$new_film = $film->copy(42);
is $new_film->id, 42, "copy() with new id";

done_testing;
