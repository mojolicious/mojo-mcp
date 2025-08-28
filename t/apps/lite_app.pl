use Mojolicious::Lite -signatures;

use MCP::Server;
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::File qw(curfile);

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{msg}";
  }
);
$server->tool(
  name         => 'echo_async',
  description  => 'Echo the input text asynchronously',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    my $promise = Mojo::Promise->new;
    Mojo::IOLoop->timer(0.5 => sub { $promise->resolve("Echo (async): $args->{msg}") });
    return $promise;
  }
);
$server->tool(
  name         => 'echo_header',
  description  => 'Echo the input text with a header',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    my $context = $tool->context;
    my $header  = $context->{controller}->req->headers->header('Mcp-Custom-Header');
    return "Echo with header: $args->{msg} (Header: $header)";
  }
);
$server->tool(
  name        => 'time',
  description => 'Get the current time in epoch format',
  code        => sub ($tool, $args) {
    return time;
  }
);
$server->tool(
  name         => 'generate_image',
  description  => 'Generate a simple image from text',
  input_schema => {type => 'object', properties => {text => {type => 'string'}}, required => ['text']},
  code         => sub ($tool, $args) {
    my $image = curfile->sibling('mojolicious.png')->slurp;
    return $tool->image_result($image, {annotations => {audience => ['user']}});
  }
);
$server->tool(
  name         => 'current_weather',
  description  => 'Get current weather data for a location',
  input_schema => {
    type       => 'object',
    properties => {location => {type => 'string', description => 'City name or zip code'}},
    required   => ['location']
  },
  output_schema => {
    type       => 'object',
    properties => {
      temperature => {type => 'number', description => 'Temperature in celsius'},
      conditions  => {type => 'string', description => 'Weather conditions description'},
      humidity    => {type => 'number', description => 'Humidity percentage'}
    },
    required => ['temperature', 'conditions', 'humidity']
  },
  code => sub ($tool, $args) {
    return $tool->structured_result({temperature => 22, conditions => 'Partly cloudy', humidity => 65})
      if $args->{location} eq 'Bremen';
    return $tool->structured_result({temperature => 19, conditions => 'Raining', humidity => 80});
  }
);
$server->prompt(
  name        => 'time',
  description => 'Tell the user the time',
  code        => sub ($tool, $args) {
    return 'Tell the user the current time';
  }
);
$server->prompt(
  name        => 'prompt_echo_async',
  description => 'Make a prompt from the input text',
  arguments   => [{name => 'msg', description => 'Message to echo', required => 1}],
  code        => sub ($prompt, $args) {
    my $promise = Mojo::Promise->new;
    Mojo::IOLoop->timer(0.5 => sub { $promise->resolve("Tell the user (async): $args->{msg}") });
    return $promise;
  }
);
$server->prompt(
  name        => 'prompt_echo_header',
  description => 'Make a prompt from the input text with a header',
  arguments   => [{name => 'msg', description => 'Message to echo', required => 1}],
  code        => sub ($prompt, $args) {
    my $context = $prompt->context;
    my $header  = $context->{controller}->req->headers->header('Mcp-Custom-Header');
    return $prompt->text_prompt("Prompt with header: $args->{msg} (Header: $header)",
      'assistant', 'Echoed message with header');
  }
);

any '/mcp' => $server->to_action;

get '/' => {text => 'Hello MCP!'};

app->start;
