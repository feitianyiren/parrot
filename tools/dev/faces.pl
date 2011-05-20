#! perl
# Copyright (C) 2010, Parrot Foundation.

use strict;
use warnings;

use Gravatar::URL;

=head1 NAME

faces.pl - Generate source for Parrot wiki ParrotFaces page

=head1 SYNOPSIS

    perl tools/dev/faces.pl

=head1 DESCRIPTION

Used to create L<http://trac.parrot.org/parrot/wiki/ParrotFaces>

=head1 PREREQUISITE

Gravatar::URL (L<http://search.cpan.org/dist/Gravatar-URL/>).

=cut

open my $fh, '<', 'CREDITS';

my %urls;
while(<$fh>) {
    next unless /^E: (.*)/;
    my $email = lc $1;
    next if $email eq 'svn@perl.org' or
            $email eq 'cvs@perl.org';
    if (!exists $urls{$email}) {
        $urls{$email} = gravatar_url(
            email   => $email,
            rating  => 'r',
            size    => 80,
            default => 'wavatar',
        );
    }
    else {
        warn "duplicated email address in CREDITS: $email\n";
    }
}

foreach my $email (sort keys %urls) {
    print "[[Image($urls{$email},title=$email)]]\n";
}
print "[[BR]]''Generated by $0''\n";

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
