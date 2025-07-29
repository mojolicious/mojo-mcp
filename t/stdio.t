use Mojo::Base -strict;

use Test::More;

BEGIN {
  plan skip_all => 'set TEST_STDIO to enable this test (developer only!)' unless $ENV{TEST_STDIO} || $ENV{TEST_ALL};
}

use Mojo::File qw(curfile);
use Mojo::JSON qw(false);
use lib curfile->dirname->child('lib')->to_string;
use MCPStdioTest;

my $test = MCPStdioTest->new;
$test->run('perl', curfile->dirname->child('apps', 'stdio.pl')->to_string);

subtest 'Initialization' => sub {
  my $res = $test->request(initialize =>
      {capabilities => {}, clientInfo => {name => 'mojo-mcp', version => '1.0.0'}, protocolVersion => '2025-06-18'});
  is $res->{jsonrpc},                     '2.0',        'JSON-RPC version';
  is $res->{id},                          1,            'request id';
  is $res->{result}{protocolVersion},     '2025-06-18', 'protocol version';
  is $res->{result}{serverInfo}{name},    'MojoServer', 'server name';
  is $res->{result}{serverInfo}{version}, '1.0.0',      'server version';
  ok $res->{result}{capabilities}, 'has capabilities';

  ok $test->notify('notifications/initialized', {}), 'initialized';
};

subtest 'List tools' => sub {
  my $res = $test->request('tools/list', {});
  is $res->{jsonrpc},                             '2.0',                 'JSON-RPC version';
  is $res->{id},                                  2,                     'request id';
  is $res->{result}{tools}[0]{name},              'echo',                'tool name';
  is $res->{result}{tools}[0]{description},       'Echo the input text', 'tool description';
  is $res->{result}{tools}[0]{inputSchema}{type}, 'object',              'input schema type';

  ok $test->notify('notifications/cancelled', {requestId => 2, reason => 'AbortError: This operation was aborted'}),
    'cancelled';
};

subtest 'Tool call' => sub {
  my $res = $test->request('tools/call', {name => 'echo', arguments => {test => 'hello mojo'}});
  is $res->{jsonrpc}, '2.0', 'JSON-RPC version';
  is $res->{id},      3,     'request id';
  is_deeply $res->{result}, {content => [{text => 'Echo: hello mojo', type => 'text'}], isError => false},
    'tool call result';
};

ok $test->stop, 'process stopped';

done_testing;
