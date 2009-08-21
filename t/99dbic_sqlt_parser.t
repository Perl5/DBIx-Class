#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use lib qw(t/lib);
use DBICTest;


BEGIN {
    eval "use SQL::Translator 0.09003;";
    if ($@) {
        plan skip_all => 'needs SQL::Translator 0.09003 for testing';
    }
}

my $schema = DBICTest->init_schema();
# Dummy was yanked out by the sqlt hook test
# CustomSql tests the horrific/deprecated ->name(\$sql) hack
# YearXXXXCDs are views
#
my @sources = grep
  { $_ !~ /^ (?: Dummy | CustomSql | Year\d{4}CDs ) $/x }
  $schema->sources
;

plan tests => ( @sources * 3);

{ 
	my $sqlt_schema = create_schema({ schema => $schema, args => { parser_args => { } } });

	foreach my $source (@sources) {
		my $table = get_table($sqlt_schema, $schema, $source);

		my $fk_count = scalar(grep { $_->type eq 'FOREIGN KEY' } $table->get_constraints);
		my @indices = $table->get_indices;
		my $index_count = scalar(@indices);
    $index_count++ if ($source eq 'TwoKeys'); # TwoKeys has the index turned off on the rel def
		is($index_count, $fk_count, "correct number of indices for $source with no args");
	}
}

{ 
	my $sqlt_schema = create_schema({ schema => $schema, args => { parser_args => { add_fk_index => 1 } } });

	foreach my $source (@sources) {
		my $table = get_table($sqlt_schema, $schema, $source);

		my $fk_count = scalar(grep { $_->type eq 'FOREIGN KEY' } $table->get_constraints);
		my @indices = $table->get_indices;
		my $index_count = scalar(@indices);
    $index_count++ if ($source eq 'TwoKeys'); # TwoKeys has the index turned off on the rel def
		is($index_count, $fk_count, "correct number of indices for $source with add_fk_index => 1");
	}
}

{ 
	my $sqlt_schema = create_schema({ schema => $schema, args => { parser_args => { add_fk_index => 0 } } });

	foreach my $source (@sources) {
		my $table = get_table($sqlt_schema, $schema, $source);

		my @indices = $table->get_indices;
		my $index_count = scalar(@indices);
		is($index_count, 0, "correct number of indices for $source with add_fk_index => 0");
	}
}

sub create_schema {
	my $args = shift;

	my $schema = $args->{schema};
	my $additional_sqltargs = $args->{args} || {};

	my $sqltargs = {
		add_drop_table => 1, 
		ignore_constraint_names => 1,
		ignore_index_names => 1,
		%{$additional_sqltargs}
		};

	my $sqlt = SQL::Translator->new( $sqltargs );

	$sqlt->parser('SQL::Translator::Parser::DBIx::Class');
	return $sqlt->translate({ data => $schema }) or die $sqlt->error;
}

sub get_table {
    my ($sqlt_schema, $schema, $source) = @_;

    my $table_name = $schema->source($source)->from;
    $table_name    = $$table_name if ref $table_name;

    return $sqlt_schema->get_table($table_name);
}
