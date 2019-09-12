#03_method.t

use strict;
use warnings;
use Test::More;

# use lib '/storage/perlwork/mojowork/server/site1/lib/Site1';
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules';
use Sessionid;

my $string = 'test@test.com';


subtest 'word method' => sub {
    my $obj = Sessionid->new($string);
    my $word = $obj->word;
    is $word, 'test@test.com';
};

subtest 'sid' => sub {
    my $obj = Sessionid->new->sid;
    print "SID: $obj \n";
    ok $obj;
};

subtest 'uid' => sub {
    my $obj = Sessionid->new($string);
    my $uid = $obj->uid;
    print "UID: $uid \n";
    ok $uid;
};

subtest 'guid' => sub {
    my $obj = Sessionid->new($string);
    my $guid = $obj->guid;
    print "GUID: $guid \n";

    #比較用
    my $obj2 = Sessionid->new($string);
    my $guid2 = $obj2->guid;
    print "GUID2: $guid2 \n";

    is $guid , $guid2;  # 2つが一致する
};



done_testing;
