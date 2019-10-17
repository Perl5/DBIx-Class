package DBIx::Class::SQLMaker;

use strict;
use warnings;

use base qw(
  DBIx::Class::SQLMaker::ClassicExtensions
  SQL::Abstract::Classic
);

# NOTE THE LACK OF mro SPECIFICATION
# This is deliberate to ensure things will continue to work
# with ( usually ) untagged custom darkpan subclasses

1;

__END__

=head1 NAME

DBIx::Class::SQLMaker - An SQL::Abstract::Classic-like SQL maker class

=head1 DESCRIPTION

This module serves as a mere "nexus class" providing
L<SQL::Abstract::Classic>-like functionality to L<DBIx::Class> itself, and
to a number of database-engine-specific subclasses. This indirection is
explicitly maintained in order to allow swapping out the core of SQL
generation within DBIC on per-C<$schema> basis without major architectural
changes. It is guaranteed by design and tests that this fast-switching
will continue being maintained indefinitely.

=head2 Implementation switching

See L<DBIx::Class::Storage::DBI/connect_call_rebase_sqlmaker>

=head1 ROADMAP

Some maintainer musings on the current state of SQL generation within DBIC as
of October 2019

=head2 Folding of most (or all) of L<SQL::Abstract::Classic (SQLAC)
|SQL::Abstract::Classic> into DBIC.

The rise of complex prefetch use, and the general streamlining of result
parsing within DBIC ended up pushing the actual SQL generation to the forefront
of many casual performance profiles. While the idea behind the SQLAC-like API
is sound, the actual implementation is terribly inefficient (once again bumping
into the ridiculously high overhead of perl function calls).

Given that SQLAC has a B<very> distinct life on its own, and will hopefully
continue to be used within an order of magnitude more projects compared to
DBIC, it is prudent to B<not> disturb the current call chains within SQLAC
itself. Instead in the future an effort will be undertaken to seek a more
thorough decoupling of DBIC SQL generation from reliance on SQLAC, possibly
to a point where B<< in the future DBIC may no longer depend on
L<SQL::Abstract::Classic> >> at all.

B<The L<SQL::Abstract::Classic> library itself will continue being maintained>
although it is not likely to gain many extra features, notably it will B<NOT>
add further dialect support, at least not within the preexisting
C<SQL::Abstract::Classic> namespace.

Such streamlining work (if undertaken) will take into consideration the
following constraints:

=over

=item Main API compatibility

The object returned by C<< $schema->storage->sqlmaker >> needs to be able to
satisfy most of the basic tests found in the current-at-the-time SQLAC dist.
While things like L<case|SQL::Abstract::Classic/case> or
L<logic|SQL::Abstract::Classic/logic> or even worse
L<convert|SQL::Abstract::Classic/convert> will definitely remain
unsupported, the rest of the tests should pass (within reason).

=item Ability to replace SQL::Abstract::Classic with a derivative module

During the initial work on L<Data::Query>, which later was slated to occupy
the preexisting namespace of L<SQL::Abstract>, the test suite of DBIC turned
out to be an invaluable asset to iron out hard-to-reason-about corner cases.
In addition the test suite is much more vast and intricate than the tests of
SQLAC itself. This state of affairs is way too valuable to sacrifice in order
to gain faster SQL generation. Thus the
L<SQLMaker rebase|DBIx::Class::Storage::DBI/connect_call_rebase_sqlmaker>
functionality introduced in DBIC v0.082850 along with extra CI configurations
will continue to ensure that DBIC can be used with an off-the-CPAN SQLAC and
derivatives, and that it continues to flawlessly run its entire test suite.
While this will undoubtedly complicate the future implementation of a better
performing SQL generator, it will preserve both the usability of the test suite
for external projects and will keep L<SQL::Abstract::Classic> from regressions
in the future.

=back

Aside from these constraints it is becoming more and more practical to simply
stop using SQLAC in day-to-day production deployments of DBIC. The flexibility
of the internals is simply not worth the performance cost.

=head2 Relationship to L<SQL::Abstract> and what formerly was known as L<Data::Query (DQ)|Data::Query>

When initial work on DQ was taking place, the tools in L<::Storage::DBIHacks
|https://github.com/Perl5/DBIx-Class/blob/master/lib/DBIx/Class/Storage/DBIHacks.pm>
were only beginning to take shape, and it wasn't clear how important they will
become further down the road. In fact the I<regexing all over the place> was
considered an ugly stop-gap, and even a couple of highly entertaining talks
were given to that effect. As the use-cases of DBIC were progressing, and
evidence for the importance of supporting arbitrary SQL was mounting, it became
clearer that DBIC itself would not really benefit in any significant way from
tigher integration with DQ, but on the contrary is likely to lose L<crucial
functionality|https://github.com/Perl5/DBIx-Class/blob/7ef1a09ec4/lib/DBIx/Class/Storage/DBIHacks.pm#L373-L396>
while the corners of the brand new DQ/SQLA codebase are sanded off.

The current stance on DBIC/SQLA integration is that it would mainly benefit
SQLA by having access to the very extensive "early adopter" test suite, in the
same manner as early DBIC benefitted tremendously from usurping the Class::DBI
test suite. As far as the DBIC user-base - there are no immediate large-scale
upsides to deep SQLA integration, neither in terms of API nor in performance.
As such it is unlikely that DBIC will switch back to using L<SQL::Abstract> in
its core any time soon, if ever.

Accordingly the DBIC development effort will in the foreseable future ignore
the existence of the new-guts SQLA, and will continue optimizing the
preexisting SQLAC-based solution, potentially "organically growing" its own
compatible implementation. Also, as described higher up, the ability to plug a
separate SQLAC-compatible class providing the necessary surface API will remain
possible, and will be protected at all costs in order to continue providing
SQLA and friends access to the test cases of DBIC.

=head1 FURTHER QUESTIONS?

Check the list of L<additional DBIC resources|DBIx::Class/GETTING HELP/SUPPORT>.

=head1 COPYRIGHT AND LICENSE

This module is free software L<copyright|DBIx::Class/COPYRIGHT AND LICENSE>
by the L<DBIx::Class (DBIC) authors|DBIx::Class/AUTHORS>. You can
redistribute it and/or modify it under the same terms as the
L<DBIx::Class library|DBIx::Class/COPYRIGHT AND LICENSE>.
