use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Constants qw(HEADER_MISMATCH META_CLIENT_CAPABILITIES META_PROTOCOL_VERSION METHOD_NOT_FOUND),
  qw(PROTOCOL_VERSION);
use MCP::Server;
use Mojo::File qw(curfile);
use lib curfile->dirname->child('lib')->to_string;
use MCPStdioTest;

my $server = MCP::Server->new(name => 'LegacyServer', version => '2.0.0');
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {"Echo: $args->{msg}"}
);
$server->prompt(
  name      => 'greet',
  arguments => [{name => 'who', required => \1}],
  code      => sub ($prompt, $args) {"Hello $args->{who}"}
);
$server->resource(uri => 'file:///readme', name => 'readme', code => sub ($resource) {'Read me'});

my $minimal = MCP::Server->new(name => 'MinimalServer', version => '1.0.0');
$minimal->tool(name => 'noop', input_schema => {type => 'object'}, code => sub ($tool, $args) {'ok'});

any '/mcp'     => $server->to_action;
any '/minimal' => $minimal->to_action;

my $t = Test::Mojo->new;

sub legacy ($id, $method, $params = {}) {
  my $body = {jsonrpc => '2.0', id => $id, method => $method, params => $params};
  return $t->post_ok('/mcp' => {'MCP-Protocol-Version' => '2025-11-25'} => json => $body);
}

subtest 'Handshake' => sub {
  my $params = {protocolVersion => '2025-11-25', capabilities => {}, clientInfo => {name => 'Old', version => '1'}};
  $t->post_ok('/mcp' => json => {jsonrpc => '2.0', id => 1, method => 'initialize', params => $params})
    ->status_is(200)
    ->json_is('/result/protocolVersion' => '2025-11-25')
    ->json_is('/result/serverInfo/name' => 'LegacyServer')
    ->json_is('/result/capabilities'    => {prompts => {}, resources => {}, tools => {}})
    ->json_hasnt('/result/capabilities/tools/listChanged');

  $t->post_ok('/minimal' => json => {jsonrpc => '2.0', id => 1, method => 'initialize', params => $params})
    ->status_is(200)
    ->json_is('/result/capabilities' => {tools => {}});

  $t->post_ok('/mcp' => json => {jsonrpc => '2.0', method => 'notifications/initialized'})->status_is(202);

  legacy(2, 'ping')->status_is(200)->json_hasnt('/error');
};

subtest 'Tools' => sub {
  legacy(3, 'tools/list')->status_is(200)->json_is('/result/tools/0/name' => 'echo');

  legacy(4, 'tools/call', {name => 'echo', arguments => {msg => 'hi'}})
    ->status_is(200)
    ->json_is('/result/content/0/text' => 'Echo: hi');

  legacy(5, 'tools/call', {name => 'echo', arguments => {}})
    ->status_is(200)
    ->json_is('/error/message' => 'Invalid arguments');
};

subtest 'Prompts and resources' => sub {
  legacy(6, 'prompts/list')->status_is(200)->json_is('/result/prompts/0/name' => 'greet');

  legacy(7, 'prompts/get', {name => 'greet', arguments => {who => 'world'}})
    ->status_is(200)
    ->json_is('/result/messages/0/content/text' => 'Hello world');

  legacy(8, 'resources/list')->status_is(200)->json_is('/result/resources/0/uri' => 'file:///readme');

  legacy(9, 'resources/read', {uri => 'file:///readme'})
    ->status_is(200)
    ->json_is('/result/contents/0/text' => 'Read me');
};

subtest 'No routing headers required' => sub {
  my $body
    = {jsonrpc => '2.0', id => 10, method => 'tools/call', params => {name => 'echo', arguments => {msg => 'x'}}};
  $t->post_ok('/mcp' => {'MCP-Protocol-Version' => '2025-11-25'} => json => $body)
    ->status_is(200)
    ->json_is('/result/content/0/text' => 'Echo: x');
};

subtest 'Older revisions' => sub {
  for my $version ('2024-11-05', '2025-03-26', '2025-06-18') {
    my $params = {protocolVersion => $version, capabilities => {}, clientInfo => {name => 'Old', version => '1'}};
    $t->post_ok('/mcp' => json => {jsonrpc => '2.0', id => 20, method => 'initialize', params => $params})
      ->status_is(200)
      ->json_is('/result/protocolVersion' => $version);
  }

  my $params = {protocolVersion => '1999-01-01', capabilities => {}};
  $t->post_ok('/mcp' => json => {jsonrpc => '2.0', id => 21, method => 'initialize', params => $params})
    ->status_is(200)
    ->json_is('/result/protocolVersion' => '2025-11-25');

  my $body
    = {jsonrpc => '2.0', id => 22, method => 'tools/call', params => {name => 'echo', arguments => {msg => 'y'}}};
  $t->post_ok('/mcp' => json => $body)->status_is(200)->json_is('/result/content/0/text' => 'Echo: y');
};

subtest 'Current clients are unaffected' => sub {
  my $meta = {META_CLIENT_CAPABILITIES() => {}, META_PROTOCOL_VERSION() => PROTOCOL_VERSION};
  my $body = {
    jsonrpc => '2.0',
    id      => 11,
    method  => 'tools/call',
    params  => {name => 'echo', arguments => {msg => 'hi'}, _meta => $meta}
  };

  $t->post_ok('/mcp' => {'MCP-Protocol-Version' => PROTOCOL_VERSION} => json => $body)
    ->status_is(400)
    ->json_is('/error/code'    => HEADER_MISMATCH)
    ->json_is('/error/message' => 'Missing Mcp-Method header');

  my $headers = {'MCP-Protocol-Version' => PROTOCOL_VERSION, 'Mcp-Method' => 'tools/call', 'Mcp-Name' => 'echo'};
  $t->post_ok('/mcp' => $headers => json => $body)->status_is(200)->json_is('/result/content/0/text' => 'Echo: hi');

  $t->post_ok('/mcp' => $headers => json => {%$body, method => 'ping'})->status_is(400);

  $t->post_ok('/mcp' => {%$headers, 'MCP-Protocol-Version' => '2025-11-25'} => json => $body)
    ->status_is(400)
    ->json_is('/error/message' => 'MCP-Protocol-Version header does not match the request body');

  my $discover = {jsonrpc => '2.0', id => 12, method => 'server/discover', params => {_meta => $meta}};
  $t->post_ok(
    '/mcp' => {'MCP-Protocol-Version' => PROTOCOL_VERSION, 'Mcp-Method' => 'server/discover'} => json => $discover)
    ->status_is(200)
    ->json_is('/result/supportedVersions/0' => PROTOCOL_VERSION);
};

subtest 'Stdio' => sub {
  plan skip_all => 'set TEST_STDIO to enable this test (developer only!)' unless $ENV{TEST_STDIO} || $ENV{TEST_ALL};

  my $test = MCPStdioTest->new;
  $test->run($^X, curfile->dirname->child('apps', 'stdio.pl')->to_string);

  my $res = $test->send({jsonrpc => '2.0', id => 1, method => 'initialize', params => {}});
  is $res->{id},                       1,            'request id';
  is $res->{result}{protocolVersion},  '2025-11-25', 'protocol version';
  is $res->{result}{serverInfo}{name}, 'PerlServer', 'server name';

  $res
    = $test->send({
    jsonrpc => '2.0', id => 2, method => 'tools/call', params => {name => 'echo', arguments => {msg => 'hi'}}
    });
  is $res->{id}, 2, 'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hi', type => 'text'}], 'tool call result';

  ok $test->stop, 'process stopped';
};

done_testing;
