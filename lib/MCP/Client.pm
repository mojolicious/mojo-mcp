package MCP::Client;
use Mojo::Base -base, -signatures;

use Carp           qw(croak);
use MCP::Constants qw(PROTOCOL_VERSION);
use Mojo::JSON     qw(decode_json);
use Mojo::UserAgent;
use Scalar::Util qw(weaken);

has name => 'PerlClient';
has 'session_id';
has ua      => sub { Mojo::UserAgent->new };
has url     => sub {'http://localhost:3000/mcp'};
has version => '1.0.0';

sub build_request ($self, $method, $params = {}) {
  my $request = $self->build_notification($method, $params);
  $request->{id} = $self->{id} = $self->{id} ? $self->{id} + 1 : 1;
  return $request;
}

sub build_notification ($self, $method, $params = {}) {
  return {jsonrpc => '2.0', method => $method, params => $params};
}

sub call_tool ($self, $name, $args = {}) {
  my $request = $self->build_request('tools/call', {name => $name, arguments => $args});
  return _result($self->send_request($request));
}

sub initialize_session ($self) {
  my $request = $self->build_request(
    initialize => {
      protocolVersion => PROTOCOL_VERSION,
      capabilities    => {},
      clientInfo      => {name => $self->name, version => $self->version,},
    }
  );
  my $result = _result($self->send_request($request));
  $self->send_request($self->build_notification('notifications/initialized'));
  return $result;
}

sub list_tools ($self) { _result($self->send_request($self->build_request('tools/list'))) }
sub ping       ($self) { _result($self->send_request($self->build_request('ping'))) }

sub send_request ($self, $request) {
  my $headers = {Accept => 'application/json, text/event-stream', 'Content-Type' => 'application/json'};
  if (my $session_id = $self->session_id) { $headers->{'Mcp-Session-Id'} = $session_id }
  my $ua = $self->ua;
  my $tx = $ua->build_tx(POST => $self->url => $headers => json => $request);

  # SSE handling
  my $id = $request->{id};
  my $response;
  $tx->res->content->on(
    sse => sub {
      my ($content, $event) = @_;
      return unless my $res = eval { decode_json($event) };
      return unless defined($res->{id}) && defined($id) && $res->{id} eq $id;
      $response = $res;
      $tx->res->error({message => 'Interrupted'});
    }
  );

  $tx = $ua->start($tx);

  if (my $session_id = $tx->res->headers->header('Mcp-Session-Id')) { $self->session_id($session_id) }

  # Request or notification accepted without a response
  return undef if $tx->res->code eq '202';

  if (my $err = $tx->error) {
    return $response                               if $err->{message} eq 'Interrupted';
    croak "$err->{code} response: $err->{message}" if $err->{code};
    croak "Connection error: $err->{message}";
  }

  return $tx->res->json;
}

sub _result ($res) {
  croak 'No response' unless $res;
  if (my $err = $res->{error}) { croak "Error $err->{code}: $err->{message}" }
  return $res->{result};
}

1;

=encoding utf8

=head1 NAME

MCP::Server::Transport::HTTP - HTTP transport for MCP servers

=head1 SYNOPSIS

  use MCP::Client;

  my $client = MCP::Client->new(url => 'http://localhost:3000/mcp');
  $client->initialize_session;
  my $tools = $client->list_tools;

=head1 DESCRIPTION

L<MCP::Client> is a client for MCP (Model Context Protocol) that communicates with MCP servers over HTTP.

=head1 ATTRIBUTES

L<MCP::Client> inherits all attributes from L<Mojo::Base> and implements the following new ones.

=head2 name

  my $name = $client->name;
  $client  = $client->name('PerlClient');

The name of the client, defaults to C<PerlClient>.

=head2 session_id

  my $session_id = $client->session_id;
  $client        = $client->session_id('12345');

The session ID for the client, used to maintain state across requests.

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

L<MCP::Client> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 build_request

  my $request = $client->build_request('method_name', {param1 => 'value1'});

Builds a JSON-RPC request with the given method name and parameters.

=head2 build_notification

  my $notification = $client->build_notification('method_name', {param1 => 'value1'});

Builds a JSON-RPC notification with the given method name and parameters.

=head2 call_tool

  my $result = $client->call_tool('tool_name');
  my $result = $client->call_tool('tool_name', {arg1 => 'value1'});

Calls a tool on the MCP server with the specified name and arguments, returning the result.

=head2 initialize_session

  my $result = $client->initialize_session;

Initializes a session with the MCP server, setting up the protocol version and client information.

=head2 list_tools

  my $tools = $client->list_tools;

Lists all available tools on the MCP server.

=head2 ping

  my $result = $client->ping;

Sends a ping request to the MCP server to check connectivity.

=head2 send_request

  my $response = $client->send_request($request);

Sends a JSON-RPC request to the MCP server and returns the response.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
