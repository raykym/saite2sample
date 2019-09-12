#t/04_email.t

use strict;
use warnings;
use Test::More;
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules';
use Inputchk;


subtest 'email check' => sub {

my $str = 'aaa@bbb.com';
my $obj = Inputchk->new($str);
   $obj->email;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
   print "\n";

   my $res = $obj->result;
   is $res,0;
};

subtest 'err email null address' => sub {

my $str = ' ';
my $obj = Inputchk->new($str);
   $obj->email;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
   print "\n";

   my $res = $obj->result;
   isnt $res,0;

};

subtest 'err email address' => sub {

my $str = 'aaa@bbb.@com';
my $obj = Inputchk->new($str);
   $obj->email;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
   print "\n";

   my $res = $obj->result;
   isnt $res,0;

};

subtest 'err email2 address' => sub {

my $str = 'aaa@bbb.(aa)com';
my $obj = Inputchk->new($str);
   $obj->email;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
   print "\n";

   my $res = $obj->result;
   isnt $res,0;

};

subtest 'err email3 address' => sub {

local $SIG{__WARN__} = sub { fail shift };
my $str = 'aaa.bbb.com';
my $obj = Inputchk->new($str);
   $obj->email;
   my $resp = $obj->res;
   foreach my $i (@$resp){
       print "$i ";
       };
   print "\n";

   my $res = $obj->result;
   isnt $res,0;

};
done_testing;
