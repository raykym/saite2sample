package Site2::Controller::Transferuser;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::JSON qw(from_json to_json);

sub accept {
  my $self = shift;

  my $uid = $self->param('uid');
  # uid無しはunknown pageへ飛ぶ
  my $res = $self->app->pg->db->query("select data from backloop where (data->>'uid' = ? ) order by id DESC limit 1" , $uid )->hash;

  if (! defined $res ) {
      $self->render(text => "unknown UID... or old uid .. No recode left...");
  } else {

	  my $data = from_json($res->{data});
	  my %data = %$data;
	  $self->stash(user => $data->{user});
	  $self->stash(icon_url => $data->{icon_url});
	  $self->stash(uid => $uid );

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

    my $olduid = $self->param('olduid');

    my $mess = { 'olduid' => $olduid };

    my $messjson = to_json($mess);

    $self->app->pg->db->insert('obsoleteuid' , { 'data' => $messjson } );

    $self->stash( url_orig => $self->url_for->to_abs );
 my $url_host = Mojo::URL->new($self->url_for->to_abs );
    $self->stash( url_host => $url_host->host );

    $self->render(text => 'finish' , status => '200' );
}

1;
