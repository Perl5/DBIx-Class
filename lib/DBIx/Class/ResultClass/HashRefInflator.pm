package DBIx::Class::ResultClass::HashRefInflator;

# $me is the hashref of cols/data from the immediate resultsource
# $rest is a deep hashref of all the data from the prefetched
# related sources.

sub mk_hash {
    my ($me, $rest) = @_;

    # to avoid emtpy has_many rels contain one empty hashref
    return if (not keys %$me);

    return { %$me,
        map { ($_ => ref($rest->{$_}[0]) eq 'ARRAY' ? [ map { mk_hash(@$_) } @{$rest->{$_}} ] : mk_hash(@{$rest->{$_}}) ) } keys %$rest
    };
}

sub inflate_result {
    my ($self, $source, $me, $prefetch) = @_;

    return mk_hash($me, $prefetch);
}

1;
