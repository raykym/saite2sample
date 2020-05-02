#t/02_new.t

use strict;
use warnings;
use Test::More;
#use lib '/storage/perlwork/mojowork/server/site1/lib/Site1';
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules';
use Sessionid;

subtest 'no_args' => sub {
   my $obj = Sessionid->new;
   isa_ok $obj, 'Sessionid';
};

subtest '$str is null' => sub {
    my $str = '';
    my $obj = Sessionid->new($str);
    isa_ok $obj, 'Sessionid';
};

subtest '$str' => sub {
    my $str = 'aaa@bbb.ccc';
    my $obj = Sessionid->new($str);
    isa_ok $obj, 'Sessionid';
};

subtest '$str duble byte data' => sub {
    my $str = '日本語の文字列';
    my $obj = Sessionid->new($str);
    isa_ok $obj, 'Sessionid';
};

done_testing;
