package Backloop::Walkworld;
    # Backloopのwebsocketの判定処理を分離
    #
   
    sub decision {
	    #   my ($self , $redis , $clients , $jsonobj) = @_;

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
                               # ブラウザが非同期に処理するためバーストする可能性がある 2secでリミ
#ットをかけると処理が回らなくて、結果的にバーストしているかもしれない。    

                               my $keys = $redis->db->keys('ghostaccEntry*');  # リミッターを設定>する
                               my @npcuser = @$keys;
                               my @count = ();

                               for my $i (@npcuser){

                                   my $res = $redis->db->hvals($i);

                                   # $resは配列の中身がテキストなので、バイナリに直す ブラウザ側で
#の変換が1度で済む
                                   for my $j (@$res){
                                       push(@count , $j );
                                   }

                               } # for @npcuser 
 

                          if ( $#count >= 29 ) {   # 99ではCPUの負荷が大きすぎるので今はここまで
                              $self->app->log->info("DEBUG: npcuser process limit over ");
                              return;
                          }
                          #undef @count;

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

                               # @countを事前に再計算
                               #  for my $i (@npcuser){
                               #    my $res = $redis->db->hvals($i);
                                   # $reshは配列の中身がテキストなので、バイナリに直す ブラウザ側>での変換が1度で済む
                                   #    for my $j (@$res){
                                   #    push(@count , $j );
                                   #}
                                   #} # for @npcuser 

                          undef @npcuser;
                          undef $keys;

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

    } # decision


1;
