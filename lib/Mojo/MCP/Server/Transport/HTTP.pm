package Mojo::MCP::Server::Transport::HTTP;
use Mojo::Base 'Mojo::MCP::Server::Transport', -signatures;

use Crypt::Misc qw(random_v4uuid);
use Mojo::JSON  qw(to_json true);

has sessions => sub { {} };
has 'server';

sub handle_request ($self, $c) {
  my $method = $c->req->method;
  return $self->_handle_post($c)   if $method eq 'POST';
  return $self->_handle_get($c)    if $method eq 'GET';
  return $self->_handle_delete($c) if $method eq 'DELETE';
  return $c->render(json => {error => 'Method not allowed'}, status => 405);
}

sub _cleanup_session ($self, $session_id) {
  return unless my $session = delete $self->sessions->{$session_id};
  $session->{sse}->finish if $session->{sse};
}

sub _extract_session_id ($self, $c) { return $c->req->headers->header('Mcp-Session-Id') }

sub _handle_delete ($self, $c) {
  return $self->_respond_missing_session_id($c) unless my $session_id = $self->_extract_session_id($c);
  $self->_cleanup_session($session_id);
  return $c->render(json => {success => true}, status => 200);
}

sub _handle_get ($self, $c) {
  return $self->_respond_missing_session_id($c) unless my $session_id = $self->_extract_session_id($c);
  return $c->render(json => {error => 'Session not found'}, status => 404) unless $self->sessions->{$session_id};
  $self->_setup_sse($c, $session_id);
}

sub _handle_initialization ($self, $c, $data) {
  my $session_id = random_v4uuid;
  $self->sessions->{$session_id} = {sse => undef};
  my $result = $self->server->handle($data);
  $c->res->headers->header('Mcp-Session-Id' => $session_id);
  $c->render(json => $result, status => 200);
}

sub _handle_post ($self, $c) {
  my $session_id = $c->res->headers->header('Mcp-Session-Id');

  return $c->render(json => {error => 'Invalid JSON'}, status => 400) unless my $data = $c->req->json;
  return $c->render(json => {error => 'Invalid JSON', status => 400}) unless ref $data eq 'HASH';

  if ($data->{method} && $data->{method} eq 'initialize') { $self->_handle_initialization($c, $data) }
  else                                                    { $self->_handle_regular_request($c, $data, $session_id) }
}

sub _handle_regular_request ($self, $c, $data, $session_id) {
  return $c->render(json => {error => 'Invalid session ID'}, status => 400)
    if $session_id && !$self->sessions->{$session_id};

  return $c->render(data => '', status => 202) unless defined(my $result = $self->server->handle($data));

  if ($session_id && $self->_send($result, $session_id)) { $c->render(json => {accepted => true}, status => 200) }
  else                                                   { $c->render(json => $result, status => 200) }
}

sub _respond_missing_session_id ($self, $c) { $c->render(json => {error => 'Missing session ID'}, status => 400) }

sub _send ($self, $data, $session_id) {
  return undef unless my $sse = $self->sessions->{$session_id}{sse};
  $sse->write_sse({data => to_json($data)});
  return 1;
}

sub _setup_sse ($self, $c, $session_id) {
  $c->res->headers->header('Mcp-Session-Id' => $session_id);

  $c->inactivity_timeout(0);
  $c->write_sse;

  my $id = Mojo::IOLoop->recurring(30 => sub { $c->write_sse({comment => 'ping ' . time}) });
  $self->sessions->{$session_id}{sse} = $c;
  $c->on(
    finish => sub {
      Mojo::IOLoop->remove($id);
      $self->_cleanup_session($session_id);
    }
  );
}

1;
