package # hide package from pause
  DBIx::Class::PK::Auto::Oracle;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

1;

=head1 NAME

DBIx::Class::PK::Auto::Oracle - (DEPRECATED) Automatic primary key class for Oracle

=head1 SYNOPSIS

Just load PK::Auto instead; auto-inc is now handled by Storage.

=head1 AUTHOR AND CONTRIBUTORS

See L<AUTHOR|DBIx::Class/AUTHOR> and L<CONTRIBUTORS|DBIx::Class/CONTRIBUTORS> in DBIx::Class

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
