use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Constants qw(HEADER_MISMATCH INVALID_PARAMS META_CLIENT_CAPABILITIES META_PROTOCOL_VERSION),
  qw(METHOD_NOT_FOUND PROTOCOL_VERSION UNSUPPORTED_PROTOCOL_VERSION);
use MCP::Server;

my $server = MCP::Server->new;

$server->tool(
  name         => 'search',
  input_schema => {
    type       => 'object',
    properties => {
      query  => {type => 'string',           'x-mcp-header' => 'Query'},
      limit  => {type => 'integer',          'x-mcp-header' => 'Limit'},
      pretty => {type => 'boolean',          'x-mcp-header' => 'Pretty'},
      notes  => {type => ['string', 'null'], 'x-mcp-header' => 'Notes'},
      filter => {type => 'object',           properties     => {tag => {type => 'string', 'x-mcp-header' => 'Tag'}}}
    }
  },
  code => sub ($tool, $args) {
    return 'searched';
  }
);
$server->tool(
  name => "Ünicode",
  code => sub ($tool, $args) {
    return 'unicode';
  }
);

any '/mcp' => $server->to_action({origins => ['https://example.com']});

my $t = Test::Mojo->new;

sub call ($name, $args, $headers) {
  my $meta = {META_CLIENT_CAPABILITIES() => {}, META_PROTOCOL_VERSION() => PROTOCOL_VERSION};
  my $body = {
    jsonrpc => '2.0',
    id      => 1,
    method  => 'tools/call',
    params  => {name => $name, arguments => $args, _meta => $meta}
  };
  my %all = ('MCP-Protocol-Version' => PROTOCOL_VERSION, 'Mcp-Method' => 'tools/call', 'Mcp-Name' => $name, %$headers);
  delete @all{grep { !defined $all{$_} } keys %all};
  return $t->post_ok('/mcp' => \%all => json => $body);
}

subtest 'Routing headers' => sub {
  call('search', {}, {})->status_is(200)->json_is('/result/content/0/text' => 'searched');

  my $lower = {'Mcp-Method' => undef, 'Mcp-Name' => undef, 'mcp-method' => 'tools/call', 'mcp-name' => 'search'};
  call('search', {}, $lower)->status_is(200)->json_is('/result/content/0/text' => 'searched');

  call('search', {}, {'Mcp-Method' => undef})
    ->status_is(400)
    ->json_is('/error/code'    => HEADER_MISMATCH)
    ->json_is('/error/message' => 'Missing Mcp-Method header');

  call('search', {}, {'Mcp-Method' => 'tools/list'})
    ->status_is(400)
    ->json_is('/error/message' => 'Mcp-Method header does not match the request body');

  call('search', {}, {'Mcp-Name' => undef})->status_is(400)->json_is('/error/message' => 'Missing Mcp-Name header');

  call('search', {}, {'Mcp-Name' => 'other'})
    ->status_is(400)
    ->json_is('/error/message' => 'Mcp-Name header does not match the request body');
};

subtest 'Protocol version' => sub {
  call('search', {}, {'MCP-Protocol-Version' => undef})
    ->status_is(400)
    ->json_is('/error/code'    => HEADER_MISMATCH)
    ->json_is('/error/message' => 'Missing MCP-Protocol-Version header');

  call('search', {}, {'MCP-Protocol-Version' => '2025-11-25'})
    ->status_is(400)
    ->json_is('/error/message' => 'MCP-Protocol-Version header does not match the request body');
};

subtest 'Base64 sentinel' => sub {
  call("Ünicode", {}, {'Mcp-Name' => '=?base64?w5xuaWNvZGU=?='})
    ->status_is(200)
    ->json_is('/result/content/0/text' => 'unicode');

  call("Ünicode", {}, {'Mcp-Name' => "Ünicode"})
    ->status_is(400)
    ->json_is('/error/message' => 'Invalid Mcp-Name header');

  call('=?base64?x?=', {}, {'Mcp-Name' => '=?base64?PT9iYXNlNjQ/eD89?='})
    ->status_is(200)
    ->json_is('/error/code' => INVALID_PARAMS);

  call('=?base64?x?=', {}, {'Mcp-Name' => '=?base64?x?='})
    ->status_is(400)
    ->json_is('/error/message' => 'Mcp-Name header does not match the request body');
};

subtest 'Parameter headers' => sub {
  my $args = {query => 'perl', limit => 10, pretty => \1, filter => {tag => 'news'}};
  my $all
    = {'Mcp-Param-Query' => 'perl', 'Mcp-Param-Limit' => 10, 'Mcp-Param-Pretty' => 'true', 'Mcp-Param-Tag' => 'news'};
  call('search', $args, $all)->status_is(200)->json_is('/result/content/0/text' => 'searched');

  call('search', $args, {%$all, 'Mcp-Param-Limit' => '10.0'})
    ->status_is(200)
    ->json_is('/result/content/0/text' => 'searched');

  call('search', $args, {%$all, 'Mcp-Param-Limit' => '11'})
    ->status_is(400)
    ->json_is('/error/message' => 'Mcp-Param-Limit header does not match the request body');

  call('search', $args, {%$all, 'Mcp-Param-Tag' => undef})
    ->status_is(400)
    ->json_is('/error/message' => 'Missing Mcp-Param-Tag header');

  call('search', {query => 'perl'}, {'Mcp-Param-Query' => 'perl'})
    ->status_is(200)
    ->json_is('/result/content/0/text' => 'searched');

  call('search', {query => 'perl'}, {'Mcp-Param-Query' => 'perl', 'Mcp-Param-Limit' => 10})
    ->status_is(400)
    ->json_is('/error/message' => 'Unexpected Mcp-Param-Limit header');

  call('search', {notes => undef}, {})->status_is(200)->json_is('/result/content/0/text' => 'searched');

  call('search', {notes => undef}, {'Mcp-Param-Notes' => ''})
    ->status_is(400)
    ->json_is('/error/message' => 'Unexpected Mcp-Param-Notes header');
};

subtest 'Request meta' => sub {
  my $body    = {jsonrpc => '2.0', id => 1, method => 'tools/list', params => {}};
  my $headers = {'MCP-Protocol-Version' => PROTOCOL_VERSION, 'Mcp-Method' => 'tools/list'};
  $t->post_ok('/mcp' => $headers => json => $body)
    ->status_is(400)
    ->json_is('/error/code'    => INVALID_PARAMS)
    ->json_is('/error/message' => 'Missing protocol version');

  $body->{params}{_meta} = {META_PROTOCOL_VERSION() => PROTOCOL_VERSION};
  $t->post_ok('/mcp' => $headers => json => $body)
    ->status_is(400)
    ->json_is('/error/message' => 'Missing client capabilities');

  $body->{params}{_meta} = {META_CLIENT_CAPABILITIES() => {}, META_PROTOCOL_VERSION() => '2025-11-25'};
  $t->post_ok('/mcp' => {%$headers, 'MCP-Protocol-Version' => '2025-11-25'} => json => $body)
    ->status_is(400)
    ->json_is('/error/code'           => UNSUPPORTED_PROTOCOL_VERSION)
    ->json_is('/error/data/supported' => [PROTOCOL_VERSION])
    ->json_is('/error/data/requested' => '2025-11-25');
};

subtest 'Unknown method' => sub {
  my $meta    = {META_CLIENT_CAPABILITIES() => {}, META_PROTOCOL_VERSION() => PROTOCOL_VERSION};
  my $body    = {jsonrpc => '2.0', id => 1, method => 'ping', params => {_meta => $meta}};
  my $headers = {'MCP-Protocol-Version' => PROTOCOL_VERSION, 'Mcp-Method' => 'ping'};
  $t->post_ok('/mcp' => $headers => json => $body)->status_is(404)->json_is('/error/code' => METHOD_NOT_FOUND);
};

subtest 'Notifications' => sub {
  my $body = {jsonrpc => '2.0', method => 'notifications/cancelled', params => {requestId => 1}};
  $t->post_ok('/mcp' => json => $body)->status_is(202)->content_is('');
};

subtest 'Origin' => sub {
  my $meta    = {META_CLIENT_CAPABILITIES() => {}, META_PROTOCOL_VERSION() => PROTOCOL_VERSION};
  my $body    = {jsonrpc => '2.0', id => 1, method => 'tools/list', params => {_meta => $meta}};
  my $headers = {'MCP-Protocol-Version' => PROTOCOL_VERSION, 'Mcp-Method' => 'tools/list'};
  $t->post_ok('/mcp' => {%$headers, Origin => 'https://example.com'} => json => $body)->status_is(200);
  $t->post_ok('/mcp' => {%$headers, Origin => 'https://evil.com'}    => json => $body)
    ->status_is(403)
    ->json_is('/error' => 'Origin not allowed');
};

subtest 'Invalid JSON' => sub {
  $t->post_ok('/mcp' => {'Content-Type' => 'application/json'} => 'not json')
    ->status_is(400)
    ->json_is('/error' => 'Invalid JSON');
};

done_testing;
