use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Client;
use MCP::Server;
use Mojo::JSON qw(true);

my $deploy = sub ($tool, $args) {
  my $context = $tool->context;
  my $state   = $context->request_state;
  my $confirm = ($context->input_responses // {})->{confirm} // {};
  return $tool->text_result("Deployed $state->{target}") if $state && ($confirm->{action} // '') eq 'accept';
  return $tool->input_required(
    {
      confirm => {
        method => 'elicitation/create',
        params => {
          message         => "Really deploy to $args->{target}?",
          requestedSchema => {type => 'object', properties => {ok => {type => 'boolean'}}}
        }
      }
    },
    {target => $args->{target}}
  );
};
my $schema = {type => 'object', properties => {target => {type => 'string'}}, required => ['target']};

my $server = MCP::Server->new(state_secret => 'test-secret');
$server->tool(name => 'deploy', input_schema => $schema, code => $deploy);
$server->tool(
  name => 'steal',
  code => sub ($tool, $args) {
    my $state = $tool->context->request_state;
    return $tool->text_result($state ? "Stolen $state->{target}" : 'No state');
  }
);
$server->prompt(
  name => 'plan',
  code => sub ($prompt, $args) {
    return $prompt->text_prompt('Ready to deploy') if $prompt->context->request_state;
    return $prompt->input_required(undef, {asked => 1});
  }
);
$server->resource(
  uri       => 'file:///report',
  cache_ttl => 60_000,
  code      => sub ($resource) {
    return 'Deployment report';
  }
);

my $expired = MCP::Server->new(state_secret => 'test-secret', state_timeout => -1);
$expired->tool(name => 'deploy', input_schema => $schema, code => $deploy);

any '/mcp' => $server->to_action({
  auth => sub ($c) {
    return undef unless ($c->req->headers->authorization // '') =~ /^Bearer\s+(\S+)$/;
    return {principal => $1};
  }
});
any '/expired' => $expired->to_action;

my $t      = Test::Mojo->new;
my $client = MCP::Client->new(
  ua      => $t->ua,
  url     => $t->ua->server->url->path('/mcp'),
  headers => {Authorization => 'Bearer alice'}
);

my $state;

subtest 'Input required' => sub {
  my $result = $client->call_tool('deploy', {target => 'prod'});
  is $result->{resultType},                              'input_required',         'result type';
  is $result->{inputRequests}{confirm}{method},          'elicitation/create',     'input request method';
  is $result->{inputRequests}{confirm}{params}{message}, 'Really deploy to prod?', 'input request message';
  is $result->{content},                                 undef,                    'no content';
  is $result->{ttlMs},                                   undef,                    'no cache ttl';
  is $result->{cacheScope},                              undef,                    'no cache scope';
  ok $state = $result->{requestState}, 'request state';
};

subtest 'Retry' => sub {
  my $responses = {confirm => {action => 'accept', content => {ok => true}}};
  my $result
    = $client->call_tool('deploy', {target => 'prod'}, {input_responses => $responses, request_state => $state});
  is $result->{resultType}, 'complete', 'result type';
  is_deeply $result->{content}, [{text => 'Deployed prod', type => 'text'}], 'tool call result';
};

subtest 'Retry (no input responses)' => sub {
  my $result = $client->call_tool('deploy', {target => 'prod'}, {request_state => $state});
  is $result->{resultType}, 'input_required', 'asked again';
};

subtest 'Tampered state' => sub {
  my $tampered = $state;
  substr $tampered, 0, 1, 'X';
  my $responses = {confirm => {action => 'accept', content => {ok => true}}};
  my $result
    = $client->call_tool('deploy', {target => 'prod'}, {input_responses => $responses, request_state => $tampered});
  is $result->{resultType}, 'input_required', 'asked again';
};

subtest 'State from another tool' => sub {
  my $result = $client->call_tool('steal', {}, {request_state => $state});
  is_deeply $result->{content}, [{text => 'No state', type => 'text'}], 'tool call result';
};

subtest 'State from another principal' => sub {
  my $bob = MCP::Client->new(
    ua      => $t->ua,
    url     => $t->ua->server->url->path('/mcp'),
    headers => {Authorization => 'Bearer bob'}
  );
  my $responses = {confirm => {action => 'accept', content => {ok => true}}};
  my $result = $bob->call_tool('deploy', {target => 'prod'}, {input_responses => $responses, request_state => $state});
  is $result->{resultType}, 'input_required', 'asked again';
};

subtest 'Expired state' => sub {
  my $stale = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/expired'));
  my $first = $stale->call_tool('deploy', {target => 'prod'});
  is $first->{resultType}, 'input_required', 'result type';

  my $responses = {confirm => {action => 'accept', content => {ok => true}}};
  my $result    = $stale->call_tool(
    'deploy',
    {target          => 'prod'},
    {input_responses => $responses, request_state => $first->{requestState}}
  );
  is $result->{resultType}, 'input_required', 'asked again';
};

subtest 'Prompt' => sub {
  my $result = $client->get_prompt('plan');
  is $result->{resultType},    'input_required', 'result type';
  is $result->{inputRequests}, undef,            'no input requests';
  ok $result->{requestState}, 'request state';

  my $retry = $client->get_prompt('plan', {}, {request_state => $result->{requestState}});
  is $retry->{resultType},                 'complete',        'result type';
  is $retry->{messages}[0]{content}{text}, 'Ready to deploy', 'prompt result';
};

subtest 'Resource cache hints' => sub {
  my $result = $client->read_resource('file:///report');
  is $result->{ttlMs},      60_000,   'cache ttl';
  is $result->{cacheScope}, 'public', 'cache scope';

  my $retry = $client->read_resource('file:///report', {request_state => $state});
  is $retry->{ttlMs},      undef, 'no cache ttl';
  is $retry->{cacheScope}, undef, 'no cache scope';
};

done_testing;
