# Copyright (C) 2001-2011, Parrot Foundation.

=head1 NAME

Parrot::Test::HBDB - OO interface for testing the HBDB debugger

=head1 SYNOPSIS

Set the number of tests to be run like this:

    use Parrot::Test::HBDB tests => 8;

=head1 DESCRIPTION

The C<Parrot::Test::HBDB> module provides various test functions specific to HBDB.

=head1 REQUIREMENTS

This module requires you to build HBDB, by running "make hbdb". If this
requirement has not been met, all tests will be skipped.

=head2 Constructor

=over 4

=item B<new()>

Returns a new C<Parrot::Test::HBDB> object. Note that this does not actually
start a HBDB process. For that you must invoke C<start()>.

    my $hbdb = Parrot::Test::HBDB->new();

=back

=head2 Methods

=over 4

=item B<start($file, $args)>

Creates a new HBDB process. C<$file> is the name of the file to debug and
C<$args> contains the command-line switches.

    $hbdb->start('foo.pir', '--bar');

=item B<arg_output_is($arg, $expected, $desc)>

Similar to C<Test::More::is()>. C<$arg> contains the switch(es) to pass to HBDB,
C<$expected> is the resulting output that the switch(es) I<should> generate,
and C<$desc> is a short description of the test that will be displayed. The
test will pass if the output generated by the C<$arg> switch(es) matches the
string C<$expected> exactly.

    $hbdb->arg_output_is('--cat', 'Ceiling cat is watching you', 'Test --cat');

NOTE: Unlike the other methods, you do not need to call C<start()> before
invoking C<arg_output_is()> as a new HBDB process will be created implicitly.

=item B<arg_output_like($arg, qr/expected/, $desc)>

Similar to C<Test::More::like()>. C<$arg> contains is the switch(es) to pass
to HBDB, C<qr/expected/> is a regular expression to match, and C<$desc> is a short
description of the test that will be displayed. The test will pass if the
output generated by the C<$arg> switch(es) (if any) matches the given regular
expression.

    $hbdb->arg_output_like('--cat', qr/Ceiling cat is \w+ you/, 'Test --cat');

NOTE: Unlike the other methods, you do not need to call C<start()> before
invoking C<arg_output_like()> as a new HBDB process will be created implicitly.

=item B<cmd_output_is($cmd, $expected, $desc)>

Similar to C<Test::More::is()>. C<$cmd> is the command to run, C<$expected> is
the resulting output that the command I<should> generate, and C<$desc> is a
short description of the test that will be displayed. The test will pass if the
output generated by C<$cmd> matches the string C<$expected> exactly.

    $hbdb->cmd_output_is('break', 'lolz, imma break now', 'Test break command');

=item B<cmd_output_like($cmd, qr/expected/, $desc)>

Similar to C<Test::More::like()>. C<$cmd> is the command to run, C<qr/expected/> is
a regular expression to match, and C<$desc> is a short description of the test
that will be displayed. The test will pass if the output generated by C<$cmd>
(if any) matches the given regular expression.

    $hbdb->cmd_output_like('break', qr/lolz, imma break (now|later)/, 'Test break command');

=back

=head1 SEE ALSO

L<Test::More>, L<Parrot::Test>,  F<docs/tests.pod>, F<docs/hbdb.pod>

=head1 HISTORY

Initial version by Kevin Polulak (soh_cah_toa) <kpolulak@gmail.com>

=cut

# TODO Refactor this code into a common subroutine

package Parrot::Test::HBDB;

use strict;
use warnings;
use lib  'lib';
use base 'Test::Builder::Module';

use Carp;
use File::Spec;
use IO::Select;
use IPC::Open3;

use Parrot::Config;

########################
# File-scope variables #
########################

my $test;   # Represents current state of test
my $pid;    # PID of HBDB process being tested

# Check that HBDB has been built first
BEGIN {
    $test    = Test::Builder->new();

    my $hbdb = File::Spec->join('.', 'hbdb') . $PConfig{exe};

    # Skip tests if executable doesn't exist
    unless (-e $hbdb) {
        $test->plan(skip_all => 'HBDB hasn\'t been built. Please run \"make hbdb\"');
        exit(0);
    }
}

###########
# Methods #
###########

# Custom import() method that's called when package is used
sub import {
    my ($self, $plan, $args) = @_;

    $test->plan($plan, $args);
}

# Constructor
sub new {
    my $class = shift;

    my $obj = {
        exe => ".$PConfig{slash}hbdb$PConfig{exe}"
    };

    bless $obj, $class;
}

# Compares output of command-line switches
sub arg_output_is {
    my ($self, $arg, $expected, $desc) = @_;
    my $builder                        = __PACKAGE__->builder;

    my $output                         = `$self->{exe} $arg`;

    $builder->is($output, $expected, $desc);
}

# Matches output of command-line switches with regex
sub arg_output_like {
    my ($self, $arg, $expected, $desc) = @_;
    my $builder                        = __PACKAGE__->builder;

    my $output                         = `$self->{exe} $arg`;

    $builder->like($output, $expected, $desc);
}

# Compares output of commands
sub cmd_output_is {
    my ($self, $cmd, $expected, $desc) = @_;
    my $builder                        = __PACKAGE__->builder;
    my $lines;

    $self->{cmd} = $cmd if defined $cmd;

    _select($self, \$lines);

    $builder->is($lines, $expected, $desc);

    _close_fh();
}

# Compares output of commands (with regex)
sub cmd_output_like {
    my ($self, $cmd, $expected, $desc) = @_;
    my $builder                        = __PACKAGE__->builder;
    my $lines;

    $self->{cmd} = $cmd if defined $cmd;

    _select($self, \$lines);

    $builder->like($lines, $expected, $desc);

    _close_fh();
}

# Starts HBDB
sub start {
    my ($self, $file, $args) = @_;

    # TODO Add handling for PIR files

    $self->{file} = _generate_pbc($file) if defined $file;
    $self->{args} = $args                if defined $args;

    # Don't write to `HBDB_STDIN` anymore when child has exited
    $SIG{CHLD} = sub {
        close HBDB_STDIN if fileno HBDB_STDIN;
    };

    $pid = open3(\*HBDB_STDIN, \*HBDB_STDOUT, \*HBDB_STDERR, "$self->{exe} $self->{args} $self->{file}");
}

#######################
# Private subroutines #
#######################

# Closes filehandles connected to stdout/stderr
sub _close_fh {
    close HBDB_STDOUT;
    close HBDB_STDERR;
}

# Enters a command
sub _enter_cmd {
    my $cmd = shift || '';

    print HBDB_STDIN "$cmd\n";
    print HBDB_STDIN "quit\n";
    close HBDB_STDIN;

    waitpid $pid, 0;
}

# Compiles .pir file into .pbc
sub _generate_pbc {
    my $pir    = shift;
    my $pbc    = $pir;
    my $parrot = ".$PConfig{slash}$PConfig{test_prog}";

    $pbc =~ s|\.pir|\.pbc|i;

    # Compile to bytecode
    eval { system "$parrot -o $pbc $pir" };
    $test->diag("Failed to generate $pbc") if $@;

    return $pbc;
}

END {
    # TODO How can I get rid of this hard-coded string?
    unlink "t/tools/hbdb/testlib/hello.pbc";
}

sub _select {
    my ($self, $lines) = @_;

    #$self->{cmd} = $cmd if defined $cmd;

    _enter_cmd($self->{cmd});

    my $select = IO::Select->new();
    $select->add(\*HBDB_STDOUT, \*HBDB_STDERR);

    my @fh_ready = $select->can_read();

    foreach my $fh (@fh_ready) {
        next unless defined $fh;

        if (fileno $fh  == fileno \*HBDB_STDERR) {
            $lines = <HBDB_STDERR> || '';
        }
        else {
            $lines = <HBDB_STDOUT> || ''; 
        }

        $select->remove($fh) if eof $fh;
    }
}

1;

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:

