package Plagger::Plugin::CustomFeed::Filesys;
use strict;
use base qw( Plagger::Plugin );

use URI;
use URI::http; # for autoloading
use File::Find::Rule::Filesys::Virtual;
use Filesys::Virtual;
use URI::Escape;
use Path::Class;

sub register {
    my($self, $context) = @_;
    $context->register_hook(
        $self,
        'customfeed.handle' => \&handle,
    );
}

sub handle {
    my($self, $context, $args) = @_;

    if (URI->new($args->{feed}->url)->scheme eq 'file') {
        $self->aggregate($context, $args);
        return 1;
    }

    return;
}

sub aggregate {
    my($self, $context, $args) = @_;

    my $ident = URI->new($args->{feed}->url)->opaque;
    my($vfs, $uri) = $self->vfs_uri($ident);

    my $finder = File::Find::Rule::Filesys::Virtual->virtual($vfs);
    my @exts = @{ $self->conf->{extensions} || [] };
    $finder->name(map "*.$_", @exts) if @exts;

    my $path = dir(URI::Escape::uri_unescape($uri->path));

    my $feed = $args->{feed};
    $feed->title($path->{dirs}->[-1]); # why can't I just do $path->name?
    $feed->link($uri);

    my @files = $finder->in($path->stringify);
    for my $file (@files) {
        $context->log(debug => "Found file $file");
        my $vfile = file($file);

        my $entry = Plagger::Entry->new;
        $entry->title($vfile->basename);
        $entry->link(URI->new("file://$vfile"));
        $feed->add_entry($entry);
    }

    $context->update->add($feed);
}

sub vfs_uri {
    my($self, $ident) = @_;

    my($vfs, $uri);
    if ($ident =~ m!^(\w+):!) {
        $uri = URI->new($ident);
        my $module = "Filesys::Virtual::" . uc($uri->scheme);
        eval "require $module";
        if ($@) {
            Plagger->context->error("Error loading $module: $@");
        }
        $vfs = $module->new({ host => $uri->host }); # TODO auth
    } else {
        $ident =~ s!^//!!;
        require Filesys::Virtual::Plain;
        $vfs = Filesys::Virtual::Plain->new;
        $uri = URI->new("file://$ident");
    }

    return $vfs, $uri;
}

1;
__END__

=head1 NAME

Plagger::Plugin::CustomFeed::Filesys - File system folder as a feed

=head1 SYNOPSIS

  - module: Subscription::Config
    config:
      feed:
        - file:///path/to/videos
        - file:ssh://username:password@remote/path/videos
        - file:daap//localhost:3689/Library
  - module: CustomFeed::Filesys
    config:
      extensions:
        - mp4
        - avi

=head1 DESCRIPTION

This plugin scans local (or remote, to be implemented) filesystem and
finds files matching the extensions specified in the configuration.

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Plagger>

=cut
