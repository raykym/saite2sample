package Site2::Controller::Backloop;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::JSON qw( from_json to_json );
use Time::HiRes qw( time );
use Mojo::Redis;
use DateTime;
use Math::Trig ':pi';

use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules/';
use Sessionid;

my $clients = {};
my $stream_io = {};
my $pubsub_cb = {};
my $stream = {};


sub signaling {
    my $self = shift;

    #websocket 確認
    my $wsid = $self->tx->connection;
       $self->app->log->info(sprintf 'Client connected: %s', $self->tx->connection);
       $clients->{$wsid} = $self->tx;

       # ブラウザにwsidを送信する
       my $wsidsend = { "type" => "wsidnotice" , "wsid" => $wsid };
       my $wsidjson = to_json($wsidsend);
       $clients->{$wsid}->send($wsidjson);
       undef $wsidsend;
       undef $wsidjson;

       my $mess = { "type" => "checkuser" };
       my $messjson = to_json($mess);
       $clients->{$wsid}->send($messjson);
       $stream->{$wsid} = Mojo::IOLoop->stream($self->tx->connection);
       $stream->{$wsid}->timeout(60);
       $self->inactivity_timeout(60000); #60secで応答が無いと切れる
       undef $mess;
       undef $messjson;

    # WebSocket接続維持設定
    #  $stream_io->{$wsid} = Mojo::IOLoop->stream($self->tx->connection);
    #   $stream_io->{$wsid}->timeout(10);   # 10sec timeout 常時接続なのですぐに切れる
       $stream_io->{$wsid} = Mojo::IOLoop->recurring( 50 => sub {
           my $loop = shift;
	   # if ($self->inactivity_timeout < 50000 ){
		  my $mess = { "dummy" => "dummy" };
		  my $messjson = to_json($mess);
                  $clients->{$wsid}->send($messjson);
		  $self->app->log->debug("DEBUG: send socket wait!!");
           #  }
	       });

       #  $self->inactivity_timeout(60000); #60sec   50secでdummyが送信され

    # pubsub listen
          $pubsub_cb->{$wsid} = $self->app->pg->pubsub->listen( $wsid => sub {
              my ($pubsub, $payload) = @_;

              # pubsubを受信したら自分のwebsocketに送信
              $clients->{$wsid}->send($payload);
          });

    # openchat listen
       my $cb = $self->app->pg->pubsub->listen( "openchat" => sub {
              my ($pubsub, $payload) = @_;

              # pubsubを受信したら自分のwebsocketに送信
              $clients->{$wsid}->send($payload);
          });

    # redis setup
        my $redisserver = $self->app->config->{redisserver};
      #my $redis ||= Mojo::Redis->new("redis://10.140.0.8");
        my $redis ||= Mojo::Redis->new("redis://$redisserver");

# サブルーチンエリア
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

			   my @return = ( $lat_min , $lat_max , $lng_min , $lng_max ) ;

			   return @return;
   }
          
    # on message・・・・・・・
       $self->on(message => sub {
                  my ($self, $msg) = @_;

                  my $jsonobj = from_json($msg);
                     $self->app->log->debug("DEBUG: on session: $wsid");
                     $self->app->log->debug("DEBUG: msg: $msg");

		     $jsonobj->{from} = $wsid;

                  if ( $jsonobj->{dummy} ) {
		       $self->app->log->debug("DEBUG: pass dummy!! ");
                   # dummy pass
		       return;
                  }   

                   # server又はチャットルームへの送信
		   if ( $jsonobj->{type}) {

		         if ( $jsonobj->{type} eq "entry" ) {
		              # user情報アイコンパスが変更された場合
		              $jsonobj->{wsid} = $wsid;
		              $jsonobj->{ttl} = time();
		           my $jsontext = to_json($jsonobj);

		           my $datasec = { "data" => $jsontext };

		              $self->app->pg->db->insert("backloop", $datasec );
		              $self->app->log->debug("DEBUG: write backloop table");

		           return;
		           } # type entry

			 if ( $jsonobj->{type} eq 'rescheckuser' ){
			     if ( $jsonobj->{res} ne 'USER' ){
				 $stream->{$wsid}->timeout(60);
                                 $self->inactivity_timeout(60000); #60sec   50secでdummyが送信され
			     }
			     return;
			 }
			  
			  
		   #下記のイベントを記録する (typeイベント)
		   {  
			$jsonobj->{datetime} = DateTime->now();
		        $jsonobj->{ttl} = time();
	             my $jsontext = to_json($jsonobj);
		     my $datasec = { "data" => $jsontext };
		        $self->app->pg->db->insert("backloop", $datasec );
	            }   


			 if ( $jsonobj->{type} eq "openchat" ) {
			     # openchatのメッセージが流れたとき
                             my $jsontxt = to_json($jsonobj);
                             $self->app->pg->pubsub->notify( "openchat" => $jsontxt );
                             return;
			 }

			 if ( $jsonobj->{type} eq "makechatroom" ) {
                             # チャットルームの作成

			     my $sobj = Sessionid->new($jsonobj->{roomname});
			     $self->app->log->info("DEBUG: 通過 ");
			     my $chatroomnamehash = $sobj->guid;

                             my $userdata = { "user" => $jsonobj->{user} ,
                                              "icon_url" => $jsonobj->{icon_url},
                                              "wsid" => $jsonobj->{wsid},
					      "room" => $jsonobj->{roomname},
					      "pubstat" => $jsonobj->{pubstat},
					      "roomnamehash" => $chatroomnamehash,
				            };
			     my $userjson = to_json($userdata);

			     #$redis->db->hset("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}", $jsonobj->{wsid} , $userjson);
                             $redis->db->hset("ENTRY$jsonobj->{pubstat}$chatroomnamehash", $jsonobj->{wsid} , $userjson);

			        $userdata->{type} = "makechatroomact";
				$clients->{$wsid}->send({json => $userdata}); # hashを自分に返信

			     return;
			 }

			 if ( $jsonobj->{type} eq "entrychatroom" ) {
                             # チャットルームへのエントリー
			   $self->app->log->info("DEBUG: entrychatroom $jsonobj->{user}"); 

			     my $chatroomnamehash = Sessionid->new($jsonobj->{roomname})->guid;

                             my $userdata = { "user" => $jsonobj->{user} ,
                                              "icon_url" => $jsonobj->{icon_url},
                                              "wsid" => $jsonobj->{wsid},
					      "room" => $jsonobj->{roomname},
					      "pubstat" => $jsonobj->{pubstat},
					      "roomnamehash" => $chatroomnamehash,
				            };
			     my $userjson = to_json($userdata);

			     #$redis->db->hset("ENTRYpublic$jsonobj->{roomname}", $jsonobj->{wsid} , $userjson);
                             $redis->db->hset("ENTRYpublic$chatroomnamehash", $jsonobj->{wsid} , $userjson);

			     my $mess = { "type" => "entrychatroomact" ,
			                  "roomnamehash" => $chatroomnamehash ,
			                };
			     $clients->{$wsid}->send({ json => $mess });

			     return;
			 }

			 if ( $jsonobj->{type} eq "getlistchatroom") {
                            # チャットルームの参照

			    my $res = $redis->db->keys("ENTRYpublic*");

                            my @roomlist = ();
                            for my $key (@$res){
                            
				    #  $key =~ s/ENTRYpublic//;    # prefixを除去
				    #  push (@roomlist , $key);
				    #  roomnameをハッシュに置き換えるために、上2行を処理を変更する
				my $reskeyroom = $redis->db->hvals($key);
				for my $proom ( @$reskeyroom){
					$proom = from_json($proom);
                                        push (@roomlist , $proom->{room});
					last; # 強制で1回のみ実行
			        }
			    }

			    my $roomlist = \@roomlist;

                            my $mess = { "type" => "roomlistnotice" , "chatroomlist" => $roomlist };

			    my $resjson = to_json($mess);

			    $clients->{$wsid}->send($resjson);

			    $self->app->log->debug("DEBUG: send $resjson ");

			    return;
			 }

			 if ( $jsonobj->{type} eq "getlist" ) {
                             # chatroomでメンバーを確認する

                             $self->app->log->debug("DEBUG: key: ENTRY$jsonobj->{pubstat}$jsonobj->{roomnamehash}   $jsonobj->{roomname}");

			     #my $res = $redis->db->hvals("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");
			     my $res = $redis->db->hvals("ENTRY$jsonobj->{pubstat}$jsonobj->{roomnamehash}");

			     # $reshは配列の中身がテキストなので、バイナリに直す ブラウザ側での変換が1度で済む
			     my $resp = [];
			     for my $i (@$res){
                                 $i = from_json($i);
				 push(@$resp , $i );
			     }

			     my $mess = { "type" => "reslist" , "reslist" => $resp , "from" => $jsonobj->{from} };

			     my $memberlistjson = to_json($mess);

                                $clients->{$wsid}->send($memberlistjson);

			        $self->app->log->debug("DEBUG: send memberlist $memberlistjson");

			     return;
			 }

			 if ( $jsonobj->{type} eq "reloadmember" ){
                             #チャットのメンバーリストの再読込をメンバーに依頼する
			     #my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomnamehash}");

			     for my $i (@$res){
				 if ( $i eq $wsid ) { next ; }  # 自分は除外
				 #	 $clients->{$i}->send({ json => $jsonobj });  // websocketからpubsubに変更
				 my $jsontext = to_json($jsonobj);
				 $self->app->pg->pubsub->notify( $i => $jsontext );
				 $self->app->log->debug("DEBUG: reloadmember send $jsonobj->{roomname} $i ");
			     }

                             return;
			 }

			 if ( $jsonobj->{type} eq "chatroomchat" ) {
			     # cchatのメッセージが流れたとき
			     #my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomnamehash}");
			     my $debug = to_json($res);

			     for my $i (@$res){
                                 my $jsontxt = to_json($jsonobj);
                                 $self->app->pg->pubsub->notify( $i => $jsontxt );
				 $self->app->log->debug("DEBUG: chatroomchat send $jsonobj->{roomname} $i ");
		             } 
                             return;
			 }

			 # type call以外、order responseはsendtoで送信される
			 if ( $jsonobj->{type} eq "call" ) {
                             # webRTC用
			     #my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomnamehash}");

			     for my $i (@$res){
				 if ( $i eq $wsid ) { next ; }  # 自分は除外
				 #	 $clients->{$i}->send({ json => $jsonobj });  // websocketからpubsubに変更
				 my $jsontext = to_json($jsonobj);
				 $self->app->pg->pubsub->notify( $i => $jsontext );
				 $self->app->log->debug("DEBUG: type call send $jsonobj->{roomname} $i ");
			     }
                             return;
			 }

			 if ( $jsonobj->{type} eq "detachvoice"){
                             # hung up detachvoiceの転送
			     #my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomname}");
                             my $res = $redis->db->hkeys("ENTRY$jsonobj->{pubstat}$jsonobj->{roomnamehash}");
			     my $debug = to_json($res);

			     for my $i (@$res){
                                 my $jsontxt = to_json($jsonobj);
                                 $self->app->pg->pubsub->notify( $i => $jsontxt );
				 $self->app->log->debug("DEBUG: detachvoice send $jsonobj->{roomname} $i ");
		             } 

                             return;
			 }

                         if ( $jsonobj->{type} eq "obsoleteuid" ) {
                             # chkuidからidを探して、在ると、ブラウザに削除処理を。そして、idから削除を
                             my $res = $self->app->pg->db->query("select id from obsoleteuid where data->>'olduid' = ?" , $jsonobj->{chkuid})->hash;

			     if ( ! defined $res->{id} ) {
                                 my $mess = { "type" => "resobsoleteuid" , "res" => "nonobsolete" };
				 my $messjson = to_json($mess);
                                 $clients->{$wsid}->send($messjson);
				 $self->app->log->debug("DEBUG: send nonobsolete");
                                 return;
			     } else {
                                 my $mess = { "type" => "resobsoleteuid" , "res" => "obsolete" };
				 my $messjson = to_json($mess);
                                 $clients->{$wsid}->send($messjson);
				 $self->app->log->debug("DEBUG: send obsolete");
				 $self->app->pg->db->delete('obsoleteuid' , { 'id' => $res->{id} } );
				 $self->app->log->debug("DEBUG: obsolete id: $res->{id}");
                                 return;
			     }
			 }

                         if ( $jsonobj->{type} eq "iconrotate" ){

			     my $recodetext = $self->app->pg->db->select('icondata', 'params' , { 'oid' => $jsonobj->{oid} } )->hash;
			        $self->app->log->info("DEBUG: $recodetext->{params}");
			     my $params = from_json($recodetext->{params});
			        $params->{oriented} = $jsonobj->{oriented};
			     my $paramjson = to_json($params);
                                $self->app->pg->db->update('icondata', {'params' => $paramjson }, {'oid' => $jsonobj->{oid} } );

		             my $mess = { "type" => "resiconrotate" , "oriented" => $jsonobj->{oriented} };
			     my $messjson = to_json($mess);
			        $clients->{$wsid}->send($messjson);

                             return;
			 }

			 if ($jsonobj->{type} eq "icondel" ){

			    $self->app->pg->db->delete('icondata', { "oid" => $jsonobj->{oid} } );

			    $self->app->log->info("DEBUG: delete icon data $jsonobj->{oid}");
                            return;
			 }


			 

                   # type の末尾はreternは無し  type付きのsendtoを個別送信する
	           } # if type

		   # walkworld用イベント   backloopにイベントは記録しない
		   if ( $jsonobj->{walkworld} ){

	           # logging
	if (0){
		   {  
			$jsonobj->{datetime} = DateTime->now();
		        $jsonobj->{ttl} = time();
	             my $jsontext = to_json($jsonobj);
		     my $datasec = { "data" => $jsontext };
		        $self->app->pg->db->insert("backloop", $datasec );
	            }   
	    } # block

                       if ( $jsonobj->{walkworld} eq "postuserdata" ){

			   $self->app->log->debug("DEBUG: walkworld userdata posted");
                          
			   my $udata = $jsonobj->{userdata};
			   $udata->{ttl} = time();
			   my $udatajson = to_json($udata);

                           $self->app->pg->db->query("INSERT INTO walkworld(data) VALUES ( ? )" , $udatajson );

                           $self->app->log->debug("DEBUG: udatajson: $udatajson ");

			   # pointlist取得処理
                           # 半径1km圏内のユニットを検索 (東経北緯限定)

			   my ( $lat_min , $lat_max , $lng_min, $lng_max ) = &kmlatlng($udata->{loc}->{lat} , $udata->{loc}->{lng} );

			   $self->app->log->debug("DEBUG: lat: $lat_min | $lat_max  lng: $lng_min | $lng_max ");

		           my $res = $self->app->pg->db->query("select data from walkworld where (data->'loc'->>'lng')::numeric < $lng_max and 
                                                           (data->'loc'->>'lng')::numeric > $lng_min and 
                                                           (data->'loc'->>'lat')::numeric < $lat_max and 
                                                           (data->'loc'->>'lat')::numeric > $lat_min order by id DESC")->hashes;
		           #my $resdebug = to_json($res);
			   #$self->app->log->info("DEBUG: res: $resdebug ");
			   # $res = [ { 'data' => "json line" } , { 'data' => "json line" } .... ] 
                           # 同じユーザーの重複が大量にあるので、listuidに登録済は除外する方向で重複を排除
			   my $hashlist = ();  
			   for my $a (@$res){
				   #  my $adebug = to_json($a);
				   #$self->app->log->info("DEBUG: a: $adebug");
				   my $data = from_json($a->{data});

                               my @listuid = ();
                               for my $line (@$hashlist){    #登録済のuidをリスト (重複排除）
			           push(@listuid, $line->{uid});
			       }
                               $self->app->log->debug("DEBUG: listuid: @listuid");

			       my $flg = 0;
			       for my $i (@listuid){
				   $self->app->log->debug("DEBUG: cmp listuid: $data->{uid} | $i ");
                                   if ( $data->{uid} eq $i ){
                                       $flg = 1;  # uidが既存だと1
				   }
			       }

			       $self->app->log->debug("DEBUG: flg: $flg");
			       if ( $flg == 0 ) { # uidが存在しないと
                                   push(@$hashlist, $data );
			       }
			   } # for res
                          
			   #my $hashdebug = to_json($hashlist);
			   #$self->app->log->info("DEBUG: hashlist: $hashdebug");

                           my $mess = { "walkworld" => "resuserdata" ,
                                        "reslist" => $hashlist ,
                                      };
                           my $messjson = to_json($mess);

                           $clients->{$wsid}->send($messjson);
                           
                           $self->app->log->debug("DEBUG: send resuserdata");

                           undef $res;
			   undef $hashlist;

                           return;
		       }

                       if ( $jsonobj->{walkworld} eq "entryghost" ) {

		          my $keys = $redis->db->keys('ghostaccEntry*');  # リミッターを設定する
			  my @npcuser = @$keys;
			  my @count;
                          for my $i (@npcuser){
                          
			     my $res = $redis->db->hvals($i);

			     # $reshは配列の中身がテキストなので、バイナリに直す ブラウザ側での変換が1度で済む
			     for my $j (@$res){
				 push(@count , $j );
			     }

			  } # for @npcuser 

			  if ( $#count >= 99 ) {
                              $self->app->log->info("DEBUG: npcuser process limit over ");
			      return;
			  }
			  undef @count;

			  my $setkey;

			  if (!@npcuser){
                              $setkey = "ghostaccEntry";
			  } else {
		              # ghostaccEntryの何処に追加するのか判定する
			      for my $key (@npcuser){
		                  my $fields = $redis->db->hkeys($key); 
			          my @ghostcount = @$fields;
			          if ( $#ghostcount >= 19 ) {
			              next;
			          }
			          $setkey = $key;
			          last;
		              } # for $key
		          } # else 

			  $self->app->log->info("DEBUG: setkey: $setkey");

			  # setkeyが設定されない場合　プロセスを追加してキーを設定する
	        	  if ( ! defined $setkey ) {
                              my $num = int(rand(9999999));
                              my $sid = Sessionid->new($num)->uid;

			      $setkey = "ghostaccEntry$sid";

			     $self->app->minion->enqueue(procadd => [ $setkey ] );

			     $self->app->log->info("DEBUG: add npcuser_move.pl $sid ");
		          }

                          my @latlng = &kmlatlng($jsonobj->{lat}, $jsonobj->{lng});
			  my $kmlat_d = ($latlng[1] - $latlng[0]) / 2; # (max - min ) / 2
			  my $kmlng_d = ($latlng[3] - $latlng[2]) / 2;
			  
                          my $g_lat = $jsonobj->{lat} + ((rand($kmlat_d)) - ($kmlat_d / 2)); # 1kmあたりを乱数で、500m分を引いて+-が出るように 
                          my $g_lng = $jsonobj->{lng} + ((rand($kmlng_d)) - ($kmlng_d / 2));
                          my $num = int(rand(999));
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
                                          "lifecount" => 21600,   # 6hour /sec
					  "hitcount" => 0,
					  "chasecnt" => 0 ,
                                         };

                          my $ghostaccjson = to_json($ghostacc);

                          $redis->db->hset($setkey, $uid , $ghostaccjson );

                          $self->app->log->info("DEBUG: ghostacc set: $name $uid ");

			  undef $keys;
			  undef @npcuser;

                          return;
		       }

                       if ( $jsonobj->{walkworld} eq "putmine" ){

                          my @latlng = &kmlatlng($jsonobj->{lat}, $jsonobj->{lng});
			  my $kmlat_d = ($latlng[1] - $latlng[0]) / 2; # (max - min ) / 2
			  my $kmlng_d = ($latlng[3] - $latlng[2]) / 2;
			  my $lat = $jsonobj->{lat} + ($kmlat_d / 1000); # 1mずらす
                          my $lng = $jsonobj->{lng} + ($kmlng_d / 1000);
		          my $uid = Sessionid->new($jsonobj->{name})->uid;

		          my $trap = { "setuser" => $jsonobj->{name},
				       "name" => 'mine',
			               "loc" => { "lat" => $lat , "lng" => $lng },
				       "uid" => $uid,
				       "category" => "MINE",
				       "icon_url" => $jsonobj->{icon_url},
				       "ttl" => time(),
				       "ttlcount" => 241920,
			             };
		          my $trapjson = to_json($trap);

                         $redis->db->hset("trapeventEntry", $uid , $trapjson);

                           return;
		       }


                       if ( $jsonobj->{walkworld} eq "puttower" ){

                          my @latlng = &kmlatlng($jsonobj->{lat}, $jsonobj->{lng});
			  my $kmlat_d = ($latlng[1] - $latlng[0]) / 2; # (max - min ) / 2
			  my $kmlng_d = ($latlng[3] - $latlng[2]) / 2;
			  my $lat = $jsonobj->{lat} + ($kmlat_d / 1000); # 1mずらす
                          my $lng = $jsonobj->{lng} + ($kmlng_d / 1000);
		          my $uid = Sessionid->new($jsonobj->{name})->uid;

		          my $trap = { "setuser" => $jsonobj->{name},
				       "name" => 'tower',
			               "loc" => { "lat" => $lat , "lng" => $lng },
				       "uid" => $uid,
				       "category" => "TOWER",
				       "icon_url" => $jsonobj->{icon_url},
				       "ttl" => time(),
				       "ttlcount" => 120,
				       "rundirect" => 0,
			             };
		          my $trapjson = to_json($trap);

                         $redis->db->hset("trapeventEntry", $uid , $trapjson);

                           return;
		       }

		       if ( $jsonobj->{walkworld} eq 'putmessage' ){

                          my @latlng = &kmlatlng($jsonobj->{lat}, $jsonobj->{lng});
			  my $kmlat_d = ($latlng[1] - $latlng[0]) / 2; # (max - min ) / 2
			  my $kmlng_d = ($latlng[3] - $latlng[2]) / 2;
			  my $lat = $jsonobj->{lat} + ($kmlat_d / 1000); # 1mずらす
                          my $lng = $jsonobj->{lng} + ($kmlng_d / 1000);
		          my $uid = Sessionid->new($jsonobj->{name})->uid;

		          my $trap = { "setuser" => $jsonobj->{user},
				       "name" => 'message',
			               "loc" => { "lat" => $lat , "lng" => $lng },
				       "uid" => $uid,
				       "text" => $jsonobj->{text},
				       "category" => "MESSAGE",
				       "icon_url" => $jsonobj->{icon_url},
				       "ttl" => "",
				       "ttlcount" => $jsonobj->{ttlcount},
				       "rundirect" => 0,
			             };
		          my $trapjson = to_json($trap);

                         $redis->db->hset("trapeventEntry", $uid , $trapjson);

                         return;
		       }
                       
		       if ($jsonobj->{walkworld} eq 'messagedelete'){

			   $redis->db->hdel('trapeventEntry',$jsonobj->{uid});
                           $self->app->pg->db->query("delete from walkworld where data->>'uid' = ?" , $jsonobj->{uid} );

                           return;
		       }



                      # walkworldの末尾はreturnしない
		   }  # if walkworld




		   #下記のイベントを記録する (type以外) webRTCのorder responseは2重に登録されるかも
		   {  
			$jsonobj->{datetime} = DateTime->now();
		        $jsonobj->{ttl} = time();
	             my $jsontext = to_json($jsonobj);
		     my $datasec = { "data" => $jsontext };
		        $self->app->pg->db->insert("backloop", $datasec );
	            }   
        
                  # sendtoが含まれる場合  ブラウザ間の直接やり取りtypeを付けない個別送信
                  if ($jsonobj->{sendto}){

                      my $jsontxt = to_json($jsonobj);
                         $self->app->pg->pubsub->notify( $jsonobj->{sendto} => $jsontxt );
                         $self->app->log->debug("DEBUG: sendto: $jsonobj->{sendto} ");

		    return;
                   }



       }); # on message

    # on finish・・・・・・・
         $self->on(finish => sub{
               my ($self, $code,$reson) = @_;

	           $self->app->log->info("finish connection $wsid");

	           $self->app->pg->pubsub->unlisten($wsid => $pubsub_cb->{$wsid});
	           $self->app->pg->pubsub->unlisten("openchat" => $cb);

		   my $res = $redis->db->keys('ENTRY*'); # すべてのchatroomをチェックする

		   # picture chatを利用した場合、画像を削除する
                   for my $key (@$res){
                       my $info = $redis->db->hget( $key , $wsid );
		       $self->app->log->debug("DEBUG: info: $info");
		       if ( ! defined $info ){ next; }
		          $info = from_json($info);
			  #$self->app->pg->db->query("delete from icondata where params->>'room' = ?" , "$info->{pubstat}$info->{room}" );
		          $self->app->pg->db->query("delete from icondata where params->>'room' = ?" , "$info->{pubstat}$info->{roomnamehash}" );
			  $self->app->log->debug("DEBUG: delete pic $info->{pubstat} $info->{roomname}");
		   }

		   for my $key (@$res){
			   #  $self->app->log->info("DEBUG: key: $key");
		       my $fields = $redis->db->hkeys($key);  # fieldをチェックして一致したら削除する
		           for my $id (@$fields){
				   #  $self->app->log->info("DEBUG: id: $id");
			       if ( $wsid eq $id ) {
			           $redis->db->hdel($key , $id ); # wsidを削除する
			           $self->app->log->info("DEBUG: delete ENTRY: $key $id");
			        }
		            }
		   } # for $res   ENTRYchatrooms

		   #    $self->app->log->info("DEBUG: into websocket finish!!!");

             delete $clients->{$wsid};
	     Mojo::IOLoop->remove($stream_io->{$wsid});
	     Mojo::IOLoop->remove($stream->{$wsid});

       }); # on finish


} # signaling

# 
sub delclientwsid {
    my $self = shift;
    
    # redis setup
    my $redisserver = $self->app->config->{redisserver};
    my $redis ||= Mojo::Redis->new("redis://$redisserver");

    my $wsid = $self->param('wsid');
    my $roomnamehash = $self->param('roomnamehash');
    my $pubstat = $self->param('pubstat');

    if ((! defined $wsid ) || ( ! defined $roomnamehash ) || ( ! defined $pubstat )){
        $self->render( text => 'ok' , status => '200' );  # とりあえず終わらせる
        return;
    }

    $self->app->log->info("finish connection $wsid by client");

    my $res = $redis->db->keys("ENTRY$pubstat$roomnamehash");

    for my $key (@$res){
        my $fields = $redis->db->hkeys($key);  # fieldをチェックして一致したら削除する
            for my $id (@$fields){
                if ( $wsid eq $id ) {
                    $redis->db->hdel($key , $id ); # wsidを削除する
                    $self->app->log->info("DEBUG: delete ENTRY: $key $id");
                }
            }
    } # for $res   ENTRYchatrooms

    delete $clients->{$wsid};
    Mojo::IOLoop->remove($stream_io->{$wsid});
    Mojo::IOLoop->remove($stream->{$wsid});

    # とりあえずレスポンスしておく
    $self->render( text => 'ok' , status => '200' );

    undef $wsid;
    undef $roomnamehash;
    undef $pubstat;
    undef $redisserver;
    undef $redis;
    undef $res;

}



