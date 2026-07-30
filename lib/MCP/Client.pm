package MCP::Client;
use Mojo::Base 'Mojo::EventEmitter', -signatures;

use Carp           qw(croak);
use List::Util     qw(first);
use MCP::Constants qw(META_CLIENT_CAPABILITIES META_CLIENT_INFO META_PROTOCOL_VERSION PROTOCOL_VERSION),
  qw(SUPPORTED_VERSIONS UNSUPPORTED_PROTOCOL_VERSION);
use Mojo::JSON qw(from_json);
use Mojo::Util qw(b64_encode encode);
use Mojo::UserAgent;

use constant NAMES => {'prompts/get' => 'name', 'resources/read' => 'uri', 'tools/call' => 'name'};

has capabilities     => sub { {} };
has headers          => sub { {} };
has name             => 'PerlClient';
has protocol_version => PROTOCOL_VERSION;
has ua               => sub { Mojo::UserAgent->new };
has url              => sub {'http://localhost:3000/mcp'};
has version          => '1.0.0';

sub build_notification ($self, $method, $params = {}) {
  return {jsonrpc => '2.0', method => $method, params => $params};
}

sub build_request ($self, $method, $params = {}) {
  my $meta = {%{$params->{_meta} // {}}};
  $meta->{+META_CLIENT_CAPABILITIES} = $self->capabilities;
  $meta->{+META_CLIENT_INFO}         = {name => $self->name, version => $self->version};
  $meta->{+META_PROTOCOL_VERSION}    = $self->protocol_version;
  my $request = $self->build_notification($method, {%$params, _meta => $meta});
  $request->{id} = $self->{id} = $self->{id} ? $self->{id} + 1 : 1;
  return $request;
}

sub call_tool ($self, $name, $args = {}, $options = {}) {
  my $request = $self->build_request('tools/call', {name => $name, arguments => $args, %{_retry($options)}});
  return _result($self->send_request($request));
}

sub discover ($self) { _result($self->send_request($self->build_request('server/discover'))) }

sub get_prompt ($self, $name, $args = {}, $options = {}) {
  my $request = $self->build_request('prompts/get', {name => $name, arguments => $args, %{_retry($options)}});
  return _result($self->send_request($request));
}

sub list_prompts   ($self) { _result($self->send_request($self->build_request('prompts/list'))) }
sub list_resources ($self) { _result($self->send_request($self->build_request('resources/list'))) }
sub list_tools     ($self) { _result($self->send_request($self->build_request('tools/list'))) }

sub listen ($self, $filter, $cb) {
  my $request = $self->build_request('subscriptions/listen', {notifications => $filter});
  my $ua      = $self->ua;
  my $tx      = $ua->build_tx(POST => $self->url => $self->_headers($request) => json => $request);

  $tx->res->content->on(
    sse => sub ($content, $event = undef) {
      return unless $event && $event->{text} && (my $message = eval { from_json($event->{text}) });
      $tx->res->error({message => 'Interrupted'}) unless $cb->($message);
    }
  );
  $ua->start($tx);

  return 1;
}

sub read_resource ($self, $uri, $options = {}) {
  my $request = $self->build_request('resources/read', {uri => $uri, %{_retry($options)}});
  return _result($self->send_request($request));
}

sub send_request ($self, $request) {
  my $res = $self->_send($request);
  return $res unless my $version = _renegotiate($res);
  return $res if $version eq $self->protocol_version;

  $self->protocol_version($version);
  $request->{params}{_meta}{+META_PROTOCOL_VERSION} = $version;
  return $self->_send($request);
}

sub _encode_header ($value) {
  return $value if $value =~ /^[\x20-\x7e]*\z/ && $value !~ /^=\?base64\?.*\?=$/;
  return '=?base64?' . b64_encode(encode('UTF-8', $value), '') . '?=';
}

sub _headers ($self, $request) {
  my $headers = {
    %{$self->headers},
    Accept                 => 'application/json, text/event-stream',
    'Content-Type'         => 'application/json',
    'MCP-Protocol-Version' => $request->{params}{_meta}{+META_PROTOCOL_VERSION} // $self->protocol_version,
    'Mcp-Method'           => $request->{method}
  };
  if (my $key = NAMES->{$request->{method}}) {
    $headers->{'Mcp-Name'} = _encode_header($request->{params}{$key} // '');
  }
  return $headers;
}

sub _renegotiate ($res) {
  return undef unless ref $res eq 'HASH' && ref(my $error = $res->{error}) eq 'HASH';
  return undef unless ($error->{code} // 0) == UNSUPPORTED_PROTOCOL_VERSION;
  my %supported = map { $_ => 1 } @{($error->{data} // {})->{supported} // []};
  return first { $supported{$_} } @{(SUPPORTED_VERSIONS)};
}

sub _result ($res) {
  croak 'No response' unless $res;
  if (my $err = $res->{error}) { croak "Error $err->{code}: $err->{message}" }
  return $res->{result};
}

sub _retry ($options) {
  my $params = {};
  $params->{inputResponses} = $options->{input_responses} if $options->{input_responses};
  $params->{requestState}   = $options->{request_state}   if defined $options->{request_state};
  return $params;
}

sub _send ($self, $request) {
  my $ua = $self->ua;
  my $tx = $ua->build_tx(POST => $self->url => $self->_headers($request) => json => $request);

  # SSE handling
  my $id = $request->{id};
  my $response;
  $tx->res->content->on(
    sse => sub ($content, $event = undef) {
      return unless $event && $event->{text} && (my $res = eval { from_json($event->{text}) });
      return $self->emit(notification => $res) unless defined($res->{id}) && defined($id) && $res->{id} eq $id;
      $response = $res;
      $tx->res->error({message => 'Interrupted'});
    }
  );

  $tx = $ua->start($tx);

  # Request or notification accepted without a response
  return undef if $tx->res->code eq '202';

  if (my $err = $tx->error) {
    return $response                               if $err->{message} eq 'Interrupted';
    return $tx->res->json                          if $err->{code} && $tx->res->json;
    croak "$err->{code} response: $err->{message}" if $err->{code};
    croak "Connection error: $err->{message}";
  }

  return $tx->res->json;
}

1;

=encoding utf8

=head1 NAME

MCP::Client - MCP client

=head1 SYNOPSIS

  use MCP::Client;

  my $client = MCP::Client->new(url => 'http://localhost:3000/mcp');
  my $tools  = $client->list_tools;

=head1 DESCRIPTION

L<MCP::Client> is a client for MCP (Model Context Protocol) that communicates with MCP servers over HTTP.

It is exactly conformant on the wire, sending the C<_meta> fields and routing headers every request has to carry,
and it is deliberately nothing more than that. TTL caching, retry loops for input requests, and the OAuth
authorization flow are all left to the application, so this is a good client to test a server with and a starting
point rather than a finished agent.

=head1 EVENTS

L<MCP::Client> inherits all events from L<Mojo::EventEmitter> and emits the following new ones.

=head2 notification

  $client->on(notification => sub ($client, $notification) { ... });

Emitted for every JSON-RPC notification the server sends on the response stream of a request, such as a progress
report for a long running tool call.

=head1 ATTRIBUTES

L<MCP::Client> inherits all attributes from L<Mojo::EventEmitter> and implements the following new ones.

=head2 capabilities

  my $capabilities = $client->capabilities;
  $client          = $client->capabilities({elicitation => {}});

Capabilities to declare with every request, defaults to an empty hash reference.

=head2 headers

  my $headers = $client->headers;
  $client     = $client->headers({Authorization => 'Bearer abc123'});

Extra HTTP headers to send with every request, as a hash reference. Useful for passing an C<Authorization> header to
an MCP server that requires OAuth bearer authentication. Defaults to an empty hash reference.

=head2 name

  my $name = $client->name;
  $client  = $client->name('PerlClient');

The name of the client, defaults to C<PerlClient>.

=head2 protocol_version

  my $version = $client->protocol_version;
  $client     = $client->protocol_version('2026-07-28');

The protocol version to make requests with, defaults to L<MCP::Constants/"PROTOCOL_VERSION">. A server rejecting it
with an C<UnsupportedProtocolVersionError> gets one more chance with the newest version both sides support, and that
version is remembered for subsequent requests.

=head2 ua

  my $ua  = $client->ua;
  $client = $client->ua(Mojo::UserAgent->new);

The user agent used for making HTTP requests, defaults to a new instance of L<Mojo::UserAgent>.

=head2 url

  my $url  = $client->url;
  $client  = $client->url('http://localhost:3000/mcp');

The URL of the MCP server, defaults to C<http://localhost:3000/mcp>.

=head2 version

  my $version = $client->version;
  $client     = $client->version('1.0.0');

The version of the client, defaults to C<1.0.0>.

=head1 METHODS

L<MCP::Client> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 build_notification

  my $notification = $client->build_notification('method_name', {param1 => 'value1'});

Builds a JSON-RPC notification with the given method name and parameters.

=head2 build_request

  my $request = $client->build_request('method_name', {param1 => 'value1'});

Builds a JSON-RPC request with the given method name and parameters, adding the C<_meta> fields every request has to
carry.

=head2 call_tool

  my $result = $client->call_tool('tool_name');
  my $result = $client->call_tool('tool_name', {arg1 => 'value1'});
  my $result = $client->call_tool('tool_name', {arg1 => 'value1'}, {request_state => $state});

Calls a tool on the MCP server with the specified name and arguments, returning the result.

A result with C<resultType> set to C<input_required> is returned as-is; gathering the requested input and deciding
whether to call again is up to you.

These options are currently available:

=over 2

=item input_responses

  input_responses => {confirm => {action => 'accept', content => {ok => \1}}}

Responses to the input requests of an earlier C<input_required> result, keyed by the same names.

=item request_state

  request_state => 'eyJ...'

The C<requestState> of an earlier C<input_required> result, passed back verbatim.

=back

=head2 discover

  my $result = $client->discover;

Discover the protocol versions, capabilities, and instructions of the MCP server.

=head2 get_prompt

  my $result = $client->get_prompt('prompt_name');
  my $result = $client->get_prompt('prompt_name', {arg1 => 'value1'});
  my $result = $client->get_prompt('prompt_name', {arg1 => 'value1'}, {request_state => $state});

Get a prompt from the MCP server with the specified name and arguments, returning the result. Takes the same options
as L</"call_tool">.

=head2 list_prompts

  my $prompts = $client->list_prompts;

Lists all available prompts on the MCP server.

=head2 list_resources

  my $resources = $client->list_resources;

Lists all available resources on the MCP server.

=head2 list_tools

  my $tools = $client->list_tools;

Lists all available tools on the MCP server.

=head2 listen

  my $bool = $client->listen({toolsListChanged => \1}, sub ($message) {...});

Open a C<subscriptions/listen> stream for the requested notification types and block, invoking the callback for
every message the server sends, starting with the acknowledgement. Returning a false value from the callback closes
the stream. Only servers configured with C<< streaming => 1 >> support this.

=head2 read_resource

  my $result = $client->read_resource('file:///path/to/resource.txt');
  my $result = $client->read_resource('file:///path/to/resource.txt', {request_state => $state});

Reads a resource from the MCP server with the specified URI, returning the result. Takes the same options as
L</"call_tool">.

=head2 send_request

  my $response = $client->send_request($request);

Sends a JSON-RPC request to the MCP server and returns the response, or C<undef> if the server accepted it without
one.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
