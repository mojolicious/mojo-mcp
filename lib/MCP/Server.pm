package MCP::Server;
use Mojo::Base 'Mojo::EventEmitter', -signatures;

use Crypt::PRNG qw(random_bytes);
use List::Util  qw(first min);
use Mojo::JSON  qw(false true);
use Mojo::Log;
use MCP::Constants qw(INSUFFICIENT_SCOPE INTERNAL_ERROR INVALID_PARAMS INVALID_REQUEST META_CLIENT_CAPABILITIES),
  qw(META_CLIENT_INFO META_LOG_LEVEL META_PROTOCOL_VERSION META_SERVER_INFO METHOD_NOT_FOUND PARSE_ERROR),
  qw(SUPPORTED_VERSIONS UNSUPPORTED_PROTOCOL_VERSION);
use MCP::Prompt;
use MCP::Resource;
use MCP::Server::Legacy qw(legacy_context legacy_result);
use MCP::Server::Subscription;
use MCP::Server::Transport::HTTP;
use MCP::Server::Transport::Stdio;
use MCP::Tool;
use Scalar::Util qw(blessed);

has cache_scope => 'public';
has cache_ttl   => 0;
has 'instructions';
has log           => sub { Mojo::Log->new };
has name          => 'PerlServer';
has prompts       => sub { [] };
has resources     => sub { [] };
has state_secret  => sub { random_bytes(32) };
has state_timeout => 300;
has tools         => sub { [] };
has 'transport';
has version => '1.0.0';

sub handle ($self, $request, $context) {
  return _jsonrpc_error(PARSE_ERROR,     'Invalid JSON-RPC request') unless ref $request eq 'HASH';
  return _jsonrpc_error(INVALID_REQUEST, 'Missing JSON-RPC method')  unless $request->{method};

  # Requests
  if (defined(my $id = $request->{id})) {
    my $response;
    return $self->_internal_error($context, $id, $@)
      unless eval { $response = $self->_dispatch($request, $id, $context); 1 };
    return $response;
  }

  # Notifications (ignored for now)
  return undef;
}

sub notify_list_changed ($self, $kind) {
  return undef unless my $transport = $self->transport;
  return $transport->notify_all("notifications/$kind/list_changed");
}

sub oauth_metadata ($self, %args) {
  my %scopes;
  for my $primitive (@{$self->tools}, @{$self->prompts}, @{$self->resources}) {
    $scopes{$_} = 1 for @{$primitive->scopes};
  }
  my $metadata = {%args};
  $metadata->{scopes_supported} //= [sort keys %scopes] if keys %scopes;
  return $metadata;
}

sub prompt ($self, %args) {
  my $prompt = MCP::Prompt->new(%args);
  push @{$self->prompts}, $prompt;
  return $prompt;
}

sub resource ($self, %args) {
  my $resource = MCP::Resource->new(%args);
  push @{$self->resources}, $resource;
  return $resource;
}

sub to_action ($self, $options = {}) {
  $self->transport(my $http = MCP::Server::Transport::HTTP->new(server => $self, %$options));
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

sub _handle_discover ($self) {
  my $transport = $self->transport;
  my $caps      = $transport && $transport->notifications ? {listChanged => true} : {};

  my $capabilities = {extensions => {}};
  $capabilities->{prompts}   = $caps if @{$self->prompts};
  $capabilities->{resources} = $caps if @{$self->resources};
  $capabilities->{tools}     = $caps if @{$self->tools};

  my $result = {supportedVersions => SUPPORTED_VERSIONS, capabilities => $capabilities};
  if (defined(my $instructions = $self->instructions)) { $result->{instructions} = $instructions }
  return $result;
}

sub _handle_listen ($self, $params, $id, $context) {
  my $transport = $self->transport;
  return MCP::Server::Subscription->new(id => $id, notifications => $params->{notifications} // {})
    if $transport && $transport->notifications;
  $context->status(404);
  return _jsonrpc_error(METHOD_NOT_FOUND, "Method 'subscriptions/listen' not found", $id);
}

sub _handle_prompts_list ($self, $context) {
  my $all = $self->_prompts($context);

  my (@prompts, @listed);
  for my $prompt (@$all) {
    next unless $context->has_scope(@{$prompt->scopes});
    my $info = {name => $prompt->name, description => $prompt->description, arguments => $prompt->arguments};
    push @prompts, $info;
    push @listed,  $prompt;
  }

  return {prompts => \@prompts}, $self->_list_cache_hints('prompts', $all, \@listed);
}

sub _handle_prompts_get ($self, $params, $id, $context) {
  my $name = $params->{name}      // '';
  my $args = $params->{arguments} // {};
  return _jsonrpc_error(INVALID_PARAMS, "Prompt '$name' not found", $id)
    unless my $prompt = first { $_->name eq $name } @{$self->_prompts($context)};
  if (my $err = $self->_check_scope($prompt, $context, $id)) { return $err }
  return _jsonrpc_error(INVALID_PARAMS, 'Invalid arguments', $id) if $prompt->validate_input($args);
  $self->_state($context, $params, 'prompts/get', $name);

  return $self->_respond($prompt->call($args, $context), $id, $context);
}

sub _handle_resources_list ($self, $context) {
  my $all = $self->_resources($context);

  my (@resources, @listed);
  for my $resource (@$all) {
    next unless $context->has_scope(@{$resource->scopes});
    my $info = {
      uri         => $resource->uri,
      name        => $resource->name,
      description => $resource->description,
      mimeType    => $resource->mime_type
    };
    push @resources, $info;
    push @listed,    $resource;
  }

  return {resources => \@resources}, $self->_list_cache_hints('resources', $all, \@listed);
}

sub _handle_resources_read ($self, $params, $id, $context) {
  my $uri = $params->{uri} // '';
  return _jsonrpc_error(INVALID_PARAMS, "Resource '$uri' not found", $id)
    unless my $resource = first { $_->uri eq $uri } @{$self->_resources($context)};
  if (my $err = $self->_check_scope($resource, $context, $id)) { return $err }
  my $hints
    = $self->_state($context, $params, 'resources/read', $uri)
    ? undef
    : _cache_hints($resource->cache_ttl, @{$resource->scopes} ? 'private' : $resource->cache_scope);

  return $self->_respond($resource->call($context), $id, $context, $hints);
}

sub _handle_tools_call ($self, $params, $id, $context) {
  my $name = $params->{name}      // '';
  my $args = $params->{arguments} // {};
  return _jsonrpc_error(INVALID_PARAMS, "Tool '$name' not found", $id)
    unless my $tool = first { $_->name eq $name } @{$self->_tools($context)};
  if (my $err = $self->_check_scope($tool, $context, $id)) { return $err }
  return _jsonrpc_error(INVALID_PARAMS, 'Invalid arguments', $id) if $tool->validate_input($args);
  $self->_state($context, $params, 'tools/call', $name);

  return $self->_respond($tool->call($args, $context), $id, $context);
}

sub _handle_tools_list ($self, $context) {
  my $all = $self->_tools($context);

  my (@tools, @listed);
  for my $tool (@$all) {
    next unless $context->has_scope(@{$tool->scopes});
    my $info = {name => $tool->name, description => $tool->description, inputSchema => $tool->input_schema};
    if (my $output_schema = $tool->output_schema) { $info->{outputSchema} = $output_schema }

    my $annotations = $tool->annotations;
    $info->{annotations} = $annotations if keys %$annotations;
    push @tools,  $info;
    push @listed, $tool;
  }

  return {tools => \@tools}, $self->_list_cache_hints('tools', $all, \@listed);
}

sub _cache_hints ($ttl, $scope) { return {cacheScope => $scope, ttlMs => $ttl} }

sub _check_fields ($meta, $id) {
  my $version = $meta->{+META_PROTOCOL_VERSION};
  return _jsonrpc_error(INVALID_PARAMS, 'Missing protocol version', $id) unless defined $version;
  return _jsonrpc_error(UNSUPPORTED_PROTOCOL_VERSION, "Unsupported protocol version '$version'",
    $id, {supported => SUPPORTED_VERSIONS, requested => $version})
    unless first { $_ eq $version } @{(SUPPORTED_VERSIONS)};
  return _jsonrpc_error(INVALID_PARAMS, 'Missing client capabilities', $id)
    unless ref $meta->{+META_CLIENT_CAPABILITIES} eq 'HASH';
  return undef;
}

sub _check_meta ($self, $params, $id, $context) {
  my $meta = $params->{_meta} // {};

  if (my $err = _check_fields($meta, $id)) {
    $context->status(400);
    return $err;
  }

  $context->protocol_version($meta->{+META_PROTOCOL_VERSION});
  $context->client_capabilities($meta->{+META_CLIENT_CAPABILITIES});
  if (my $info = $meta->{+META_CLIENT_INFO})       { $context->client_info($info) }
  if (my $level = $meta->{+META_LOG_LEVEL})        { $context->log_level($level) }
  if (defined(my $token = $meta->{progressToken})) { $context->progress_token($token) }

  return undef;
}

sub _check_scope ($self, $primitive, $context, $id) {
  my $scopes = $primitive->scopes;
  return undef if $context->has_scope(@$scopes);
  $context->insufficient_scope($scopes)->status(403);
  return _jsonrpc_error(INSUFFICIENT_SCOPE, 'Insufficient scope', $id);
}

sub _dispatch ($self, $request, $id, $context) {
  my $method = $request->{method};
  my $params = $request->{params} // {};

  # Legacy
  if (my $version = $context->legacy) {
    if (my $result = legacy_result($self, $method, $version)) { return $self->_jsonrpc_response($result, $id) }
    legacy_context($params, $context);
  }
  elsif (my $err = $self->_check_meta($params, $id, $context)) { return $err }

  if ($method eq 'server/discover') {
    my $hints = _cache_hints($self->cache_ttl, $self->cache_scope);
    return $self->_jsonrpc_response($self->_handle_discover, $id, $hints);
  }
  elsif ($method eq 'tools/list') {
    my ($result, $hints) = $self->_handle_tools_list($context);
    return $self->_jsonrpc_response($result, $id, $hints);
  }
  elsif ($method eq 'tools/call') {
    return $self->_handle_tools_call($params, $id, $context);
  }
  elsif ($method eq 'prompts/list') {
    my ($result, $hints) = $self->_handle_prompts_list($context);
    return $self->_jsonrpc_response($result, $id, $hints);
  }
  elsif ($method eq 'prompts/get') {
    return $self->_handle_prompts_get($params, $id, $context);
  }
  elsif ($method eq 'resources/list') {
    my ($result, $hints) = $self->_handle_resources_list($context);
    return $self->_jsonrpc_response($result, $id, $hints);
  }
  elsif ($method eq 'resources/read') {
    return $self->_handle_resources_read($params, $id, $context);
  }
  elsif ($method eq 'subscriptions/listen') {
    return $self->_handle_listen($params, $id, $context);
  }

  # Method not found
  $context->status(404);
  return _jsonrpc_error(METHOD_NOT_FOUND, "Method '$method' not found", $id);
}

sub _internal_error ($self, $context, $id, $err) {
  $self->log->error("MCP request failed: $err");
  $context->status(500);
  return _jsonrpc_error(INTERNAL_ERROR, 'Internal error', $id);
}

sub _jsonrpc_error ($code, $message, $id = undef, $data = undef) {
  my $error = {code => $code, message => $message};
  $error->{data} = $data if defined $data;
  return {jsonrpc => '2.0', id => $id, error => $error};
}

sub _jsonrpc_response ($self, $result, $id = undef, $hints = undef) {
  my $type = $result->{resultType} // 'complete';
  my %new  = (%$result, ($hints && $type eq 'complete' ? %$hints : ()), resultType => $type);
  $new{_meta} = {%{$result->{_meta} // {}}, META_SERVER_INFO() => {name => $self->name, version => $self->version}};
  return {jsonrpc => '2.0', id => $id, result => \%new};
}

sub _list_cache_hints ($self, $event, $all, $listed) {
  my $private = $self->has_subscribers($event) || grep { @{$_->scopes} } @$all;
  return _cache_hints(min(map { $_->cache_ttl } @$listed) // 0, $private ? 'private' : 'public');
}

sub _prompts ($self, $context) {
  my $prompts = [@{$self->prompts}];
  $self->emit('prompts', $prompts, $context);
  return $prompts;
}

sub _resources ($self, $context) {
  my $resources = [@{$self->resources}];
  $self->emit('resources', $resources, $context);
  return $resources;
}

sub _respond ($self, $result, $id, $context, $hints = undef) {
  return $self->_jsonrpc_response($result, $id, $hints) unless blessed($result) && $result->isa('Mojo::Promise');
  return $result->then(sub { $self->_jsonrpc_response($_[0], $id, $hints) })
    ->catch(sub { $self->_internal_error($context, $id, $_[0]) });
}

sub _state ($self, $context, $params, @binding) {
  $context->state_binding(join "\0", @binding)->state_secret($self->state_secret);
  $context->state_timeout($self->state_timeout);
  $context->input_responses($params->{inputResponses}) if ref $params->{inputResponses} eq 'HASH';
  $context->raw_request_state($params->{requestState}) if defined $params->{requestState};
  return $context->input_responses || defined $context->raw_request_state ? 1 : 0;
}

sub _tools ($self, $context) {
  my $tools = [@{$self->tools}];
  $self->emit('tools', $tools, $context);
  return $tools;
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

  $server->resource(
    uri         => 'file:///example.txt',
    name        => 'example',
    description => 'A simple text resource',
    mime_type   => 'text/plain',
    code        => sub ($resource) {
      return 'This is an example resource content.';
    }
  );

  $server->to_stdio;

=head1 DESCRIPTION

L<MCP::Server> is an MCP (Model Context Protocol) server.

=head1 EVENTS

L<MCP::Server> inherits all events from L<Mojo::EventEmitter> and emits the following new ones.

=head2 prompts

  $server->on(prompts => sub ($server, $prompts, $context) { ... });

Emitted whenever the list of prompts is accessed.

=head2 resources

  $server->on(resources => sub ($server, $resources, $context) { ... });

Emitted whenever the list of resources is accessed.

=head2 tools

  $server->on(tools => sub ($server, $tools, $context) { ... });

Emitted whenever the list of tools is accessed.

=head1 ATTRIBUTES

L<MCP::Server> implements the following attributes.

=head2 cache_scope

  my $scope = $server->cache_scope;
  $server   = $server->cache_scope('private');

Cache scope advertised for C<server/discover> results, either C<public> or C<private>. Defaults to C<public>. Cache
hints for the other cacheable results are declared per primitive with L<MCP::Primitive/"cache_scope">.

=head2 cache_ttl

  my $ttl = $server->cache_ttl;
  $server = $server->cache_ttl(3_600_000);

How long C<server/discover> results may be cached, in milliseconds. Defaults to C<0>, which means the document must
be revalidated on every request.

=head2 instructions

  my $instructions = $server->instructions;
  $server          = $server->instructions('Use the echo tool to repeat text.');

Free-form guidance for the model on how to use this server, returned by C<server/discover>. Omitted from the
document when C<undef>, which is the default.

=head2 log

  my $log = $server->log;
  $server = $server->log(Mojo::Log->new);

Where exceptions thrown by prompts, resources, and tools are reported, defaults to a L<Mojo::Log> object writing to
C<STDERR>, which is where an MCP host collects the output of a stdio server.

A server mounted in a L<Mojolicious> application with L</"to_action"> adopts the log of that application on its
first request, so exceptions end up wherever the rest of the application logs, with the same level and format. Set
this attribute yourself to opt out of that.

The caller never sees the exception itself, only an C<InternalError>, since it can easily contain file system paths
or connection strings.

=head2 name

  my $name = $server->name;
  $server  = $server->name('MyServer');

The name of the server, used for identification.

=head2 prompts

  my $prompts = $server->prompts;
  $server    = $server->prompts([MCP::Prompt->new]);

An array reference containing registered prompts.

=head2 resources

  my $resources = $server->resources;
  $server      = $server->resources([MCP::Resource->new]);

An array reference containing registered resources.

=head2 state_secret

  my $secret = $server->state_secret;
  $server    = $server->state_secret($ENV{MY_MCP_SECRET});

Key used to authenticate the request state of C<input_required> results, which travels through the client and has to
be tamper proof. Defaults to 32 random bytes generated once per process.

That default is only correct for a single process. Under a pre-forking web server or behind a load balancer every
worker mints state the others reject, so retries loop instead of completing, and you have to configure the same
secret everywhere. Use at least 32 bytes from a cryptographically secure source, and keep it out of your code.

=head2 state_timeout

  my $seconds = $server->state_timeout;
  $server     = $server->state_timeout(60);

How long the request state of an C<input_required> result stays valid, in seconds. Defaults to C<300>, and should be
no longer than a client plausibly needs to gather the requested input.

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

L<MCP::Server> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 handle

  my $response = $server->handle($request, $context);

Handle a JSON-RPC request and return a response, which may also be a L<Mojo::Promise>. A C<subscriptions/listen>
request yields an L<MCP::Server::Subscription> object instead, which the transport turns into a notification
stream. Notifications yield C<undef>.

=head2 notify_list_changed

  my $bool = $server->notify_list_changed('tools');

Broadcast a C<notifications/$kind/list_changed> JSON-RPC notification to all connected clients. Returns true on
success, or C<undef> if no notification could be delivered.

=head2 oauth_metadata

  my $metadata = $server->oauth_metadata(
    resource              => 'https://example.com/mcp',
    authorization_servers => ['https://auth.example.com']
  );

Build an OAuth 2.0 Protected Resource Metadata document from the given fields, to be served from
C</.well-known/oauth-protected-resource>. Unless C<scopes_supported> is provided, it is filled in with the sorted
union of all scopes declared by registered tools, prompts, and resources.

=head2 prompt

  my $prompt = $server->prompt(
    name        => 'my_prompt',
    description => 'A sample prompt',
    arguments   => [{name => 'foo', description => 'Whatever', required => 1}],
    code        => sub ($prompt, $args) { ... }
  );

Register a new prompt with the server.

=head2 resource

  my $resource = $server->resource(
    uri         => 'file://my_resource',
    name        => 'sample_resource',
    description => 'A sample resource',
    mime_type   => 'text/plain',
    code        => sub ($resource) { ... }
  );

Register a new resource with the server.

=head2 to_action

  my $action = $server->to_action;
  my $action = $server->to_action({streaming => 1});

Convert the server to a L<Mojolicious> action. Any options are passed through to the constructor of
L<MCP::Server::Transport::HTTP>; in particular, C<< streaming => 1 >> opts in to C<subscriptions/listen>, the
long-lived notification stream.

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
