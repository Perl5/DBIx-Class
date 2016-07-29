package DBIx::Class::Schema::SanityChecker;

use strict;
use warnings;

use DBIx::Class::_Util qw(
  dbic_internal_try refdesc uniq serialize
  describe_class_methods emit_loud_diag
);
use DBIx::Class ();
use DBIx::Class::Exception ();
use Scalar::Util qw( blessed refaddr );
use namespace::clean;

=head1 NAME

DBIx::Class::Schema::SanityChecker - Extensible "critic" for your Schema class hierarchy

=head1 SYNOPSIS

  package MyApp::Schema;
  use base 'DBIx::Class::Schema';

  # this is the default setting
  __PACKAGE__->schema_sanity_checker('DBIx::Class::Schema::SanityChecker');
  ...

=head1 DESCRIPTION

This is the default implementation of the Schema and related classes
L<validation framework|DBIx::Class::Schema/schema_sanity_checker>.

The validator is B<enabled by default>. See L</Performance considerations>
for discussion of the runtime effects.

Use of this class begins by invoking L</perform_schema_sanity_checks>
(usually via L<DBIx::Class::Schema/connection>), which in turn starts
invoking validators I<C<check_$checkname()>> in the order listed in
L</available_checks>. For each set of returned errors (if any)
I<C<format_$checkname_errors()>> is called and the resulting strings are
passed to L</emit_errors>, where final headers are prepended and the entire
thing is printed on C<STDERR>.

The class does not provide a constructor, due to the lack of state to be
passed around: object orientation was chosen purely for the ease of
overriding parts of the chain of events as described above. The general
pattern of communicating errors between the individual methods (both
before and after formatting) is an arrayref of hash references.

=head2 WHY

DBIC existed for more than a decade without any such setup validation
fanciness, let alone something that is enabled by default (which in turn
L<isn't free|/Performance considerations>). The reason for this relatively
drastic change is a set of revamps within the metadata handling framework,
in order to resolve once and for all problems like
L<RT#107462|https://rt.cpan.org/Ticket/Display.html?id=107462>,
L<RT#114440|https://rt.cpan.org/Ticket/Display.html?id=114440>, etc. While
DBIC internals are now way more robust than they were before, this comes at
a price: some non-issues in code that has been working for a while, will
now become hard to explain, or if you are unlucky: B<silent breakages>.

Thus, in order to protect existing codebases to the fullest extent possible,
the executive decision (and substantial effort) was made to introduce this
on-by-default setup validation framework. A massive amount of work has been
invested ensuring that none of the builtin checks emit a false-positive:
each and every complaint made by these checks B<should be investigated>.

=head2 Performance considerations

First of all - after your connection has been established - there is B<no
runtime penalty> whenever the checks are enabled.

By default the checks are triggered every time
L<DBIx::Class::Schema/connection> is called. Thus there is a
noticeable startup slowdown, most notably during testing (each test is
effectively a standalone program connecting anew). As an example the test
execution phase of the L<DBIx::Class::Helpers> C<v2.032002> distribution
suffers a consistent slowdown of about C<16%>. This is considered a relatively
small price to pay for the benefits provided.

Nevertheless, there are valid cases for disabling the checks during
day-to-day development, and having them run only during CI builds. In fact
the test suite of DBIC does exactly this as can be seen in
F<t/lib/DBICTest/BaseSchema.pm>:

 ~/dbic_repo$ git show 39636786 | perl -ne "print if 16..61"

Whatever you do, B<please do not disable the checks entirely>: it is not
worth the risk.

=head3 Perl5.8

The situation with perl interpreters before C<v5.10.0> is sadly more
complicated: due to lack of built-in L<pluggable mro support|mro>, the
mechanism used to interrogate various classes is
L<< B<much> slower|https://github.com/dbsrgits/dbix-class/commit/296248c3 >>.
As a result the very same version of L<DBIx::Class::Helpers>
L<mentioned above|/Performance considerations> takes a C<B<220%>> hit on its
test execution time (these numbers are observed with the speedups of
L<Class::C3::XS> available, without them the slowdown reaches the whopping
C<350%>).

It is the author's B<strongest> recommendation to find a way to run the
checks on your codebase continuously, even if it takes much longer. Refer to
the last paragraph of L</Performance considerations> above for an example how
to do this during CI builds only.

=head2 Validations provided by this module

=head3 no_indirect_method_overrides

There are many methods within DBIC which are
L<"strictly sugar"|DBIx::Class::MethodAttributes/DBIC_method_is_indirect_sugar>
and should never be overridden by your application (e.g. see warnings at the
end of L<DBIx::Class::ResultSet/create> and L<DBIx::Class::Schema/connect>).
Starting with C<v0.082900> DBIC is much more aggressive in calling the
underlying non-sugar methods directly, which in turn means that almost all
user-side overrides of sugar methods are never going to be invoked. These
situations are now reliably detected and reported individually (you may
end up with a lot of output on C<STDERR> due to this).

Note: B<ANY AND ALL ISSUES> reported by this check B<*MUST*> be resolved
before upgrading DBIC in production. Malfunctioning business logic and/or
B<SEVERE DATA LOSS> may result otherwise.

=head3 valid_c3_composition

Looks through everything returned by L</all_schema_related_classes>, and
for any class that B<does not> already utilize L<c3 MRO|mro/The C3 MRO> a
L<method shadowing map|App::Isa::Splain/SYNOPSIS> is calculated and then
compared to the shadowing map as if C<c3 MRO> was requested in the first place.
Any discrepancies are reported in order to clearly identify L<hard to explain
bugs|https://blog.afoolishmanifesto.com/posts/mros-and-you> especially when
encountered within complex inheritance hierarchies.

=head3 no_inheritance_crosscontamination

Checks that every individual L<Schema|DBIx::Class::Schema>,
L<Storage|DBIx::Class::Storage>, L<ResultSource|DBIx::Class::ResultSource>,
L<ResultSet|DBIx::Class::ResultSet>
and L<Result|DBIx::Class::Manual::ResultClass> class does not inherit from
an unexpected DBIC base class: e.g. an error will be raised if your
C<MyApp::Schema> inherits from both C<DBIx::Class::Schema> and
C<DBIx::Class::ResultSet>.

=head1 METHODS

=head2 perform_schema_sanity_checks

=over

=item Arguments: L<$schema|DBIx::Class::Schema>

=item Return Value: unspecified (ignored by caller)

=back

The entry point expected by the
L<validation framework|DBIx::Class::Schema/schema_sanity_checker>. See
L</DESCRIPTION> for details.

=cut

sub perform_schema_sanity_checks {
  my ($self, $schema) = @_;

  local $DBIx::Class::_Util::describe_class_query_cache->{'!internal!'} = {}
    if
      # does not make a measurable difference on 5.10+
      DBIx::Class::_ENV_::OLD_MRO
        and
      # the callstack shouldn't really be recursive, but for completeness...
      ! $DBIx::Class::_Util::describe_class_query_cache->{'!internal!'}
  ;

  my (@errors_found, $schema_desc);
  for my $ch ( @{ $self->available_checks } ) {

    my $err = $self->${\"check_$ch"} ( $schema );

    push @errors_found, map
      {
        {
          check_name => $ch,
          formatted_error => $_,
          schema_desc => ( $schema_desc ||=
            ( length ref $schema )
              ? refdesc $schema
              : "'$schema'"
          ),
        }
      }
      @{
        $self->${\"format_${ch}_errors"} ( $err )
          ||
        []
      }
    if @$err;
  }

  $self->emit_errors(\@errors_found)
    if @errors_found;
}

=head2 available_checks

=over

=item Arguments: none

=item Return Value: \@list_of_check_names

=back

The list of checks L</perform_schema_sanity_checks> will perform on the
provided L<$schema|DBIx::Class::Schema> object. For every entry returned
by this method, there must be a pair of I<C<check_$checkname()>> and
I<C<format_$checkname_errors()>> methods available.

Override this method to add checks to the
L<currently available set|/Validations provided by this module>.

=cut

sub available_checks { [qw(
  valid_c3_composition
  no_inheritance_crosscontamination
  no_indirect_method_overrides
)] }

=head2 emit_errors

=over

=item Arguments: \@list_of_formatted_errors

=item Return Value: unspecified (ignored by caller)

=back

Takes an array reference of individual errors returned by various
I<C<format_$checkname_errors()>> formatters, and outputs them on C<STDERR>.

This method is the most convenient integration point for a 3rd party logging
framework.

Each individual error is expected to be a hash reference with all values being
plain strings as follows:

  {
    schema_desc     => $human_readable_description_of_the_passed_in_schema
    check_name      => $name_of_the_check_as_listed_in_available_checks()
    formatted_error => $error_text_as_returned_by_format_$checkname_errors()
  }

If the environment variable C<DBIC_ASSERT_NO_FAILING_SANITY_CHECKS> is set to
a true value this method will throw an exception with the same text. Those who
prefer to take no chances could set this variable permanently as part of their
deployment scripts.

=cut

# *NOT* using carp_unique and the warn framework - make
# it harder to accidentaly silence problems via $SIG{__WARN__}
sub emit_errors {
  #my ($self, $errs) = @_;

  my @final_error_texts = map {
    sprintf( "Schema %s failed the '%s' sanity check: %s\n",
      @{$_}{qw( schema_desc check_name formatted_error )}
    );
  } @{$_[1]};

  emit_loud_diag(
    msg => $_
  ) for @final_error_texts;

  # Do not use the constant - but instead check the env every time
  # This will allow people to start auditing their apps piecemeal
  DBIx::Class::Exception->throw( join "\n",  @final_error_texts, ' ' )
    if $ENV{DBIC_ASSERT_NO_FAILING_SANITY_CHECKS};
}

=head2 all_schema_related_classes

=over

=item Arguments: L<$schema|DBIx::Class::Schema>

=item Return Value: @sorted_list_of_unique_class_names

=back

This is a convenience method providing a list (not an arrayref) of
"interesting classes" related to the supplied schema. The returned list
currently contains the following class names:

=over

=item * The L<Schema|DBIx::Class::Schema> class itself

=item * The associated L<Storage|DBIx::Class::Schema/storage> class if any

=item * The classes of all L<registered ResultSource instances|DBIx::Class::Schema/sources> if any

=item * All L<Result|DBIx::Class::ResultSource/result_class> classes for all registered ResultSource instances

=item * All L<ResultSet|DBIx::Class::ResultSource/resultset_class> classes for all registered ResultSource instances

=back

=cut

sub all_schema_related_classes {
  my ($self, $schema) = @_;

  sort( uniq( map {
    ( not defined $_ )      ? ()
  : ( defined blessed $_ )  ? ref $_
                            : $_
  } (
    $schema,
    $schema->storage,
    ( map {
      $_,
      $_->result_class,
      $_->resultset_class,
    } map { $schema->source($_) } $schema->sources ),
  )));
}


sub format_no_indirect_method_overrides_errors {
  # my ($self, $errors) = @_;

  [ map { sprintf(
    "Method(s) %s override the convenience shortcut %s::%s(): "
  . 'it is almost certain these overrides *MAY BE COMPLETELY IGNORED* at '
  . 'runtime. You MUST reimplement each override to hook a method from the '
  . "chain of calls within the convenience shortcut as seen when running:\n  "
  . '~$ perl -M%2$s -MDevel::Dwarn -e "Ddie { %3$s => %2$s->can(q(%3$s)) }"',
    join (', ', map { "$_()" } sort @{ $_->{by} } ),
    $_->{overridden}{via_class},
    $_->{overridden}{name},
  )} @{ $_[1] } ]
}

sub check_no_indirect_method_overrides {
  my ($self, $schema) = @_;

  my( @err, $seen_shadowing_configurations );

  METHOD_STACK:
  for my $method_stack ( map {
    values %{ describe_class_methods($_)->{methods_with_supers} || {} }
  } $self->all_schema_related_classes($schema) ) {

    my $nonsugar_methods;

    for (@$method_stack) {

      push @$nonsugar_methods, $_ and next
        unless $_->{attributes}{DBIC_method_is_indirect_sugar};

      push @err, {
        overridden => {
          name => $_->{name},
          via_class => (
            # this way we report a much better Dwarn oneliner in the error
            $_->{attributes}{DBIC_method_is_bypassable_resultsource_proxy}
              ? 'DBIx::Class::ResultSource'
              : $_->{via_class}
          ),
        },
        by => [ map { "$_->{via_class}::$_->{name}" } @$nonsugar_methods ],
      } if (
          $nonsugar_methods
            and
          ! $seen_shadowing_configurations->{
            join "\0",
              map
                { refaddr $_ }
                (
                  $_,
                  @$nonsugar_methods,
                )
          }++
        )
      ;

      next METHOD_STACK;
    }
  }

  \@err
}


sub format_valid_c3_composition_errors {
  # my ($self, $errors) = @_;

  [ map { sprintf(
    "Class '%s' %s using the '%s' MRO affecting the lookup order of the "
  . "following method(s): %s. You MUST add the following line to '%1\$s' "
  . "right after strict/warnings:\n  use mro 'c3';",
    $_->{class},
    ( ($_->{initial_mro} eq $_->{current_mro}) ? 'is' : 'was originally' ),
    $_->{initial_mro},
    join (', ', map { "$_()" } sort keys %{$_->{affected_methods}} ),
  )} @{ $_[1] } ]
}


my $base_ISA = {
  map { $_ => 1 } @{mro::get_linear_isa("DBIx::Class")}
};

sub check_valid_c3_composition {
  my ($self, $schema) = @_;

  my @err;

  #
  # A *very* involved check, to absolutely minimize false positives
  # If this check returns an issue - it *better be* a real one
  #
  for my $class ( $self->all_schema_related_classes($schema) ) {

    my $desc = do {
      no strict 'refs';
      describe_class_methods({
        class => $class,
        ( ${"${class}::__INITIAL_MRO_UPON_DBIC_LOAD__"}
          ? ( use_mro => ${"${class}::__INITIAL_MRO_UPON_DBIC_LOAD__"} )
          : ()
        ),
      })
    };

    # is there anything to check?
    next unless (
      ! $desc->{mro}{is_c3}
        and
      $desc->{methods_with_supers}
        and
      my @potentially_problematic_method_stacks =
        grep
          {
            # at least 2 variants came via inheritance (not ours)
            (
              (grep { $_->{via_class} ne $class } @$_)
                >
              1
            )
              and
            #
            # last ditch effort to skip examining an alternative mro
            # IFF the entire "foreign" stack is located in the "base isa"
            #
            # This allows for extra efficiency (as there are several
            # with_supers methods that would always be there), but more
            # importantly saves one from tripping on the nonsensical yet
            # begrudgingly functional (as in - no adverse effects):
            #
            #  use base 'DBIx::Class';
            #  use base 'DBIx::Class::Schema';
            #
            (
              grep {
                # not ours
                $_->{via_class} ne $class
                  and
                # not from the base stack either
                ! $base_ISA->{$_->{via_class}}
              } @$_
            )
          }
          values %{ $desc->{methods_with_supers} }
    );

    my $affected_methods;

    for my $stack (@potentially_problematic_method_stacks) {

      # If we got so far - we need to see what the class would look
      # like under c3 and compare, sigh
      #
      # Note that if the hierarchy is *really* fucked (like the above
      # double-base e.g.) then recalc under 'c3' WILL FAIL, hence the
      # extra eval: if we fail we report things as "jumbled up"
      #
      $affected_methods->{$stack->[0]{name}} = [
        map { $_->{via_class} } @$stack
      ] unless dbic_internal_try {

        serialize($stack)
          eq
        serialize(
          describe_class_methods({ class => $class, use_mro => 'c3' })
                               ->{methods}
                                ->{$stack->[0]{name}}
        )
      };
    }

    push @err, {
      class => $class,
      isa => $desc->{isa},
      initial_mro => $desc->{mro}{type},
      current_mro => mro::get_mro($class),
      affected_methods => $affected_methods,
    } if $affected_methods;
  }

  \@err;
}


sub format_no_inheritance_crosscontamination_errors {
  # my ($self, $errors) = @_;

  [ map { sprintf(
    "Class '%s' registered in the role of '%s' unexpectedly inherits '%s': "
  . 'you must resolve this by either removing an erroneous `use base` call '
  . "or switching to Moo(se)-style delegation (i.e. the 'handles' keyword)",
    $_->{class},
    $_->{type},
    $_->{unexpectedly_inherits},
  )} @{ $_[1] } ]
}

sub check_no_inheritance_crosscontamination {
  my ($self, $schema) = @_;

  my @err;

  my $to_check = {
    Schema => [ $schema ],
    Storage => [ $schema->storage ],
    ResultSource => [ map { $schema->source($_) } $schema->sources ],
  };

  $to_check->{ResultSet} = [
    map { $_->resultset_class } @{$to_check->{ResultSource}}
  ];

  $to_check->{Core} = [
    map { $_->result_class } @{$to_check->{ResultSource}}
  ];

  # Reduce everything to a unique sorted list of class names
  $_ = [ sort( uniq( map {
    ( not defined $_ )      ? ()
  : ( defined blessed $_ )  ? ref $_
                            : $_
  } @$_ ) ) ] for values %$to_check;

  for my $group ( sort keys %$to_check ) {
    for my $class ( @{ $to_check->{$group} } ) {
      for my $foreign_base (
        map { "DBIx::Class::$_" } sort grep { $_ ne $group } keys %$to_check
      ) {

        push @err, {
          class => $class,
          type => ( $group eq 'Core' ? 'ResultClass' : $group ),
          unexpectedly_inherits => $foreign_base
        } if $class->isa($foreign_base);
      }
    }
  }

  \@err;
}

1;

__END__

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
