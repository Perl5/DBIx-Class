package DBIx::Class::ResultSourceProxy::View;

use strict;
use warnings;

use base qw/DBIx::Class::ResultSourceProxy/;

use DBIx::Class::ResultSource::View;

__PACKAGE__->mk_classdata(view_class => 'DBIx::Class::ResultSource::View');

__PACKAGE__->mk_classdata('view_definition');
__PACKAGE__->mk_classdata('view_alias'); # FIXME: Doesn't actually do
                                          # anything yet!

sub _init_result_source_instance {
    my $class = shift;

    $class->mk_classdata('result_source_instance')
        unless $class->can('result_source_instance');

    my $view = $class->result_source_instance;
    my $class_has_view_instance = ($view and $view->result_class eq $class);
    return $view if $class_has_view_instance;

    if( $view ) {
        $view = $class->view_class->new({
            %$view,
            result_class => $class,
            source_name => undef,
            schema => undef
        });
    }
    else {
        $view = $class->view_class->new({
            name            => undef,
            result_class    => $class,
            source_name     => undef,
        });
    }

    $class->result_source_instance($view);

    if ($class->can('schema_instance')) {
        $class =~ m/([^:]+)$/;
        $class->schema_instance->register_class($class, $class);
    }

    return $view;
}

=head1 NAME

DBIx::Class::ResultSourceProxy::View - provides a classdata view
object and method proxies

=head1 SYNOPSIS

  #optional, for deploy support
  __PACKAGE__->view_definition('SELECT cdid, artist, title, year FROM foo');

  __PACKAGE__->view('cd');
  __PACKAGE__->add_columns(qw/cdid artist title year/);
  __PACKAGE__->set_primary_key('cdid');

=head1 METHODS

=head2 add_columns

  __PACKAGE__->add_columns(qw/cdid artist title year/);

Adds columns to the current class and creates accessors for them.

=cut

=head2 view

  __PACKAGE__->view('view_name');
  
Gets or sets the view name.

=cut

sub view {
  my ($class, $view) = @_;
  return $class->result_source_instance->name unless $view;
  unless (ref $view) {
    $view = $class->view_class->new({
        $class->can('result_source_instance') ?
          %{$class->result_source_instance||{}} : (),
        name => $view,
        result_class => $class,
        source_name => undef,
    });
  }

  $class->mk_classdata('result_source_instance')
    unless $class->can('result_source_instance');

  $class->result_source_instance($view);

  if ($class->can('schema_instance')) {
    $class =~ m/([^:]+)$/;
    $class->schema_instance->register_class($class, $class);
  }
  return $class->result_source_instance->name;
}

=head2 has_column

  if ($obj->has_column($col)) { ... }

Returns 1 if the class has a column of this name, 0 otherwise.

=cut

=head2 column_info

  my $info = $obj->column_info($col);

Returns the column metadata hashref for a column. For a description of
the various types of column data in this hashref, see
L<DBIx::Class::ResultSource/add_column>

=cut

=head2 columns

  my @column_names = $obj->columns;

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

