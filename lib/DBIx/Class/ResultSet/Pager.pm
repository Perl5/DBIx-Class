package DBIx::Class::ResultSet::Pager;

use warnings;
use strict;

use DBIx::Class::Exception;

sub new {
  my( $proto, $total_entries, $entries_per_page, $current_page ) = @_;

  my $self  = {};
  bless( $self, ( ref $proto || $proto ) );

  $self->total_entries( $total_entries       || 0 );
  $self->entries_per_page( $entries_per_page || 10 );
  $self->current_page( $current_page         || 1 );

  return $self;
}


sub entries_per_page {
  my $self = shift;

  return $self->{entries_per_page}
    unless @_;

  DBIx::Class::Exception->throw( "Fewer than one entry per page!" )
    if $_[0] < 1;

  $self->{entries_per_page} = $_[0];

  $self;
}

sub current_page {
  my $self = shift;

  if( @_ ) {
    $self->{current_page} = $_[0];
    return $self;
  }

  return $self->first_page
    unless defined $self->{current_page};

  return $self->first_page
    if $self->{current_page} < $self->first_page;

  return $self->last_page
    if $self->{current_page} > $self->last_page;

  $self->{current_page};
}

sub total_entries {
  my $self = shift;

  if( @_ ) {
    $self->{total_entries} = $_[0];
    return $self;
  }

  # lazification for DBIC's benefit
  if( ref $self->{total_entries} eq 'CODE' ) {
    $self->{total_entries} = $self->{total_entries}->();
  }

  $self->{total_entries};
}


sub entries_on_this_page {
  my $self = shift;

  if ( $self->total_entries == 0 ) {
    return 0;
  } else {
    return $self->last - $self->first + 1;
  }
}

sub first_page {
  return 1;
}

sub last_page {
  my $self = shift;

  my $pages = $self->total_entries / $self->entries_per_page;
  my $last_page;

  if ( $pages == int $pages ) {
    $last_page = $pages;
  } else {
    $last_page = 1 + int($pages);
  }

  $last_page = 1 if $last_page < 1;
  return $last_page;
}

sub first {
  my $self = shift;

  if ( $self->total_entries == 0 ) {
    return 0;
  } else {
    return ( ( $self->current_page - 1 ) * $self->entries_per_page ) + 1;
  }
}

sub last {
  my $self = shift;

  if ( $self->current_page == $self->last_page ) {
    return $self->total_entries;
  } else {
    return ( $self->current_page * $self->entries_per_page );
  }
}

sub previous_page {
  my $self = shift;

  if ( $self->current_page > 1 ) {
    return $self->current_page - 1;
  } else {
    return undef;
  }
}

sub next_page {
  my $self = shift;

  $self->current_page < $self->last_page ? $self->current_page + 1 : undef;
}

# This method would probably be better named 'select' or 'slice' or
# something, because it doesn't modify the array the way
# CORE::splice() does.
sub splice {
  my ( $self, $array ) = @_;
  my $top = @$array > $self->last ? $self->last : @$array;
  return () if $top == 0;    # empty
  return @{$array}[ $self->first - 1 .. $top - 1 ];
}

sub skipped {
  my $self = shift;

  my $skipped = $self->first - 1;
  return 0 if $skipped < 0;
  return $skipped;
}

sub change_entries_per_page {
  my ( $self, $new_epp ) = @_;

  use integer;
  croak("Fewer than one entry per page!") if $new_epp < 1;
  my $new_page = 1 + ( $self->first / $new_epp );
  $self->entries_per_page($new_epp);
  $self->current_page($new_page);
}

1;

__END__

=head1 NAME

DBIx::Class::ResultSet::Pager - help when paging through sets of results

=head1 SYNOPSIS

  use DBIx::Class::ResultSet::Pager;

  my $page = DBIx::Class::ResultSet::Pager->new();
  $page->total_entries($total_entries);
  $page->entries_per_page($entries_per_page);
  $page->current_page($current_page);

  print "         First page: ", $page->first_page, "\n";
  print "          Last page: ", $page->last_page, "\n";
  print "First entry on page: ", $page->first, "\n";
  print " Last entry on page: ", $page->last, "\n";

=head1 DESCRIPTION

This module is a near-verbatim copy of L<Data::Page 2.02
|https://metacpan.org/pod/release/LBROCARD/Data-Page-2.02/lib/Data/Page.pm>,
which remained unchanged on CPAN from late 2009 through late 2019. The only
differences are dropping a number of accessor generators in lieu of direct
method implementations, and the incorporation of the lazily evaluated
L</total_entries> which was the only part originally provided by
L<DBIx::Class::ResultSet::Pager>. This module passes the entire contemporary
test suite of L<Data::Page> unmodified.




B<WHAT FOLLOWS IS A VERBATIM COPY OF Data::Page's 2.02 DOCUMENTATION>




When searching through large amounts of data, it is often the case
that a result set is returned that is larger than we want to display
on one page. This results in wanting to page through various pages of
data. The maths behind this is unfortunately fiddly, hence this
module.

The main concept is that you pass in the number of total entries, the
number of entries per page, and the current page number. You can then
call methods to find out how many pages of information there are, and
what number the first and last entries on the current page really are.

For example, say we wished to page through the integers from 1 to 100
with 20 entries per page. The first page would consist of 1-20, the
second page from 21-40, the third page from 41-60, the fourth page
from 61-80 and the fifth page from 81-100. This module would help you
work this out.

=head1 METHODS

=head2 new

This is the constructor, which takes no arguments.

  my $page = DBIx::Class::ResultSet::Pager->new();

There is also an old, deprecated constructor, which currently takes
two mandatory arguments, the total number of entries and the number of
entries per page. It also optionally takes the current page number:

  my $page = DBIx::Class::ResultSet::Pager->new($total_entries, $entries_per_page, $current_page);

=head2 total_entries

This method get or sets the total number of entries:

  print "Entries:", $page->total_entries, "\n";

=head2 entries_per_page

This method gets or sets the total number of entries per page (which
defaults to 10):

  print "Per page:", $page->entries_per_page, "\n";

=head2 current_page

This method gets or sets the current page number (which defaults to 1):

  print "Page: ", $page->current_page, "\n";

=head2 entries_on_this_page

This methods returns the number of entries on the current page:

  print "There are ", $page->entries_on_this_page, " entries displayed\n";

=head2 first_page

This method returns the first page. This is put in for reasons of
symmetry with last_page, as it always returns 1:

  print "Pages range from: ", $page->first_page, "\n";

=head2 last_page

This method returns the total number of pages of information:

  print "Pages range to: ", $page->last_page, "\n";

=head2 first

This method returns the number of the first entry on the current page:

  print "Showing entries from: ", $page->first, "\n";

=head2 last

This method returns the number of the last entry on the current page:

  print "Showing entries to: ", $page->last, "\n";

=head2 previous_page

This method returns the previous page number, if one exists. Otherwise
it returns undefined:

  if ($page->previous_page) {
    print "Previous page number: ", $page->previous_page, "\n";
  }

=head2 next_page

This method returns the next page number, if one exists. Otherwise
it returns undefined:

  if ($page->next_page) {
    print "Next page number: ", $page->next_page, "\n";
  }

=head2 splice

This method takes in a listref, and returns only the values which are
on the current page:

  @visible_holidays = $page->splice(\@holidays);

=head2 skipped

This method is useful paging through data in a database using SQL
LIMIT clauses. It is simply $page->first - 1:

  $sth = $dbh->prepare(
    q{SELECT * FROM table ORDER BY rec_date LIMIT ?, ?}
  );
  $sth->execute($page->skipped, $page->entries_per_page);

=head2 change_entries_per_page

This method changes the number of entries per page and the current page number
such that the L<first> item on the current page will be present on the new page.

 $page->total_entries(50);
 $page->entries_per_page(20);
 $page->current_page(3);
 print $page->first; # 41
 $page->change_entries_per_page(30);
 print $page->current_page; # 2 - the page that item 41 will show in

=head1 NOTES

It has been said before that this code is "too simple" for CPAN, but I
must disagree. I have seen people write this kind of code over and
over again and they always get it wrong. Perhaps now they will spend
more time getting the rest of their code right...

Based on code originally by Leo Lapworth, with many changes added by by
Leon Brocard <acme@astray.com>, and few enhancements by James Laver (ELPENGUIN)

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
