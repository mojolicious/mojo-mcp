use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use Mojo::IOLoop;
use Mojo::JSON qw(from_json true);
use Mojo::Promise;
use MCP::Client;
use MCP::Server;

my $server = MCP::Server->new;

$server->tool(
  name => 'push_log',
  code => sub ($tool, $args) {
    $tool->notify('notifications/message', {level => 'info', data => 'hello stream'});
    return 'pushed';
  }
);
$server->tool(
  name => 'notify_status',
  code => sub ($tool, $args) {
    my $sent = $tool->notify('notifications/message', {data => 'x'});
    return $sent ? 'sent' : 'no stream';
  }
);
$server->tool(
  name => 'progress',
  code => sub ($tool, $args) {
    my $sent = $tool->notify_progress(1, 2, 'halfway');
    return $sent ? 'sent' : 'no token';
  }
);

any '/mcp' => $server->to_action({streaming => 1, heartbeat => 0, session_timeout => 0.5});

my $t = Test::Mojo->new;

subtest 'No session' => sub {
  $t->get_ok('/mcp')->status_is(400)->json_is('/error' => 'Missing session ID');
  $t->delete_ok('/mcp')->status_is(400)->json_is('/error' => 'Missing session ID');
};

subtest 'Unknown session' => sub {
  $t->get_ok('/mcp' => {'Mcp-Session-Id' => 'nope'})->status_is(404);
  $t->delete_ok('/mcp' => {'Mcp-Session-Id' => 'nope'})->status_is(404);

  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  eval { $client->session_id('nope'); $client->ping };
  like $@, qr/404 response/, 'POST with unknown session is rejected';
};

subtest 'List changed' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  my $caps   = $client->initialize_session->{capabilities};
  is $caps->{tools}{listChanged},     true, 'tools listChanged advertised';
  is $caps->{prompts}{listChanged},   true, 'prompts listChanged advertised';
  is $caps->{resources}{listChanged}, true, 'resources listChanged advertised';

  my $got_notification = Mojo::Promise->new;
  my $msg;
  my $url = $t->ua->server->url->path('/mcp');
  my $tx  = $t->ua->build_tx(GET => $url => {Accept => 'text/event-stream', 'Mcp-Session-Id' => $client->session_id});
  $tx->res->content->on(
    sse => sub ($content, $event = undef) {
      return if $msg;
      return unless $event && $event->{text} && (my $parsed = eval { from_json($event->{text}) });
      $msg = $parsed;
      $got_notification->resolve;
    }
  );
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->res->code || $tx->error;

  ok $server->notify_list_changed('tools'), 'broadcast attempted';
  $got_notification->timeout(5)->wait;
  is $msg->{jsonrpc}, '2.0',                              'JSON-RPC version';
  is $msg->{method},  'notifications/tools/list_changed', 'notification method';

  $client->delete_session;
};

subtest 'List changed (no streams)' => sub {
  ok $server->notify_list_changed('prompts'), 'broadcast attempted';
};

subtest 'Bidirectional flow' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->initialize_session;
  ok $client->session_id, 'session id set';

  my $got_notification = Mojo::Promise->new;
  my $msg;
  my $url = $t->ua->server->url->path('/mcp');
  my $tx  = $t->ua->build_tx(GET => $url => {Accept => 'text/event-stream', 'Mcp-Session-Id' => $client->session_id});
  $tx->res->content->on(
    sse => sub ($content, $event = undef) {
      return if $msg;
      return unless $event && $event->{text} && (my $parsed = eval { from_json($event->{text}) });
      $msg = $parsed;
      $got_notification->resolve;
    }
  );
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->res->code || $tx->error;
  is $tx->res->code,                  200,                 'stream open';
  is $tx->res->headers->content_type, 'text/event-stream', 'right content type';

  my $result = $client->call_tool('push_log');
  is $result->{content}[0]{text}, 'pushed', 'tool call result';

  $got_notification->timeout(5)->wait;
  is $msg->{jsonrpc},       '2.0',                   'JSON-RPC version';
  is $msg->{method},        'notifications/message', 'notification method';
  is $msg->{params}{data},  'hello stream',          'notification payload';
  is $msg->{params}{level}, 'info',                  'notification level';

  $t->get_ok('/mcp' => {'Mcp-Session-Id' => $client->session_id})->status_is(409);

  my $session_id = $client->session_id;
  ok $client->delete_session, 'session deleted';
  is $client->session_id, undef, 'session id cleared';

  my $closed = Mojo::Promise->new;
  $tx->on(finish => sub { $closed->resolve });
  $closed->timeout(5)->wait unless $tx->is_finished;
  ok $tx->is_finished, 'stream closed by server';

  $t->get_ok('/mcp' => {'Mcp-Session-Id' => $session_id})->status_is(404);
  $t->delete_ok('/mcp' => {'Mcp-Session-Id' => $session_id})->status_is(404);
};

subtest 'Notify (no stream)' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->initialize_session;
  my $result = $client->call_tool('notify_status');
  is $result->{content}[0]{text}, 'no stream', 'notify returns false without an open stream';
  $client->delete_session;
};

subtest 'Progress notifications' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->initialize_session;

  my $got_notification = Mojo::Promise->new;
  my $msg;
  my $url = $t->ua->server->url->path('/mcp');
  my $tx  = $t->ua->build_tx(GET => $url => {Accept => 'text/event-stream', 'Mcp-Session-Id' => $client->session_id});
  $tx->res->content->on(
    sse => sub ($content, $event = undef) {
      return if $msg;
      return unless $event && $event->{text} && (my $parsed = eval { from_json($event->{text}) });
      $msg = $parsed;
      $got_notification->resolve;
    }
  );
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->res->code || $tx->error;

  my $request
    = $client->build_request('tools/call', {name => 'progress', arguments => {}, _meta => {progressToken => 'tok-1'}});
  my $response = $client->send_request($request);
  is $response->{result}{content}[0]{text}, 'sent', 'tool call result';

  $got_notification->timeout(5)->wait;
  is $msg->{jsonrpc},               '2.0',                    'JSON-RPC version';
  is $msg->{method},                'notifications/progress', 'notification method';
  is $msg->{params}{progressToken}, 'tok-1',                  'progress token echoed';
  is $msg->{params}{progress},      1,                        'progress value';
  is $msg->{params}{total},         2,                        'total value';
  is $msg->{params}{message},       'halfway',                'progress message';

  $client->delete_session;
};

subtest 'Progress (no token)' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->initialize_session;
  my $result = $client->call_tool('progress');
  is $result->{content}[0]{text}, 'no token', 'notify_progress returns false without a token';
  $client->delete_session;
};

subtest 'Delete (no stream)' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->initialize_session;
  my $session_id = $client->session_id;
  ok $client->delete_session, 'session deleted';
  $t->get_ok('/mcp' => {'Mcp-Session-Id' => $session_id})->status_is(404);
};

subtest 'Stream cleanup on disconnect' => sub {
  my $transport = $server->transport;
  my $client    = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->initialize_session;
  my $session_id = $client->session_id;

  my $url = $t->ua->server->url->path('/mcp');
  my $tx  = $t->ua->build_tx(GET => $url => {Accept => 'text/event-stream', 'Mcp-Session-Id' => $session_id});
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->res->code || $tx->error;
  ok $transport->sessions->{$session_id}->stream, 'stream registered';

  my $closed = Mojo::Promise->new;
  $tx->on(finish => sub { $closed->resolve });
  $transport->sessions->{$session_id}->stream->finish;
  $closed->timeout(5)->wait;
  ok !$transport->sessions->{$session_id}->stream, 'stream cleared on finish';

  $client->delete_session;
};

subtest 'Heartbeat' => sub {
  my $transport = $server->transport;
  $transport->heartbeat(1);
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->initialize_session;
  my $session_id = $client->session_id;

  my $url = $t->ua->server->url->path('/mcp');
  my $tx  = $t->ua->build_tx(GET => $url => {Accept => 'text/event-stream', 'Mcp-Session-Id' => $session_id});
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->res->code || $tx->error;
  is $tx->res->code, 200, 'stream open';

  # SSE parser strips comments
  my $bytes = '';
  Mojo::IOLoop->stream($tx->connection)->on(read => sub ($stream, $chunk) { $bytes .= $chunk });

  my $deadline = Mojo::Promise->new;
  Mojo::IOLoop->timer(1.5 => sub { $deadline->resolve });
  $deadline->wait;
  like $bytes, qr/: keepalive/, 'heartbeat sent';

  $transport->heartbeat(0);
  $client->delete_session;
};

subtest 'Session expiration' => sub {
  my $sessions = $server->transport->sessions;

  my $idle = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $idle->initialize_session;
  my $idle_id = $idle->session_id;

  my $open = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $open->initialize_session;
  my $open_id = $open->session_id;
  my $url     = $t->ua->server->url->path('/mcp');
  my $tx      = $t->ua->build_tx(GET => $url => {Accept => 'text/event-stream', 'Mcp-Session-Id' => $open_id});
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->res->code || $tx->error;

  ok exists $sessions->{$idle_id}, 'idle session registered';
  ok exists $sessions->{$open_id}, 'streaming session registered';

  my $tick = Mojo::Promise->new;
  Mojo::IOLoop->timer(1.5 => sub { $tick->resolve });
  $tick->wait;

  ok !exists $sessions->{$idle_id}, 'idle session swept';
  ok exists $sessions->{$open_id},  'streaming session survives sweep';

  $open->delete_session;

  eval { $idle->ping };
  like $@, qr/404 response/, 'POST for swept session is rejected';
};

done_testing;
