use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Client;
use MCP::Constants qw(INTERNAL_ERROR META_PROTOCOL_VERSION PROTOCOL_VERSION);
use MCP::Server;
use Mojo::Promise;

my $server = MCP::Server->new;
$server->tool(name => 'boom',       code => sub ($tool, $args) { die "kaboom in /secret/path.pm line 23\n" });
$server->tool(name => 'boom_async', code => sub ($tool, $args) { Mojo::Promise->reject('async kaboom') });
$server->tool(
  name => 'boom_late',
  code => sub ($tool, $args) {
    Mojo::Promise->resolve->then(sub { die "late\n" });
  }
);
$server->tool(name => 'fine', code => sub ($tool, $args) {'still here'});
$server->tool(
  name         => 'bad_dialect',
  input_schema => {'$schema' => 'https://example.com/nope', type => 'object'},
  code         => sub ($tool, $args) {'unreachable'}
);
$server->prompt(name => 'boom', code => sub ($prompt, $args) { die "prompt kaboom\n" });
$server->resource(uri => 'file:///boom', name => 'boom', code => sub ($resource) { die "resource kaboom\n" });

$server->on(
  tools => sub ($server, $tools, $context) { die "hook kaboom\n" if $context->client_info->{name} eq 'Boom' });

app->log->level('fatal');
any '/mcp' => $server->to_action;

my $t      = Test::Mojo->new;
my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));

subtest 'Tool exceptions' => sub {
  eval { $client->call_tool('boom') };
  like $@, qr/^Error -32603: Internal error/, 'internal error';

  eval { $client->call_tool('boom_async') };
  like $@, qr/^Error -32603: Internal error/, 'rejected promise';

  eval { $client->call_tool('boom_late') };
  like $@, qr/^Error -32603: Internal error/, 'exception in a promise';
};

subtest 'Exceptions outside the primitive' => sub {
  eval { $client->call_tool('bad_dialect') };
  like $@, qr/^Error -32603: Internal error/, 'unsupported schema dialect';

  my $boom = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'), name => 'Boom');
  eval { $boom->list_tools };
  like $@, qr/^Error -32603: Internal error/, 'dying event handler';

  is scalar @{$client->list_tools->{tools}}, 5, 'other callers are unaffected';
};

subtest 'Prompt and resource exceptions' => sub {
  eval { $client->get_prompt('boom') };
  like $@, qr/^Error -32603: Internal error/, 'prompt internal error';

  eval { $client->read_resource('file:///boom') };
  like $@, qr/^Error -32603: Internal error/, 'resource internal error';
};

subtest 'Nothing is leaked' => sub {
  my $meta = {META_PROTOCOL_VERSION() => PROTOCOL_VERSION, 'io.modelcontextprotocol/clientCapabilities' => {}};
  my $request
    = {jsonrpc => '2.0', id => 1, method => 'tools/call', params => {name => 'boom', arguments => {}, _meta => $meta}};
  my $headers = {'MCP-Protocol-Version' => PROTOCOL_VERSION, 'Mcp-Method' => 'tools/call', 'Mcp-Name' => 'boom'};

  $t->post_ok('/mcp' => $headers => json => $request)
    ->status_is(500)
    ->json_is('/error/code'    => INTERNAL_ERROR)
    ->json_is('/error/message' => 'Internal error')
    ->json_hasnt('/error/data')
    ->content_unlike(qr/kaboom|secret/);
};

subtest 'Server survives' => sub {
  is $client->call_tool('fine')->{content}[0]{text}, 'still here', 'still serving requests';
};

subtest 'Exceptions go to the application log' => sub {
  is $server->log, app->log, 'application log adopted';

  my $messages = app->log->capture('error');
  eval { $client->call_tool('boom') };
  eval { $client->get_prompt('boom') };
  like $messages,       qr/\[error\].*MCP request failed: kaboom in \/secret\/path\.pm/, 'tool exception logged';
  like $messages->[-1], qr/MCP request failed: prompt kaboom/,                           'prompt exception logged';
  undef $messages;

  $messages = app->log->capture('error');
  is $client->call_tool('fine')->{content}[0]{text}, 'still here', 'tool called';
  is_deeply [@$messages], [], 'nothing logged for a successful call';
  undef $messages;
};

done_testing;
