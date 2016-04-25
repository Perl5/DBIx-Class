package DBIx::Class::ResultSourceProxy::Table;

use strict;
use warnings;

use base qw/DBIx::Class::ResultSourceProxy/;

use DBIx::Class::ResultSource::Table;
use Scalar::Util 'blessed';
use namespace::clean;

# FIXME - both of these *PROBABLY* need to be 'inherited_ro_instance' type
__PACKAGE__->mk_classaccessor(table_class => 'DBIx::Class::ResultSource::Table');
# FIXME: Doesn't actually do anything yet!
__PACKAGE__->mk_group_accessors( inherited => 'table_alias' );

sub _init_result_source_instance {
    my $class = shift;

    $class->mk_group_accessors( inherited => [ result_source_instance => '_result_source' ] )
      unless $class->can('result_source_instance');

    # might be pre-made for us courtesy of DBIC::DB::result_source_instance()
    my $rsrc = $class->result_source_instance;

    return $rsrc
      if $rsrc and $rsrc->result_class eq $class;

    my $table_class = $class->table_class;
    $class->ensure_class_loaded($table_class);

    if( $rsrc ) {
        #
        # NOTE! - not using clone() here and *NOT* marking source as derived
        # from the one already existing on the class (if any)
        #
        $rsrc = $table_class->new({
            %$rsrc,
            result_class => $class,
            source_name => undef,
            schema => undef
        });
    }
    else {
        $rsrc = $table_class->new({
            name            => undef,
            result_class    => $class,
            source_name     => undef,
        });
    }

    $class->result_source_instance($rsrc);
}

=head1 NAME

DBIx::Class::ResultSourceProxy::Table - provides a classdata table
object and method proxies

=head1 SYNOPSIS

  __PACKAGE__->table('cd');
  __PACKAGE__->add_columns(qw/cdid artist title year/);
  __PACKAGE__->set_primary_key('cdid');

=head1 METHODS

=head2 add_columns

  __PACKAGE__->add_columns(qw/cdid artist title year/);

Adds columns to the current class and creates accessors for them.

=cut

=head2 table

  __PACKAGE__->table('tbl_name');

Gets or sets the table name.

=cut

sub table {
  return $_[0]->result_source_instance->name unless @_ > 1;

  my ($class, $table) = @_;

  unless (blessed $table && $table->isa($class->table_class)) {

    my $ancestor = $class->can('result_source_instance')
      ? $class->result_source_instance
      : undef
    ;

    my $table_class = $class->table_class;
    $class->ensure_class_loaded($table_class);


    # NOTE! - not using clone() here and *NOT* marking source as derived
    # from the one already existing on the class (if any)
    # This is logically sound as we are operating at class-level, and is
    # in fact necessary, as otherwise any base-class with a "dummy" table
    # will be marked as an ancestor of everything
    $table = $table_class->new({
        %{ $ancestor || {} },
        name => $table,
        result_class => $class,
    });
  }

  $class->mk_group_accessors( inherited => [ result_source_instance => '_result_source' ] )
    unless $class->can('result_source_instance');

  $class->result_source_instance($table)->name;
}

=head2 table_class

  __PACKAGE__->table_class('DBIx::Class::ResultSource::Table');

Gets or sets the table class used for construction and validation.

=head2 has_column

  if ($obj->has_column($col)) { ... }

Returns 1 if the class has a column of this name, 0 otherwise.

=head2 column_info

  my $info = $obj->column_info($col);

Returns the column metadata hashref for a column. For a description of
the various types of column data in this hashref, see
L<DBIx::Class::ResultSource/add_column>

=head2 columns

  my @column_names = $obj->columns;

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.

=cut

1;


