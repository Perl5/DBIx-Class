package # Hide from PAUSE
    ImplicitInflate;

# Test class for the testing of Implicit inflation
# in CDBI Classes using Compat layer
# See t/cdbi/70-implicit_inflate.t

use strict;
use warnings;

use base 'DBIC::Test::SQLite';

__PACKAGE__->set_table('Date');

__PACKAGE__->columns(Primary    => 'id');
__PACKAGE__->columns(All        => qw/ update_datetime text/);

__PACKAGE__->has_a(
    update_datetime => 'MyDateStamp',
);

sub create_sql {
       # SQLite doesn't support Datetime datatypes.
    return qq{
        id              INTEGER PRIMARY KEY,
        update_datetime TEXT,
        text            VARCHAR(20)
    }
}

{
    package MyDateStamp;

    use DateTime::Format::SQLite;

    sub new {
        my ($self, $value) = @_;
        return DateTime::Format::SQLite->parse_datetime($value);
    }
}

1;
