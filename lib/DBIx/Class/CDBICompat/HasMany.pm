package DBIx::Class::CDBICompat::HasMany;

use strict;
use warnings;

sub has_many {
  my ($class, $rel, $f_class, $f_key, $args) = @_;

  my @f_method;

  if (ref $f_class eq 'ARRAY') {
    ($f_class, @f_method) = @$f_class;
  }

  my ($pri, $too_many) = keys %{ $class->_primaries };
  $class->throw( "has_many only works with a single primary key; ${class} has more" )
      if $too_many;
  my $self_key = $pri;
    
  eval "require $f_class";

  if (ref $f_key eq 'HASH') { $args = $f_key; undef $f_key; };

  #unless ($f_key) { Not selective enough. Removed pending fix.
  #  ($f_rel) = grep { $_->{class} && $_->{class} eq $class }
  #               $f_class->_relationships;
  #}

  unless ($f_key) {
    #warn join(', ', %{ $f_class->_columns });
    $class =~ /([^\:]+)$/;
    #warn $1;
    $f_key = lc $1 if $f_class->_columns->{lc $1};
  }

  $class->throw( "Unable to resolve foreign key for has_many from ${class} to ${f_class}" )
    unless $f_key;
  $class->throw( "No such column ${f_key} on foreign class ${f_class}" )
    unless $f_class->_columns->{$f_key};
  $args ||= {};
  my $cascade = not (ref $args eq 'HASH' && delete $args->{no_cascade_delete});

 $class->add_relationship($rel, $f_class,
                            { "foreign.${f_key}" => "self.${self_key}" },
                            { accessor => 'multi',
                              join_type => 'LEFT',
                              ($cascade ? ('cascade_delete' => 1) : ()),
                              %$args } );
  if (@f_method) {
    no strict 'refs';
    no warnings 'redefine';
    my $post_proc = sub { my $o = shift; $o = $o->$_ for @f_method; $o; };
    *{"${class}::${rel}"} =
      sub {
        my $rs = shift->search_related($rel => @_);
        $rs->{attrs}{record_filter} = $post_proc;
        return (wantarray ? $rs->all : $rs);
      };
    return 1;
  }

}

1;
