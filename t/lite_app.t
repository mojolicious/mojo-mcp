use Mojo::Base -strict, -signatures;

use Test::More;

use Test::Mojo;
use Mojo::File qw(curfile);
use MCP::Client;
use MCP::Constants qw(PROTOCOL_VERSION);

my $t = Test::Mojo->new(curfile->sibling('apps', 'lite_app.pl'));

subtest 'Normal HTTP endpoint' => sub {
  $t->get_ok('/')->status_is(200)->content_like(qr/Hello MCP!/);
};

subtest 'MCP endpoint' => sub {
  $t->get_ok('/mcp')->status_is(405)->content_like(qr/Method not allowed/);

  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));

  subtest 'Initialize session' => sub {
    is $client->session_id, undef, 'no session id';
    my $result = $client->initialize_session;
    is $result->{protocolVersion},     PROTOCOL_VERSION, 'protocol version';
    is $result->{serverInfo}{name},    'PerlServer',     'server name';
    is $result->{serverInfo}{version}, '1.0.0',          'server version';
    ok $result->{capabilities}, 'has capabilities';
    ok $client->session_id,     'session id set';
  };

  subtest 'Ping' => sub {
    my $result = $client->ping;
    is_deeply $result, {}, 'ping response';
  };

  subtest 'List tools' => sub {
    my $result = $client->list_tools;
    is $result->{tools}[0]{name},        'echo',                'tool name';
    is $result->{tools}[0]{description}, 'Echo the input text', 'tool description';
    is_deeply $result->{tools}[0]{inputSchema},
      {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']}, 'tool input schema';
    is $result->{tools}[1]{name},        'echo_async',                         'tool name';
    is $result->{tools}[1]{description}, 'Echo the input text asynchronously', 'tool description';
    is_deeply $result->{tools}[1]{inputSchema},
      {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']}, 'tool input schema';
    is $result->{tools}[2]{name},        'echo_header',                       'tool name';
    is $result->{tools}[2]{description}, 'Echo the input text with a header', 'tool description';
    is_deeply $result->{tools}[2]{inputSchema},
      {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']}, 'tool input schema';
    is $result->{tools}[3]{name},        'time',                                 'tool name';
    is $result->{tools}[3]{description}, 'Get the current time in epoch format', 'tool description';
    is_deeply $result->{tools}[3]{inputSchema}, {type => 'object'}, 'tool input schema';
    is $result->{tools}[4], undef, 'no more tools';
  };

  subtest 'Tool call' => sub {
    my $result = $client->call_tool('echo', {msg => 'hello mojo'});
    is $result->{content}[0]{text}, 'Echo: hello mojo', 'tool call result';
  };

  subtest 'Tool call (async)' => sub {
    my $result = $client->call_tool('echo_async', {msg => 'hello mojo'});
    is $result->{content}[0]{text}, 'Echo (async): hello mojo', 'tool call result';
  };

  subtest 'Tool call (Unicode)' => sub {
    my $result = $client->call_tool('echo', {msg => 'i ♥ mcp'});
    is $result->{content}[0]{text}, 'Echo: i ♥ mcp', 'tool call result';
  };

  subtest 'Tool call (with HTTP header)' => sub {
    $client->ua->once(
      start => sub ($ua, $tx) {
        $tx->req->headers->header('MCP-Custom-Header' => 'TestHeaderWorks');
      }
    );
    my $result = $client->call_tool('echo_header', {msg => 'hello mojo'});
    is $result->{content}[0]{text}, 'Echo with header: hello mojo (Header: TestHeaderWorks)', 'tool call result';
  };

  subtest 'Tool call (no arguments)' => sub {
    my $result = $client->call_tool('time');
    like $result->{content}[0]{text}, qr/^\d+$/, 'tool call result';
  };

  subtest 'Unknown method' => sub {
    my $res = $client->send_request($client->build_request('unknownMethod'));
    is $res->{error}{code},    -32601,                             'error code';
    is $res->{error}{message}, "Method 'unknownMethod' not found", 'error message';
  };

  subtest 'Invalid tool name' => sub {
    eval { $client->call_tool('unknownTool', {}) };
    like $@, qr/Error -32601: Tool 'unknownTool' not found/, 'right error';
  };

  subtest 'Invalid tool arguments' => sub {
    eval { $client->call_tool('echo', {just => 'a test'}) };
    like $@, qr/Error -32602: Invalid arguments/, 'right error';
  };
};

done_testing;
