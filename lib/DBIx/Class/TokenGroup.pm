package DBIx::Class::TokenGroup;
use strict;
use warnings;

use base qw( DBIx::Class );

=head1 NAME

DBIx::Class::TokenGroup - Search for tokens in a tree of groups. (EXPERIMENTAL)

=head1 SYNOPSIS

Define your user tokens class.

  package Schema::User::Token;
  use base qw( DBIx::Class::Core );
  __PACKAGE__->table('user_tokens');
  __PACKAGE__->add_columns(qw( name user_id value ));
  __PACKAGE__->set_primary_key(qw( name user_id ));
  1;

Define your group tokens class.

  package Schema::Group::Token;
  use base qw( DBIx::Class::Core );
  __PACKAGE__->table('group_tokens');
  __PACKAGE__->add_columns(qw( name group_id value ));
  __PACKAGE__->set_primary_key(qw( name group_id ));
  1;

Define your group class.

  package Schema::Group;
  use base qw( DBIx::Class::Core );
  __PACKAGE__->load_components(qw(
    Tree::AdjacencyList
  ));
  __PACKAGE__->table('groups');
  __PACKAGE__->add_columns(qw( group_id parent_id ));
  __PACKAGE__->set_primary_key('group_id');
  __PACKAGE__->parent_column('parent_id');
  __PACKAGE__->has_many( 'tokens' => 'Group::Token' => 'group_id' );
  1;

Define your user class.

  package Schema::User;
  use base qw( DBIx::Class::Core );
  __PACKAGE__->table('users');
  __PACKAGE__->add_columns(qw( user_id group_id ));
  __PACKAGE__->set_primary_key('user_id');
  __PACKAGE__->token_name_column('name');
  __PACKAGE__->token_value_column('value');
  __PACKAGE__->has_many( 'tokens' => 'User::Token' => 'user_id' );
  __PACKAGE__->belongs_to( 'group' => 'Group', { 'foreign.group_id' => 'self.group_id' } );
  1;

=head1 DESCRIPTION

This L<DBIx::Class> component provides several utilities for 
retrieving tokens for a tree of groups.  A token is, at a minimum, 
a name and a value.  Groups are associated using either 
L<DBIx::Class::Tree::AdjacencyList> or L<DBIx::Class::Tree::NestedSet>.

This component itself is fairly simple, but it requires that you 
structure your classes in a certain way.

=head1 REQUIREMENTS

The sample shown in the SYNOPSIS is just that, an example.  
As long your clases respond the way that this component 
expects it doesn't care how things are structure.  So, here 
are the requirements for the class that uses this component.

=over 4

=item *

A tokens() method that returns a DBIx::Class::ResultSet object.  The 
objects (tokens) that the result set returns must have the name and 
value columns that you specified with the...

=item *

TODO

=back

=head1 METHODS

=head2 token_name_column

  __PACKAGE__->token_name_column('name');

Sets the name of the column that can be queried to 
retrieve a token's name.

=cut

__PACKAGE__->mk_classdata( 'token_name_column' => 'name' );

=head2 token_value_column

  __PACKAGE__->token_value_column('value');

Sets the name of the column that can be queried to 
retrieve a token's value.  This settings is optional 
as long as you do not use the token_true() and 
token_false() methods.

=cut

__PACKAGE__->mk_classdata( 'token_value_column' => 'value' );

=head2 token

  $object->token('name');

Returns the token object, or 0 if none was found.

=cut

sub token {
    my( $self, $name ) = @_;
    my $name_col = $self->token_name_column();
    my $token = $self->tokens->search({
        $name_col => $name
    })->all();
    return $token if ($token);
    $token = $self->group->tokens->search({
        $name_col => $name
    })->all();
    return $token if ($token);
    my $descendant = $self->group->descendant_by_depth();
    while (my $group = $descendant->next()) {
        $token = $group->tokens->search({
            $name_col => $name
        })->all();
        return $token if ($token);
    }
    return 0;
}

=head2 token_exists

  if ($object->token_exists('name')){ ... }

Tests whether there is a token defined of the 
specified name.

=cut

sub token_exists {
    my( $self, $name ) = @_;
    my $name_col = $self->token_name_column();
    return 1 if( $self->tokens->search({
        $name_col => $name
    })->count() );
    return 1 if( $self->group->tokens->search({
        $name_col => $name
    })->count() );
    my $ancestors = $self->group->ancestors_by_depth();
    while (my $group = $ancestors->next()) {
        return 1 if( $group->tokens->search({
            $name_col => $name
        })->count() );
    }
    return 0;
}

=head2 token_true

  if ($object->token_true('name')) {

Returns 1 if the token exists and its value is a 
true value.  Returns 0 otherwise.

=cut

sub token_true {
    my( $self, $name ) = @_;
    my $token = $self->token( $name );
    return 0 if(!$token);
    return ( $token->get_column($self->token_value_column()) ? 1 : 0 );
}

=head2 token_false

  if ($object->token_false('name')) {

Returns 1 if the token exists and its value is a 
false value.  Returns 0 otherwise.

=cut

sub token_false {
    my( $self, $name ) = @_;
    my $token = $self->token( $name );
    return 0 if(!$token);
    return ( $token->get_column($self->token_value_column()) ? 0 : 1 );
}

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

