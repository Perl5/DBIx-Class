use Test::More;

plan tests => 56;

use DBIx::Class::SQL::Abstract;

# Make sure to test the examples, since having them break is somewhat
# embarrassing. :-(

my @handle_tests = (
    {
        where => {
            requestor => 'inna',
            worker => ['nwiger', 'rcwe', 'sfz'],
            status => { '!=', 'completed' }
        },
        stmt => "( requestor = ? AND status != ? AND ( ( worker = ? ) OR"
              . " ( worker = ? ) OR ( worker = ? ) ) )",
        bind => [qw/inna completed nwiger rcwe sfz/],
    },

    {
        where  => {
            user   => 'nwiger',
            status => 'completed'
        },
        stmt => "( status = ? AND user = ? )",
        bind => [qw/completed nwiger/],
    },

    {
        where  => {
            user   => 'nwiger',
            status => { '!=', 'completed' }
        },
        stmt => "( status != ? AND user = ? )",
        bind => [qw/completed nwiger/],
    },

    {
        where  => {
            status   => 'completed',
            reportid => { 'in', [567, 2335, 2] }
        },
        stmt => "( reportid IN ( ?, ?, ? ) AND status = ? )",
        bind => [qw/567 2335 2 completed/],
    },

    {
        where  => {
            status   => 'completed',
            reportid => { 'not in', [567, 2335, 2] }
        },
        stmt => "( reportid NOT IN ( ?, ?, ? ) AND status = ? )",
        bind => [qw/567 2335 2 completed/],
    },

    {
        where  => {
            status   => 'completed',
            completion_date => { 'between', ['2002-10-01', '2003-02-06'] },
        },
        stmt => "( completion_date BETWEEN ? AND ? AND status = ? )",
        bind => [qw/2002-10-01 2003-02-06 completed/],
    },

    {
        where => [
            {
                user   => 'nwiger',
                status => { 'in', ['pending', 'dispatched'] },
            },
            {
                user   => 'robot',
                status => 'unassigned',
            },
        ],
        stmt => "( ( status IN ( ?, ? ) AND user = ? ) OR ( status = ? AND user = ? ) )",
        bind => [qw/pending dispatched nwiger unassigned robot/],
    },

    {
        where => {  
            priority  => [ {'>', 3}, {'<', 1} ],
            requestor => \'is not null',
        },
        stmt => "( ( ( priority > ? ) OR ( priority < ? ) ) AND requestor is not null )",
        bind => [qw/3 1/],
    },

    {
        where => {  
            priority  => [ {'>', 3}, {'<', 1} ],
            requestor => { '!=', undef }, 
        },
        stmt => "( ( ( priority > ? ) OR ( priority < ? ) ) AND requestor IS NOT NULL )",
        bind => [qw/3 1/],
    },

    {
        where => {  
            priority  => { 'between', [1, 3] },
            requestor => { 'like', undef }, 
        },
        stmt => "( priority BETWEEN ? AND ? AND requestor IS NULL )",
        bind => [qw/1 3/],
    },


    {
        where => {  
            id  => 1,
	    num => {
	     '<=' => 20,
	     '>'  => 10,
	    },
        },
        stmt => "( id = ? AND num <= ? AND num > ? )",
        bind => [qw/1 20 10/],
    },

    {
        where => { foo => {-not_like => [7,8,9]},
                   fum => {'like' => [qw/a b/]},
                   nix => {'between' => [100,200] },
                   nox => {'not between' => [150,160] },
                   wix => {'in' => [qw/zz yy/]},
                   wux => {'not_in'  => [qw/30 40/]}
                 },
        stmt => "( ( ( foo NOT LIKE ? ) OR ( foo NOT LIKE ? ) OR ( foo NOT LIKE ? ) ) AND ( ( fum LIKE ? ) OR ( fum LIKE ? ) ) AND nix BETWEEN ? AND ? AND nox NOT BETWEEN ? AND ? AND wix IN ( ?, ? ) AND wux NOT IN ( ?, ? ) )",
        bind => [7,8,9,'a','b',100,200,150,160,'zz','yy','30','40'],
    },
    
    # a couple of the more complex tests from S::A 01generate.t that test -nest, etc.
    {
        where => { name => {'like', '%smith%', -not_in => ['Nate','Jim','Bob','Sally']},
                                     -nest => [ -or => [ -and => [age => { -between => [20,30] }, age => {'!=', 25} ],
                                                         yob => {'<', 1976} ] ] },
        stmt => "( ( ( ( ( ( ( age BETWEEN ? AND ? ) AND ( age != ? ) ) ) OR ( yob < ? ) ) ) ) AND name NOT IN ( ?, ?, ?, ? ) AND name LIKE ? )",
        bind => [qw(20 30 25 1976 Nate Jim Bob Sally %smith%)],
    },
    
    {
        where => [-maybe => {race => [-and => [qw(black white asian)]]},
                                                          {-nest => {firsttime => [-or => {'=','yes'}, undef]}},
                                                          [ -and => {firstname => {-not_like => 'candace'}}, {lastname => {-in => [qw(jugs canyon towers)]}} ] ],
        stmt => "( ( ( ( ( ( ( race = ? ) OR ( race = ? ) OR ( race = ? ) ) ) ) ) ) OR ( ( ( ( firsttime = ? ) OR ( firsttime IS NULL ) ) ) ) OR ( ( ( firstname NOT LIKE ? ) ) AND ( lastname IN ( ?, ?, ? ) ) ) )",
        bind => [qw(black white asian yes candace jugs canyon towers)],
    }
);

for (@handle_tests) {
    local $" = ', '; 

    # run twice
    for (my $i=0; $i < 2; $i++) {
        my($stmt, @bind) = DBIx::Class::SQL::Abstract->_cond_resolve($_->{where}, {});

        is($stmt, $_->{stmt}, 'SQL ok');
        cmp_ok(@bind, '==', @{$_->{bind}}, 'bind vars ok');
    }
}


