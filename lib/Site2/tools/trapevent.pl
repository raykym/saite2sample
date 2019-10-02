#!/usr/bin/env perl
#
# walkworldでtrapイベント処理を受け持つ npcuserの攻撃受信処理も受け持つ
#
use strict;
use warnings;
use utf8;
use feature 'say';

#use EV;
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojo::JSON qw( from_json to_json);
use DateTime;
use Math::Trig qw( great_circle_distance rad2deg deg2rad pi );
use AnyEvent;
use Mojo::Pg;
use Mojo::Pg::PubSub;
use Mojo::Redis;
use Time::HiRes qw( time usleep gettimeofday tv_interval );
use Encode qw( encode_utf8 decode_utf8 );;

$|=1;

my $redis ||= Mojo::Redis->new("redis://10.140.0.8");

my $pg = Mojo::Pg->new( 'postgresql://sitedata:sitedatapass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/sitedata' );

my $pubsub = Mojo::Pg::PubSub->new( pg => $pg );

# 表示用ログフォーマット
sub Logging{
    my $logline = shift;
       $logline = encode_utf8($logline);
    my $dt = DateTime->now();
    say "$dt | $logline";
    $logline = decode_utf8($logline);
    my $dblog = { 'PROG' => $0 , 'ttl' => time() , 'logline' => $logline, "dt" => $dt };
    my $dblogjson = to_json($dblog);
       $pg->db->insert('log_tbl' , { 'data' => $dblogjson } );

    undef $logline;
    undef $dt;
    undef $dblog;
    undef $dblogjson;

    return;
}

my $childpid = -1;
my $t1;
my $t2;

# 基本無限ループ
while(1) {

    if ( $childpid == -1 ) {
        $childpid = fork();
    } else {
        Logging("childpid no NULL");
        exit;
    }

    if ( $childpid ) {

    Logging("$0 mainprocess $$ start");

    my $cvp = AE::cv;
       $t1 = AnyEvent->timer(
        after => 3600,
        interval => 0,
           cb => sub {

           Logging("change chile process");
           system("kill -TERM $childpid");

           $childpid = -1; #初期

        $cvp->send;
        });
        # TERMシグナルを受けるとメッセージを記録して終了する
        my $sig = AnyEvent->signal(
              signal => 'TERM',
              cb => sub {

              Logging("$0 process signal TERM!");
              system("kill -TERM $childpid");
              $cvp->send;
          exit;
        });

$cvp->recv;

#################################

    } else {
            # childprocess

# ghostchat listen
    my $cb_ghost = $pubsub->listen( "ghostevent" => sub {
           my ($pubsub, $payload) = @_;

           Logging("chatch event $payload");

           my $jsonobj = from_json($payload);

           if ($jsonobj->{walkworld} ){

               if ( $jsonobj->{walkworld} eq 'hitghost' ) {

                   my $resid = $redis->db->hget('ghostaccEntry',$jsonobj->{uid});

                   if (( ! defined $resid )|| ( $resid eq "" )) { return ; }

                     $redis->db->hdel('ghostaccEntry', $jsonobj->{uid} );

                     $pg->db->query("delete from walkworld where data->>'uid' = ?" , $jsonobj->{uid} );

                   my $ghostid = from_json($resid);

                   my $mess = { "type" => "openchat",
                                "text" => "ぐふぉ、やられた。。。",
                                "user" => $ghostid->{name} ,
                                "icon_url" => $ghostid->{icon_url},
                              };
                  my $messjson = to_json($mess);

                  $pubsub->notify('openchat', $messjson );

                  undef $resid;
                  undef $ghostid;
                  undef $mess;
                  undef $messjson;
                  undef $jsonobj;

                   return;
               } # hitghost



           } #walkworld

    });

if (0) {
    my $cb = $pubsub->listen( "trapevent" => sub {
           my ($pubsub, $payload) = @_;

           Logging("chatch event $payload");

           my $jsonobj = from_json($payload);

           # trapeentを受信して登録する

    });
} # block

my $cv = AE::cv;
my $t = AnyEvent->timer(
        after => 0,
        interval => 5,
           cb => sub {
            Logging("trapevent start");

            # 5秒ごとにイベントをwalkworldに継続的に書き込む
            my $res = $redis->db->hvals('trapeventEntry');

	    if ( ! @$res ){ 
		    Logging("no trapevent");
		    return;
	    }

	    my @eventlist = ();
            for my $linejson ( @$res ){
                my $line = from_json($linejson);
                   $line->{ttl} = time();          # ttlの更新　いきなり全部消える

		if ($line->{category} eq 'MINE') {
		    my $linejson = to_json($line);
		    $redis->db->hset('trapeventEntry' , $line->{uid} , $linejson );
		}

                if ($line->{category} eq 'TOWER' ) {
                    $line->{ttlcount} = $line->{ttlcount} - 1;    # towerのタイムリミット設定
		    my $linejson = to_json($line);
		    $redis->db->hset('trapeventEntry' , $line->{uid} , $linejson );

		    if ( $line->{ttlcount} <= 0 ) {
                        $redis->db->hdel('trapeventEntry', $line->{uid});
			Logging("Time out TOWER delete");
			next;
		    }
		}
                push(@eventlist , $line);
	    } # for

	    my @el = ();
            for my $line (@eventlist){
	        my $linejson = to_json($line);
                push(@el , $linejson );
		#  Logging("trapevent: $linejson");
	    }

	    eval {
		Logging("write trap events");
                my $tx = $pg->db->begin;   # 一括コミットで高速化
	        for my $linejson (@el){
                       my $dataset = { 'data' => $linejson };
                       $pg->db->insert( 'walkworld', $dataset  );
	        }
                   $tx->commit;
            }; # eval
	    if ( my $error = $@ ) {
                Logging("DEBUG: pg: $error");
	    }

	    undef @eventlist;
	    undef $res;
});
# TERMシグナルを受けるとメッセージを記録して終了する
my $sig = AnyEvent->signal(
          signal => 'TERM',
          cb => sub {

              Logging("GET signal TERM");

              $cv->send;  # timer loop stop 

             });
$cv->recv;

exit;
} # else

} # while(1)




