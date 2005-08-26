package DBIx::Class::Pager;

use strict;
use warnings;

use NEXT;
use Data::Page;

=head1 NAME 

DBIx::Class::Pager -  Pagination of resultsets

=head1 SYNOPSIS

=head1 DESCRIPTION

This class lets you page through a resultset.

=head1 METHODS

=over 4

=item page

=item pager

=cut

*pager = \&page;

sub page {
  my $self = shift;
  my ($criteria, $attr) = @_;
  
  my $rows    = $attr->{rows} || 10;
  my $current = $attr->{page} || 1;
  
  # count must not use LIMIT, so strip out rows/offset
  delete $attr->{$_} for qw/rows offset/;
  
  my $total = $self->count( $criteria, $attr );
  my $page = Data::Page->new( $total, $rows, $current );
  
  $attr->{rows}   = $page->entries_per_page;
  $attr->{offset} = $page->skipped;

  my $iterator = $self->search( $criteria, $attr );

  return ( $page, $iterator );
}

1;

=back

=head1 AUTHORS

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

