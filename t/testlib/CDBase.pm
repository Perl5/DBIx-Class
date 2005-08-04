package CDBase;

use strict;
use base qw(DBIx::Class);
__PACKAGE__->load_components(qw/CDBICompat Core/);

use File::Temp qw/tempfile/;
my (undef, $DB) = tempfile();
my @DSN = ("dbi:SQLite:dbname=$DB", '', '', { AutoCommit => 1 });

END { unlink $DB if -e $DB }

__PACKAGE__->connection(@DSN);

1;
