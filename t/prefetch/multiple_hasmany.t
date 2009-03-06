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
