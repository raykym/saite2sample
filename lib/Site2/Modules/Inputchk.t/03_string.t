#t/03_string.t

use strict;
use warnings;
use Test::More;
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules';
use Inputchk;

my $str = 'aaa@bbb.com';
my $obj = Inputchk->new($str);

subtest 'string check' => sub {

   my $res = $obj->string;
   is $res,'aaa@bbb.com';
};

done_testing;
