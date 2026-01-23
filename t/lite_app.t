use Mojo::Base -strict, -signatures;

use Test::More;

use Test::Mojo;
use Mojo::ByteStream qw(b);
use Mojo::File       qw(curfile);
use Mojo::JSON       qw(from_json true false);
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
    ok $result->{capabilities},            'has capabilities';
    ok $result->{capabilities}{prompts},   'has prompts capability';
    ok $result->{capabilities}{resources}, 'has resources capability';
    ok $result->{capabilities}{tools},     'has tools capability';
    ok $client->session_id,                'session id set';
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
    ok !exists($result->{tools}[0]{outputSchema}), 'no output schema';
    is_deeply $result->{tools}[0]{annotations}, {title => 'echo'}, 'corrent number of annotations';
    is $result->{tools}[1]{name},        'echo_async',                         'tool name';
    is $result->{tools}[1]{description}, 'Echo the input text asynchronously', 'tool description';
    is_deeply $result->{tools}[1]{inputSchema},
      {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']}, 'tool input schema';
    ok !exists($result->{tools}[1]{outputSchema}), 'no output schema';
    is keys %{$result->{tools}[1]{annotations}}, 0,             'empty annotations not serialized';
    is $result->{tools}[2]{name},                'echo_header', 'tool name';
    is $result->{tools}[2]{description},         'Echo the input text with a header', 'tool description';
    is_deeply $result->{tools}[2]{inputSchema},
      {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']}, 'tool input schema';
    ok !exists($result->{tools}[2]{outputSchema}), 'no output schema';
    is $result->{tools}[3]{name},        'time',                                 'tool name';
    is $result->{tools}[3]{description}, 'Get the current time in epoch format', 'tool description';
    is_deeply $result->{tools}[3]{inputSchema}, {type => 'object'}, 'tool input schema';
    ok !exists($result->{tools}[3]{outputSchema}), 'no output schema';
    is $result->{tools}[4]{name},        'generate_image',                    'tool name';
    is $result->{tools}[4]{description}, 'Generate a simple image from text', 'tool description';
    is_deeply $result->{tools}[4]{inputSchema},
      {type => 'object', properties => {text => {type => 'string'}}, required => ['text']}, 'tool input schema';
    ok !exists($result->{tools}[4]{outputSchema}), 'no output schema';
    is $result->{tools}[5]{name},        'generate_audio',           'tool name';
    is $result->{tools}[5]{description}, 'Generate audio from text', 'tool description';
    is_deeply $result->{tools}[5]{inputSchema},
      {type => 'object', properties => {text => {type => 'string'}}, required => ['text']}, 'tool input schema';
    ok !exists($result->{tools}[5]{outputSchema}), 'no output schema';
    is $result->{tools}[6]{name},        'find_resource',                      'tool name';
    is $result->{tools}[6]{description}, 'Find a resource for the given text', 'tool description';
    is_deeply $result->{tools}[6]{inputSchema},
      {type => 'object', properties => {text => {type => 'string'}}, required => ['text']}, 'tool input schema';
    ok !exists($result->{tools}[6]{outputSchema}), 'no output schema';
    ok exists($result->{tools}[6]{annotations}),   'has annotations';
    is keys %{$result->{tools}[6]{annotations}},       5,                 'all annotations are serialized';
    is $result->{tools}[6]{annotations}{readOnlyHint}, true,              'annotation has correct value';
    is $result->{tools}[7]{name},                      'current_weather', 'tool name';
    is $result->{tools}[7]{description},               'Get current weather data for a location', 'tool description';
    my $input_schema = {
      type       => 'object',
      properties => {location => {type => 'string', description => 'City name or zip code'}},
      required   => ['location']
    };
    is_deeply $result->{tools}[7]{inputSchema}, $input_schema, 'tool input schema';
    my $output_schema = {
      type       => 'object',
      properties => {
        temperature => {type => 'number', description => 'Temperature in celsius'},
        conditions  => {type => 'string', description => 'Weather conditions description'},
        humidity    => {type => 'number', description => 'Humidity percentage'}
      },
      required => ['temperature', 'conditions', 'humidity']
    };
    is_deeply $result->{tools}[7]{outputSchema}, $output_schema, 'tool output schema';
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

  subtest 'Tool call (Unicode and async)' => sub {
    my $result = $client->call_tool('echo_async', {msg => 'i ♥ mcp'});
    is $result->{content}[0]{text}, 'Echo (async): i ♥ mcp', 'tool call result';
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

  subtest 'Tool call (image)' => sub {
    my $result = $client->call_tool('generate_image', {text => 'a cat?'});
    is $result->{content}[0]{mimeType}, 'image/png', 'tool call image type';
    is b($result->{content}[0]{data})->b64_decode->md5_sum, 'f55ea29e32455f6314ecc8b5c9f0590b',
      'tool call image result';
    is_deeply $result->{content}[0]{annotations}, {audience => ['user']}, 'tool call image annotations';
  };

  subtest 'Tool call (audio)' => sub {
    my $result = $client->call_tool('generate_audio', {text => 'a cat?'});
    is $result->{content}[0]{mimeType}, 'audio/wav', 'tool call audio type';
    is b($result->{content}[0]{data})->b64_decode->md5_sum, 'e5de045688efc9777361ee3f7d47551d',
      'tool call audio result';
  };

  subtest 'Tool call (resource link)' => sub {
    my $result = $client->call_tool('find_resource', {text => 'a cat?'});
    is $result->{content}[0]{uri},         'file:///path/to/resource.txt', 'tool call resource uri';
    is $result->{content}[0]{name},        'sample',                       'tool call resource name';
    is $result->{content}[0]{description}, 'An example resource',          'tool call resource description';
    is $result->{content}[0]{mimeType},    'text/plain',                   'tool call resource mime type';
  };

  subtest 'Tool call (structured)' => sub {
    my $result = $client->call_tool('current_weather', {location => 'Bremen'});
    my $json   = from_json($result->{content}[0]{text});
    is $json->{temperature}, 22,              'temperature';
    is $json->{conditions},  'Partly cloudy', 'conditions';
    is $json->{humidity},    65,              'humidity';
    is_deeply $result->{structuredContent}, $json, 'structured content';

    my $result2 = $client->call_tool('current_weather', {location => 'Whatever'});
    my $json2   = from_json($result2->{content}[0]{text});
    is $json2->{temperature}, 19,        'temperature';
    is $json2->{conditions},  'Raining', 'conditions';
    is $json2->{humidity},    80,        'humidity';
    is_deeply $result2->{structuredContent}, $json2, 'structured content';
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

  subtest 'List prompts' => sub {
    my $result = $client->list_prompts;
    is $result->{prompts}[0]{name},        'time',                   'prompt name';
    is $result->{prompts}[0]{description}, 'Tell the user the time', 'prompt description';
    is_deeply $result->{prompts}[0]{arguments}, [], 'no prompt arguments';
    is $result->{prompts}[1]{name},        'prompt_echo_async',                 'prompt name';
    is $result->{prompts}[1]{description}, 'Make a prompt from the input text', 'prompt description';
    is_deeply $result->{prompts}[1]{arguments}, [{name => 'msg', description => 'Message to echo', required => 1}],
      'prompt arguments';
    is $result->{prompts}[2]{name},        'prompt_echo_header',                              'prompt name';
    is $result->{prompts}[2]{description}, 'Make a prompt from the input text with a header', 'prompt description';
    is_deeply $result->{prompts}[2]{arguments}, [{name => 'msg', description => 'Message to echo', required => 1}],
      'prompt arguments';
    is $result->{prompts}[3], undef, 'no more prompts';
  };

  subtest 'Get prompt' => sub {
    my $result = $client->get_prompt('time');
    is $result->{messages}[0]{role},          'user',                           'prompt role';
    is $result->{messages}[0]{content}{text}, 'Tell the user the current time', 'prompt result';
  };

  subtest 'Get prompt (async)' => sub {
    my $result = $client->get_prompt('prompt_echo_async', {msg => 'hello mojo'});
    is $result->{messages}[0]{role},          'user',                              'prompt role';
    is $result->{messages}[0]{content}{text}, 'Tell the user (async): hello mojo', 'prompt result';
  };

  subtest 'Get prompt (Unicode)' => sub {
    my $result = $client->get_prompt('prompt_echo_async', {msg => 'i ♥ mcp'});
    is $result->{messages}[0]{role},          'user',                           'prompt role';
    is $result->{messages}[0]{content}{text}, 'Tell the user (async): i ♥ mcp', 'prompt result';
  };

  subtest 'Get prompt (with HTTP header)' => sub {
    $client->ua->once(
      start => sub ($ua, $tx) {
        $tx->req->headers->header('MCP-Custom-Header' => 'TestHeaderWorks');
      }
    );
    my $result = $client->get_prompt('prompt_echo_header', {msg => 'hello mojo'});
    is $result->{description},       'Echoed message with header', 'prompt description';
    is $result->{messages}[0]{role}, 'assistant',                  'prompt role';
    is $result->{messages}[0]{content}{text}, 'Prompt with header: hello mojo (Header: TestHeaderWorks)',
      'prompt result';
  };

  subtest 'Invalid prompt name' => sub {
    eval { $client->get_prompt('unknownPrompt', {}) };
    like $@, qr/Error -32601: Prompt 'unknownPrompt' not found/, 'right error';
  };

  subtest 'Invalid prompt arguments' => sub {
    eval { $client->get_prompt('prompt_echo_async', {just => 'a test'}) };
    like $@, qr/Error -32602: Invalid arguments/, 'right error';
  };

  subtest 'List resources' => sub {
    my $result = $client->list_resources;
    is $result->{resources}[0]{name},        'static_text',                   'resource name';
    is $result->{resources}[0]{description}, 'A static text resource',        'resource description';
    is $result->{resources}[0]{uri},         'file:///path/to/static.txt',    'resource uri';
    is $result->{resources}[0]{mimeType},    'text/plain',                    'resource mime type';
    is $result->{resources}[1]{name},        'static_image',                  'resource name';
    is $result->{resources}[1]{description}, 'A static image resource',       'resource description';
    is $result->{resources}[1]{uri},         'file:///path/to/image.png',     'resource uri';
    is $result->{resources}[1]{mimeType},    'image/png',                     'resource mime type';
    is $result->{resources}[2]{name},        'async_text',                    'resource name';
    is $result->{resources}[2]{description}, 'An asynchronous text resource', 'resource description';
    is $result->{resources}[2]{uri},         'file:///path/to/async.txt',     'resource uri';
    is $result->{resources}[2]{mimeType},    'text/plain',                    'resource mime type';
    is $result->{resources}[3],              undef,                           'no more resources';
  };

  subtest 'Read resource (text)' => sub {
    my $result = $client->read_resource('file:///path/to/static.txt');
    is $result->{contents}[0]{uri},      'file:///path/to/static.txt',      'resource uri';
    is $result->{contents}[0]{mimeType}, 'text/plain',                      'resource mime type';
    is $result->{contents}[0]{text},     'This is a static text resource.', 'resource text';
  };

  subtest 'Read resource (image)' => sub {
    my $result = $client->read_resource('file:///path/to/image.png');
    is $result->{contents}[0]{uri},                          'file:///path/to/image.png',        'resource uri';
    is $result->{contents}[0]{mimeType},                     'image/png',                        'resource mime type';
    is b($result->{contents}[0]{blob})->b64_decode->md5_sum, 'f55ea29e32455f6314ecc8b5c9f0590b', 'resource image data';
  };

  subtest 'Read resource (async)' => sub {
    my $result = $client->read_resource('file:///path/to/async.txt');
    is $result->{contents}[0]{uri},      'file:///path/to/async.txt',              'resource uri';
    is $result->{contents}[0]{mimeType}, 'text/plain',                             'resource mime type';
    is $result->{contents}[0]{text},     'This is an asynchronous text resource.', 'resource text';
  };

  subtest 'Invalid resource uri' => sub {
    eval { $client->read_resource('file://whatever') };
    like $@, qr/Error -32002: Resource not found/, 'right error';
  };
};

done_testing;
