package DBIx::Class::ResultSource::Table::Cached;

use Scalar::Util qw/weaken/;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/ResultSource::Table/);

sub resultset {
  my $self = shift;
  return $self->{_resultset} ||= do {
      my $rs = $self->next::method;
      weaken $rs->result_source;
      $rs;
  };
}

1;

__END__

=head1 NAME 

DBIx::Class::ResultSource::Table::Cached - Table object that caches its own resultset

=head1 SYNOPSIS
    
    # in a table class or base of table classes (_before_ you call ->table)
    __PACKAGE__->table_class('DBIx::Class::ResultSource::Table::Cached');

=head1 DESCRIPTION

This is a modified version of L<DBIx::Class::ResultSource::Table> that caches
its resultset, so when you call $schema->resultset('Foo') it does not 
re-instantiate the resultset each time. In pathological cases this may not
work correctly, e.g. if you change important attributes of the result source
object.

=head1 AUTHORS

David Kamholz <dkamholz@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
