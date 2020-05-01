package Site2::Controller::Filestore;
use Mojo::Base 'Mojolicious::Controller';

use GD;
use DateTime;
use Mojo::JSON qw( from_json to_json );

use lib '/home/debian/perlwork/mojowork/server/site2/lib/Site2/Modules/';
use Sessionid;


# 初期値は16MB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 100 * 1024 * 1024; # 100MBとす

# デフォルト用アイコン生成
sub cicon {
  my $self = shift;

  my $char = $self->param('s');
     if ( ! defined $char ) {
         $char = "*";
     }
     $self->app->log->debug("DEBUG: char: $char ");

  use Mojolicious::Types;
  my $types = Mojolicious::Types->new;

  my $image = GD::Image->new(50,50);

  my $black = $image->colorAllocate(0,0,0);
  my $white = $image->colorAllocate(255,255,255);

  # 色合いは乱数で決定する
  my $c1 = int(rand(200))+55;
  my $c2 = int(rand(200))+55;
  my $c3 = int(rand(200))+55;
  my $color = $image->colorAllocate($c1,$c2,$c3);

    # $image->stringFT($color,"/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",30,0,10,40,$char);
     $image->stringFT($color,"/usr/share/fonts/truetype/fonts-japanese-mincho.ttf",30,0,10,40,$char);

     $image->rectangle(0,0,49,49,$white);

  my $extention = $types->detect("image/jpeg");

  $self->render(data => $image->jpeg(), format => $extention);
}

# アイコン用画像受け入れ
sub iconupload {
    my $self = shift;

       my $wsid = $self->param('wsid');
       my $fileobj = $self->req->upload('filename');
       my $filename = $fileobj->filename;
       my $data = $fileobj->asset->slurp;
       my $mimetype = $fileobj->headers->content_type; 

       my $oid = Sessionid->new($wsid)->uid;
       my $checkdate = DateTime->now();

       my $params = { "filename" => $filename , "mime" => $mimetype , "checkdate" => $checkdate };
       my $paramjson = to_json($params);

           {
                 use DBD::Pg qw(:pg_types);
                 my $tx = $self->app->pg->db->begin;
                 my $sth_uploadfile = $self->app->pg->db->dbh->prepare($self->app->config->{sql_icondata_insert});
                    $sth_uploadfile->bind_param(3, $data,{ pg_type => DBD::Pg::PG_BYTEA });
                    $sth_uploadfile->execute($oid,$paramjson,$data);

                    $tx->commit;
                  undef $tx;
		  undef $sth_uploadfile;
           }

         my $message = { "type" => "oidnotice" , "sendto" => $wsid , "oid" => $oid };
         my $jsontxt = to_json($message);

            $self->app->pg->pubsub->notify( $wsid => $jsontxt );

            # レスポンスは利用しないが、ブラウザでエラーにならないように応答を返す
	    $self->render( json => $message , status => '200' );

       undef $fileobj;
       undef $filename;
       undef $data;
       undef $checkdate;
       undef $params;
       undef $paramjson;

}

# アイコン出力
sub geticon {
    my $self = shift;

    use Mojolicious::Types;
    my $types = Mojolicious::Types->new;

    GD::Image->trueColor(1);

    my $oid = $self->param('oid');
    my $oriented = $self->param('oriented');

    my $field = [ "params" , "data" ];
    my $where = { "oid" => $oid };
    my $sth_icon = $self->app->pg->db->select("icondata", $field , $where );
    my $res = $sth_icon->hash;
    my $params = $res->{params};
       $params = from_json($params);


       #  my $bimage = GD::Image->newFromJpegData($res->{data});
        my $bimage;
        if ( $params->{mime} =~ /jpg|jpeg/ ){
             $bimage = GD::Image->newFromJpegData($res->{data});
	} elsif ( $params->{mime} =~ /png/ ){
             $bimage = GD::Image->newFromPngData($res->{data});
	} elsif ( $params->{mime} =~ /gif/ ){
             $bimage = GD::Image->newFromGifData($res->{data});
	}
    my @bound = $bimage->getBounds();

    my $wx = 50 / $bound[0];
    my $hx = 50 / $bound[1];

    my $w = int($bound[0] * $wx);
    my $h = int($bound[1] * $hx);

    my $newImage = new GD::Image($w, $h);
       $newImage->alphaBlending(0);
       $newImage->saveAlpha(1);
       #  $newImage->copyResized($bimage, 0, 0, 0, 0, $w, $h, $bound[0], $bound[1]);
       $newImage->copyResampled($bimage, 0, 0, 0, 0, $w, $h, $bound[0], $bound[1]);

    my $oimage;   

    ### TEST jpegデータをもとに透過pngで  fillが動作しない
    #$params->{mime} = 'png';
    #  my $transcolor = $newImage->getPixel(0,0);
    #my @rgb = $newImage->rgb($transcolor);
    #my $clear = $newImage->colorAllocateAlpha(255,255,255,127);
    #   $newImage->fill(0,0,$clear);
    #   $newImage->alphaBlending(0);
    #   $newImage->saveAlpha(1);

    my $extention = $types->detect($params->{mime});

    if ( defined $oriented ){
        $params->{oriented} = $oriented;   # 通常は引数で受け取らないので、DBにorientedの登録名が無いとローテーションされない。
    }

    if (! defined $params->{oriented}){
	    if ( $params->{mime} =~ /jpeg|jpg/ ){
               $self->render(data => $newImage->jpeg,format => $extention);
           } elsif ( $params->{mime} =~ /png/ ) {
               $self->render(data => $newImage->png,format => $extention);
	   } elsif ( $params->{mime} =~ /gif/ ){
               $self->render(data => $newImage->gif,format => $extention);
	   }
    } else {
           $oimage = new GD::Image(50,50);
           $oimage->alphaBlending(0);
           $oimage->saveAlpha(1);
           $oimage->copyRotated($newImage,25,25,0,0,50,50,$params->{oriented});
	    if ( $params->{mime} =~ /jpeg|jpg/ ){
               $self->render(data => $oimage->jpeg,format => $extention);
           } elsif ( $params->{mime} =~ /png/ ) {
               $self->render(data => $oimage->png,format => $extention);
	   } elsif ( $params->{mime} =~ /gif/ ){
               $self->render(data => $oimage->gif,format => $extention);
	   }
    }

    undef $res;
    undef $bimage;
    undef $newImage;
    undef $oimage;
    undef $sth_icon;
}


sub fileupload {
    my $self = shift;

       my $wsid = $self->param('wsid');
       my $roomname = $self->param('roomname');
       my $pubstat = $self->param('pubstat');
       my $option = $self->param('option');
       if ( ! defined $option ) {
           $option = "";
       }

       my $fileobj = $self->req->upload('filename');
       my $filename = $fileobj->filename;
       my $data = $fileobj->asset->slurp;
       my $mimetype = $fileobj->headers->content_type; 

       my $oid = Sessionid->new($wsid)->uid;
       my $checkdate = DateTime->now();

       my $params = { "filename" => $filename , "mime" => $mimetype , "checkdate" => $checkdate , "room" => "$pubstat$roomname" , "option" => $option };
       my $paramjson = to_json($params);

           {
                 use DBD::Pg qw(:pg_types);
                 my $tx = $self->app->pg->db->begin;
                 my $sth_uploadfile = $self->app->pg->db->dbh->prepare($self->app->config->{sql_icondata_insert});
                    $sth_uploadfile->bind_param(3, $data,{ pg_type => DBD::Pg::PG_BYTEA });
                    $sth_uploadfile->execute($oid,$paramjson,$data);

                    $tx->commit;
                  undef $tx;
		  undef $sth_uploadfile;
           }

         my $message = { "type" => "filenotice" , "sendto" => $wsid , "oid" => $oid , "mime" => $mimetype };
         my $jsontxt = to_json($message);

            $self->app->pg->pubsub->notify( $wsid => $jsontxt );

            # レスポンスは利用しないが、ブラウザでエラーにならないように応答を返す
	    $self->render( json => $message , status => '200' );

       undef $fileobj;
       undef $filename;
       undef $data;
       undef $checkdate;
       undef $params;
       undef $paramjson;

}

sub fileout {
    my $self = shift;

    use Mojolicious::Types;
    my $types = Mojolicious::Types->new;

    my $oid = $self->param('oid');
    my $oriented = $self->param('oriented');  # 0,90,180,270

    my $field = [ "params" , "data" ];
    my $where = { "oid" => $oid };
    my $sth_icon = $self->app->pg->db->select("icondata", $field , $where );
    my $res = $sth_icon->hash;
    my $params = $res->{params};
       $params = from_json($params);

    if ($params->{mime} =~ /jpg|jpeg|png|gif/ ){

        my $bimage;
        if ( $params->{mime} =~ /jpg|jpeg/ ){
             $bimage = GD::Image->newFromJpegData($res->{data});
	} elsif ( $params->{mime} =~ /png/ ){
             $bimage = GD::Image->newFromPngData($res->{data});
	} elsif ( $params->{mime} =~ /gif/ ){
             $bimage = GD::Image->newFromGifData($res->{data});
	}

            my @bound = $bimage->getBounds();
	    # 1/2に縮小
            my $w = int($bound[0] / 2);
            my $h = int($bound[1] / 2);

	    my $w_c = int($w / 2); # 中心点
	    my $h_c = int($h / 2);

	    my $image;

	       $image = new GD::Image($w,$h); 
	   
               $image->copyResized($bimage, 0, 0, 0, 0, $w, $h, $bound[0], $bound[1]);

            my $iimage = new GD::Image($w,$h);
               $iimage->copyRotated($image,$w_c,$h_c,0,0,$w,$h,$oriented);

	if ( $params->{mime} =~ /jpeg|jpg/ ){
            $self->render(data => $iimage->jpeg , format => $params->{mime} );
        } elsif ( $params->{mime} =~ /png/ ){
            $self->render(data => $iimage->png , format => $params->{mime} );
	} elsif ( $params->{mime} =~ /gif/ ){
            $self->render(data => $iimage->gif , format => $params->{mime} );
	}

	undef $bimage;
	undef $image;
	undef $iimage;

	#   my $extention = $types->detect($params->{mime});
	#   $self->render(data => $res->{data},format => $extention);

    } elsif ( $params->{mime} =~ /mpeg|mpg|3gp|mp4|m4a|realtext|mp3|octet-stream|flac/){

        my $extention = $types->detect($params->{mime});

           $self->render(data => $res->{data},format => $extention);

    } elsif ( $params->{mime} =~ /pdf/ ){

        my $extention = $types->detect($params->{mime});

           $self->render(data => $res->{data},format => $extention);
    }

}



sub imgchk {
   my $self = shift;
   # 画像の縦横確認用
   # icondataのidを指定して表示する仕組み
    
    $self->stash( url_orig => $self->url_for->to_abs );
 my $url_host = Mojo::URL->new($self->url_for->to_abs );
    $self->stash( url_host => $url_host->host );
   
    $self->render();
}

sub imgout {
    my $self = shift;
    # 画像向きテスト用出力
    my $id = $self->param('id');
    my $orient = $self->param('orient');

    my $field = [ "params" , "data" ];
    my $where = { "id" => $id };
    my $res = $self->app->pg->db->select('icondata', $field , $where )->hash;

    $self->app->log->info("DEBUG: res: $res->{params} ");

    my $flg = 0;
        my @keys = keys(%$res);
        for my $i (@keys){
            if ( $i eq 'params' ) {
                $flg = 1;
	    }
        }
    if ($flg == 0 ){
        $self->render( text => "not found id." );
	return;
    }

    my $params = from_json($res->{params});

    if ( ! defined $orient ){

        $self->render(data => $res->{data}, format => $params->{mime});

    } else {

        my $bimage = GD::Image->newFromJpegData($res->{data});

        my @bound = $bimage->getBounds();
        my $wx = 350 / $bound[0];
        my $hx = 350 / $bound[1];

        my $w = int($bound[0] * $wx);
        my $h = int($bound[1] * $hx);

	my $w_c = int($bound[0] / 2); # 中心点
	my $h_c = int($bound[1] / 2);

	my $image;

	   $image = new GD::Image($w,$h); 
	   
	   #  $image->copyRotated($bimage,$w_c,$h_c,0,0,$w,$h,$orient);   # 回転処理では縦横の判定が出来ない。
	   #  リサイズしてから回転させる
	   
           $image->copyResized($bimage, 0, 0, 0, 0, $w, $h, $bound[0], $bound[1]);

        my $iimage = new GD::Image(350,350);
           $iimage->copyRotated($image,175,175,0,0,350,350,$orient);

        $self->render(data => $iimage->jpeg , format => $params->{mime} );

	undef $bimage;
	undef $image;
	undef $iimage;

    }
    undef $res;
}

1;
