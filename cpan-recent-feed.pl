#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use Time::Piece;
use Carp;
use Archive::Tar;
use File::Temp;
use Algorithm::Diff ();
use HTML::TreeBuilder::XPath;
use XML::Feed;
use DateTime;
use Getopt::Long;
use Pod::Usage;
use URI::Fetch;
use File::Path qw/mkpath/;
use Cache::File;

our $VERSION = '0.01';

my $duration = 2 * 24 * 60 * 60;
my $FEEDURL = 'http://friendfeed-api.com/v2/feed/cpan';
my $cachedir = '/tmp/cache/';
mkpath($cachedir) unless -d $cachedir;
my $cache = Cache::File->new( cache_root => $cachedir );

&main;exit;

sub dbg {
    print STDERR join("", @_, $/) if $ENV{DEBUG};
}

sub main {
    my $feed_content = get($FEEDURL);
    my $entries = from_json($feed_content)->{entries};
       $entries = [ map { parse_entry( $_->{body}, $_->{date} ) } @$entries ];
    my $feed = XML::Feed->new('RSS', version => 2.0);
    $feed->title('Yet Another CPAN Recent Changes');
    $feed->link('http://64p.org/');
    for my $entry ( @$entries ) {
        print "-- ", $entry->{dist}, ' ', $entry->{version}, $/;
        my $diff = extract_diff($entry) || '';
        print $diff;
        $feed->add_entry(do {
            my $e = XML::Feed::Entry->new('RSS');
               $e->title("$entry->{dist} $entry->{version}");
               $e->link($entry->{url});
               $e->author($entry->{author});
               $e->issued(do {
                    DateTime->from_epoch(epoch => $entry->{'time'}->epoch)
               });
               $e->summary($diff);
               $e->content(make_content($entry, $diff));
               $e;
        });
    }
    print $feed->as_xml;
}

sub make_content {
    my ($entry, $diff) = @_;
    <<"...";
<img src="$entry->{gravatar}" /><br />
Diff:<br />
<pre>$diff</pre>
...
}

sub extract_diff {
    my $entry = shift;

    my $url = "http://search.cpan.org/dist/$entry->{dist}";
    my $pagecontent = get($url);
    if ($pagecontent =~ m{<img src="(http://www\.gravatar\.com/[^"]+)"}) {
        $entry->{gravatar} = $1;
    }

    if ($pagecontent =~ m{<td class="version">([^<>]+)</td>}) {
        # last one is already on search.cpan.org.
        my $lastversion = $1;
        dbg("search.cpan.org version is $lastversion");
        if ($entry->{version} eq $lastversion) {
            dbg "search.cpan.org has latest release... try to get old one";
            my $tree = HTML::TreeBuilder::XPath->new();
            $tree->parse_content($pagecontent);
            my $path = $tree->findvalue('//select[@name="url"]/option[position()=1]/@value');
            $tree = $tree->delete;
            if ($path) {
                dbg "found path, get it";
                $pagecontent = get("http://search.cpan.org$path");
            } else {
                dbg "cannot detect latest url";
                return;
            }
        }
    } else {
        dbg("cannot scrape last version");
    }

    unless ($pagecontent =~ m{<a href="([^"]+)">(?:Changes|ChangeLog)</a><br>}) {
        Carp::carp("cannot get url for Changes file");
        return '';
    }

    my $changes_url = "http://search.cpan.org$1";
    my $old_changes = get($changes_url);

    my $tmp = File::Temp->new(UNLINK => 1, SUFFIX => '.tar.gz');
    print $tmp get($entry->{url});
    close $tmp;
    my $tar = Archive::Tar->new;
    $tar->read($tmp->filename) or return;
    my $iter = Archive::Tar->iter($tmp->filename, 1, {filter => qr/(?:Changes|ChangeLog)$/});
    while (my $file = $iter->()) {
        my $content = $file->get_content();
        my $res = '';
        my $diff = Algorithm::Diff->new(
            [ split /\n/, $old_changes ],
            [ split /\n/, $content ],
        );
        $diff->Base(1);
        while ($diff->Next()) {
            next if $diff->Same();
            $res .= "$_\n" for $diff->Items(2);
        }
        return $res;
    }
    Carp::carp('This archive does not contains changes flie');
    return;
}

sub get {
    my $url = shift;
    dbg "fetching $url";
    my $res = URI::Fetch->fetch( $url, Cache => $cache )
      or die URI::Fetch->errstr;
    return $res->content;
}

sub parse_entry {
    my ( $body, $date ) = @_;

    my $time = Time::Piece->strptime( $date, "%Y-%m-%dT%H:%M:%SZ" ) or return;
    if ( time - $time->epoch > $duration ) {
        # entry found, but it's old
        return;
    }

    if ($body =~ /^([\w\-]+) ([0-9\._]*) by (.+?) - <a.*href="(http:.*?\.tar\.gz)"/)
    {
        return {
            dist    => $1,
            version => $2,
            author  => $3,
            url     => $4,
            time    => $time,
        };
    }

    return;
}

__END__

=head1 SYNOPSIS

    % cpanrecent-feed.pl

