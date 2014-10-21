package DBIx::Class::Storage::DBI::SetConstraintsDeferred;

use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI';
use mro 'c3';

use Scope::Guard ();
use Context::Preserve 'preserve_context';

use namespace::clean;

=head1 NAME

DBIx::Class::Storage::DBI::SetConstraintsDeferred - Storage component for deferred constraints via C<SET CONSTRAINTS>

=head1 DESCRIPTION

This component implements L<DBIx::Class::Storage::DBI/with_deferred_fk_checks>
by wrapping the the coderef in C<SET CONSTRAINTS ALL DEFERRED> and
C<SET CONSTRAINTS ALL IMMEDIATE>.

=cut

sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  my $txn_scope_guard = $self->txn_scope_guard;

  $self->_do_query('SET CONSTRAINTS ALL DEFERRED');

  return preserve_context {
    my $inner_self = $self; # avoid nested closure leak on 5.8
    my $sg = Scope::Guard->new(sub {
      $inner_self->_do_query('SET CONSTRAINTS ALL IMMEDIATE');
    });
    $sub->()
  } after => sub { $txn_scope_guard->commit };
}

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut

1;
