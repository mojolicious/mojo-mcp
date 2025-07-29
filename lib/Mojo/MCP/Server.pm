package Mojo::MCP::Server;
use Mojo::Base -base, -signatures;

use List::Util           qw(first);
use Mojo::JSON           qw(false true);
use Mojo::MCP::Constants qw(INVALID_REQUEST METHOD_NOT_FOUND PARSE_ERROR PROTOCOL_VERSION);
use Mojo::MCP::Server::Transport::HTTP;
use Mojo::MCP::Server::Transport::Stdio;
use Mojo::MCP::Tool;

has name  => 'MojoServer';
has tools => sub { [] };
has 'transport';
has version => '1.0.0';

sub handle ($self, $request) {
  return _jsonrpc_error(PARSE_ERROR, 'Invalid JSON-RPC request') unless ref $request eq 'HASH';
  return _jsonrpc_error(INVALID_REQUEST, 'Missing JSON-RPC method') unless my $method = $request->{method};

  # Requests
  if (defined(my $id = $request->{id})) {

    if ($method eq 'initialize') {
      my $result = $self->_handle_initialize($request->{params} // {});
      return _jsonrpc_response($result, $id);
    }
    elsif ($method eq 'tools/list') {
      my $result = $self->_handle_tools_list;
      return _jsonrpc_response($result, $id);
    }
    elsif ($method eq 'tools/call') {
      my $result = $self->_handle_tools_call($request->{params} // {});
      return _jsonrpc_response($result, $id);
    }

    # Method not found
    return _jsonrpc_error(METHOD_NOT_FOUND, "Method '$method' not found", $id);
  }

  # Notifications (ignored for now)
  return undef;
}

sub to_action ($self) {
  $self->transport(my $http = Mojo::MCP::Server::Transport::HTTP->new(server => $self));
  return sub ($c) { $http->handle_request($c) };
}

sub to_stdio ($self) {
  $self->transport(my $stdio = Mojo::MCP::Server::Transport::Stdio->new(server => $self));
  $self->transport->handle_requests;
}

sub tool ($self, %args) {
  my $tool = Mojo::MCP::Tool->new(%args);
  push @{$self->tools}, $tool;
  return $tool;
}

sub _handle_initialize ($self, $params) {
  return {
    protocolVersion => PROTOCOL_VERSION,
    capabilities    => {tools => {listChanged => true}},
    serverInfo      => {name  => $self->name, version => $self->version}
  };
}

sub _handle_tools_call ($self, $params) {
  my $name   = $params->{name};
  my $args   = $params->{arguments} // {};
  my $tool   = first { $_->name eq $name } @{$self->tools};
  my $result = $tool->call($args);
  return {content => [{type => 'text', text => $result}], isError => false};
}

sub _handle_tools_list ($self) {
  my @tools
    = map { {name => $_->name, description => $_->description, inputSchema => $_->input_schema} } @{$self->tools};
  return {tools => \@tools};
}

sub _jsonrpc_error ($code, $message, $id = undef) {
  return {jsonrpc => '2.0', id => $id, error => {code => $code, message => $message}};
}

sub _jsonrpc_response ($result, $id = undef) {
  return {jsonrpc => '2.0', id => $id, result => $result};
}

1;
