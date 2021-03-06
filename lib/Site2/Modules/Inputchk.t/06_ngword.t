#06_ngword.t

use strict;
use warnings;
use Test::More;
use feature 'say';

use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules';
use Inputchk;

subtest 'ngword check' => sub {
   local $SIG{__WARN__} = sub { fail shift };

my $str = 'エロ';
my $obj = Inputchk->new($str);
   $obj->ngword;

   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
       print "\n------\n";

my $got = $obj->result;
   isnt $got,0; 

};

say "";
subtest 'no input check' => sub {
   local $SIG{__WARN__} = sub { fail shift };

my $str = '';
my $obj = Inputchk->new($str);
   $obj->ngword;

   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
       print "\n------\n";

my $got = $obj->result;
   isnt $got,0; 

};

say "";
subtest 'CR contain check' => sub {
   local $SIG{__WARN__} = sub { fail shift };

my $str = 'asakitume\n エロ ヤ';
my $obj = Inputchk->new($str);
   $obj->ngword;

   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
       print "\n------\n";

my $got = $obj->result;
   isnt $got,0; 

};

say "";
subtest 'nomal contain check' => sub {
   local $SIG{__WARN__} = sub { fail shift };

my $str = 'ピエロ';  # 部分一致はパスする
my $obj = Inputchk->new($str);
   $obj->ngword;

   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
       print "\n------\n";

my $got = $obj->result;
   is $got,0; 

};


done_testing;
