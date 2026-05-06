package MCPStdioTest;
use Mojo::Base -base, -signatures;

use Carp        qw(croak);
use IPC::Run    qw(finish pump start timeout);
use Time::HiRes qw(sleep);
use Mojo::JSON  qw(decode_json encode_json);
use MCP::Client;

has client => sub { MCP::Client->new };

sub notify ($self, $method, $params) {
  $self->{timeout}->start(60);
  $self->{stdin} .= encode_json($self->client->build_notification($method, $params)) . "\n";
  return 1;
}

sub read_line ($self) {
  $self->{timeout}->start(60);
  pump $self->{run} until $self->{stdout} =~ s/^(.*)\n//;
  return eval { decode_json($1) };
}

sub request ($self, $method, $params) {
  $self->send_request($method, $params);
  return $self->read_line;
}

sub send_request ($self, $method, $params) {
  $self->{timeout}->start(60);
  $self->{stdin} .= encode_json($self->client->build_request($method, $params)) . "\n";
  return 1;
}

sub run ($self, @command) {
  $self->{run} = start(\@command, \$self->{stdin}, \$self->{stdout}, \$self->{stderr}, $self->{timeout} = timeout(60));
}

sub stop ($self) {
  return undef unless $self->{run};
  finish($self->{run}) or croak "Command returned: $?";
  delete $self->{run};
  return 1;
}

1;
