package Site2::Controller::Transferuser;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::JSON qw(from_json to_json);

sub accept {
  my $self = shift;

  my $uid = $self->param('uid');
  # uid無しはunknown pageへ飛ぶ
  my $res = $self->app->pg->db->query("select data from backloop where data->>'uid' = ? and data->>'type' = 'entry'  order by id DESC limit 1" , $uid )->hash;

  if (! defined $res ) {
      $self->render(text => "unknown UID... or old uid .. No recode left...");
  } else {
          # ここではすべてのデータは送らない
	  my $data = from_json($res->{data});

	  $self->stash(uid => $uid );
	  # 表示上必要
	  $self->stash(user => $data->{user});
	  $self->stash(icon_url => $data->{icon_url});

          $self->stash( url_orig => $self->url_for->to_abs );
          my $url_host = Mojo::URL->new($self->url_for->to_abs );
          $self->stash( url_host => $url_host->host );

	  #$self->render(text => "good by $data->{user}  $data->{icon_url} ");
	  #$self->render(json => $data);
	  $self->render();
      }
}

sub uidobsolete {
    my $self = shift;
    # UID切り替えページから古いUIDを登録する
    # takeoverでuid,user,icon_url以外を送信する

    #uidの廃止処理
    my $olduid = $self->param('olduid');

    # acceptでは全てを送っていないので追加をここで送る acceptで通っていれば少なくともデータは存在する
    my $res = $self->app->pg->db->query("select data from backloop where data->>'uid' = ? and data->>'type' = 'entry'  order by id DESC limit 1" , $olduid )->hash;

    my $resdata = from_json($res->{data});
    my $mess = { 'olduid' => $olduid };

    my $messjson = to_json($mess);

    $self->app->pg->db->insert('obsoleteuid' , { 'data' => $messjson } );

    $self->stash( url_orig => $self->url_for->to_abs );
 my $url_host = Mojo::URL->new($self->url_for->to_abs );
    $self->stash( url_host => $url_host->host );

    $self->render(json => $resdata );
}

1;
