package # hide from PAUSE
    DBIx::Class::CDBICompat::ColumnGroups;

use strict;
use warnings;

use base qw/DBIx::Class::Row/;

use List::Util ();
use DBIx::Class::_Util 'set_subname';
use namespace::clean;

__PACKAGE__->mk_classdata('_column_groups' => { });

sub columns :DBIC_method_is_bypassable_resultsource_proxy {
  my $proto = shift;
  my $class = ref $proto || $proto;
  my $group = shift || "All";
  $class->_init_result_source_instance();

  $class->_add_column_group($group => @_) if @_;
  return $class->all_columns    if $group eq "All";
  return $class->primary_column if $group eq "Primary";

  my $grp = $class->_column_groups->{$group};
  my @grp_cols = sort { $grp->{$b} <=> $grp->{$a} } (keys %$grp);
  return @grp_cols;
}

sub _add_column_group {
  my ($class, $group, @cols) = @_;
  $class->mk_group_accessors(column => @cols);
  $class->add_columns(@cols);
  $class->_register_column_group($group => @cols);
}

sub add_columns :DBIC_method_is_bypassable_resultsource_proxy {
  my ($class, @cols) = @_;
  $class->result_source->add_columns(@cols);
}

sub _register_column_group {
  my ($class, $group, @cols) = @_;

  # Must do a complete deep copy else column groups
  # might accidentally be shared.
  my $groups = DBIx::Class::_Util::deep_clone( $class->_column_groups );

  if ($group eq 'Primary') {
    $class->set_primary_key(@cols);
    delete $groups->{'Essential'}{$_} for @cols;
    my $first = List::Util::max(values %{$groups->{'Essential'}});
    $groups->{'Essential'}{$_} = ++$first for reverse @cols;
  }

  if ($group eq 'All') {
    unless (exists $class->_column_groups->{'Primary'}) {
      $groups->{'Primary'}{$cols[0]} = 1;
      $class->set_primary_key($cols[0]);
    }
    unless (exists $class->_column_groups->{'Essential'}) {
      $groups->{'Essential'}{$cols[0]} = 1;
    }
  }

  delete $groups->{$group}{$_} for @cols;
  my $first = List::Util::max(values %{$groups->{$group}});
  $groups->{$group}{$_} = ++$first for reverse @cols;

  $class->_column_groups($groups);
}

# CDBI will never overwrite an accessor, but it only uses one
# accessor for all column types.  DBIC uses many different
# accessor types so, for example, if you declare a column()
# and then a has_a() for that same column it must overwrite.
#
# To make this work CDBICompat has decide if an accessor
# method was put there by itself and only then overwrite.
{
  my %our_accessors;

  sub _has_custom_accessor {
    my($class, $name) = @_;

    no strict 'refs';
    my $existing_accessor = *{$class .'::'. $name}{CODE};

    return(
      defined $existing_accessor
        and
      ! $our_accessors{$existing_accessor}
        and
      # under 5.8 mro the CODE slot may simply be a "cached method"
      ! (
        DBIx::Class::_ENV_::OLD_MRO
          and
        grep {
          $_ ne $class
            and
          ( $Class::C3::MRO{$_} || {} )->{methods}{$name}
        } @{mro::get_linear_isa($class)}
      )
    )
  }

  sub _deploy_accessor {
    my($class, $name, $accessor) = @_;

    return if $class->_has_custom_accessor($name);

    {
      no strict 'refs';
      no warnings 'redefine';
      my $fullname = join '::', $class, $name;
      *$fullname = set_subname $fullname, $accessor;
    }

    $our_accessors{$accessor}++;

    return 1;
  }
}

sub _mk_group_accessors {
  my ($class, $type, $group, @fields) = @_;

  # So we don't have to do lots of lookups inside the loop.
  my $maker = $class->can($type) unless ref $type;

  # warn "$class $type $group\n";
  foreach my $field (@fields) {
    if( $field eq 'DESTROY' ) {
        carp("Having a data accessor named DESTROY in ".
             "'$class' is unwise.");
    }

    my $name = $field;

    ($name, $field) = @$field if ref $field;

    for( $name, "_${name}_accessor" ) {
      $class->_deploy_accessor(
        $_,
        $class->$maker($group, $field, $_)
      );
    }
  }
}

sub all_columns { return shift->result_source->columns; }

sub primary_column {
  my ($class) = @_;
  my @pri = $class->primary_columns;
  return wantarray ? @pri : $pri[0];
}

sub _essential {
    return shift->columns("Essential");
}

sub find_column {
  my ($class, $col) = @_;
  return $col if $class->has_column($col);
}

sub __grouper {
  my ($class) = @_;
  my $grouper = { class => $class };
  return bless($grouper, 'DBIx::Class::CDBICompat::ColumnGroups::GrouperShim');
}

sub _find_columns {
  my ($class, @col) = @_;
  return map { $class->find_column($_) } @col;
}

package # hide from PAUSE (should be harmless, no POD no Version)
    DBIx::Class::CDBICompat::ColumnGroups::GrouperShim;

sub groups_for {
  my ($self, @cols) = @_;
  my %groups;
  foreach my $col (@cols) {
    foreach my $group (keys %{$self->{class}->_column_groups}) {
      $groups{$group} = 1 if $self->{class}->_column_groups->{$group}->{$col};
    }
  }
  return keys %groups;
}

1;
