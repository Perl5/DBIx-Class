package DBIx::Class::InflateColumn::DateTime;

use strict;
use warnings;
use base qw/DBIx::Class/;

=head1 NAME

DBIx::Class::InflateColumn::DateTime - Auto-create DateTime objects from date and datetime columns.

=head1 SYNOPSIS

Load this component and then declare one or more 
columns to be of the datetime, timestamp or date datatype.

  package Event;
  __PACKAGE__->load_components(qw/InflateColumn::DateTime Core/);
  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime' }
  );

Then you can treat the specified column as a L<DateTime> object.

  print "This event starts the month of ".
    $event->starts_when->month_name();

If you want to set a specific timezone and locale for that field, use:

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', extra => { timezone => "America/Chicago", locale => "de_DE" } }
  );

If you want to inflate no matter what data_type your column is,
use inflate_datetime or inflate_date:

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'varchar', inflate_datetime => 1 }
  );
  
  __PACKAGE__->add_columns(
    starts_when => { data_type => 'varchar', inflate_date => 1 }
  );

It's also possible to explicitly skip inflation:
  
  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', inflate_datetime => 0 }
  );

=head1 DESCRIPTION

This module figures out the type of DateTime::Format::* class to 
inflate/deflate with based on the type of DBIx::Class::Storage::DBI::* 
that you are using.  If you switch from one database to a different 
one your code should continue to work without modification (though note
that this feature is new as of 0.07, so it may not be perfect yet - bug
reports to the list very much welcome).

For more help with using components, see L<DBIx::Class::Manual::Component/USING>.

=cut

__PACKAGE__->load_components(qw/InflateColumn/);

__PACKAGE__->mk_group_accessors('simple' => '__datetime_parser');

=head2 register_column

Chains with the L<DBIx::Class::Row/register_column> method, and sets
up datetime columns appropriately.  This would not normally be
directly called by end users.

In the case of an invalid date, L<DateTime> will throw an exception.  To
bypass these exceptions and just have the inflation return undef, use
the C<datetime_undef_if_invalid> option in the column info:
  
    "broken_date",
    {
        data_type => "datetime",
        default_value => '0000-00-00',
        is_nullable => 1,
        datetime_undef_if_invalid => 1
    }

=cut

sub register_column {
  my ($self, $column, $info, @rest) = @_;
  $self->next::method($column, $info, @rest);
  return unless defined($info->{data_type});

  my $type;

  for (qw/date datetime/) {
    my $key = "inflate_${_}";

    next unless exists $info->{$key};
    return unless $info->{$key};

    $type = $_;
    last;
  }

  unless ($type) {
    $type = lc($info->{data_type});
    $type = 'datetime' if ($type =~ /^timestamp/);
  }

  my $timezone;
  if ( defined $info->{extra}{timezone} ) {
    $timezone = $info->{extra}{timezone};
  }

  my $locale;
  if ( defined $info->{extra}{locale} ) {
    $locale = $info->{extra}{locale};
  }

  my $undef_if_invalid = $info->{datetime_undef_if_invalid};

  if ($type eq 'datetime' || $type eq 'date') {
    my ($parse, $format) = ("parse_${type}", "format_${type}");

    # This assignment must happen here, otherwise Devel::Cycle treats
    # the resulting deflator as a circular reference (go figure):
    #
    # Cycle #1
    #     DBICTest::Schema A->{source_registrations} => %B
    #     %B->{Event} => DBIx::Class::ResultSource::Table C
    #     DBIx::Class::ResultSource::Table C->{_columns} => %D
    #     %D->{created_on} => %E
    #     %E->{_inflate_info} => %F
    #     %F->{deflate} => &G
    #     closure &G, $info => $H
    #     $H => %E
    #
    my $floating_tz_ok = $info->{extra}{floating_tz_ok};

    $self->inflate_column(
      $column =>
        {
          inflate => sub {
            my ($value, $obj) = @_;
            my $dt = eval { $obj->_datetime_parser->$parse($value); };
            die "Error while inflating ${value} for ${column} on ${self}: $@"
              if $@ and not $undef_if_invalid;
            $dt->set_time_zone($timezone) if $timezone;
            $dt->set_locale($locale) if $locale;
            return $dt;
          },
          deflate => sub {
            my ($value, $obj) = @_;
            if ($timezone) {
                warn "You're using a floating timezone, please see the documentation of"
                  . " DBIx::Class::InflateColumn::DateTime for an explanation"
                  if ref( $value->time_zone ) eq 'DateTime::TimeZone::Floating'
                      and not $floating_tz_ok
                      and not $ENV{DBIC_FLOATING_TZ_OK};
                $value->set_time_zone($timezone);
                $value->set_locale($locale) if $locale;
            }
            $obj->_datetime_parser->$format($value);
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

=head1 USAGE NOTES

If you have a datetime column with the C<timezone> extra setting, and subsenquently 
create/update this column with a DateTime object in the L<DateTime::TimeZone::Floating>
timezone, you will get a warning (as there is a very good chance this will not have the
result you expect). For example:

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', extra => { timezone => "America/Chicago" } }
  );

  my $event = $schema->resultset('EventTZ')->create({
    starts_at => DateTime->new(year=>2007, month=>12, day=>31, ),
  });

The warning can be avoided in several ways:

=over

=item Fix your broken code

When calling C<set_time_zone> on a Floating DateTime object, the timezone is simply
set to the requested value, and B<no time conversion takes place>. It is always a good idea
to be supply explicit times to the database:

  my $event = $schema->resultset('EventTZ')->create({
    starts_at => DateTime->new(year=>2007, month=>12, day=>31, time_zone => "America/Chicago" ),
  });

=item Suppress the check on per-column basis

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', extra => { timezone => "America/Chicago", floating_tz_ok => 1 } }
  );

=item Suppress the check globally

Set the environment variable DBIC_FLOATING_TZ_OK to some true value.

=back



=head1 SEE ALSO

=over 4

=item More information about the add_columns method, and column metadata, 
      can be found in the documentation for L<DBIx::Class::ResultSource>.

=item Further discussion of problems inherent to the Floating timezone:
      L<Floating DateTimes|DateTime/Floating_DateTimes> 
      and L<< $dt->set_time_zone|DateTime/"Set" Methods >>

=back

=head1 AUTHOR

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

Aran Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

