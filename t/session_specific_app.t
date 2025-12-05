use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Client;
use MCP::Server;

my $server = MCP::Server->new;

$server->tool(
  name => 'user_tool',
  code => sub ($tool, $args) {
    return 'Hello user!';
  }
);
$server->tool(
  name => 'admin_tool',
  code => sub ($tool, $args) {
    return 'Hello admin!';
  }
);
$server->on(
  tools => sub ($server, $tools, $context) {
    my $role = $context->{controller}->stash('role');
    return if $role eq 'admin';
    @$tools = grep { $_->{name} ne 'admin_tool' } @$tools;
  }
);

$server->prompt(
  name => 'user_prompt',
  code => sub ($prompt, $args) {
    return 'This is a user prompt';
  }
);
$server->prompt(
  name => 'admin_prompt',
  code => sub ($prompt, $args) {
    return 'This is an admin prompt';
  }
);
$server->on(
  prompts => sub ($server, $prompts, $context) {
    my $role = $context->{controller}->stash('role');
    return if $role eq 'admin';
    @$prompts = grep { $_->{name} ne 'admin_prompt' } @$prompts;
  }
);

$server->resource(
  uri  => 'file:///user_resource',
  code => sub ($resource) {
    return 'User resource content';
  }
);
$server->resource(
  uri  => 'file:///admin_resource',
  code => sub ($resource) {
    return 'Admin resource content';
  }
);
$server->on(
  resources => sub ($server, $resources, $context) {
    my $role = $context->{controller}->stash('role');
    return if $role eq 'admin';
    @$resources = grep { $_->{uri} ne 'file:///admin_resource' } @$resources;
  }
);

get '/' => {text => 'Hello MCP!'};

# Fake authentication
under sub ($c) {
  my $role = $c->param('role');
  $c->stash(role => $role);
  return 1;
};

any '/mcp' => $server->to_action;

my $t = Test::Mojo->new;

subtest 'Normal HTTP endpoint' => sub {
  $t->get_ok('/')->status_is(200)->content_like(qr/Hello MCP!/);
};

subtest 'MCP endpoint' => sub {
  subtest 'Admin user' => sub {
    my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp')->query(role => 'admin'));
    $client->initialize_session;

    subtest 'Tools' => sub {
      my $result = $client->list_tools;
      is $result->{tools}[0]{name}, 'user_tool',  'user tool present';
      is $result->{tools}[1]{name}, 'admin_tool', 'admin tool present';
      is $result->{tools}[2],       undef,        'no more tools';

      my $user_result = $client->call_tool('user_tool');
      is $user_result->{content}[0]{text}, 'Hello user!', 'user tool call result';
      my $admin_result = $client->call_tool('admin_tool');
      is $admin_result->{content}[0]{text}, 'Hello admin!', 'admin tool call result';
    };

    subtest 'Prompts' => sub {
      my $result = $client->list_prompts;
      is $result->{prompts}[0]{name}, 'user_prompt',  'user prompt present';
      is $result->{prompts}[1]{name}, 'admin_prompt', 'admin prompt present';
      is $result->{prompts}[2],       undef,          'no more prompts';

      my $user_prompt = $client->get_prompt('user_prompt');
      is $user_prompt->{messages}[0]{content}[0]{text}, 'This is a user prompt', 'user prompt result';
      my $admin_prompt = $client->get_prompt('admin_prompt');
      is $admin_prompt->{messages}[0]{content}[0]{text}, 'This is an admin prompt', 'admin prompt result';
    };

    subtest 'Resources' => sub {
      my $result = $client->list_resources;
      is $result->{resources}[0]{uri}, 'file:///user_resource',  'user resource present';
      is $result->{resources}[1]{uri}, 'file:///admin_resource', 'admin resource present';
      is $result->{resources}[2],      undef,                    'no more resources';

      my $user_resource = $client->read_resource('file:///user_resource');
      is $user_resource->{contents}[0]{text}, 'User resource content', 'user resource result';
      my $admin_resource = $client->read_resource('file:///admin_resource');
      is $admin_resource->{contents}[0]{text}, 'Admin resource content', 'admin resource result';
    };
  };

  subtest 'Normal user' => sub {
    my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp')->query(role => 'user'));
    $client->initialize_session;

    subtest 'Tools' => sub {
      my $result = $client->list_tools;
      is $result->{tools}[0]{name}, 'user_tool', 'user tool present';
      is $result->{tools}[1],       undef,       'no more tools';

      my $user_result = $client->call_tool('user_tool');
      is $user_result->{content}[0]{text}, 'Hello user!', 'user tool call result';
      eval { $client->call_tool('admin_tool', {}) };
      like $@, qr/Error -32601: Tool 'admin_tool' not found/, 'right error';
    };

    subtest 'Prompts' => sub {
      my $result = $client->list_prompts;
      is $result->{prompts}[0]{name}, 'user_prompt', 'user prompt present';
      is $result->{prompts}[1],       undef,         'no more prompts';

      my $user_prompt = $client->get_prompt('user_prompt');
      is $user_prompt->{messages}[0]{content}[0]{text}, 'This is a user prompt', 'user prompt result';
      eval { $client->get_prompt('admin_prompt') };
      like $@, qr/Error -32601: Prompt 'admin_prompt' not found/, 'right error';
    };

    subtest 'Resources' => sub {
      my $result = $client->list_resources;
      is $result->{resources}[0]{uri}, 'file:///user_resource', 'user resource present';
      is $result->{resources}[1],      undef,                   'no more resources';

      my $user_resource = $client->read_resource('file:///user_resource');
      is $user_resource->{contents}[0]{text}, 'User resource content', 'user resource result';
      eval { $client->read_resource('file:///admin_resource') };
      like $@, qr/Error -32002: Resource not found/, 'right error';
    };
  };
};

done_testing;
