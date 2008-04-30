package DBIx::Class::Storage::DBI::Replicated::Replicant;

use Moose;
extends 'DBIx::Class::Storage::DBI', 'Moose::Object';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::Replicant; A replicated DBI Storage

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.  You
shouldn't need to create instances of this class.
    
=head1 DESCRIPTION

Replicants are DBI Storages that follow a master DBI Storage.  Typically this
is accomplished via an external replication system.  Please see the documents
for L<DBIx::Class::Storage::DBI::Replicated> for more details.

This class exists to define methods of a DBI Storage that only make sense when
it's a classic 'slave' in a pool of slave databases which replicate from a
given master database.

=head1 ATTRIBUTES

This class defines the following attributes.

=head1 METHODS

This class defines the following methods.

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut