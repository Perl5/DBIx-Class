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

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::DateTime - DateTime inflation/deflation
support for Sybase in L<DBIx::Class>.

=head1 DESCRIPTION

This needs to become L<DateTime::Format::Sybase>.

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
# vim:sts=2 sw=2:
