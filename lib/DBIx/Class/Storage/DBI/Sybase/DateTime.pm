package # hide from PAUSE
    DBIx::Class::Storage::DBI::Sybase::DateTime;

use strict;
use warnings;
use DateTime::Format::Strptime;

my $inflate_format = DateTime::Format::Strptime->new(
    pattern => '%Y-%m-%dT%H:%M:%S.%3NZ'
);

my $deflate_format = DateTime::Format::Strptime->new(
    pattern => '%m/%d/%Y %H:%M:%S.%3N'
);

sub parse_datetime  { shift; $inflate_format->parse_datetime(@_) }

sub format_datetime { shift; $deflate_format->format_datetime(@_) }

1;
