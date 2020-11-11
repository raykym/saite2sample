#!/usr/bin/env perl
#
# walkworldでghostの移動を担当　redisからアカウント情報を得て、redis,postgresqlへ書き込む
#
use strict;
use warnings;
use utf8;
use feature 'say';

use EV;
use Mojo::IOLoop::Subprocess;
use Mojo::UserAgent;
use Mojo::JSON qw( from_json to_json);
use Mojo::Date;
#use DateTime;
use Math::Trig qw( great_circle_distance rad2deg deg2rad pi );
use AnyEvent;
use Mojo::Pg;
use Mojo::Pg::PubSub;
use Mojo::Redis;
use Time::HiRes qw( time usleep gettimeofday tv_interval );
use Encode qw( encode_utf8 decode_utf8 );;
use Proc::ProcessTable;
use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules/';
use Sessionid;
#use Minion;
#use Scalar::Util qw( weaken );
#use Devel::Cycle;


$|=1;

#my $pg = Mojo::Pg->new( 'postgresql://sitedata:sitedatapass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/sitedata' );
my $pg;
my $redis;
my $pubsub;
my $keyword;

if ( defined $ARGV[0] ){
    $keyword = $ARGV[0];
} else {
    $keyword = 'ghostaccEntry';
}

# 表示用ログフォーマット
sub Logging{
    my $logline = shift;
       $logline = encode_utf8($logline);
       #my $dt = DateTime->now();
    my $dt = Mojo::Date->new()->to_datetime;
    say "$dt | $logline";
    $logline = decode_utf8($logline);
    my $dblog = { 'PROG' => $0 , 'ttl' => time() , 'logline' => $logline, "dt" => $dt , "processid" => $keyword };
    my $dblogjson = to_json($dblog);
       $pg->db->insert('log_tbl' , { 'data' => $dblogjson } );
    
    undef $logline;
    undef $dt;
    undef $dblog;
    undef $dblogjson;

    return;
}


# icon変更 
sub iconchg {
    my $runmode = shift;

 #   Logging("iconchg: runmode: $runmode");

    if ( $runmode eq "random"){
          my $icon_url = "/geticon?oid=e4e6c8e123eae539d9622d68fcd5a18017434650b4561df6e51b783f";
      #    Logging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "chase"){ 
          my $icon_url =  "/geticon?oid=04384248b3d529e9d287be50a6e188a6668ef1f8d6df63c384dad395";
      #    Logging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "runaway" ){
          my $icon_url = "/geticon?oid=fe93fad485f8fae9aa9333730af31070dc7f01aa0afb03905d0011c0";
      #    Logging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "round" ){
          my $icon_url = "/geticon?oid=78d6ef1151276a034839d822cb3a7a89b2179fbadb612ed850c744c9";
      #    Logging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "STAY"){ 
          my $icon_url = "/geticon?oid=a0526942cbb91b158716c273e34d080e70e9e0eba2214c221038f6be";
      #    Logging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "search"){
          my $icon_url = "/geticon?oid=3e6d105fbcc97a6c8716ecf9b81a2c68519c817006778576ae9632da";
      #    Logging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        }
          undef $runmode;
        return; #そのまま戻す
}


# 東経西経北緯南偉の範囲判定　１：東経北緯　２：西経北緯　３：東経南偉　４：西経南偉
# 方位判定は北極基準で360度の判定。結果、同じ方角でも境目を超えると値の増減が変わる為の判定
sub geoarea {
    my ($lat,$lng) = @_;

    my $resp = 1;

    if (( 0 < $lat) and ($lat < 180) and (0 < $lng) and ( $lng < 90)) { $resp = 1; }
    if ((-180 < $lat ) and ( $lat < 0 ) and ( 0 < $lng) and ( $lng < 90 )) { $resp = 2;}
    if (( 0 < $lat ) and ( $lat < 180 ) and ( -90 < $lng ) and ( $lng < 0 )) { $resp = 3;}
    if ((-180 < $lat ) and ( $lat < 0 ) and ( -90 < $lng ) and ( $lng < 0 )) { $resp = 4;}

    undef $lat;
    undef $lng;

    return $resp ;
}


# -90 < $lat < 90
sub overArealat {
    my $ghostid = shift;
        # 南半球は超えても南半球
        if ( $ghostid->{loc}->{lat} < -90 ) {
            my $dif = abs($ghostid->{loc}->{lat}) - 90;           
            $ghostid->{loc}->{lat} = -90 + $dif;
            $ghostid->{rundirect} = $ghostid->{rundirect} - 180; #グローバル変数に方向性を変更
            undef $dif;
            return $ghostid;
         }
        # 北半球は超えても北半球
        if ( 90 < $ghostid->{loc}->{lat} ) {
            my $dif = $ghostid->{loc}->{lat} - 90;
            $ghostid->{loc}->{lat} = 90 - $dif;
            $ghostid->{rundirect} = $ghostid->{rundirect} + 180; #グローバル変数に方向性を変更
            undef $dif;
            return $ghostid;
         }
    return $ghostid; # スルーの場合
}


# -180 < $lng < 180
sub overArealng {
    my $ghostid = shift;

        if ( $ghostid->{loc}->{lng} > 180 ) {
            my $dif = $ghostid->{loc}->{lng} - 180;
            $ghostid->{loc}->{lng} = -180 + $dif;
            undef $dif;
            return $ghostid;
            }
        if ( -180 > $ghostid->{loc}->{lng} ) {
            my $dif = abs($ghostid->{loc}->{lng}) - 180;
               $ghostid->{loc}->{lng} = 180 - $dif;
            undef $dif;
            return $ghostid;
           }
    return $ghostid; # スルーの場合
}


sub NESW { deg2rad($_[0]), deg2rad(90 - $_[1]) }


# 2点間の方角を算出 (度) 
sub geoDirect {
    my ($lat1, $lng1, $lat2, $lng2) = @_;

    my $Y = cos ($lng2 * pi / 180) * sin($lat2 * pi / 180 - $lat1 * pi / 180);

    my $X = cos ($lng1 * pi / 180) * sin($lng2 * pi / 180 ) - sin($lng1 * pi /180) * cos($lng2 * pi / 180 ) * cos($lat2 * pi / 180 - $lat1 * pi / 180);

    my $dirE0 = 180 * atan2($Y,$X) / pi;
    if ($dirE0 < 0 ) {
        $dirE0 = $dirE0 + 360;
       }
    my $dirN0 = ($dirE0 + 90) % 360;

    undef $lat1;
    undef $lng1;
    undef $lat2;
    undef $lng2;
    undef $Y;
    undef $X;
    undef $dirE0;

    return $dirN0;
}


    sub kmlatlng {
            my ( $lat , $lng ) = @_;
                           # 緯度によって変化する1km当たりの度数を返す
                           my $R = 6378.1; #km 
                           my $cf = cos( $lat / 180 * pi) * 2 * pi * $R; # 円周 km
                           my $kd = $cf / 360 ;  # 1度のkm
                           my $lng_km = 1 / $kd; # 軽度/1km

                           # 緯度 一定
                           my $cd = 2 * pi * $R;  # 円周 km
                           my $lat_d = $cd / 360 ;  # 1度 km
                           my $lat_km = 1 / $lat_d ; # 1km の 緯度

                           #上限値、下限値判定はパス   合わせて2kmの範囲
                           # 東経北緯の範囲のみ
                           my $lat_max = $lat + $lat_km;
                           my $lat_min = $lat - $lat_km;

                           my $lng_max = $lng + $lng_km;
                           my $lng_min = $lng - $lng_km;

                           return ( $lat_min , $lat_max , $lng_min , $lng_max ) ;
   }


sub writedata {
    my $ghostid = shift;

       $ghostid->{ttl} = time();

       $ghostid->{icon_url} = iconchg($ghostid->{status}); 

    my $ghostidjson = to_json($ghostid);

       $redis->db->hset($keyword , $ghostid->{uid} , $ghostidjson );

       $pg->db->insert('walkworld', { 'data' => $ghostidjson } );

       Logging("write ghostdata | $ghostidjson");

       undef $ghostidjson;
       undef $ghostid;

    return;
}


sub d_correction {
    # rundirectへの補正を検討する   d_correction($npcuser_stat,@pointlist); で利用する
    my ($ghostid,@pointlist) = @_;

    Logging("DEBUG: d_correction: in: $ghostid->{rundirect} pointlist: $#pointlist");

    # 空なら0を返す
    if (! @pointlist){
        Logging("DEBUG: d_correction: out: $ghostid->{rundirect}");

	undef @pointlist;
        return $ghostid;
    }

    my @userslist = ();

    #自分を除外
    for my $i (@pointlist){
        if ( $i->{uid} eq $ghostid->{uid}){
           next;
           }
        push(@userslist,$i);
    }

    # UNITが居ない場合
    if (! @userslist){
       Logging("DEBUG: d_correction: out: $ghostid->{rundirect}");

       undef @pointlist;
       return $ghostid;
    }

    # 追跡ターゲットが設定されていた場合,ターゲットは回避対象から外す
    if ( $ghostid->{target} ){
        for (my $i=0; $i <= $#userslist; $i++){
            if ( $pointlist[$i]->{uid} eq $ghostid->{target} ){
                 Logging("DROP userslist: $userslist[$i]->{name} ");
                 splice(@userslist,$i,1);
                 last;
            }
        } # for
    } # if

   my @usersdirect = ();

   # 距離と方角を計算する 距離が50m以下のみを抽出
   for my $i (@userslist){

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($ghostid->{loc}->{lng}, $ghostid->{loc}->{lat});
              my @t_p = NESW($i->{loc}->{lng}, $i->{loc}->{lat});
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($ghostid->{loc}->{lat}, $ghostid->{loc}->{lng}, $i->{loc}->{lat}, $i->{loc}->{lng});
              my $dist_direct = { "dist" => $t_dist, "direct" => $t_direct };
              push(@usersdirect,$dist_direct) if ($t_dist < 50);    
   }

   undef @userslist;

   # 50m以内に居ない
   if (! @usersdirect) {
       Logging("DEBUG: d_correction: out: $ghostid->{rundirect}");

       undef @pointlist;
       return $ghostid;
   }
   
   for my $i (@usersdirect){
       
       my $cul_direct = $ghostid->{rundirect} - $i->{direct};

       if ( ($cul_direct > 45 ) || ($cul_direct < -45)){
          # 進行方向左右45度以外(補正範囲外）
          Logging("DEBUG: d_correction: out: $ghostid->{rundirect}");

	  undef @pointlist;
          return $ghostid;
       }

       if (( $cul_direct < 45 ) && ( $cul_direct > 0)) {
          # 補正左に45度
          $ghostid->{rundirect} = $ghostid->{rundirect} - 45;
          if ($ghostid->{rundirect} < 0 ) {
             $ghostid->{rundirect} = 360 + $ghostid->{rundirect};
          } 
          Logging("DEBUG: d_correction: out: $ghostid->{rundirect}");

          # lat lngへの補正
          $ghostid = latlng_correction($ghostid);

	  undef @pointlist;
          return $ghostid;
       }
       if (( $cul_direct > -45 ) && ( $cul_direct < 0 )) {
          # 補正右に45度
          $ghostid->{rundirect} = $ghostid->{rundirect} + 45;
          if ($ghostid->{rundirect} > 360){
             $ghostid->{rundirect} = $ghostid->{rundirect} - 360;
          }
          Logging("DEBUG: d_correction: out: $ghostid->{rundirect}");

          # lat lngへの補正
          $ghostid = latlng_correction($ghostid);

	  undef @pointlist;
          return $ghostid;
       }
   } # for
   Logging("DEBUG: d_correction: out: $ghostid->{rundirect}");

   undef @usersdirect;
   undef @pointlist;
   return $ghostid;  # 念のため
} # d_crrection


sub latlng_correction {
    # d_correction用に補正したrundirectからlat or lngのどちらに補正するか判定する
    # 45度単位で分割して補正する
    my $ghostid = shift;

    if ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 1 ){
        # 東経北緯
        if (( $ghostid->{rundirect} > 315 )||( $ghostid->{rundirect} < 45 )){
             # 北方向へ補正
             $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + 0.0001;
             $ghostid = overArealat($ghostid);
             Logging("DEBUG: lat+ correction");
             return $ghostid;
           } elsif (($ghostid->{rundirect} > 45 ) || ( $ghostid->{rundirect} < 135)){
             # 東方向へ補正
             $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + 0.0001;
             $ghostid = overArealng($ghostid);
             Logging("DEBUG: lng+ correction");
             return $ghostid;
           } elsif (( $ghostid->{rundirect} > 135 ) || ( $ghostid->{rundirect} < 225 )){
             # 南方向へ補正
             $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - 0.0001;
             $ghostid = overArealat($ghostid);
             Logging("DEBUG: lat- correction");
             return $ghostid;
           } elsif (( $ghostid->{rundirect} > 225 ) || ( $ghostid->{rundirect} < 315 )) {
             # 西方向へ補正
             $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - 0.0001;
             $ghostid = overArealng($ghostid);
             Logging("DEBUG: lng- correction");
             return $ghostid;
           }
       } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 2) {
       # 西経北緯 

       } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 3) {
       # 東経南緯

       } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 4) {
       # 西経南緯
       
       }
}


sub baseloop {
# メインループ
    my $ghostid = shift;

    my $ghostidjson = to_json($ghostid);
    Logging("get ghostid $ghostidjson");
    undef $ghostidjson;

    #初期化
    if (! defined $ghostid->{icon_urli}) {
        $ghostid->{icon_url} = "/geticon?oid=e4e6c8e123eae539d9622d68fcd5a18017434650b4561df6e51b783f";
    }


    if (( ! defined $ghostid->{status} ) || ( $ghostid->{status} eq "")){
        $ghostid->{status} = "random";
    }

    if ( ! defined $ghostid->{rundirect} ){
        $ghostid->{rundirect} = int(rand(360));
    }

    my $targets;

    Logging("init set or passed");

    # lifecount処理
    $ghostid->{lifecount}--;
    if ($ghostid->{lifecount} <= 0 ){
       Logging("Time out $ghostid->{name}");

       $redis->db->hdel($keyword , $ghostid->{uid} );

       $pg->db->query("delete from walkworld where data->>'uid' = ?" , $ghostid->{uid} );

       undef $ghostid;
       undef $targets;

      return; 
    }


    #周辺情報の取得
    my ( $lat_min , $lat_max , $lng_min, $lng_max ) = &kmlatlng($ghostid->{loc}->{lat} , $ghostid->{loc}->{lng} ); 

    my $lat_spn = ((($lat_max - $lat_min) / 2) / 1000); # 1m相当 度数
    my $lng_spn = ((($lng_max - $lng_min) / 2) / 1000);

    Logging("spn: $lat_spn | $lng_spn ");

    $ghostid->{point_spn} = [ $lat_spn , $lng_spn ];

    undef $lat_spn;
    undef $lng_spn;

    my $res = $pg->db->query("select data from walkworld where (data->'loc'->>'lng')::numeric < $lng_max and 
                                                           (data->'loc'->>'lng')::numeric > $lng_min and 
                                                           (data->'loc'->>'lat')::numeric < $lat_max and 
                                                           (data->'loc'->>'lat')::numeric > $lat_min order by id DESC")->hashes;
    undef $lng_max;
    undef $lng_min;
    undef $lat_max;
    undef $lat_min;

    # my $debug = to_json($res);
    #Logging("res: $debug");    
    if (!@$res){
        Logging("DEBUG: pg response nothing");
    }

    my $hashlist = ();
    for my $a (@$res){
        my $data = from_json($a->{data});
	
	if ( $data->{category} eq 'MESSAGE' ){  # MESSAGEイベントは除外する
            next;
	}

        my @listuid = ();
        for my $line (@$hashlist){    #登録済のuidをリスト (重複排除）
            push(@listuid, $line->{uid});
        }
	#  Logging("DEBUG: listuid: @listuid");

        my $flg = 0;
        for my $i (@listuid){
		#  Logging("DEBUG: cmp listuid: $data->{uid} | $i ");
            if ( $data->{uid} eq $i ){
                       $flg = 1;  # uidが既存だと1
                       }
        }

      undef @listuid;

	#  Logging("DEBUG: flg: $flg");
        if ( $flg == 0 ) { # uidが存在しないと
                       push(@$hashlist, $data );
                      }
	undef $data;
      } # for res
      
      undef $res;

      # makercheck用
      my @makerlist = ();
      for my $line (@$hashlist){
          if ( $line->{category} eq 'TOWER' ) {
              push(@makerlist , $line);
          }
      } 
      
      my @userlist = ();
      for my $line (@$hashlist){
          if ( $line->{category} eq 'USER' ){
              push(@userlist, $line);
	  }
      }

      my @npclist = ();
      for my $line (@$hashlist){
          if ( $line->{category} eq 'NPC' ){
              push(@npclist, $line);
	  }
      }

      # trapHitCheck
      Logging("Trapevent check");
      # my $lat_1m = ($ghostid->{point_spn}[0] / 5) /2 ;
      # my $lng_1m = ($ghostid->{point_spn}[1] / 5) /2 ;
      my $lat_1m = $ghostid->{point_spn}[0];  # spnを1mに変更したため
      my $lng_1m = $ghostid->{point_spn}[1];
      for my $line ( @$hashlist ){

          if ( $line->{category} eq 'MINE' ){

               if (( $line->{loc}->{lat} >= $ghostid->{loc}->{lat} - $lat_1m ) && ( $line->{loc}->{lat} <= $ghostid->{loc}->{lat} + $lat_1m )
	         && ( $line->{loc}->{lng} >= $ghostid->{loc}->{lng} - $lng_1m ) && ( $line->{loc}->{lng} <= $ghostid->{loc}->{lng} + $lng_1m) 
	          ) {
                  # hit trap

		  Logging(" trap hit $ghostid->{name} ");
		  $redis->db->hdel('trapeventEntry', $line->{uid});   # trap削除
                  $pg->db->query("delete from walkworld where data->>'uid' = ?" , $line->{uid} );

		  # ghost削除
                  $redis->db->hdel($keyword, $ghostid->{uid} );
                  $pg->db->query("delete from walkworld where data->>'uid' = ?" , $ghostid->{uid} );

                  my $mess = { type => 'openchat',
                               text => "ぐふぉ、トラップに引っかかった",
                               user => $ghostid->{name},
                           icon_url => $ghostid->{icon_url},
	                     };
	          my $messjson = to_json($mess);
	             $pubsub->notify('openchat', $messjson);

                  undef $messjson;
	          undef $mess;
	          undef $hashlist;
	          undef $ghostid;
		  undef $lat_1m;
		  undef $lng_1m;
                 
		  return;

		  }
          } # MINE
      } #for

     # Makerがある場合の処理 targetをmakerに変更してstatをchaseに
       if (@makerlist) {
           Logging("makerlist FOUND");
           my $skipflg = 0;   # targetがmakerの場合を判定する
           if (( $ghostid->{status} eq 'chase' )||($ghostid->{status} eq 'round')) {
               for my $i ( @makerlist ) {
                   if ( $ghostid->{target} eq $i->{uid} ){
                       $skipflg = 1;   # makerを追っている
                       last;
                   }
               }
	       Logging("$ghostid->{name} not chase tower") if ( $skipflg == 0 );
            }  # if chase 

	    if ( $skipflg == 0 ) {
               my $spm = int(rand($#makerlist));

               $ghostid->{target} = $makerlist[$spm]->{uid};
               $ghostid->{status} = "chase";
               Logging("Mode change Chase! to Tower");
               writedata($ghostid);
	       undef $spm;

              my $mess = { type => 'openchat',
                           text => "タワーみっけた",
                           user => $ghostid->{name},
                       icon_url => $ghostid->{icon_url},
	                 };
	      my $messjson = to_json($mess);
	         $pubsub->notify('openchat', $messjson);

		 undef $mess;
		 undef $messjson;
	     }

       } else {     # if @makerlist
           # USERがいる場合、ghostの誰かが追跡する
	   # まず、chseされていないユーザーを探す
	   Logging("non Chase User CHECK!");
	   my @chaseUser = ();
           if (@userlist) {
	   #  Logging("USER LIST FOUND");
               for my $line (@userlist){
                   for my $i (@npclist){
                       if ( $i->{target} eq $line->{uid} ){
                           push(@chaseUser, $line);
                       }
		   }
	       }
	       undef @npclist;
               my @nonChaseUser = ();
	       #  Logging("Chased user FOUND ") if (@chaseUser);
               for my $i (@userlist){
	           my $flg = 0;
                   for my $j (@chaseUser){
                       if ($j->{uid} eq $i->{uid} ){
                           $flg = 1;
	               }
		   }
		   push(@nonChaseUser, $i) if ( $flg == 0 );
	        }# $i 
		undef @chaseUser;
		#  Logging("non Chase USER FOUND!") if (@nonChaseUser);

               # 自分が追跡しておらず、chaseされていないユーザがいた場合
	       if (( $ghostid->{status} ne 'chase')&&(@nonChaseUser)){

                   $ghostid->{status} = 'chase';
		   $ghostid->{target} = $nonChaseUser[0]->{uid};

		   my $mess = { type => 'openchat',
		                text => "みっけたから追っかける。。。",
		                user => $ghostid->{name},
		            icon_url => $ghostid->{icon_url},
		              };
		   my $messjson = to_json($mess);
		      $pubsub->notify('openchat', $messjson);

		   undef $mess;
		   undef $messjson;

               } # if  not chase
               undef @nonChaseUser;
	   } #if @userlist
       } # else

       undef @userlist;

       # {chasecnt}が剰余0になると分裂する chasecntが0は除外する 連続しないために5%の確率を付与する
       if ( ($ghostid->{chasecnt} % 100 == 0) && ($ghostid->{chasecnt} != 0) && ( int(rand(1000)) <= 50 ) ) {

           Logging("ghostが分裂");
           my @latlng = &kmlatlng($ghostid->{loc}->{lat}, $ghostid->{loc}->{lng});
           my $kmlat_d = ($latlng[1] - $latlng[0]) / 2; # (max - min ) / 2
           my $kmlng_d = ($latlng[3] - $latlng[2]) / 2;

           my $g_lat = $ghostid->{loc}->{lat} + ((rand($kmlat_d)) - ($kmlat_d / 2)); # 1kmあたりを乱数で、500m分を引いて+-が出るように 
           my $g_lng = $ghostid->{loc}->{lng} + ((rand($kmlng_d)) - ($kmlng_d / 2));
           my $num = int(rand(9999999));
           my $name = "ghost$num";
           my $uid = Sessionid->new($name)->uid;

           my $ghostacc = {"name" => $name,
                       "icon_url" => "",
                            "uid" => $uid,
                            "run" => "",
                            "loc" => {"lat" => $g_lat, "lng" => $g_lng},
                         "status" => "",
                      "rundirect" => 0,
                         "target" => "",
                       "category" => "NPC",
                            "ttl" => "",
                          "place" => { "lat" => 0, "lng" => 0, "name" => ""},
                      "point_spn" => [],
                      "uifecount" => 21600,   # 6hour  /sec
                       "hitcount" => 0,
                       "chasecnt" => 0 ,
                         };

            my $ghostaccjson = to_json($ghostacc);
               $redis->db->hset($keyword, $uid , $ghostaccjson );

             my $mess = { type => 'openchat',
                          text => "あれっ分身した。。。",
                          user => $ghostid->{name},
                      icon_url => $ghostid->{icon_url},
	                };
	     my $messjson = to_json($mess);
	        $pubsub->notify('openchat', $messjson);

		$ghostid->{chasecnt} = 0 if ( $ghostid->{chasecnt} >= 1000 );

             undef $messjson;
	     undef $mess;
	     undef $ghostacc;
	     undef $ghostaccjson;
	     undef $uid;
	     undef $name;
	     undef $num;
	     undef $g_lat;
	     undef $g_lng;
	     undef $kmlat_d;
	     undef $kmlng_d;
             undef @latlng;
       }

       # tower配置処理、chasecntが1000を前提にに確率で配置する 乱数がchasecntと一致した場合
       if ( ($ghostid->{chasecnt} == int(rand(1000))) && ( int(rand(1000)) <= 50 ) ) { 
           Logging("TOWERの設置");
           my @latlng = &kmlatlng($ghostid->{loc}->{lat}, $ghostid->{loc}->{lng});
           my $kmlat_d = ($latlng[1] - $latlng[0]) / 2; # (max - min ) / 2
           my $kmlng_d = ($latlng[3] - $latlng[2]) / 2;
           my $lat = $ghostid->{loc}->{lat} + ($kmlat_d / 1000); # 1mずらす
           my $lng = $ghostid->{loc}->{lng} + ($kmlng_d / 1000);
           my $uid = Sessionid->new($ghostid->{name})->uid;

           my $trap = { "setuser" => $ghostid->{name},
                           "name" => 'tower',
                            "loc" => { "lat" => $lat , "lng" => $lng },
                            "uid" => $uid,
                       "category" => "TOWER",
                       "icon_url" => "https://westwind.backbone.site/geticon?oid=13525cd44fdd5a34f19da7794c4c43a972ff759a9fbcab06bd322712",
                            "ttl" => time(),
                       "ttlcount" => 120,
                      "rundirect" => 0,
                      };
           my $trapjson = to_json($trap);
              $redis->db->hset("trapeventEntry", $uid , $trapjson);

             my $mess = { type => 'openchat',
                          text => "TOWERをぽいっと",
                          user => $ghostid->{name},
                      icon_url => $ghostid->{icon_url},
	                };
	     my $messjson = to_json($mess);
	        $pubsub->notify('openchat', $messjson);

		$ghostid->{chasecnt} = 0 if ( $ghostid->{chasecnt} >= 1000 );

             undef $messjson;
	     undef $mess;
	     undef $trap;
	     undef $trapjson;
	     undef $uid;
	     undef $lat;
	     undef $lng;
	     undef $kmlat_d;
	     undef $kmlng_d;
             undef @latlng;
       }

    # 以下はstatusで分岐する

      # テスト用　位置保持
      if ( $ghostid->{status} eq "STAY") {
             $ghostid->{icon_url} = iconchg($ghostid->{status});
             writedata($ghostid);

             my $mess = { type => 'openchat',
                          text => "STAY desuyo",
                          user => $ghostid->{name},
                      icon_url => $ghostid->{icon_url},
	                };
	     my $messjson = to_json($mess);
	        $pubsub->notify('openchat', $messjson);

            undef $messjson;
	    undef $mess;
	    undef $hashlist;
	    undef $ghostid;

            return; 
       }

      my $runway_dir = 1;

      # ランダム移動処理
      if ( $ghostid->{status} eq "random" ){

            #周囲にユニットが在るか確認
            @$targets = ();
            #自分をリストから除外する
            for my $i (@$hashlist){
                if ( $i->{uid} eq $ghostid->{uid}){
                     next;
                }
                push(@$targets,$i);
            }

             # CHECK
	     my @chk_targets = ();
	     for my $line (@$targets){
                 push(@chk_targets, $line) if ( $line->{category} ne 'MINE');  # NPC,TOWER,USERに限る
             } 
	undef $targets;     
        Logging("DEBUG: random chk_targets: $#chk_targets");
	#  undef @chk_targets;

        # 初期方向
        $runway_dir = 1 if (! defined $runway_dir);

        if ($ghostid->{rundirect} < 90) { $runway_dir = 1; }
        if (( 90 <= $ghostid->{rundirect})&&( $ghostid->{rundirect} < 180)) { $runway_dir = 2; }
        if (( 180 <= $ghostid->{rundirect})&&( $ghostid->{rundirect} < 270 )) { $runway_dir = 3; }
        if (( 270 <= $ghostid->{rundirect})&&( $ghostid->{rundirect} < 360 )) { $runway_dir = 4; } 

        if ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 1){

            # 東経北緯
            if ($runway_dir == 1) {
                      $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + $ghostid->{point_spn}[0];
                      $ghostid = overArealat($ghostid);        #規定値超え判定 rundirectも変更している
                      $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + $ghostid->{point_spn}[1];
                      $ghostid = overArealng($ghostid);        #規定値超え判定
                      $ghostid->{rundirect} = $ghostid->{rundirect} + int(rand(90)) - int(rand(90));
                      if ($ghostid->{rundirect} <= 0 ) {
                         $ghostid->{rundirect} = $ghostid->{rundirect} + 359;
                         }
                      }
            if ($runway_dir == 2) {
                      $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - $ghostid->{point_spn}[0];
                      $ghostid = overArealat($ghostid);
                      $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + $ghostid->{point_spn}[1];
                      $ghostid = overArealng($ghostid);
                      $ghostid->{rundirect} = $ghostid->{rundirect} + int(rand(90)) - int(rand(90));
                      }

            if ($runway_dir == 3) {
                      $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - $ghostid->{point_spn}[0];
                      $ghostid = overArealat($ghostid);
                      $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - $ghostid->{point_spn}[1];
                      $ghostid = overArealng($ghostid);
                      $ghostid->{rundirect} = $ghostid->{rundirect} + int(rand(90)) - int(rand(90));
                      }

            if ($runway_dir == 4) {
                      $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + $ghostid->{point_spn}[0];
                      $ghostid = overArealat($ghostid);
                      $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - $ghostid->{point_spn}[1];
                      $ghostid = overArealng($ghostid);
                      $ghostid->{rundirect} = $ghostid->{rundirect} + int(rand(90)) - int(rand(90));
                      if ($ghostid->{rundirect} >= 360 ) {
                         $ghostid->{rundirect} = $ghostid->{rundirect} - 359;
                         }
                      }
                } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 2 ) {
                # 西経北緯

                  #保留

                } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 3 ) {
                # 東経南偉

                  #保留

                } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 4 ) {
                # 西経南偉

                  #保留

                } # geoarea if

		Logging("random move");

                # 補正
                $ghostid = d_correction($ghostid,@$hashlist);

                # モード変更チェック 

                if (($ghostid->{status} eq "random" ) && ( $#chk_targets > 20 )) {
                   # runawayモードへ変更
                          $ghostid->{status} = "runaway";
                          Logging("Mode change Runaway!");
                          writedata($ghostid);

			  my $mess = { type => 'openchat',
			             text => "ごみごみしているよ・・・",
			             user => $ghostid->{name},
			             icon_url => $ghostid->{icon_url},
			           };
			  my $messjson = to_json($mess);
			   $pubsub->notify('openchat', $messjson);

			undef $mess;
			undef $messjson;
			undef $ghostid;
			undef $hashlist;

                          return;
                 }

                   if (int(rand(50)) > 48) {

                        if ($#chk_targets == -1) { return; } #pass

                        $ghostid->{status} = "chase";
                        Logging("Mode change Chase!");
                        writedata($ghostid);

			my $mess = { type => 'openchat',
			             text => "追っかけるるる。。。",
			             user => $ghostid->{name},
			             icon_url => $ghostid->{icon_url},
			           };
			my $messjson = to_json($mess);
			   $pubsub->notify('openchat', $messjson);

		       undef $mess;
		       undef $messjson;
	               undef $ghostid;
                       undef @chk_targets; 
	               undef $hashlist;
                        return;
                   } elsif (int(rand(50)) > 48 ) {

                        if ($#chk_targets == -1) { return; } #pass

                        $ghostid->{status} = "round";
                        Logging("Mode change Round!");
                        writedata($ghostid);

			my $mess = { type => 'openchat',
			             text => "ぐるぐるぐるぐる・・・",
			             user => $ghostid->{name},
			             icon_url => $ghostid->{icon_url},
			           };
			my $messjson = to_json($mess);
			   $pubsub->notify('openchat', $messjson);

		       undef $mess;
	   	       undef $messjson;
	               undef $ghostid;
                       undef @chk_targets; 
	               undef $hashlist;
                        return;
                   } elsif (int(rand(50)) > 48 ) {

                        if ($#chk_targets == -1) { return; } #pass

                        $ghostid->{status} = "runaway";
                        Logging("Mode change Runaway!");
                        writedata($ghostid);

		        my $mess = { type => 'openchat',
			             text => "すたこらさっさ。。。",
			             user => $ghostid->{name},
			             icon_url => $ghostid->{icon_url},
			           };
		       my $messjson = to_json($mess);
			  $pubsub->notify('openchat', $messjson);

		       undef $mess;
		       undef $messjson;
	               undef $ghostid;
                       undef @chk_targets; 
	               undef $hashlist;
                       return;
                    }

              $ghostid->{status} = 'random';

              writedata($ghostid);
	      undef $targets;
	      undef $ghostid;
              undef @chk_targets; 
	      undef $hashlist;
              return;
      } # random

    # 追跡モード
      my $t_obj;   # targetのステータス 毎度更新される
         @$targets = ();
             #自分をリストから除外する
             for my $i (@$hashlist){
                 if ( $i->{uid} eq $ghostid->{uid}){
                     next;
                     }
                     push(@$targets,$i);
                 }

       if ( $ghostid->{status} eq "chase" ){

             # CHECK
	     my @chk_targets = ();
	     for my $line (@$targets){
                 push(@chk_targets, $line) if ( $line->{category} ne 'MINE');  # NPC,TOWER,USERに限る
             } 

             Logging("DEBUG: Chase Targets $#chk_targets ");

             if (($ghostid->{target} eq "")&&($#chk_targets != -1)) {
		     #  my @t_list = @$targets; 
                     my @t_list = @chk_targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $ghostid->{target} = $t_list[$tnum]->{uid};
                     Logging("target: $ghostid->{target} : $lc : $tnum : $t_list[$tnum]->{name}"); 
                     undef @t_list;
                     undef $lc;
                     undef $tnum;

                     #ターゲットステータスの抽出
                     foreach my $t_p (@$targets){
                             if ( $t_p->{uid} eq $ghostid->{target}){
                                $t_obj = $t_p;
                                }
                             } 
		 	 my $mess = { type => 'openchat',
		 	              text => "$t_obj->{name}を追跡中。。。",
		 	              user => $ghostid->{name},
		 	          icon_url => $ghostid->{icon_url},
		                    };
		 	 my $messjson = to_json($mess);
		 	 $pubsub->notify('openchat', $messjson);

		 	 undef $mess;
		 	 undef $messjson;
                } # target = "" & $#chk_targets != -1

              #ターゲットステータスの抽出
                 foreach my $t_p (@$targets){
                         if ( $t_p->{uid} eq $ghostid->{target}){
                            $t_obj = $t_p;
                            }
                         } 

              # ターゲットをロストした場合 random-mode
              if ( ! defined $t_obj->{name} ) {
                 $ghostid->{status} = "random"; 
                 $ghostid->{target} = ""; 
                 writedata($ghostid);
                 Logging("Mode Change........radom. Lost object name...");
		 
		  my $mess = { type => 'openchat',
		 	      text => "あれ？、見失った。。。",
			      user => $ghostid->{name},
		 	      icon_url => $ghostid->{icon_url},
		      };
		  my $messjson = to_json($mess);
		     $pubsub->notify('openchat', $messjson);

		 	 undef $mess;
		 	 undef $messjson;
		 undef $ghostid;
		 undef $hashlist;
		 undef @chk_targets;
		 undef $targets;
                 return;
              }

	      #  my $deb_obj = to_json($t_obj); 
	      #  Logging("DEBUG: ======== $deb_obj ========"); 
	      #  undef $deb_obj;

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($ghostid->{loc}->{lng}, $ghostid->{loc}->{lat});
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($ghostid->{loc}->{lat}, $ghostid->{loc}->{lng}, $t_lat, $t_lng);
                 $ghostid->{rundirect} = $t_direct;
              undef @s_p;
              undef @t_p;
	      undef $t_lat;
	      undef $t_lng;

              Logging("Chase Direct: $t_direct Distace: $t_dist ");

              my $addpoint = 0.00001;
	      if ( $t_dist > 30 ){
                 $addpoint =  ( $t_dist / 2000000 ) if ( defined $t_dist );
                 Logging("DEBUG: addpoint: $addpoint $ghostid->{name} ");
	      }

              my $directchk = 180;  # 初期値は大きく

                 $directchk = abs ( $t_direct - $t_obj->{rundirect}) ;
              #進行方向が同じ場合には、 追い越す:
              if (( $directchk < 45 ) && ($t_dist > 20 ) && (int(rand(359)) == $t_obj->{rundirect})){
		      #  $addpoint = ( int( $t_dist / 250 ) * $ghostid->{point_spn}[1]) if ( defined $t_dist );   # 最大4倍くらいの加速
                     $addpoint = 1; #急激に飛ぶ

                  if ( $addpoint == 0 ){
                       $addpoint = $addpoint + 0.00001;
	          }

                 Logging("DEBUG: addpoint: $addpoint $ghostid->{name} ");
                 if ( ! defined $addpoint ) {
                     $addpoint = 0;
                 }
              } elsif ( int(rand(1000)) < 10 ) {
                  $addpoint = 1;
	      }

              my $runway_dir = 1;   # default

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 <= $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 <= $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 <= $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

              if ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 1 ) {

              # 追跡は速度を多めに設定 30m以上離れている場合は高速モード
              if ($runway_dir == 1) {
                 if ( $t_dist > 10 ) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + ($ghostid->{point_spn}[0] + $addpoint);   # addpointは基本０ 条件で可算:
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                    } else {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + $ghostid->{point_spn}[0];
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + $ghostid->{point_spn}[1];
                        $ghostid = overArealng($ghostid);
                          }}

              if ($runway_dir == 2) {
                 if ( $t_dist > 10 ){
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - ($ghostid->{point_spn}[0] + $addpoint);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                    } else {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - $ghostid->{point_spn}[0];
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + $ghostid->{point_spn}[1];
                        $ghostid = overArealng($ghostid);
                          }}

              if ($runway_dir == 3) {
                 if ( $t_dist > 10 ){
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - ($ghostid->{point_spn}[0] + $addpoint);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                    } else {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - $ghostid->{point_spn}[0];
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - $ghostid->{point_spn}[1];
                        $ghostid = overArealng($ghostid);
                          }}

              if ($runway_dir == 4) {
                 if ( $t_dist > 10 ){
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + ($ghostid->{point_spn}[0] + $addpoint);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                    } else {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + $ghostid->{point_spn}[0];
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - $ghostid->{point_spn}[1];
                        $ghostid = overArealng($ghostid);
                          }}

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 2 ) {

                #保留

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 3 ) {

                #保留

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 4 ) {

                #保留

              } # geoarea if

              $addpoint = 0;   # 初期化:

                # 補正
              $ghostid = d_correction($ghostid,@$hashlist);

              # 5m以下に近づくとモードを変更  chase時のペナルティーは現在未定義
              if ($t_dist < 5 ) {

              # NPCがUSERに近づいた場合にカウントダウンをする  t_objと$ghostid->{target}から算出
              # targetがUSERの場合
                if ( $t_obj->{category} eq "USER" ) {
                        # USERにはdamagecountをupするイベントを
			
			my $mess = { "walkworld" => "hitdamage" ,
				      "sendto" => $t_obj->{wsid} ,
				      "hituser" => $ghostid->{name},
			            };
                        my $messjson = to_json($mess);
		        $pubsub->notify("$t_obj->{wsid}" , $messjson );
                        Logging("DEBUG: hitdamage send $ghostid->{name} to $t_obj->{name}");   # アカウントは{user}、　user_statでは{name}
			undef $mess;
			undef $messjson;

                 } elsif ( $t_obj->{category} eq "NPC" ){
                     # NPC to NPC
		     # ghostaccEntryから削除してwalkworldからも削除

                     $redis->db->hdel($keyword, $t_obj->{uid} );

                     $pg->db->query("delete from walkworld where data->>'uid' = ?" , $t_obj->{uid} );

                     my $mess = { "type" => "openchat",
                                  "text" => "$t_obj->{name}は討たれた。",
                                  "user" => $t_obj->{name},
                                  "icon_url" => $t_obj->{icon_url},
                                };
                     my $messjson = to_json($mess);
                     $pubsub->notify('openchat', $messjson);

		     undef $mess;
		     undef $messjson;

                 } elsif ( $t_obj->{category} eq "TOWER" ) {
                 
                     # TOWERに着いた
                     $ghostid->{status} = 'round';

		 }

		 $ghostid->{hitcount} = ++$ghostid->{hitcount};
                 $ghostid->{chasecnt} = ++$ghostid->{chasecnt};
                 $ghostid->{status} = "round"; 
                 $ghostid->{target} = "" if (!@makerlist);  # makerがない場合はクリア
                 writedata($ghostid);
                 Logging("Mode Change........round.");

		 #  my $mess = { type => 'openchat',
		 #             text => "周回モードになったよ",
		 #             user => $ghostid->{name},
		 #         icon_url => $ghostid->{icon_url},
		 #           };
		 #  my $messjson = to_json($mess);
		 #   $pubsub->notify('openchat', $messjson);

		 #  undef $mess;
		 #  undef $messjson;
		 undef $ghostid;
		 undef $hashlist;
		 undef @chk_targets;
		 undef $targets;
                 return;
              } # t_dist <5

              if (($ghostid->{status} eq "chase" ) && ( $#chk_targets > 20 )) {

                 # runawayモードへ変更
                        $ghostid->{status} = "runaway";
                        Logging("Mode change Runaway!");
                        writedata($ghostid);

			#   my $mess = { type => 'openchat',
			#             text => "逃走モードになったよ",
			#             user => $ghostid->{name},
			#         icon_url => $ghostid->{icon_url},
			#           };
			#  my $messjson = to_json($mess);
			#   $pubsub->notify('openchat', $messjson);

			#	undef $mess;
			#  undef $messjson;
			undef $ghostid;
			undef $hashlist;
		        undef @chk_targets;
		        undef $targets;
                        return;
              }
             # 確率で諦める @makerlistが無い場合
              if ((($ghostid->{status} eq "chase" ) && ( int(rand(100)) == $ghostid->{chasecnt} )) && !@makerlist) {

                 # randomモードへ変更
                        $ghostid->{status} = "random";
			$ghostid->{target} = "";
                        Logging("Mode change random!");
                        writedata($ghostid);

			my $mess = { type => 'openchat',
			             text => "えっと、何してたんだっけ？",
			             user => $ghostid->{name},
			         icon_url => $ghostid->{icon_url},
			           };
			my $messjson = to_json($mess);
			   $pubsub->notify('openchat', $messjson);

			undef $mess;
			undef $messjson;
			undef $ghostid;
			undef $hashlist;
		        undef @chk_targets;
		        undef $targets;
                        return;
                  }
              $ghostid->{status} = 'chase';

              writedata($ghostid);

	      undef $ghostid;
              undef $t_obj;
              undef $t_dist;
              undef $t_direct;
              undef @chk_targets; 
	      undef $hashlist;
	      undef $targets;
              return;
      } # chase

       # 逃走モード
       if ( $ghostid->{status} eq "runaway" ){

                #周囲にユニットが在るか確認
                     @$targets = ();
                     #自分をリストから除外する
                     for my $i (@$hashlist){
                         if ( $i->{uid} eq $ghostid->{uid}){
                         next;
                         }
                         push(@$targets,$i);
                     }
                #NPC以外のターゲットリスト
                     my @nonnpc_targets = ();
                     for my $i (@$hashlist){
                         if ( $i->{category} eq "USER" ){
                         next;
                         }
                         push(@nonnpc_targets,$i);
                     }

             # CHECK
	     my @chk_targets = ();
	     for my $line (@$targets){
                 push(@chk_targets, $line) if ( $line->{category} ne 'MINE');  # NPC,TOWER,USERに限る
             } 
             Logging("DEBUG: runaway Targets $#chk_targets ");

             if (($ghostid->{target} eq "")&&($#chk_targets != -1)) {

                  if ( $#chk_targets >= 20 ){
                     # 無差別にターゲットを決定して、行動する
		     #  my @t_list = @$targets; 
                     my @t_list = @chk_targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $ghostid->{target} = $t_list[$tnum]->{uid};
                     Logging("RUNAWAY target: $ghostid->{target} : $lc : $tnum : $t_list[$tnum]->{name}"); 
                     undef @t_list;
                     undef $lc;
                     undef $tnum;

                    } elsif ($#nonnpc_targets != -1 ){
                      # ターゲットが20以下の場合nonnpc_targetsから選択
                      my $lc = $#nonnpc_targets;
                      my $tnum = int(rand($lc));
                      $ghostid->{target} = $nonnpc_targets[$tnum]->{uid};
                      Logging("RUNAWAY target: $ghostid->{target} : $lc : $tnum : $nonnpc_targets[$tnum]->{name}"); 
                      undef $lc;
                      undef $tnum;
                    }
            } # if target="" chk_targets != -1

            # trapeventの設置 
             if ( int(rand(1000)) > 998 ){ 

                 Logging("Trapeventの設置 $ghostid->{name}");

                 my @latlng = &kmlatlng($ghostid->{loc}->{lat}, $ghostid->{loc}->{lng});
                 my $kmlat_d = ($latlng[1] - $latlng[0]) / 2; # (max - min ) / 2
                 my $kmlng_d = ($latlng[3] - $latlng[2]) / 2;
                 my $lat = $ghostid->{loc}->{lat} + ($kmlat_d / 1000); # 1mずらす
                 my $lng = $ghostid->{loc}->{lng} + ($kmlng_d / 1000);
                 my $uid = Sessionid->new($ghostid->{name})->uid;

                 my $trap = { "setuser" => $ghostid->{name},
                                 "name" => 'mine',
                                  "loc" => { "lat" => $lat , "lng" => $lng },
                                  "uid" => $uid,
                             "category" => "MINE",
                             "icon_url" => "https://westwind.backbone.site/geticon?oid=cc5408ecbccb006e0135c9685957297cea3657195e1c1b2437bc6dbe" ,
                                  "ttl" => time(),
                             };
                 my $trapjson = to_json($trap);

                 $redis->db->hset("trapeventEntry", $uid , $trapjson);

		 undef @latlng;
		 undef $kmlat_d;
		 undef $kmlng_d;
		 undef $lat;
		 undef $lng;
		 undef $uid;
		 undef $trap;
		 undef $trapjson;

             } # int(rand(1000))

             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{uid} eq $ghostid->{target}){
                        $t_obj = $t_p;
                        }
                     } 

              # ターゲットをロストした場合、randomモードへ
              if (! defined $t_obj->{name} ) {
                 $ghostid->{status} = "random"; 
                 $ghostid->{target} = ""; 
                 Logging("Mode Change........radom.");
                 # trap での自爆を避けるために少しずらす
                 $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + 0.0001;
                 writedata($ghostid);

		 my $mess = { type => 'openchat',
		             text => "逃げ切った？",
                             user => $ghostid->{name},
		         icon_url => $ghostid->{icon_url},
		            };
		 my $messjson = to_json($mess);
		    $pubsub->notify('openchat', $messjson);

		 undef $mess;
		 undef $messjson;
		 undef $ghostid;
		 undef $hashlist;
		 undef @chk_targets;
		 undef $targets;
		 undef @nonnpc_targets;
                 return;
                 }

              my $deb_obj = to_json($t_obj); 
              Logging("DEBUG: RUNAWAY ======== $deb_obj ========"); 
              undef $deb_obj;

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($ghostid->{loc}->{lng}, $ghostid->{loc}->{lat});
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($ghostid->{loc}->{lat}, $ghostid->{loc}->{lng}, $t_lat, $t_lng);
              undef @s_p;
              undef @t_p;

              Logging("RUNAWAY befor Direct: $t_direct ");

                 #逆方向へ設定
	if (0){
                 if ( $t_direct > 180 ) {
                    $t_direct = $t_direct - 180 + int(rand(45)) - int(rand(45));
                    if ( $t_direct < 0 ) { $t_direct = $t_direct + 45; }
                    } else {
                    $t_direct = $t_direct + 180 + int(rand(45)) - int(rand(45));
                    if ($t_direct > 360) { $t_direct = $t_direct - 45; }
                    }
	    } # block

	         if ( $t_direct <= 90 ) {
                    $t_direct = $t_direct + 90;
		 } elsif ( $t_direct <= 180 ) {
                    $t_direct = $t_direct + 90;
		 } elsif ( $t_direct <= 270 ) {
                    $t_direct = $t_direct - 90;
		 } elsif ( $t_direct <= 360 ) {
                    $t_direct = $t_direct - 90;
		 }

              Logging("RUNAWAY Direct: $t_direct Distace: $t_dist ");

                 $ghostid->{rundirect} = $t_direct;

              my $runway_dir = 1;

              if ($ghostid->{rundirect} < 90) { $runway_dir = 1; }
              if (( 90 <= $ghostid->{rundirect})&&( $ghostid->{rundirect} < 180)) { $runway_dir = 2; }
              if (( 180 <= $ghostid->{rundirect})&&( $ghostid->{rundirect} < 270 )) { $runway_dir = 3; }
              if (( 270 <= $ghostid->{rundirect})&&( $ghostid->{rundirect} < 360 )) { $runway_dir = 4; }

	      Logging("DEBUG: runway_dir: $runway_dir ");

              if ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 1 ) {

              if ($runway_dir == 1) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + ($ghostid->{point_spn}[0] + 0.0002) ;
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + ($ghostid->{point_spn}[1] + 0.0002);
                        $ghostid = overArealng($ghostid);
                          }
              if ($runway_dir == 2) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - ($ghostid->{point_spn}[0] + 0.0002);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + ($ghostid->{point_spn}[1] + 0.0002);
                        $ghostid = overArealng($ghostid);
                          }
              if ($runway_dir == 3) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - ($ghostid->{point_spn}[0] + 0.0002);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - ($ghostid->{point_spn}[1] + 0.0002);
                        $ghostid = overArealng($ghostid);
                          }
              if ($runway_dir == 4) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + ($ghostid->{point_spn}[0] + 0.0002);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - ($ghostid->{point_spn}[1] + 0.0002);
                        $ghostid = overArealng($ghostid);
                          }

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 2 ) {

                 #保留

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 3 ) {

                 #保留

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 4 ) {

                 #保留

              } # geoarea if

              # 補正
              $ghostid = d_correction($ghostid,@$hashlist);

              #ターゲットが規定以下の場合は
              if (($#chk_targets < 20) && (int(rand(50) > 45))) {
                        $ghostid->{status} = "round";
                        Logging("Mode change Round!");
                        writedata($ghostid);

			#  my $mess = { type => 'openchat',
			#             text => "周回モードになったよ",
			#             user => $ghostid->{name},
			#         icon_url => $ghostid->{icon_url},
			#           };
			#  my $messjson = to_json($mess);
			#   $pubsub->notify('openchat', $messjson);

			#	undef $mess;
			#	undef $messjson;
			undef $ghostid;
			undef $hashlist;
		        undef @chk_targets;
		        undef $targets;
                        return;

              # 1000m以上に離れるとモードを変更
              } elsif (($t_dist > 1000 ) && ($#chk_targets > 20)) {
                 $ghostid->{status} = "random"; 
                 $ghostid->{target} = "";
                 writedata($ghostid);
                 Logging("Mode Change........radom.");

		 my $mess = { type => 'openchat',
		              text => "ここまで来れば良いだろう。。。",
		              user => $ghostid->{name},
		          icon_url => $ghostid->{icon_url},
		            };
		 my $messjson = to_json($mess);
		    $pubsub->notify('openchat', $messjson);

		    undef $mess;
		    undef $messjson;
		    undef $ghostid;
		    undef $hashlist;
		    undef @chk_targets;
		    undef $targets;
                 return;
                 }

              $ghostid->{status} = 'runaway';
              writedata($ghostid);

	      undef $ghostid;
              undef $t_obj;
              undef @chk_targets;
              undef $t_dist;
              undef $t_direct;
	      undef $hashlist;
	      undef $targets;
              return;
        } # runaway

       # 周回動作
       if ( $ghostid->{status} eq "round" ){

                #周囲にユニットが在るか確認
                     @$targets = ();
                     #自分をリストから除外する
                     for my $i (@$hashlist){
                         if ( $i->{uid} eq $ghostid->{uid}){
                         next;
                         }
			 #   if ( $i->{category} eq "USER" ) {
			 #    for ( my $j=1; $j<=3 ; $j++ ){
			 #        push(@$targets,$i);    # userを増やす
			 #    }
			 #next;
			 #}
                         push(@$targets,$i);
                     }

             # CHECK
	     my @chk_targets = ();
	     for my $line (@$targets){
                 push(@chk_targets, $line) if ( $line->{category} ne 'MINE');  # NPC,TOWER,USERに限る
             } 
             Logging("DEBUG: round Targets $#chk_targets ");

             if ($ghostid->{target} eq "") {
		     #  my @t_list = @$targets; 
                     my @t_list = @chk_targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $ghostid->{target} = $t_list[$tnum]->{uid};
                     Logging("ROUND target: $ghostid->{target} : $lc : $tnum : $t_list[$tnum]->{name}"); 
                     undef @t_list;
                     undef $lc;
                     undef $tnum;
                }

             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{uid} eq $ghostid->{target}){
                        $t_obj = $t_p;
                        }
                     } 
              # ターゲットをロストした場合、randomモードへ
              if ( ! defined $t_obj->{name} ) {
                 $ghostid->{status} = "random";
                 $ghostid->{target} = "";
                 writedata($ghostid);
                 Logging("Mode Change........radom.");

		 #  my $mess = { type => 'openchat',
		 #             text => "randomモードになったよ",
		 #             user => $ghostid->{name},
		 #         icon_url => $ghostid->{icon_url},
		 #           };
		 #  my $messjson = to_json($mess);
		 #   $pubsub->notify('openchat', $messjson);

		 #   undef $mess;
		 #   undef $messjson;
		    undef $ghostid;
		    undef $hashlist;
		    undef @chk_targets;
		    undef $targets;
                 return;
                 }

              my $deb_obj = to_json($t_obj); 
              Logging("DEBUG: ROUND ======== $deb_obj ========"); 
              undef $deb_obj;

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($ghostid->{loc}->{lng}, $ghostid->{loc}->{lat});
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($ghostid->{loc}->{lat}, $ghostid->{loc}->{lng}, $t_lat, $t_lng);
              undef @s_p;
              undef @t_p;

              my $round_dire = 1;
              # 低い確率で方向が変わる
              if ( rand(50) > 45 ) {
              if ( rand(100) > 50 ) { 
                                    $round_dire = 1;
                                   } else { 
                                    $round_dire = 2;
                  }
              } # out rand

              # 右回りプラス方向
              if ( $round_dire == 1 ) {
                  $t_direct = $t_direct + 45;
                  if ( $t_direct > 360 ) { $t_direct = $t_direct - 360; }
              } else {
                  # 左回りマイナス方向
                  $t_direct = $t_direct - 45;
                  if ( $t_direct < 0 ) { $t_direct = $t_direct + 360 ;}
                }
              $ghostid->{rundirect} = $t_direct;

              my $runway_dir = 1;

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 <= $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 <= $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 <= $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

	      #  my $addpoint =  $t_dist / 30000 if ( defined $t_dist );   # 距離(m)を割る
              my $addpoint = ( $t_dist / 2000000 ) if ( defined $t_dist ); 
	         $addpoint = $addpoint + 0.00002;
                 if ( ! defined $addpoint ) {
                     $addpoint = $ghostid->{point_spn}[1];  # lngの値を共通値として利用する
                 }

             Logging("DEBUG: ROUND: t_dist: $t_dist t_direct: $t_direct addpoint: $addpoint");

              if ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 1 ) {
              # 周回は速度を上乗せ
              if ($runway_dir == 1) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + ($ghostid->{point_spn}[0] + $addpoint);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                          }
              if ($runway_dir == 2) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - ($ghostid->{point_spn}[0] + $addpoint);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} + ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                          }
              if ($runway_dir == 3) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} - ($ghostid->{point_spn}[0] + $addpoint);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                          }
              if ($runway_dir == 4) {
                        $ghostid->{loc}->{lat} = $ghostid->{loc}->{lat} + ($ghostid->{point_spn}[0] + $addpoint);
                        $ghostid = overArealat($ghostid);
                        $ghostid->{loc}->{lng} = $ghostid->{loc}->{lng} - ($ghostid->{point_spn}[1] + $addpoint);
                        $ghostid = overArealng($ghostid);
                          }

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 2 ) {

                 # 保留

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 3 ) {

                 # 保留

              } elsif ( geoarea($ghostid->{loc}->{lat},$ghostid->{loc}->{lng}) == 4 ) {

                 # 保留

              } # geoarea if

              $addpoint = 0; # 初期化

              # 補正
              $ghostid = d_correction($ghostid,@$hashlist);

	      # 確率でモード変更 @makerlistが無い場合
              if (( int(rand(100)) > 95 ) && !@makerlist) {
                 $ghostid->{status} = "random"; 
                 $ghostid->{target} = "";
                 writedata($ghostid);
                 Logging("Mode Change........radom.");

		 #   my $mess = { type => 'openchat',
		 #             text => "randomモードになったよ",
		 #             user => $ghostid->{name},
		 #         icon_url => $ghostid->{icon_url},
		 #           };
		 #  my $messjson = to_json($mess);
		 #   $pubsub->notify('openchat', $messjson);

		 #	 undef $mess;
		 #	 undef $messjson;
		 undef $ghostid;
		 undef $hashlist;
	         undef @chk_targets;
	         undef $targets;

                 return;
                 } 

              undef @makerlist;

              if (($ghostid->{status} eq "round") && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $ghostid->{status} = "runaway";
                        Logging("Mode change Runaway!");
                        writedata($ghostid);

			#   my $mess = { type => 'openchat',
			#             text => "逃走モードになったよ",
			#             user => $ghostid->{name},
			#         icon_url => $ghostid->{icon_url},
			#           };
			#  my $messjson = to_json($mess);
			#   $pubsub->notify('openchat', $messjson);

			#undef $mess;
			#undef $messjson;
			undef $ghostid;
			undef $hashlist;
	                undef @chk_targets;
	                undef $targets;
                        return;
                }

              $ghostid->{status} = 'round';
              writedata($ghostid);

	      undef $ghostid;
              undef $t_obj;
              undef @chk_targets; 
              undef $t_dist;
              undef $t_direct;
	      undef $hashlist;
	      undef $targets;
              return;
        } # round
} # baseloop





my $childpid = -1;
my $t1;

# Minion　worker 追加のnpcuser_move.plを起動させる想定
#   my $minion ||= Minion->new( Pg => 'postgresql://minion:minionpass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/minion' );
#      $minion->add_task( procadd => sub {
#           my ($job , @args) = @_;
    
#           system("/home/debian/perlwork/mojowork/server/site2/lib/Site2/tools/npcuser_move.pl $args[0] > /dev/null 2>&1 &");
#	   Logging("add proc npcuser_move.pl $args[0] on worker");
#       });
#   my $worker = $minion->worker;
#      $worker->status->{jobs} = 1;
#      $worker->run;
# --------

# 基本無限ループ
while(1) {

   $pg ||= Mojo::Pg->new( 'postgresql://sitedata:sitedatapass@%2fcloudsql%2fvelvety-decoder-677:asia-east1:post1/sitedata' );

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
        after => 300,
        interval => 0,
           cb => sub {

           Logging("change chile process");
           system("kill -TERM $childpid");

	   $childpid = -1; #初期化

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

undef $t1;
undef $cvp;
############################################################

    } else {
	    # childprocess

$redis ||= Mojo::Redis->new("redis://10.140.0.12");

$pubsub ||= Mojo::Pg::PubSub->new( pg => $pg );

my $t0 = [gettimeofday];

my $clearcnt = 0;

my $cv = AE::cv;
my $t = AnyEvent->timer(
        after => 0,
        interval => 1,
           cb => sub {

#    Mojo::IOLoop->recurring ( 1 => sub { 

    Logging("loop start");
    my @loopids;

    $t0 = [gettimeofday];

    my $reskeys = $redis->db->hkeys($keyword);

    my @ghostids = ();
    for my $i (@$reskeys){
	my $resid = $redis->db->hget($keyword,$i);
	Logging("DEBUG: resid: $resid");
        my $j = from_json($resid);
        push(@ghostids , $j );

	undef $resid;
	undef $j;
    }

    undef $reskeys;

    # 引数を持つ場合のみ停止カウント
    if ( @ARGV ){
        if (!@ghostids){
            $clearcnt++;
        } else {
            $clearcnt = 0;
        }
    }

    # 親プロセスを判定して、killコマンドを発行できるようにする
    if ( $clearcnt >= 30 ){
        Logging(" TERM process send SIG KILL");
        my $ptbl = Proc::ProcessTable->new;

        foreach my $p ( @{$ptbl->table} ){
            if ( $p->{pid} =~ /$$/ ){
                # 親プロセスをkill 自分も親からkillされる
                system("kill $p->{ppid}");
                ######  exit #####
            }
        } # for
    } # if


    # hkeysで取得したidをループさせる
    for my $i (@ghostids) {
        &baseloop($i);
    }
    undef @ghostids;


    if (0) { # subprocess bypass

    my $subprocess = Mojo::IOLoop::Subprocess->new;

    $subprocess->run(
     sub {
	my $t1 = [ gettimeofday ];
        Logging("make IOLoop");
            # hkeysで取得したidをループさせる
            for my $i (@ghostids) {
		    my $id = Mojo::IOLoop->timer( 0 => &baseloop($i));
		    push(@loopids, $id);
            }
	    undef @ghostids;
            my $elapsed = tv_interval($t1);
            my $disp = int($elapsed * 1000 );
            Logging("<=== timer loop $disp msec ===>");
     },
     sub {
        Logging("remove IOLoop");
	    for my $i (@loopids){
                Mojo::IOLoop->remove($i);
	    }
     } 
    );  # subprocess
    } # bypass

     my $elapsed = tv_interval($t0);
     my $disp = int($elapsed * 1000 );
       Logging("<=== $disp msec ===>");
       Logging("loop next");
     undef $t0;
     undef @loopids;
   });  # AnyEvent CV Mojo::IOLoop->recurring

#Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

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


