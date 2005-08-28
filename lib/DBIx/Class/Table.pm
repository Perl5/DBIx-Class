package DBIx::Class::Table;

use strict;
use warnings;

use DBIx::Class::ResultSet;
use Data::Page;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('_columns' => {});

__PACKAGE__->mk_classdata('_table_name');

__PACKAGE__->mk_classdata('table_alias'); # FIXME: Doesn't actually do anything yet!

__PACKAGE__->mk_classdata('_resultset_class' => 'DBIx::Class::ResultSet');

__PACKAGE__->mk_classdata('_page_object');

sub iterator_class { shift->_resultset_class(@_) }

=head1 NAME 

DBIx::Class::Table - Basic table methods

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing basic operations on 
L<DBIx::Class> objects.

=head1 METHODS

=over 4

=cut

sub _register_columns {
  my ($class, @cols) = @_;
  my $names = { %{$class->_columns} };
  $names->{$_} ||= {} for @cols;
  $class->_columns($names); 
}

sub _mk_column_accessors {
  my ($class, @cols) = @_;
  $class->mk_group_accessors('column' => @cols);
}

=item add_columns

  __PACKAGE__->add_columns(qw/col1 col2 col3/);

Adds columns to the current package, and creates accessors for them

=cut

sub add_columns {
  my ($class, @cols) = @_;
  $class->_register_columns(@cols);
  $class->_mk_column_accessors(@cols);
}

=item search_literal

  my @obj    = $class->search_literal($literal_where_cond, @bind);
  my $cursor = $class->search_literal($literal_where_cond, @bind);

=cut

sub search_literal {
  my ($class, $cond, @vals) = @_;
  $cond =~ s/^\s*WHERE//i;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? { %{ pop(@vals) } } : {});
  $attrs->{bind} = \@vals;
  return $class->search(\$cond, $attrs);
}

=item count_literal

  my $count = $class->count_literal($literal_where_cond);

=cut

sub count_literal {
  my $class = shift;
  return $class->search_literal(@_)->count;
}

=item count

  my $count = $class->count({ foo => 3 });

=cut

sub count {
  my $class = shift;
  return $class->search(@_)->count;
}

=item search 

  my @obj    = $class->search({ foo => 3 });
  my $cursor = $class->search({ foo => 3 });

=cut

sub search {
  my $class = shift;
  #warn "@_";
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  $attrs->{where} = (@_ == 1 || ref $_[0] eq "HASH" ? shift: {@_});
  
  # for pagination, we create the resultset with no limit and slice it later
  my $page = {};
  if ( $attrs->{page} ) {
    map { $page->{$_} = $attrs->{$_} } qw/rows page/;
    delete $attrs->{$_} for qw/rows offset page/;
  }

  my $rs = $class->resultset($attrs);
  
  if ( $page->{page} ) {
    my $pager = Data::Page->new( 
      $rs->count, 
      $page->{rows} || 10, 
      $page->{page} || 1 );
    $class->_page_object( $pager );
    return $rs->slice( $pager->skipped,
      $pager->skipped + $pager->entries_per_page - 1 );
  }
  
  return (wantarray ? $rs->all : $rs);
}

sub resultset {
  my $class = shift;

  my $rs_class = $class->_resultset_class;
  eval "use $rs_class;";
  my $rs = $rs_class->new($class, @_);
}

=item search_like

Identical to search except defaults to 'LIKE' instead of '=' in condition

=cut

sub search_like {
  my $class    = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = pop(@_);
  }
  my $query    = ref $_[0] eq "HASH" ? { %{shift()} }: {@_};
  $query->{$_} = { 'like' => $query->{$_} } for keys %$query;
  return $class->search($query, { %$attrs });
}

sub _select_columns {
  return keys %{$_[0]->_columns};
}

=item table

  __PACKAGE__->table('tbl_name');

=cut

sub table {
  shift->_table_name(@_);
}

=item find_or_create

  $class->find_or_create({ key => $val, ... });

Searches for a record matching the search condition; if it doesn't find one,
creates one and returns that instead

=cut

sub find_or_create {
  my $class    = shift;
  my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
  my $exists = $class->find($hash);
  return defined($exists) ? $exists : $class->create($hash);
}

sub columns { return keys %{shift->_columns}; }

=item page

  $pager = $class->page;
  
Returns a Data::Page object for the most recent search that was performed
using the page parameter.

=cut

sub page { shift->_page_object }

1;

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

