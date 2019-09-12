#t/02_new.t

use strict;
use warnings;
use Test::More;
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules';
use Inputchk;

subtest 'no_args' => sub {
   my $obj = Inputchk->new;
   isa_ok $obj, 'Inputchk';
};

subtest '$str is null' => sub {
    my $str = '';
    my $obj = Inputchk->new($str);
    isa_ok $obj, 'Inputchk';
};

subtest '$str' => sub {
    my $str = 'aaa@bbb.ccc';
    my $obj = Inputchk->new($str);
    isa_ok $obj, 'Inputchk';
};

done_testing;
