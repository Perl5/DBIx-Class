use strict;
use warnings;  

use Test::More;
use Test::Exception;
use lib qw(t/lib);
use DBICTest;
use Data::Dumper;

my $schema = DBICTest->init_schema();

my $orig_debug = $schema->storage->debug;

use IO::File;

BEGIN {
    eval "use DBD::SQLite";
    plan $@
        ? ( skip_all => 'needs DBD::SQLite for testing' )
        : ( tests => 16 );
}

# figure out if we've got a version of sqlite that is older than 3.2.6, in
# which case COUNT(DISTINCT()) doesn't work
my $is_broken_sqlite = 0;
my ($sqlite_major_ver,$sqlite_minor_ver,$sqlite_patch_ver) =
    split /\./, $schema->storage->dbh->get_info(18);
if( $schema->storage->dbh->get_info(17) eq 'SQLite' &&
    ( ($sqlite_major_ver < 3) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver < 2) ||
      ($sqlite_major_ver == 3 && $sqlite_minor_ver == 2 && $sqlite_patch_ver < 6) ) ) {
    $is_broken_sqlite = 1;
}

# once the following TODO is complete, remove the 2 warning tests immediately
# after the TODO block
# (the TODO block itself contains tests ensuring that the warns are removed)
TODO: {
    local $TODO = 'Prefetch of multiple has_many rels at the same level (currently warn to protect the clueless git)';

    #( 1 -> M + M )
    my $cd_rs = $schema->resultset('CD')->search ({ 'me.title' => 'Forkful of bees' });
    my $pr_cd_rs = $cd_rs->search ({}, {
        prefetch => [qw/tracks tags/],
    });

    my $tracks_rs = $cd_rs->first->tracks;
    my $tracks_count = $tracks_rs->count;

    my ($pr_tracks_rs, $pr_tracks_count);

    my $queries = 0;
    $schema->storage->debugcb(sub { $queries++ });
    $schema->storage->debug(1);

    my $o_mm_warn;
    {
        local $SIG{__WARN__} = sub { $o_mm_warn = shift };
        $pr_tracks_rs = $pr_cd_rs->first->tracks;
    };
    $pr_tracks_count = $pr_tracks_rs->count;

    ok(! $o_mm_warn, 'no warning on attempt to prefetch several same level has_many\'s (1 -> M + M)');

    is($queries, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query');
    is($pr_tracks_count, $tracks_count, 'equal count of prefetched relations over several same level has_many\'s (1 -> M + M)');

    for ($pr_tracks_rs, $tracks_rs) {
        $_->result_class ('DBIx::Class::ResultClass::HashRefInflator');
    }

    is_deeply ([$pr_tracks_rs->all], [$tracks_rs->all], 'same structure returned with and without prefetch over several same level has_many\'s (1 -> M + M)');

    #( M -> 1 -> M + M )
    my $note_rs = $schema->resultset('LinerNotes')->search ({ notes => 'Buy Whiskey!' });
    my $pr_note_rs = $note_rs->search ({}, {
        prefetch => {
            cd => [qw/tags tracks/]
        },
    });

    my $tags_rs = $note_rs->first->cd->tags;
    my $tags_count = $tags_rs->count;

    my ($pr_tags_rs, $pr_tags_count);

    $queries = 0;
    $schema->storage->debugcb(sub { $queries++ });
    $schema->storage->debug(1);

    my $m_o_mm_warn;
    {
        local $SIG{__WARN__} = sub { $m_o_mm_warn = shift };
        $pr_tags_rs = $pr_note_rs->first->cd->tags;
    };
    $pr_tags_count = $pr_tags_rs->count;

    ok(! $m_o_mm_warn, 'no warning on attempt to prefetch several same level has_many\'s (M -> 1 -> M + M)');

    is($queries, 1, 'prefetch one->(has_many,has_many) ran exactly 1 query');

    is($pr_tags_count, $tags_count, 'equal count of prefetched relations over several same level has_many\'s (M -> 1 -> M + M)');

    for ($pr_tags_rs, $tags_rs) {
        $_->result_class ('DBIx::Class::ResultClass::HashRefInflator');
    }

    is_deeply ([$pr_tags_rs->all], [$tags_rs->all], 'same structure returned with and without prefetch over several same level has_many\'s (M -> 1 -> M + M)');
}

# remove this closure once the TODO above is working
my $w;
{
    local $SIG{__WARN__} = sub { $w = shift };

    my $rs = $schema->resultset('CD')->search ({ 'me.title' => 'Forkful of bees' }, { prefetch => [qw/tracks tags/] });
    for (qw/all count next first/) {
        undef $w;
        my @stuff = $rs->search()->$_;
        like ($w, qr/will currently disrupt both the functionality of .rs->count\(\), and the amount of objects retrievable via .rs->next\(\)/,
            "warning on ->$_ attempt prefetching several same level has_manys (1 -> M + M)");
    }
    my $rs2 = $schema->resultset('LinerNotes')->search ({ notes => 'Buy Whiskey!' }, { prefetch => { cd => [qw/tags tracks/] } });
    for (qw/all count next first/) {
        undef $w;
        my @stuff = $rs2->search()->$_;
        like ($w, qr/will currently disrupt both the functionality of .rs->count\(\), and the amount of objects retrievable via .rs->next\(\)/,
            "warning on ->$_ attempt prefetching several same level has_manys (M -> 1 -> M + M)");
    }
}

__END__
The solution is to rewrite ResultSet->_collapse_result() and
ResultSource->resolve_prefetch() to focus on the final results from the collapse
of the data. Right now, the code doesn't treat the columns from the various
tables as grouped entities. While there is a concept of hierarchy (so that
prefetching down relationships does work as expected), there is no idea of what
the final product should look like and how the various columns in the row would
play together. So, the actual prefetch datastructure from the search would be
very useful in working through this problem. We already have access to the PKs
and sundry for those. So, when collapsing the search result, we know we are
looking for 1 cd object. We also know we're looking for tracks and tags records
-independently- of each other. So, we can grab the data for tracks and data for
tags separately, uniqueing on the PK as appropriate. Then, when we're done with
the given cd object's datastream, we know we're good. This should work for all
the various scenarios.

My reccommendation is the row's data is preprocessed first, breaking it up into
the data for each of the component tables. (This could be done in the single
table case, too, but probably isn't necessary.) So, starting with something
like:
  my $row = {
    t1.col1 => 1,
    t1.col2 => 2,
    t2.col1 => 3,
    t2.col2 => 4,
    t3.col1 => 5,
    t3.col2 => 6,
  };
it is massaged to look something like:
  my $row_massaged = {
    t1 => { col1 => 1, col2 => 2 },
    t2 => { col1 => 3, col2 => 4 },
    t3 => { col1 => 5, col2 => 6 },
  };
At this point, find the stuff that's different is easy enough to do and slotting
things into the right spot is, likewise, pretty straightforward.

This implies that the collapse attribute can probably disappear or, at the
least, be turned into a boolean (which is how it's used in every other place).
