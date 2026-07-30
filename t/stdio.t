use Mojo::Base -strict;

use Test::More;

BEGIN {
  plan skip_all => 'set TEST_STDIO to enable this test (developer only!)' unless $ENV{TEST_STDIO} || $ENV{TEST_ALL};
}

use MCP::Constants qw(INTERNAL_ERROR META_LOG_LEVEL META_SERVER_INFO META_SUBSCRIPTION_ID PROTOCOL_VERSION);
use Mojo::File     qw(curfile);
use Mojo::JSON     qw(false true);
use lib curfile->dirname->child('lib')->to_string;
use MCPStdioTest;

my $test = MCPStdioTest->new;
$test->run($^X, curfile->dirname->child('apps', 'stdio.pl')->to_string);

subtest 'Discovery' => sub {
  my $res = $test->request('server/discover', {});
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      1,     'request id';
  is_deeply $res->{result}{supportedVersions}, [PROTOCOL_VERSION], 'supported versions';
  is_deeply $res->{result}{capabilities}{extensions}, {}, 'no extensions';
  is $res->{result}{capabilities}{tools}{listChanged},  true,         'tools listChanged';
  is $res->{result}{capabilities}{prompts},             undef,        'no prompts capability';
  is $res->{result}{capabilities}{resources},           undef,        'no resources capability';
  is $res->{result}{instructions},                      undef,        'no instructions';
  is $res->{result}{resultType},                        'complete',   'result type';
  is $res->{result}{cacheScope},                        'public',     'cache scope';
  is $res->{result}{ttlMs},                             0,            'cache ttl';
  is $res->{result}{_meta}{+META_SERVER_INFO}{name},    'PerlServer', 'server name';
  is $res->{result}{_meta}{+META_SERVER_INFO}{version}, '1.0.0',      'server version';
};

subtest 'Unsupported protocol version' => sub {
  my $req = $test->client->build_request('tools/list', {});
  $req->{params}{_meta}{'io.modelcontextprotocol/protocolVersion'} = '2025-11-25';
  my $res = $test->send($req);
  is $res->{id},                      2,           'request id';
  is $res->{error}{code},            -32022,       'error code';
  is $res->{error}{data}{requested}, '2025-11-25', 'requested version';
  is_deeply $res->{error}{data}{supported}, [PROTOCOL_VERSION], 'supported versions';
};

subtest 'Missing client capabilities' => sub {
  my $req = $test->client->build_request('tools/list', {});
  delete $req->{params}{_meta}{'io.modelcontextprotocol/clientCapabilities'};
  my $res = $test->send($req);
  is $res->{id},           3,     'request id';
  is $res->{error}{code}, -32602, 'error code';
};

subtest 'Unknown method' => sub {
  my $res = $test->request('ping', {});
  is $res->{id},           4,     'request id';
  is $res->{error}{code}, -32601, 'error code';
};

subtest 'List tools' => sub {
  my $res = $test->request('tools/list', {});
  is $res->{jsonrpc},                             '2.0',                 'JSON-RPC version';
  is $res->{id},                                  5,                     'request id';
  is $res->{result}{tools}[0]{name},              'echo',                'tool name';
  is $res->{result}{tools}[0]{description},       'Echo the input text', 'tool description';
  is $res->{result}{tools}[0]{inputSchema}{type}, 'object',              'input schema type';
  is $res->{result}{cacheScope},                  'private',             'cache scope';
  is $res->{result}{ttlMs},                       0,                     'cache ttl';

  ok $test->notify('notifications/cancelled', {requestId => 5, reason => 'AbortError: This operation was aborted'}),
    'cancelled';
};

subtest 'Tool call' => sub {
  my $res = $test->request('tools/call', {name => 'echo', arguments => {msg => 'hello mojo'}});
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      6,     'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hello mojo', type => 'text'}], 'tool call result';
  is $res->{result}{isError},    false,      'not an error';
  is $res->{result}{resultType}, 'complete', 'result type';
  is_deeply $res->{result}{_meta}{+META_SERVER_INFO}, {name => 'PerlServer', version => '1.0.0'}, 'server info';
};

subtest 'Unknown tool' => sub {
  my $res = $test->request('tools/call', {name => 'nope', arguments => {}});
  is $res->{id},              7,                      'request id';
  is $res->{error}{code},    -32602,                  'error code';
  is $res->{error}{message}, "Tool 'nope' not found", 'error message';
};

subtest 'Tool call (async)' => sub {
  my $res = $test->request('tools/call', {name => 'echo_async', arguments => {msg => 'hello mojo'}});
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      8,     'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo (async): hello mojo', type => 'text'}], 'tool call result';
};

subtest 'Unicode' => sub {
  my $res = $test->request('tools/call', {name => 'echo', arguments => {msg => 'i ♥ mcp'}});
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      9,     'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: i ♥ mcp', type => 'text'}], 'tool call result';
};

subtest 'Tool call (log level not requested)' => sub {
  my $res = $test->request('tools/call', {name => 'echo_log', arguments => {msg => 'hi'}});
  is $res->{id}, 10, 'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hi', type => 'text'}], 'tool call result';
};

subtest 'Tool call (with notification)' => sub {
  $test->send_request('tools/call',
    {name => 'echo_log', arguments => {msg => 'hi'}, _meta => {META_LOG_LEVEL() => 'info'}});
  my $notif = $test->read_line;
  is $notif->{jsonrpc},       '2.0',                   'JSON-RPC version';
  is $notif->{id},            undef,                   'no request id';
  is $notif->{method},        'notifications/message', 'notification method';
  is $notif->{params}{level}, 'info',                  'notification level';
  is $notif->{params}{data},  'hi',                    'notification payload';
  my $res = $test->read_line;
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      11,    'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hi', type => 'text'}], 'tool call result';
};

subtest 'Subscription' => sub {
  $test->send_request('subscriptions/listen',
    {notifications => {promptsListChanged => true, toolsListChanged => true}});
  my $ack = $test->read_line;
  is $ack->{jsonrpc},                              '2.0',                                      'JSON-RPC version';
  is $ack->{method},                               'notifications/subscriptions/acknowledged', 'notification method';
  is $ack->{params}{_meta}{+META_SUBSCRIPTION_ID}, 12,                                         'subscription id';
  is_deeply $ack->{params}{notifications}, {promptsListChanged => true, toolsListChanged => true}, 'honoured filter';

  $test->send_request('tools/call', {name => 'reload', arguments => {}});
  my $notif = $test->read_line;
  is $notif->{id},                                   undef,                              'no request id';
  is $notif->{method},                               'notifications/tools/list_changed', 'notification method';
  is $notif->{params}{_meta}{+META_SUBSCRIPTION_ID}, 12,                                 'subscription id';
  my $res = $test->read_line;
  is $res->{id}, 13, 'request id';
  is_deeply $res->{result}{content}, [{text => 'reloaded', type => 'text'}], 'tool call result';
};

subtest 'Subscription (cancelled)' => sub {
  ok $test->notify('notifications/cancelled', {requestId => 12}), 'cancelled';
  my $res = $test->request('tools/call', {name => 'reload', arguments => {}});
  is $res->{id}, 14, 'request id';
  is_deeply $res->{result}{content}, [{text => 'reloaded', type => 'text'}], 'tool call result';
};

subtest 'Tool call (with progress)' => sub {
  $test->send_request('tools/call',
    {name => 'echo_progress', arguments => {msg => 'hi'}, _meta => {progressToken => 'p1'}});
  my $notif = $test->read_line;
  is $notif->{jsonrpc},               '2.0',                    'JSON-RPC version';
  is $notif->{id},                    undef,                    'no request id';
  is $notif->{method},                'notifications/progress', 'notification method';
  is $notif->{params}{progressToken}, 'p1',                     'progress token echoed';
  is $notif->{params}{progress},      0.5,                      'progress value';
  is $notif->{params}{total},         1,                        'total value';
  is $notif->{params}{message},       'half',                   'progress message';
  my $res = $test->read_line;
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      15,    'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hi', type => 'text'}], 'tool call result';
};

subtest 'Scoped tool (no scope enforcement over stdio)' => sub {
  my $res = $test->request('tools/call', {name => 'echo_scoped', arguments => {msg => 'hi'}});
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      16,    'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hi', type => 'text'}], 'tool call result';
};

subtest 'Tool call (CRLF line endings)' => sub {
  $test->send_request_crlf('tools/call', {name => 'echo', arguments => {msg => 'hello mojo'}});
  my $res = $test->read_line;
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      17,    'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hello mojo', type => 'text'}], 'tool call result';
};

subtest 'Tool call (exception)' => sub {
  my $res = $test->request('tools/call', {name => 'boom', arguments => {}});
  is $res->{jsonrpc},        '2.0',            'JSON-RPC version';
  is $res->{id},             18,               'request id';
  is $res->{error}{code},    INTERNAL_ERROR,   'internal error';
  is $res->{error}{message}, 'Internal error', 'error message';
  unlike $res->{error}{message}, qr/kaboom/, 'exception is not leaked';

  $res = $test->request('tools/call', {name => 'echo', arguments => {msg => 'hi'}});
  is $res->{id}, 19, 'request id';
  is_deeply $res->{result}{content}, [{text => 'Echo: hi', type => 'text'}], 'server survived';
};

ok $test->stop, 'process stopped';

done_testing;
