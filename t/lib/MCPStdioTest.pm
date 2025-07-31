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

sub request ($self, $method, $params) {
  $self->{timeout}->start(60);
  $self->{stdin} .= encode_json($self->client->build_request($method, $params)) . "\n";

  my $stdout = $self->{stdout};
  pump $self->{run} until $self->{stdout} =~ s/^(.*)\n//;
  my $input = $1;
  my $res   = eval { decode_json($input) };
  return $res;
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
