package   #hide from PAUSE
  DBIx::Class::ResultSource::FromSpec::Util;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw(
  fromspec_columns_info
  find_join_path_to_alias
);

use Scalar::Util 'blessed';

# Takes $fromspec, \@column_names
#
# returns { $column_name => \%column_info, ... } for fully qualified and
# where possible also unqualified variants
# also note: this adds -result_source => $rsrc to the column info
#
# If no columns_names are supplied returns info about *all* columns
# for all sources
sub fromspec_columns_info {
  my ($fromspec, $colnames) = @_;

  return {} if $colnames and ! @$colnames;

  my $sources = (
    # this is compat mode for insert/update/delete which do not deal with aliases
    (
      blessed($fromspec)
        and
      $fromspec->isa('DBIx::Class::ResultSource')
    )                                                 ? +{ me => $fromspec }

    # not a known fromspec - no columns to resolve: return directly
  : ref($fromspec) ne 'ARRAY'                         ? return +{}

                                                      : +{
    # otherwise decompose into alias/rsrc pairs
      map
        {
          ( $_->{-rsrc} and $_->{-alias} )
            ? ( @{$_}{qw( -alias -rsrc )} )
            : ()
        }
        map
          {
            ( ref $_ eq 'ARRAY' and ref $_->[0] eq 'HASH' ) ? $_->[0]
          : ( ref $_ eq 'HASH' )                            ? $_
                                                            : ()
          }
          @$fromspec
    }
  );

  $_ = { rsrc => $_, colinfos => $_->columns_info }
    for values %$sources;

  my (%seen_cols, @auto_colnames);

  # compile a global list of column names, to be able to properly
  # disambiguate unqualified column names (if at all possible)
  for my $alias (keys %$sources) {
    (
      ++$seen_cols{$_}{$alias}
        and
      ! $colnames
        and
      push @auto_colnames, "$alias.$_"
    ) for keys %{ $sources->{$alias}{colinfos} };
  }

  $colnames ||= [
    @auto_colnames,
    ( grep { keys %{$seen_cols{$_}} == 1 } keys %seen_cols ),
  ];

  my %return;
  for (@$colnames) {
    my ($colname, $source_alias) = reverse split /\./, $_;

    my $assumed_alias =
      $source_alias
        ||
      # if the column was seen exactly once - we know which rsrc it came from
      (
        $seen_cols{$colname}
          and
        keys %{$seen_cols{$colname}} == 1
          and
        ( %{$seen_cols{$colname}} )[0]
      )
        ||
      next
    ;

    DBIx::Class::Exception->throw(
      "No such column '$colname' on source " . $sources->{$assumed_alias}{rsrc}->source_name
    ) unless $seen_cols{$colname}{$assumed_alias};

    $return{$_} = {
      %{ $sources->{$assumed_alias}{colinfos}{$colname} },
      -result_source => $sources->{$assumed_alias}{rsrc},
      -source_alias => $assumed_alias,
      -fq_colname => "$assumed_alias.$colname",
      -colname => $colname,
    };

    $return{"$assumed_alias.$colname"} = $return{$_}
      unless $source_alias;
  }

  \%return;
}

sub find_join_path_to_alias {
  my ($fromspec, $target_alias) = @_;

  # subqueries and other oddness are naturally not supported
  return undef if (
    ref $fromspec ne 'ARRAY'
      ||
    ref $fromspec->[0] ne 'HASH'
      ||
    ! defined $fromspec->[0]{-alias}
  );

  # no path - the head *is* the alias
  return [] if $fromspec->[0]{-alias} eq $target_alias;

  for my $i (1 .. $#$fromspec) {
    return $fromspec->[$i][0]{-join_path} if ( ($fromspec->[$i][0]{-alias}||'') eq $target_alias );
  }

  # something else went quite wrong
  return undef;
}

1;
