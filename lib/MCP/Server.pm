package MCP::Server;
use Mojo::Base -base, -signatures;

use List::Util     qw(first);
use Mojo::JSON     qw(false true);
use MCP::Constants qw(INVALID_PARAMS INVALID_REQUEST METHOD_NOT_FOUND PARSE_ERROR PROTOCOL_VERSION);
use MCP::Prompt;
use MCP::Server::Transport::HTTP;
use MCP::Server::Transport::Stdio;
use MCP::Tool;
use Scalar::Util qw(blessed);

has name    => 'PerlServer';
has prompts => sub { [] };
has tools   => sub { [] };
has 'transport';
has version => '1.0.0';

sub handle ($self, $request, $context) {
  return _jsonrpc_error(PARSE_ERROR, 'Invalid JSON-RPC request') unless ref $request eq 'HASH';
  return _jsonrpc_error(INVALID_REQUEST, 'Missing JSON-RPC method') unless my $method = $request->{method};

  # Requests
  if (defined(my $id = $request->{id})) {

    if ($method eq 'initialize') {
      my $result = $self->_handle_initialize($request->{params} // {});
      return _jsonrpc_response($result, $id);
    }
    elsif ($method eq 'ping') {
      return _jsonrpc_response({}, $id);
    }
    elsif ($method eq 'prompts/list') {
      my $result = $self->_handle_prompts_list;
      return _jsonrpc_response($result, $id);
    }
    elsif ($method eq 'prompts/get') {
      return $self->_handle_prompts_get($request->{params} // {}, $id, $context);
    }
    elsif ($method eq 'tools/list') {
      my $result = $self->_handle_tools_list;
      return _jsonrpc_response($result, $id);
    }
    elsif ($method eq 'tools/call') {
      return $self->_handle_tools_call($request->{params} // {}, $id, $context);
    }

    # Method not found
    return _jsonrpc_error(METHOD_NOT_FOUND, "Method '$method' not found", $id);
  }

  # Notifications (ignored for now)
  return undef;
}

sub prompt ($self, %args) {
  my $prompt = MCP::Prompt->new(%args);
  push @{$self->prompts}, $prompt;
  return $prompt;
}

sub to_action ($self) {
  $self->transport(my $http = MCP::Server::Transport::HTTP->new(server => $self));
  return sub ($c) { $http->handle_request($c) };
}

sub to_stdio ($self) {
  $self->transport(my $stdio = MCP::Server::Transport::Stdio->new(server => $self));
  $self->transport->handle_requests;
}

sub tool ($self, %args) {
  my $tool = MCP::Tool->new(%args);
  push @{$self->tools}, $tool;
  return $tool;
}

sub _handle_initialize ($self, $params) {
  return {
    protocolVersion => PROTOCOL_VERSION,
    capabilities    => {prompts => {},          tools   => {}},
    serverInfo      => {name    => $self->name, version => $self->version}
  };
}

sub _handle_prompts_list ($self) {
  my @prompts;
  for my $prompt (@{$self->prompts}) {
    my $info = {name => $prompt->name, description => $prompt->description, arguments => $prompt->arguments};
    push @prompts, $info;
  }

  return {prompts => \@prompts};
}

sub _handle_prompts_get ($self, $params, $id, $context) {
  my $name = $params->{name}      // '';
  my $args = $params->{arguments} // {};
  return _jsonrpc_error(METHOD_NOT_FOUND, "Prompt '$name' not found")
    unless my $prompt = first { $_->name eq $name } @{$self->prompts};
  return _jsonrpc_error(INVALID_PARAMS, 'Invalid arguments') if $prompt->validate_input($args);

  my $result = $prompt->call($args, $context);
  return $result->then(sub { _jsonrpc_response($_[0], $id) }) if blessed($result) && $result->isa('Mojo::Promise');
  return _jsonrpc_response($result, $id);
}

sub _handle_tools_call ($self, $params, $id, $context) {
  my $name = $params->{name}      // '';
  my $args = $params->{arguments} // {};
  return _jsonrpc_error(METHOD_NOT_FOUND, "Tool '$name' not found")
    unless my $tool = first { $_->name eq $name } @{$self->tools};
  return _jsonrpc_error(INVALID_PARAMS, 'Invalid arguments') if $tool->validate_input($args);

  my $result = $tool->call($args, $context);
  return $result->then(sub { _jsonrpc_response($_[0], $id) }) if blessed($result) && $result->isa('Mojo::Promise');
  return _jsonrpc_response($result, $id);
}

sub _handle_tools_list ($self) {
  my @tools;
  for my $tool (@{$self->tools}) {
    my $info = {name => $tool->name, description => $tool->description, inputSchema => $tool->input_schema};
    if (my $output_schema = $tool->output_schema) { $info->{outputSchema} = $output_schema }
    push @tools, $info;
  }

  return {tools => \@tools};
}

sub _jsonrpc_error ($code, $message, $id = undef) {
  return {jsonrpc => '2.0', id => $id, error => {code => $code, message => $message}};
}

sub _jsonrpc_response ($result, $id = undef) {
  return {jsonrpc => '2.0', id => $id, result => $result};
}

1;

=encoding utf8

=head1 NAME

MCP::Server - MCP server implementation

=head1 SYNOPSIS

  use MCP::Server;

  my $server = MCP::Server->new(name => 'MyServer');

  $server->tool(
    name         => 'echo',
    description  => 'Echo the input text',
    input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
    code         => sub ($tool, $args) {
      return "Echo: $args->{msg}";
    }
  );

  $server->prompt(
    name        => 'echo',
    description => 'A prompt to demonstrate the echo tool',
    code        => sub ($prompt, $args) {
      return 'Use the echo tool with the message "Hello, World!"';
    }
  );

  $server->to_stdio;

=head1 DESCRIPTION

L<MCP::Server> is an MCP (Model Context Protocol) server.

=head1 ATTRIBUTES

L<MCP::Server> implements the following attributes.

=head2 name

  my $name = $server->name;
  $server  = $server->name('MyServer');

The name of the server, used for identification.

=head2 tools

  my $tools = $server->tools;
  $server   = $server->tools([MCP::Tool->new]);

An array reference containing registered tools.

=head2 transport

  my $transport = $server->transport;
  $server       = $server->transport(MCP::Server::Transport::HTTP->new);

The transport layer used by the server, such as L<MCP::Server::Transport::HTTP> or L<MCP::Server::Transport::Stdio>.

=head2 version

  my $version = $server->version;
  $server     = $server->version('1.0.0');

The version of the server.

=head1 METHODS

L<MCP::Tool> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 handle

  my $response = $server->handle($request, $context);

Handle a JSON-RPC request and return a response.

=head2 prompt

  my $prompt = $server->prompt(
    name        => 'my_prompt',
    description => 'A sample prompt',
    arguments   => [{name => 'foo', description => 'Whatever', required => 1}],
    code        => sub ($prompt, $args) { ... }
  );

Register a new prompt with the server.

=head2 to_action

  my $action = $server->to_action;

Convert the server to a L<Mojolicious> action.

=head2 to_stdio

  $server->to_stdio;

Handles JSON-RPC requests over standard input/output.

=head2 tool

  my $tool = $server->tool(
    name         => 'my_tool',
    description  => 'A sample tool',
    input_schema => {type => 'object', properties => {foo => {type => 'string'}}},
    code         => sub ($tool, $args) { ... }
  );

Register a new tool with the server.

=head1 SEE ALSO

L<MCP>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
