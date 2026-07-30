package MCP::Server::Transport::HTTP;
use Mojo::Base 'MCP::Server::Transport', -signatures;

use Crypt::Misc    qw(random_v4uuid);
use List::Util     qw(first);
use MCP::Constants qw(HEADER_MISMATCH META_PROTOCOL_VERSION);
use MCP::Server::Context;
use MCP::Server::Legacy qw(legacy_request);
use MCP::Server::Subscription;
use Mojo::IOLoop;
use Mojo::JSON   qw(to_json);
use Mojo::Util   qw(b64_decode decode dumper);
use Scalar::Util qw(blessed looks_like_number weaken);

use constant DEBUG => $ENV{MCP_DEBUG} || 0;

use constant NAMES => {'prompts/get' => 'name', 'resources/read' => 'uri', 'tools/call' => 'name'};

has 'auth';
has heartbeat => 30;
has 'metadata_url';
has 'origins';
has streaming     => 0;
has subscriptions => sub { {} };

sub handle_request ($self, $c) {
  my $server = $self->server;
  $server->log($c->app->log) unless $server->{log};

  return $c->render(json => {error => 'Origin not allowed'}, status => 403) unless $self->_check_origin($c);

  if (my $auth = $self->auth) {
    return $self->_unauthorized($c) unless my $info = $auth->($c);
    $c->stash('mcp.auth' => $info);
  }

  return $self->_handle_post($c) if $c->req->method eq 'POST';
  return $c->render(json => {error => 'Method not allowed'}, status => 405);
}

sub notifications ($self) { $self->streaming ? 1 : 0 }

sub notify_all ($self, $method, $params = {}) {
  return undef unless $self->streaming;
  for my $subscription (values %{$self->subscriptions}) {
    next unless $subscription->wants($method);
    _write($subscription->stream, $subscription->notification($method, $params));
  }
  return 1;
}

sub _arg_value ($args, $path) {
  my $value = $args;
  for my $key (@$path) {
    return undef unless ref $value eq 'HASH';
    $value = $value->{$key};
  }
  return $value;
}

sub _challenge_header ($self, %extra) {
  my @parts;
  push @parts, qq{resource_metadata="@{[$self->metadata_url]}"} if $self->metadata_url;
  push @parts, qq{error="$extra{error}"}                        if $extra{error};
  push @parts, qq{scope="$extra{scope}"}                        if defined $extra{scope};
  return 'Bearer' . (@parts ? ' ' . join(', ', @parts) : '');
}

sub _check_headers ($self, $c, $data) {
  my $headers = $c->req->headers;
  my $params  = $data->{params} // {};

  my $version = $headers->header('MCP-Protocol-Version');
  return 'Missing MCP-Protocol-Version header' unless defined $version;
  my $expected = ($params->{_meta} // {})->{+META_PROTOCOL_VERSION};
  return 'MCP-Protocol-Version header does not match the request body' if defined $expected && $expected ne $version;

  my $method = $data->{method} // '';
  my $sent   = $headers->header('Mcp-Method');
  return 'Missing Mcp-Method header'                         unless defined $sent;
  return 'Mcp-Method header does not match the request body' unless $sent eq $method;

  if (my $key = NAMES->{$method}) {
    my $name = $headers->header('Mcp-Name');
    return 'Missing Mcp-Name header'                         unless defined $name;
    return 'Invalid Mcp-Name header'                         unless defined($name = _decode_header($name));
    return 'Mcp-Name header does not match the request body' unless $name eq ($params->{$key} // '');
  }

  return $method eq 'tools/call' ? $self->_check_params($c, $params) : undef;
}

sub _check_origin ($self, $c) {
  return 1 unless defined(my $origin = $c->req->headers->origin);
  return 1 unless my $origins = $self->origins;
  return $origins->($c, $origin) ? 1 : 0 if ref $origins eq 'CODE';
  return first { $_ eq $origin } @$origins;
}

sub _check_params ($self, $c, $params) {
  return undef unless my $tool = first { $_->name eq ($params->{name} // '') } @{$self->server->tools};
  my $args    = $params->{arguments} // {};
  my $headers = $c->req->headers;

  for my $param (@{$tool->header_params}) {
    my $name   = "Mcp-Param-$param->{name}";
    my $value  = _arg_value($args, $param->{path});
    my $header = $headers->header($name);

    if (!defined $value) {
      return "Unexpected $name header" if defined $header;
      next;
    }
    return "Missing $name header"                         unless defined $header;
    return "Invalid $name header"                         unless defined($header = _decode_header($header));
    return "$name header does not match the request body" unless _match_value($param->{type}, $header, $value);
  }

  return undef;
}

sub _decode_header ($value) {
  return decode('UTF-8', b64_decode($1)) if $value =~ /^=\?base64\?(.*)\?=$/s;
  return $value =~ /^[\t\x20-\x7e]*\z/ ? $value : undef;
}

sub _finish ($c, $context, $response) {
  return undef if $context->is_cancelled;
  $context->stream(undef);
  return _write($c, $response)->finish;
}

sub _handle ($self, $data, $context) {
  warn "-- MCP Request\n@{[dumper($data)]}\n" if DEBUG;
  my $result = $self->server->handle($data, $context);
  warn "-- MCP Response\n@{[dumper($result)]}\n" if DEBUG && $result;
  return $result;
}

sub _handle_post ($self, $c) {
  my $data = $c->req->json;
  return $c->render(json => {error => 'Invalid JSON'}, status => 400) unless ref $data eq 'HASH';

  # Legacy
  my $legacy = legacy_request($c->req->headers->header('MCP-Protocol-Version'), $data);

  if (!$legacy && defined(my $id = $data->{id})) {
    if (my $message = $self->_check_headers($c, $data)) {
      my $error = {code => HEADER_MISMATCH, message => $message};
      return $c->render(json => {jsonrpc => '2.0', id => $id, error => $error}, status => 400);
    }
  }

  return $self->_handle_request($c, $data, $legacy);
}

sub _handle_request ($self, $c, $data, $legacy = undef) {
  my $info    = $c->stash('mcp.auth') // {};
  my $context = MCP::Server::Context->new(
    controller => $c,
    legacy     => $legacy,
    principal  => $info->{principal},
    scopes     => $self->_scopes($c),
    transport  => $self
  );
  return $c->render(data => '', status => 202) unless defined(my $result = $self->_handle($data, $context));

  # Subscription
  return $self->_handle_subscription($c, $result) if blessed($result) && $result->isa('MCP::Server::Subscription');

  # Async
  if (blessed($result) && $result->isa('Mojo::Promise')) {
    _stream($c, $context);
    return $result->then(sub { _finish($c, $context, $_[0]) });
  }

  # Insufficient scope
  if (my $needed = $context->insufficient_scope) {
    $c->res->headers->header(
      'WWW-Authenticate' => $self->_challenge_header(error => 'insufficient_scope', scope => join(' ', @$needed)));
  }

  # Sync
  my $status = $context->status // 200;
  return $c->render(json => $result, status => $status) if $status != 200 || !@{$context->buffer};
  _stream($c, $context);
  return _finish($c, $context, $result);
}

sub _handle_subscription ($self, $c, $subscription) {
  my $id = random_v4uuid;
  $self->subscriptions->{$id} = $subscription->stream($c);
  _write(_open_stream($c), $subscription->acknowledgement);

  my $heartbeat_id;
  if (my $interval = $self->heartbeat) {
    $heartbeat_id = Mojo::IOLoop->recurring($interval => sub { $c->write_sse({comment => 'keepalive'}) });
  }

  weaken(my $self_weak = $self);
  return $c->on(
    finish => sub {
      Mojo::IOLoop->remove($heartbeat_id)     if $heartbeat_id;
      delete $self_weak->subscriptions->{$id} if $self_weak;
    }
  );
}

sub _match_value ($type, $header, $value) {
  return looks_like_number($header) && looks_like_number($value) && $header == $value if $type eq 'integer';
  return $header eq ($value ? 'true' : 'false')                                       if $type eq 'boolean';
  return $header eq "$value";
}

sub _open_stream ($c) {
  $c->inactivity_timeout(0);
  $c->res->headers->header('X-Accel-Buffering' => 'no');
  return $c->write_sse;
}

sub _scopes ($self, $c) {
  return undef unless $self->auth;
  return ($c->stash('mcp.auth') // {})->{scopes} // [];
}

sub _stream ($c, $context) {
  _open_stream($c);
  $c->on(finish => sub { $context->stream(undef)->cancel if $context->stream });
  return $context->stream(sub ($notification) {
    _write($c, $notification);
  })->flush;
}

sub _unauthorized ($self, $c) {
  $c->res->headers->header('WWW-Authenticate' => $self->_challenge_header);
  return $c->render(json => {error => 'Unauthorized'}, status => 401);
}

sub _write ($c, $message) { return $c->write_sse({text => to_json($message)}) }

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

Only C<POST> requests are handled; C<GET> and C<DELETE> are answered with status C<405>. The protocol is stateless,
so nothing is remembered between requests and the transport can be deployed behind a load balancer and a pre-forking
web server. Notifications that belong to a request, such as progress reports, are delivered on the response stream
of that very request, which is upgraded from C<application/json> to C<text/event-stream> whenever there is something
to deliver.

The one exception is L</"streaming">, which opts in to C<subscriptions/listen>. Long-lived notification streams
require per-process state and are therefore not compatible with pre-forking web servers.

Routing headers are validated against the JSON-RPC body before a request is dispatched, so a gateway that routes on
C<Mcp-Method>, C<Mcp-Name>, or C<Mcp-Param-*> alone can never disagree with the server about what was called.

=head1 ATTRIBUTES

L<MCP::Server::Transport::HTTP> inherits all attributes from L<MCP::Server::Transport> and implements the following
new ones.

=head2 auth

  my $cb = $http->auth;
  $http  = $http->auth(sub ($c) {...});

Optional callback to authenticate each request before it is dispatched. It receives the L<Mojolicious::Controller>
and returns a hash reference of authentication info on success, or a false value to reject the request with a
C<401> C<WWW-Authenticate> challenge. The C<scopes> and C<principal> keys of the returned hash reference are made
available to handlers as L<MCP::Server::Context/"scopes"> and L<MCP::Server::Context/"principal">. Token validation
is left to the application, so this is where you verify an OAuth 2.0 access token; when not set, requests are not
authenticated.

=head2 heartbeat

  my $seconds = $http->heartbeat;
  $http       = $http->heartbeat(30);

Interval in seconds at which a keep-alive comment is sent on each open subscription stream. Defaults to C<30>; set
to C<0> to disable. Useful when running behind reverse proxies that close idle connections. Only used when
L</"streaming"> is enabled.

=head2 metadata_url

  my $url = $http->metadata_url;
  $http   = $http->metadata_url('https://example.com/.well-known/oauth-protected-resource');

URL of the OAuth 2.0 Protected Resource Metadata document. When set, it is included as the C<resource_metadata>
parameter of the C<WWW-Authenticate> challenge sent with C<401> and C<403> responses, so clients can discover the
authorization server. Use an absolute URL so remote clients can fetch it. See L<MCP::Server/"oauth_metadata">.

=head2 origins

  my $origins = $http->origins;
  $http       = $http->origins(['https://example.com']);
  $http       = $http->origins(sub ($c, $origin) {...});

Origins allowed to make browser requests, as an array reference of exact matches or a callback returning true for
an acceptable origin. Requests carrying an C<Origin> header that is not allowed are rejected with status C<403>,
which protects against DNS rebinding attacks on servers bound to localhost. Defaults to C<undef>, which accepts
every origin.

=head2 streaming

  my $bool = $http->streaming;
  $http    = $http->streaming(1);

Enable C<subscriptions/listen>, so clients can open a long-lived stream for the C<list_changed> notifications they
ask for. Defaults to false. When enabled, the transport tracks every open stream in L</"subscriptions"> and
advertises the C<listChanged> capabilities in C<server/discover>. Progress and log notifications do not depend on
this, since they are delivered on the response stream of the request they belong to.

=head2 subscriptions

  my $subscriptions = $http->subscriptions;
  $http             = $http->subscriptions({});

Per-process registry of active L<MCP::Server::Subscription> objects. Only used when L</"streaming"> is enabled.

=head1 METHODS

L<MCP::Server::Transport::HTTP> inherits all methods from L<MCP::Server::Transport> and implements the following new
ones.

=head2 handle_request

  $http->handle_request(Mojolicious::Controller->new);

Handles an incoming HTTP request.

=head2 notifications

  my $bool = $http->notifications;

True when L</"streaming"> is enabled, false otherwise.

=head2 notify_all

  my $bool = $http->notify_all($method);
  my $bool = $http->notify_all($method, {foo => 'bar'});

Send a JSON-RPC notification to every subscription that asked for it. Returns true on success, or C<undef> when
L</"streaming"> is disabled.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
