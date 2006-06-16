package DBIx::Class::InflateColumn::DateTime;

use strict;
use warnings;
use base qw/DBIx::Class/;

=head1 NAME

DBIx::Class::InflateColumn::DateTime - Auto-create DateTime objects from datetime columns.

=head1 SYNOPSIS

Load this component and then declare one or more 
columns to be of the datetime datatype.

  package Event;
  __PACKAGE__->load_components(qw/InflateColumn::DateTime/);
  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime' }
  );

Then you can treat the specified column as a L<DateTime> object.

  print "This event starts the month of ".
    $event->starts_when->month_name();

=head1 DESCRIPTION

This module figures out the type of DateTime::Format::* class to 
inflate/deflate with based on the type of DBIx::Class::Storage::DBI::* 
that you are using.  If you switch from one database to a different 
one your code will continue to work without modification.

=cut

__PACKAGE__->load_components(qw/InflateColumn/);

__PACKAGE__->mk_group_accessors('simple' => '__datetime_parser');

=head2 register_column

Chains with the L<DBIx::Class::Row/register_column> method, and sets
up datetime columns appropriately.  This would not normally be
directly called by end users.

=cut

sub register_column {
  my ($self, $column, $info, @rest) = @_;
  $self->next::method($column, $info, @rest);
  if (defined($info->{data_type}) && $info->{data_type} =~ /^datetime$/i) {
    $self->inflate_column(
      $column =>
        {
          inflate => sub {
            my ($value, $obj) = @_;
            $obj->_datetime_parser->parse_datetime($value);
          },
          deflate => sub {
            my ($value, $obj) = @_;
            $obj->_datetime_parser->format_datetime($value);
          },
        }
    );
  }
}

sub _datetime_parser {
  my $self = shift;
  if (my $parser = $self->__datetime_parser) {
    return $parser;
  }
  my $parser = $self->result_source->storage->datetime_parser(@_);
  return $self->__datetime_parser($parser);
}

1;
__END__

=head1 SEE ALSO

=over 4

=item More information about the add_columns method, and column metadata, 
      can be found in the documentation for L<DBIx::Class::ResultSource>.

=back

=head1 AUTHOR

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

Aran Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

