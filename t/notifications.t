use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Client;
use MCP::Constants qw(META_LOG_LEVEL METHOD_NOT_FOUND);
use MCP::Server;
use Mojo::IOLoop;
use Mojo::Promise;

my $server = MCP::Server->new;

$server->tool(
  name => 'progress',
  code => sub ($tool, $args) {
    my $sent = $tool->context->notify_progress(1, 2, 'halfway');
    return $sent ? 'sent' : 'no token';
  }
);
$server->tool(
  name => 'async_progress',
  code => sub ($tool, $args) {
    my $context = $tool->context;
    my $promise = Mojo::Promise->new;
    Mojo::IOLoop->timer(
      0.1 => sub {
        $context->notify_progress(2, 2, 'late');
        $promise->resolve('done');
      }
    );
    return $promise;
  }
);
$server->tool(
  name => 'log',
  code => sub ($tool, $args) {
    my $context = $tool->context;
    my @sent    = map { $context->notify_log($_, "$_ message") ? 1 : 0 } qw(debug warning);
    return join ',', @sent;
  }
);

any '/mcp' => $server->to_action;

my $t      = Test::Mojo->new;
my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));

my @notifications;
$client->on(notification => sub ($client, $notification) { push @notifications, $notification });

subtest 'Progress' => sub {
  my $request
    = $client->build_request('tools/call', {name => 'progress', arguments => {}, _meta => {progressToken => 'tok-1'}});
  my $result = $client->send_request($request)->{result};
  is $result->{content}[0]{text}, 'sent', 'tool call result';

  my $progress = shift @notifications;
  is $progress->{jsonrpc},               '2.0',                    'JSON-RPC version';
  is $progress->{method},                'notifications/progress', 'notification method';
  is $progress->{params}{progressToken}, 'tok-1',                  'progress token echoed';
  is $progress->{params}{progress},      1,                        'progress value';
  is $progress->{params}{total},         2,                        'total value';
  is $progress->{params}{message},       'halfway',                'progress message';
  is scalar @notifications,              0,                        'no more notifications';
};

subtest 'Progress (async)' => sub {
  my $request = $client->build_request('tools/call',
    {name => 'async_progress', arguments => {}, _meta => {progressToken => 'tok-2'}});
  my $result = $client->send_request($request)->{result};
  is $result->{content}[0]{text}, 'done', 'tool call result';

  my $progress = shift @notifications;
  is $progress->{method},                'notifications/progress', 'notification method';
  is $progress->{params}{progressToken}, 'tok-2',                  'progress token echoed';
  is $progress->{params}{message},       'late',                   'progress message';
  is scalar @notifications,              0,                        'no more notifications';
};

subtest 'Progress (no token)' => sub {
  is $client->call_tool('progress')->{content}[0]{text}, 'no token', 'notify_progress declines without a token';
  is scalar @notifications,                              0,          'no notifications';
};

subtest 'Logging' => sub {
  my $request
    = $client->build_request('tools/call', {name => 'log', arguments => {}, _meta => {META_LOG_LEVEL() => 'info'}});
  my $result = $client->send_request($request)->{result};
  is $result->{content}[0]{text}, '0,1', 'levels below the minimum are declined';

  my $message = shift @notifications;
  is $message->{method},        'notifications/message', 'notification method';
  is $message->{params}{level}, 'warning',               'notification level';
  is $message->{params}{data},  'warning message',       'notification payload';
  is scalar @notifications,     0,                       'no more notifications';
};

subtest 'Logging (no level)' => sub {
  is $client->call_tool('log')->{content}[0]{text}, '0,0', 'nothing is logged unless the client asks';
  is scalar @notifications,                         0,     'no notifications';
};

subtest 'Subscriptions without streaming' => sub {
  is $server->notify_list_changed('tools'), undef, 'no broadcast without streaming';

  my $request  = $client->build_request('subscriptions/listen', {notifications => {toolsListChanged => 1}});
  my $response = $client->send_request($request);
  is $response->{error}{code}, METHOD_NOT_FOUND, 'method not found';
};

done_testing;
