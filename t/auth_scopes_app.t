use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Client;
use MCP::Constants qw(PROTOCOL_VERSION);
use MCP::Server;

my $server = MCP::Server->new;

$server->tool(
  name   => 'read_tool',
  scopes => ['mcp:read'],
  code   => sub ($tool, $args) {
    return 'Read result';
  }
);
$server->tool(
  name   => 'write_tool',
  scopes => ['mcp:write'],
  code   => sub ($tool, $args) {
    return 'Write result';
  }
);
$server->tool(
  name   => 'custom_tool',
  scopes => ['mcp:something.custom'],
  code   => sub ($tool, $args) {
    return 'custom result';
  }
);
$server->on(
  tools => sub ($server, $tools, $context) {
    my $c    = $context->controller;
    my $role = $c ? $c->stash('role') : '';
    return if $role eq 'admin';
    @$tools = grep { $_->name ne 'custom_tool' } @$tools;
  }
);

$server->prompt(
  name   => 'read_prompt',
  scopes => ['mcp:read'],
  code   => sub ($prompt, $args) {
    return 'Read prompt';
  }
);
$server->prompt(
  name   => 'write_prompt',
  scopes => ['mcp:write'],
  code   => sub ($prompt, $args) {
    return 'Write prompt';
  }
);

$server->resource(
  uri    => 'file:///read',
  scopes => ['mcp:read'],
  code   => sub ($resource) {
    return 'Read resource';
  }
);
$server->resource(
  uri    => 'file:///write',
  scopes => ['mcp:write'],
  code   => sub ($resource) {
    return 'Write resource';
  }
);

get '/.well-known/oauth-protected-resource' => sub ($c) {
  $c->render(
    json => $server->oauth_metadata(
      resource              => 'http://example.com/mcp',
      authorization_servers => ['https://auth.example.com']
    )
  );
};

# Fake token validation, replace with real OAuth access token verification in production
my $tokens = {
  ro    => {scopes => ['mcp:read'], role => 'user'},
  rw    => {scopes => ['mcp:read', 'mcp:write', 'mcp:something.custom'], role => 'user'},
  admin => {scopes => ['mcp:read', 'mcp:write', 'mcp:something.custom'], role => 'admin'}
};
my $metadata_url = 'http://example.com/.well-known/oauth-protected-resource';
any '/mcp' => $server->to_action({
  auth => sub ($c) {
    return undef unless ($c->req->headers->authorization // '') =~ /^Bearer\s+(\S+)$/;
    return undef unless my $token = $tokens->{$1};
    $c->stash(role => $token->{role});
    return {scopes => $token->{scopes}};
  },
  metadata_url => $metadata_url
});

my $t = Test::Mojo->new;

subtest 'Discovery' => sub {
  $t->post_ok('/mcp' => json => {})
    ->status_is(401)
    ->header_like('WWW-Authenticate' => qr/^Bearer/)
    ->header_like('WWW-Authenticate' => qr/resource_metadata="\Q$metadata_url\E"/);
  $t->post_ok('/mcp' => {Authorization => 'Bearer bogus'} => json => {})->status_is(401);

  $t->get_ok('/.well-known/oauth-protected-resource')
    ->status_is(200)
    ->json_is('/scopes_supported'      => ['mcp:read', 'mcp:something.custom', 'mcp:write'])
    ->json_is('/authorization_servers' => ['https://auth.example.com']);
};

subtest 'Read-only token' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'),
    headers => {Authorization => 'Bearer ro'});
  $client->initialize_session;

  subtest 'Tools' => sub {
    my $result = $client->list_tools;
    is $result->{tools}[0]{name}, 'read_tool', 'read tool present';
    is $result->{tools}[1],       undef,       'no more tools';

    is $client->call_tool('read_tool')->{content}[0]{text}, 'Read result', 'read tool call result';
    eval { $client->call_tool('write_tool') };
    like $@, qr/403 response/, 'write tool denied';
  };

  subtest 'Prompts' => sub {
    my $result = $client->list_prompts;
    is $result->{prompts}[0]{name}, 'read_prompt', 'read prompt present';
    is $result->{prompts}[1],       undef,         'no more prompts';

    is $client->get_prompt('read_prompt')->{messages}[0]{content}{text}, 'Read prompt', 'read prompt result';
    eval { $client->get_prompt('write_prompt') };
    like $@, qr/403 response/, 'write prompt denied';
  };

  subtest 'Resources' => sub {
    my $result = $client->list_resources;
    is $result->{resources}[0]{uri}, 'file:///read', 'read resource present';
    is $result->{resources}[1],      undef,          'no more resources';

    is $client->read_resource('file:///read')->{contents}[0]{text}, 'Read resource', 'read resource result';
    eval { $client->read_resource('file:///write') };
    like $@, qr/403 response/, 'write resource denied';
  };
};

subtest 'Read-write token' => sub {
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'),
    headers => {Authorization => 'Bearer rw'});
  $client->initialize_session;

  subtest 'Tools' => sub {
    my $result = $client->list_tools;
    is $result->{tools}[0]{name}, 'read_tool',  'read tool present';
    is $result->{tools}[1]{name}, 'write_tool', 'write tool present';
    is $result->{tools}[2],       undef,        'custom tool hidden by role';

    is $client->call_tool('write_tool')->{content}[0]{text}, 'Write result', 'write tool call result';
    eval { $client->call_tool('custom_tool') };
    like $@, qr/Error -32601/, 'custom tool hidden by role';
  };

  subtest 'Prompts' => sub {
    my $result = $client->list_prompts;
    is $result->{prompts}[0]{name}, 'read_prompt',  'read prompt present';
    is $result->{prompts}[1]{name}, 'write_prompt', 'write prompt present';
    is $result->{prompts}[2],       undef,          'no more prompts';

    is $client->get_prompt('write_prompt')->{messages}[0]{content}{text}, 'Write prompt', 'write prompt result';
  };

  subtest 'Resources' => sub {
    my $result = $client->list_resources;
    is $result->{resources}[0]{uri}, 'file:///read',  'read resource present';
    is $result->{resources}[1]{uri}, 'file:///write', 'write resource present';
    is $result->{resources}[2],      undef,           'no more resources';

    is $client->read_resource('file:///write')->{contents}[0]{text}, 'Write resource', 'write resource result';
  };
};

subtest 'Admin token' => sub {
  my $client = MCP::Client->new(
    ua      => $t->ua,
    url     => $t->ua->server->url->path('/mcp'),
    headers => {Authorization => 'Bearer admin'}
  );
  $client->initialize_session;

  my $result = $client->list_tools;
  is $result->{tools}[0]{name}, 'read_tool',   'read tool present';
  is $result->{tools}[1]{name}, 'write_tool',  'write tool present';
  is $result->{tools}[2]{name}, 'custom_tool', 'custom tool present';
  is $result->{tools}[3],       undef,         'no more tools';

  is $client->call_tool('custom_tool')->{content}[0]{text}, 'custom result', 'custom tool call result';
};

subtest 'Insufficient scope challenge' => sub {
  my $init = {
    jsonrpc => '2.0',
    id      => 1,
    method  => 'initialize',
    params  => {protocolVersion => PROTOCOL_VERSION, capabilities => {}, clientInfo => {name => 't', version => '1'}}
  };
  $t->post_ok('/mcp' => {Authorization => 'Bearer ro'} => json => $init)->status_is(200);
  my $session_id = $t->tx->res->headers->header('Mcp-Session-Id');

  my $call = {jsonrpc => '2.0', id => 2, method => 'tools/call', params => {name => 'write_tool', arguments => {}}};
  $t->post_ok('/mcp' => {Authorization => 'Bearer ro', 'Mcp-Session-Id' => $session_id} => json => $call)
    ->status_is(403)
    ->header_like('WWW-Authenticate' => qr/error="insufficient_scope"/)
    ->header_like('WWW-Authenticate' => qr/scope="mcp:write"/);
};

done_testing;
