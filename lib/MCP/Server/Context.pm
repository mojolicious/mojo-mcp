package MCP::Server::Context;
use Mojo::Base 'Mojo::EventEmitter', -signatures;

use Carp             qw(croak);
use Crypt::Mac::HMAC qw(hmac);
use Crypt::Misc      qw(slow_eq);
use Mojo::JSON       qw(decode_json encode_json);
use Mojo::Util       qw(b64_decode b64_encode);

use constant LEVELS =>
  {debug => 0, info => 1, notice => 2, warning => 3, error => 4, critical => 5, alert => 6, emergency => 7};

has buffer => sub { [] };
has [qw(client_capabilities client_info controller input_responses insufficient_scope legacy log_level principal)];
has [qw(progress_token protocol_version raw_request_state scopes state_binding state_secret)];
has state_timeout => 300;
has [qw(status stream transport)];

sub cancel ($self) {
  return $self if $self->{cancelled}++;
  return $self->emit('cancelled');
}

sub flush ($self) {
  return 0 unless my $stream = $self->stream;
  my @buffered = splice @{$self->buffer};
  $stream->($_) for @buffered;
  return scalar @buffered;
}

sub has_scope ($self, @needed) {
  return 1 unless defined(my $scopes = $self->scopes);
  my %granted = map { $_ => 1 } @$scopes;
  for my $scope (@needed) { return 0 unless $granted{$scope} }
  return 1;
}

sub is_cancelled ($self) { $self->{cancelled} ? 1 : 0 }

sub notify ($self, $method, $params = {}) {
  return undef if $self->is_cancelled;
  my $notification = {jsonrpc => '2.0', method => $method, params => $params};
  if   (my $stream = $self->stream) { $stream->($notification) }
  else                              { push @{$self->buffer}, $notification }
  return 1;
}

sub notify_log ($self, $level, $data) {
  return undef unless defined(my $minimum = $self->log_level);
  return undef unless (LEVELS->{$level} // 0) >= (LEVELS->{$minimum} // 0);
  return $self->notify('notifications/message', {level => $level, data => $data});
}

sub notify_progress ($self, $progress, $total = undef, $message = undef) {
  return undef unless defined(my $token = $self->progress_token);
  my $params = {progressToken => $token, progress => $progress};
  $params->{total}   = $total   if defined $total;
  $params->{message} = $message if defined $message;
  return $self->notify('notifications/progress', $params);
}

sub request_state ($self) { return $self->{request_state} //= $self->_unseal }

sub seal_state ($self, $state) {
  croak 'No state secret' unless my $secret = $self->state_secret;
  my $data = {
    binding   => $self->state_binding,
    expires   => time + $self->state_timeout,
    payload   => $state,
    principal => $self->principal
  };
  my $payload = b64_encode(encode_json($data), '');
  return "$payload." . b64_encode(hmac('SHA256', $secret, $payload), '');
}

sub _unseal ($self) {
  return undef unless my $secret = $self->state_secret;
  return undef unless ($self->raw_request_state // '') =~ /^([^.]+)\.([^.]+)$/;
  my ($payload, $mac) = ($1, $2);
  return undef unless slow_eq(b64_decode($mac), hmac('SHA256', $secret, $payload));
  return undef unless my $data = eval { decode_json(b64_decode($payload)) };
  return undef unless ($data->{expires}   // 0) > time;
  return undef unless ($data->{binding}   // '') eq ($self->state_binding // '');
  return undef unless ($data->{principal} // '') eq ($self->principal     // '');
  return $data->{payload};
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Context - Request context container

=head1 SYNOPSIS

  use MCP::Server::Context;

  my $context = MCP::Server::Context->new;
  $context->notify_progress(1, 2, 'halfway');

=head1 DESCRIPTION

L<MCP::Server::Context> is a container for per-invocation request context.

=head1 EVENTS

L<MCP::Server::Context> inherits all events from L<Mojo::EventEmitter> and emits the following new ones.

=head2 cancelled

  $context->on(cancelled => sub ($context) { ... });

Emitted once when the client abandons the current request, either by closing its response stream or by sending a
C<notifications/cancelled> notification. Long running operations should stop as soon as practical.

  my $id = Mojo::IOLoop->recurring(1 => sub { ... });
  $context->on(cancelled => sub ($context) { Mojo::IOLoop->remove($id) });

=head1 ATTRIBUTES

L<MCP::Server::Context> implements the following attributes.

=head2 buffer

  my $buffer = $context->buffer;
  $context   = $context->buffer([]);

Notifications that have been queued up because no response L</"stream"> was available yet, to be delivered by
L</"flush">.

=head2 client_capabilities

  my $capabilities = $context->client_capabilities;
  $context         = $context->client_capabilities({elicitation => {}});

Capabilities declared by the client for the current request, from
C<_meta.io.modelcontextprotocol/clientCapabilities>. Every request has to declare them, so this is only C<undef>
outside of request handling.

=head2 client_info

  my $info = $context->client_info;
  $context = $context->client_info({name => 'MyClient', version => '1.0.0'});

Name and version of the client making the current request, from C<_meta.io.modelcontextprotocol/clientInfo>, or
C<undef> if the client did not identify itself.

=head2 controller

  my $c    = $context->controller;
  $context = $context->controller(Mojolicious::Controller->new);

The L<Mojolicious::Controller> serving the current request, when the HTTP transport is in use.

=head2 input_responses

  my $responses = $context->input_responses;
  $context      = $context->input_responses({confirm => {action => 'accept', content => {ok => \1}}});

Responses to the input requests of an earlier C<input_required> result, keyed by the same names, or C<undef> if the
current request is not a retry. See L<MCP::Primitive/"input_required">.

=head2 insufficient_scope

  my $needed = $context->insufficient_scope;
  $context   = $context->insufficient_scope(['mcp:write']);

Array reference of scopes a denied request was missing, set by the server so the HTTP transport can emit an
C<insufficient_scope> challenge. C<undef> when no scope check failed.

=head2 legacy

  my $version = $context->legacy;
  $context    = $context->legacy('2025-11-25');

The protocol revision a legacy request was made with, or C<undef> for a current request, see
L<MCP::Server::Legacy>.

=head2 log_level

  my $level = $context->log_level;
  $context  = $context->log_level('info');

The minimum severity of log messages the client wants for the current request, from
C<_meta.io.modelcontextprotocol/logLevel>, or C<undef> if the client asked for none.

=head2 principal

  my $principal = $context->principal;
  $context      = $context->principal('user@example.com');

The authenticated caller the current request belongs to, populated from the C<principal> key returned by the C<auth>
hook of the HTTP transport. Request state is bound to it, so state minted for one caller is never accepted from
another. C<undef> for unauthenticated requests.

=head2 progress_token

  my $token = $context->progress_token;
  $context  = $context->progress_token('tok-1');

The progress token provided by the client in C<_meta.progressToken>, or C<undef> if none was sent.

=head2 protocol_version

  my $version = $context->protocol_version;
  $context    = $context->protocol_version('2026-07-28');

The protocol version the current request was made with, from C<_meta.io.modelcontextprotocol/protocolVersion>.

=head2 raw_request_state

  my $state = $context->raw_request_state;
  $context  = $context->raw_request_state('eyJ...');

The C<requestState> string the client sent back, exactly as received and not verified in any way. Use
L</"request_state"> instead, unless you want to protect the state yourself.

=head2 scopes

  my $scopes = $context->scopes;
  $context   = $context->scopes(['mcp:read', 'mcp:write']);

OAuth scopes granted to the current request, as an array reference, populated from the C<auth> hook of the HTTP
transport. C<undef> (the default) imposes no scope restriction, so scopes are only enforced for authenticated
requests that provide them.

=head2 state_binding

  my $binding = $context->state_binding;
  $context    = $context->state_binding("tools/call\0deploy");

Identifies the request that request state may be used with, set by the server to the method name and the name or
URI of the primitive being called. State sealed for one primitive is never accepted by another.

=head2 state_secret

  my $secret = $context->state_secret;
  $context   = $context->state_secret($bytes);

Key used to authenticate request state, copied from L<MCP::Server/"state_secret">.

=head2 state_timeout

  my $seconds = $context->state_timeout;
  $context    = $context->state_timeout(300);

How long request state sealed during this request stays valid, in seconds, copied from
L<MCP::Server/"state_timeout">.

=head2 status

  my $status = $context->status;
  $context   = $context->status(404);

HTTP status the current request has to be answered with, set by the server for the protocol errors the specification
maps to a specific status, such as C<404> for an unknown method. C<undef> (the default) means C<200>, and transports
other than L<MCP::Server::Transport::HTTP> ignore it.

=head2 stream

  my $cb   = $context->stream;
  $context = $context->stream(sub ($notification) { ... });

Callback the transport installs once the response stream for the current request is open, to be called with every
notification that belongs to it. Notifications sent before that are queued up in L</"buffer">.

=head2 transport

  my $transport = $context->transport;
  $context      = $context->transport(MCP::Server::Transport::HTTP->new);

The transport handling the current request.

=head1 METHODS

L<MCP::Server::Context> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 cancel

  $context = $context->cancel;

Mark the current request as cancelled and emit the L</"cancelled"> event, at most once.

=head2 flush

  my $num = $context->flush;

Deliver all notifications queued up in L</"buffer"> to L</"stream">, and return the number of notifications
delivered.

=head2 has_scope

  my $bool = $context->has_scope('mcp:write');
  my $bool = $context->has_scope('mcp:read', 'mcp:write');

Returns true if every given scope is present in L</"scopes">, or if L</"scopes"> is C<undef> (no restriction).

=head2 is_cancelled

  my $bool = $context->is_cancelled;

Returns true if the current request has been cancelled, for operations that cannot subscribe to the
L</"cancelled"> event and have to poll instead.

=head2 notify

  my $bool = $context->notify($method);
  my $bool = $context->notify($method, {foo => 'bar'});

Send a JSON-RPC notification on the response stream of the current request. Returns true on success, or C<undef> if
the request has been cancelled.

=head2 notify_log

  my $bool = $context->notify_log('info', 'Something happened');
  my $bool = $context->notify_log('error', {code => 23});

Send a C<notifications/message> JSON-RPC notification with the given severity and payload. Returns C<undef> unless
the client requested logging with C<_meta.io.modelcontextprotocol/logLevel> and the given severity is at or above
the level it asked for.

=head2 notify_progress

  my $bool = $context->notify_progress($progress);
  my $bool = $context->notify_progress($progress, $total);
  my $bool = $context->notify_progress($progress, $total, $message);

Send a C<notifications/progress> JSON-RPC notification for the progress token associated with the current request.
Returns true on success, or C<undef> if no progress token was provided by the client.

=head2 request_state

  my $state = $context->request_state;

Verify and decode the request state the client sent back, returning the data structure that was passed to
L<MCP::Primitive/"input_required">. Returns C<undef> if there was no state, or if it was tampered with, has expired,
was sealed for a different primitive, or belongs to a different L</"principal">, so a primitive that cannot tell
those cases apart simply asks for input again.

Replay within L</"state_timeout"> is not prevented; servers that need one-shot semantics have to enforce that
themselves, for example by embedding a nonce and remembering it.

=head2 seal_state

  my $sealed = $context->seal_state({step => 2});

Serialize a data structure into an opaque string, authenticated with L</"state_secret"> and bound to
L</"state_binding">, L</"principal">, and L</"state_timeout">. Usually called through
L<MCP::Primitive/"input_required"> rather than directly.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
