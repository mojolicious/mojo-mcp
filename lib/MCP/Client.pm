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

sub call_tool ($self, $name, $args) {
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
