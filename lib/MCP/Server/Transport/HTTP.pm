package MCP::Server::Transport::HTTP;
use Mojo::Base 'MCP::Server::Transport', -signatures;

use Crypt::Misc qw(random_v4uuid);
use MCP::Server::Context;
use MCP::Server::Session;
use Mojo::IOLoop;
use Mojo::JSON   qw(to_json true);
use Mojo::Util   qw(dumper);
use Scalar::Util qw(blessed weaken);

use constant DEBUG => $ENV{MCP_DEBUG} || 0;

has 'auth';
has heartbeat => 30;
has 'metadata_url';
has session_timeout => 3600;
has sessions        => sub { {} };
has streaming       => 0;

sub notifications ($self) { $self->streaming ? 1 : 0 }

sub handle_request ($self, $c) {
  if (my $auth = $self->auth) {
    return $self->_unauthorized($c) unless my $info = $auth->($c);
    $c->stash('mcp.auth' => $info);
  }

  my $method = $c->req->method;
  return $self->_handle_post($c)   if $method eq 'POST';
  return $self->_handle_get($c)    if $method eq 'GET'    && $self->streaming;
  return $self->_handle_delete($c) if $method eq 'DELETE' && $self->streaming;
  return $c->render(json => {error => 'Method not allowed'}, status => 405);
}

sub notify ($self, $session_id, $method, $params = {}) {
  return undef unless my $session = $self->sessions->{$session_id};
  return undef unless my $stream  = $session->stream;
  $stream->write_sse({text => to_json({jsonrpc => '2.0', method => $method, params => $params})});
  return 1;
}

sub notify_all ($self, $method, $params = {}) {
  return undef unless $self->streaming;
  my $payload = {text => to_json({jsonrpc => '2.0', method => $method, params => $params})};
  for my $session (values %{$self->sessions}) {
    next unless my $stream = $session->stream;
    $stream->write_sse($payload);
  }
  return 1;
}

sub _challenge_header ($self, %extra) {
  my @parts;
  push @parts, qq{resource_metadata="@{[$self->metadata_url]}"} if $self->metadata_url;
  push @parts, qq{error="$extra{error}"}                        if $extra{error};
  push @parts, qq{scope="$extra{scope}"}                        if defined $extra{scope};
  return 'Bearer' . (@parts ? ' ' . join(', ', @parts) : '');
}

sub _extract_session_id ($self, $c) { return $c->req->headers->header('Mcp-Session-Id') }

sub _scopes ($self, $c) { return ($c->stash('mcp.auth') // {})->{scopes} // [] }

sub _unauthorized ($self, $c) {
  $c->res->headers->header('WWW-Authenticate' => $self->_challenge_header);
  return $c->render(json => {error => 'Unauthorized'}, status => 401);
}

sub _handle ($self, $data, $context) {
  warn "-- MCP Request\n@{[dumper($data)]}\n" if DEBUG;
  my $result = $self->server->handle($data, $context);
  warn "-- MCP Response\n@{[dumper($result)]}\n" if DEBUG && $result;
  return $result;
}

sub _handle_delete ($self, $c) {
  return $c->render(json => {error => 'Missing session ID'}, status => 400)
    unless my $session_id = $self->_extract_session_id($c);
  return $c->render(json => {error => 'Session not found'}, status => 404)
    unless my $session = delete $self->sessions->{$session_id};

  if (my $stream = $session->stream) { $stream->finish }
  $c->render(data => '', status => 204);
}

sub _handle_get ($self, $c) {
  return $c->render(json => {error => 'Missing session ID'}, status => 400)
    unless my $session_id = $self->_extract_session_id($c);
  return $c->render(json => {error => 'Session not found'}, status => 404)
    unless my $session = $self->sessions->{$session_id};
  return $c->render(json => {error => 'Stream already open'}, status => 409) if $session->stream;

  $c->inactivity_timeout(0);
  $c->res->headers->header('Mcp-Session-Id' => $session_id);
  $session->stream($c)->touch;
  $c->write_sse;

  my $heartbeat_id;
  if (my $interval = $self->heartbeat) {
    $heartbeat_id = Mojo::IOLoop->recurring($interval => sub { $c->write_sse({comment => 'keepalive'}) });
  }

  weaken(my $self_weak = $self);
  $c->on(
    finish => sub {
      Mojo::IOLoop->remove($heartbeat_id) if $heartbeat_id;
      return unless $self_weak;
      return unless my $session = $self_weak->sessions->{$session_id};
      return unless ($session->stream // 0) == $c;
      $session->stream(undef)->touch;
    }
  );
}

sub _handle_initialization ($self, $c, $data) {
  my $session_id = random_v4uuid;
  my $result     = $self->_handle($data, MCP::Server::Context->new(scopes => $self->_scopes($c)));
  if ($self->streaming) {
    $self->sessions->{$session_id} = MCP::Server::Session->new(id => $session_id);
    $self->_start_sweep;
  }
  $c->res->headers->header('Mcp-Session-Id' => $session_id);
  $c->render(json => $result, status => 200);
}

sub _handle_post ($self, $c) {
  my $session_id = $self->_extract_session_id($c);

  return $c->render(json => {error => 'Invalid JSON'}, status => 400) unless my $data = $c->req->json;
  return $c->render(json => {error => 'Invalid JSON', status => 400}) unless ref $data eq 'HASH';

  if ($data->{method} && $data->{method} eq 'initialize') { $self->_handle_initialization($c, $data) }
  else                                                    { $self->_handle_regular_request($c, $data, $session_id) }
}

sub _handle_regular_request ($self, $c, $data, $session_id) {
  return $c->render(json => {error => 'Missing session ID'}, status => 400) unless $session_id;
  if ($self->streaming) {
    return $c->render(json => {error => 'Session not found'}, status => 404)
      unless my $session = $self->sessions->{$session_id};
    $session->touch;
  }

  $c->res->headers->header('Mcp-Session-Id' => $session_id);
  my $context = MCP::Server::Context->new(
    transport  => $self,
    session_id => $session_id,
    controller => $c,
    scopes     => $self->_scopes($c)
  );
  return $c->render(data => '', status => 202) unless defined(my $result = $self->_handle($data, $context));

  # Insufficient scope
  if (my $needed = $context->insufficient_scope) {
    $c->res->headers->header(
      'WWW-Authenticate' => $self->_challenge_header(error => 'insufficient_scope', scope => join(' ', @$needed)));
    return $c->render(json => $result, status => 403);
  }

  # Sync
  return $c->render(json => $result, status => 200) if !blessed($result) || !$result->isa('Mojo::Promise');

  # Async
  $c->inactivity_timeout(0);
  $c->write_sse;
  $result->then(sub { $c->write_sse({text => to_json($_[0])})->finish });
}

sub _start_sweep ($self) {
  return if $self->{_sweep_id};
  return unless my $interval = $self->session_timeout;
  weaken(my $self_weak = $self);
  $self->{_sweep_id} = Mojo::IOLoop->recurring($interval => sub { $self_weak->_sweep if $self_weak });
}

sub _sweep ($self) {
  return unless my $timeout = $self->session_timeout;
  my $cutoff   = time - $timeout;
  my $sessions = $self->sessions;
  for my $id (keys %$sessions) {
    my $session = $sessions->{$id};
    delete $sessions->{$id} if !$session->stream && $session->last_used < $cutoff;
  }
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Transport::HTTP - HTTP transport for MCP servers

=head1 SYNOPSIS

  use MCP::Server::Transport::HTTP;

  my $http = MCP::Server::Transport::HTTP->new;

=head1 DESCRIPTION

L<MCP::Server::Transport::HTTP> is a transport for MCP (Model Context Protocol) server that uses HTTP as the
underlying transport mechanism.

By default only C<POST> requests are handled. When L</"streaming"> is enabled, the transport additionally supports
the server-to-client SSE stream (C<GET>) and explicit session termination (C<DELETE>) defined by the Streamable
HTTP transport. Note that this requires per-process state and is therefore not compatible with pre-forking web
servers.

=head1 ATTRIBUTES

L<MCP::Server::Transport::HTTP> inherits all attributes from L<MCP::Server::Transport> and implements the following
new ones.

=head2 auth

  my $cb = $http->auth;
  $http  = $http->auth(sub ($c) {...});

Optional callback to authenticate each request before it is dispatched. It receives the L<Mojolicious::Controller>
and returns a hash reference of authentication info on success, or a false value to reject the request with a
C<401> C<WWW-Authenticate> challenge. The C<scopes> key of the returned hash reference is made available to handlers
as L<MCP::Server::Context/"scopes">. Token validation is left to the application, so this is where you verify an
OAuth 2.0 access token; when not set, requests are not authenticated.

=head2 heartbeat

  my $seconds = $http->heartbeat;
  $http       = $http->heartbeat(30);

Interval in seconds at which a keep-alive comment is sent on each open server-to-client stream. Defaults to C<30>;
set to C<0> to disable. Useful when running behind reverse proxies that close idle connections. Only used when
L</"streaming"> is enabled.

=head2 metadata_url

  my $url = $http->metadata_url;
  $http   = $http->metadata_url('https://example.com/.well-known/oauth-protected-resource');

URL of the OAuth 2.0 Protected Resource Metadata document. When set, it is included as the C<resource_metadata>
parameter of the C<WWW-Authenticate> challenge sent with C<401> and C<403> responses, so clients can discover the
authorization server. See L<MCP::Server/"oauth_metadata">.

=head2 session_timeout

  my $seconds = $http->session_timeout;
  $http       = $http->session_timeout(3600);

Idle timeout in seconds for sessions without an open server-to-client stream. Defaults to C<3600>; set to C<0> to
disable. A periodic sweep removes sessions whose last activity is older than this value, so the effective lifetime
of an idle session is up to twice the configured timeout. Only used when L</"streaming"> is enabled.

=head2 sessions

  my $sessions = $http->sessions;
  $http        = $http->sessions({});

Per-process registry of active L<MCP::Server::Session> objects, keyed by session ID. Only used when L</"streaming">
is enabled.

=head2 streaming

  my $bool = $http->streaming;
  $http    = $http->streaming(1);

Enable server-to-client streaming and session lifecycle management. Defaults to false. When enabled, the transport
tracks all sessions in L</"sessions">, accepts C<GET> requests to open a long-lived SSE stream the server can push
notifications to, and accepts C<DELETE> requests to terminate a session. Requests for unknown sessions are rejected
with status C<404>.

=head1 METHODS

L<MCP::Server::Transport::HTTP> inherits all methods from L<MCP::Server::Transport> and implements the following new
ones.

=head2 handle_request

  $http->handle_request(Mojolicious::Controller->new);

Handles an incoming HTTP request.

=head2 notifications

  my $bool = $http->notifications;

True when L</"streaming"> is enabled, false otherwise.

=head2 notify

  my $bool = $http->notify($session_id, $method);
  my $bool = $http->notify($session_id, $method, {foo => 'bar'});

Send a JSON-RPC notification to the open SSE stream of a session. Returns true on success, or C<undef> if the
session does not exist or has no open stream. Only available when L</"streaming"> is enabled.

=head2 notify_all

  my $bool = $http->notify_all($method);
  my $bool = $http->notify_all($method, {foo => 'bar'});

Send a JSON-RPC notification to the open SSE stream of every active session. Returns true on success, or C<undef>
when L</"streaming"> is disabled.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
