package Template::App::ttree;

#========================================================================
#
# Template::App::ttre
#
# DESCRIPTION
#   Script for processing all directory trees containing templates.
#   Template files are processed and the output directed to the
#   relvant file in an output tree.  The timestamps of the source and
#   destination files can then be examined for future invocations
#   to process only those files that have changed.  In other words,
#   it's a lot like 'make' for templates.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2013 Andy Wardley.  All Rights Reserved.
#   Copyright (C) 1998-2003 Canon Research Centre Europe Ltd.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#========================================================================

use strict;
use warnings;
use base 'Template::Base';

our $VERSION = '2.92';

use Template;
use AppConfig qw( :expand );
use File::Copy;
use File::Path;
use File::Spec;
use File::Basename;
use Text::ParseWords qw(quotewords);

use constant DEFAULT_TTMODULE => 'Template';
use constant DEFAULT_HOME     => $ENV{ HOME } || '';

sub emit_warn {
    my $self = shift;
    my $msg = shift;
    warn $msg;
}

sub emit_log {
    my $self = shift;
    print @_
}

sub _get_myname {
    my $self = shift;
    (split /[:]{2}/, __PACKAGE__)[-1];
}

sub _get_rc_file {
    my $self = shift;
    my $NAME = $self->_get_myname();
    return $ENV{"\U${NAME}rc"} || DEFAULT_HOME . "/.${NAME}rc";
}

sub offer_create_a_sample_config_file {
    my $self   = shift;
    my $RCFILE = $self->_get_rc_file();
    # offer create a sample config file if it doesn't exist, unless a '-f'
    # has been specified on the command line
    unless (-f $RCFILE or grep(/^(-f|-h|--help)$/, @ARGV) ) {
        $self->emit_log("Do you want me to create a sample '.ttreerc' file for you?\n",
          "(file: $RCFILE)   [y/n]: ");
        my $y = <STDIN>;
        if ($y =~ /^y(es)?/i) {
            $self->write_config($RCFILE);
            exit(0);
        }
    }
}

sub run {
    my $self = shift;
    my $NAME = $self->_get_myname();

    #------------------------------------------------------------------------
    # configuration options
    #------------------------------------------------------------------------

    # read configuration file and command line arguments - I need to remember
    # to fix varlist() and varhash() in AppConfig to make this nicer...
    my $config   = $self->read_config( $self->_get_rc_file() );
    my $dryrun   = $config->nothing;
    my $verbose  = $config->verbose || $dryrun;
    my $colour   = $config->colour;
    my $summary  = $config->summary;
    my $recurse  = $config->recurse;
    my $preserve = $config->preserve;
    my $all      = $config->all;
    my $libdir   = $config->lib;
    my $ignore   = $config->ignore;
    my $copy     = $config->copy;
    my $link     = $config->link;
    my $accept   = $config->accept;
    my $absolute = $config->absolute;
    my $relative = $config->relative;
    my $suffix   = $config->suffix;
    my $binmode  = $config->binmode;
    my $depends  = $config->depend;
    my $depsfile = $config->depend_file;
    my $copy_dir = $config->copy_dir;
    my ($n_proc, $n_unmod, $n_skip, $n_copy, $n_link, $n_mkdir) = (0) x 6;

    my $srcdir   = $config->src
        || die "Source directory not set (-s)\n";
    my $destdir  = $config->dest
        || die "Destination directory not set (-d)\n";
    die "Source and destination directories may not be the same:\n  $srcdir\n"
        if $srcdir eq $destdir;

    # unshift any perl5lib directories onto front of INC
    unshift(@INC, @{ $config->perl5lib });

    # get all template_* options from the config and fold keys to UPPER CASE
    my %ttopts   = $config->varlist('^template_', 1);
    my $ttmodule = delete($ttopts{ module });
    my $ucttopts = {
        map { my $v = $ttopts{ $_ }; defined $v ? (uc $_, $v) : () }
        keys %ttopts,
    };

    # get all template variable definitions
    my $replace = $config->get('define');

    # now create complete parameter hash for creating template processor
    my $ttopts   = {
        %$ucttopts,
        RELATIVE     => $relative,
        ABSOLUTE     => $absolute,
        INCLUDE_PATH => [ $srcdir, @$libdir ],
        OUTPUT_PATH  => $destdir,
    };

    # load custom template module
    if ($ttmodule) {
        my $ttpkg = $ttmodule;
        $ttpkg =~ s[::][/]g;
        $ttpkg .= '.pm';
        require $ttpkg;
    }
    else {
        $ttmodule = DEFAULT_TTMODULE;
    }


    #------------------------------------------------------------------------
    # inter-file dependencies
    #------------------------------------------------------------------------

    if ($depsfile or $depends) {
        $depends = $self->dependencies($depsfile, $depends);
    }
    else {
        $depends = { };
    }

    my $global_deps = $depends->{'*'} || [ ];

    # add any PRE_PROCESS, etc., templates as global dependencies
    foreach my $ttopt (qw( PRE_PROCESS POST_PROCESS PROCESS WRAPPER )) {
        my $deps = $ucttopts->{ $ttopt } || next;
        my @deps = ref $deps eq 'ARRAY' ? (@$deps) : ($deps);
        next unless @deps;
        push(@$global_deps, @deps);
    }

    # remove any duplicates
    $global_deps = { map { ($_ => 1) } @$global_deps };
    $global_deps = [ keys %$global_deps ];

    # update $depends hash or delete it if there are no dependencies
    if (@$global_deps) {
        $depends->{'*'} = $global_deps;
    }
    else {
        delete $depends->{'*'};
        $global_deps = undef;
    }
    $depends = undef
        unless keys %$depends;

    my $DEP_DEBUG = $config->depend_debug();


    #------------------------------------------------------------------------
    # pre-amble
    #------------------------------------------------------------------------

    if ($colour) {
        no strict 'refs';
        *red    = \&_red;
        *green  = \&_green;
        *yellow = \&_yellow;
        *blue   = \&_blue;
    }
    else {
        no strict 'refs';
        *red    = \&_white;
        *green  = \&_white;
        *yellow = \&_white;
        *blue   = \&_white;
    }

    if ($verbose) {
        local $" = ', ';


        $self->emit_log( "$NAME $VERSION (Template Toolkit version $Template::VERSION)\n\n" );

        my $sfx = join(', ', map { "$_ => $suffix->{$_}" } keys %$suffix);

        $self->emit_log("      Source: $srcdir\n",
              " Destination: $destdir\n",
              "Include Path: [ @$libdir ]\n",
              "      Ignore: [ @$ignore ]\n",
              "        Copy: [ @$copy ]\n",
              "        Link: [ @$link ]\n",
              "    Copy_Dir: [ @$copy_dir ]\n",
              "      Accept: [ @$accept ]\n",
              "      Suffix: [ $sfx ]\n");
        $self->emit_log("      Module: $ttmodule ", $ttmodule->module_version(), "\n")
            unless $ttmodule eq DEFAULT_TTMODULE;

        if ($depends && $DEP_DEBUG) {
            $self->emit_log("Dependencies:\n");
            foreach my $key ('*', grep { !/\*/ } keys %$depends) {
                $self->emit_log( sprintf( "    %-16s %s\n", $key,
                        join(', ', @{ $depends->{ $key } }) ) )
                    if defined $depends->{ $key };

            }
        }
        $self->emit_log( "\n" ) if $verbose > 1;
        $self->emit_log( red("NOTE: dry run, doing nothing...\n") )
            if $dryrun;
    }

    #------------------------------------------------------------------------
    # main processing loop
    #------------------------------------------------------------------------

    my $template = $ttmodule->new($ttopts)
        || die $ttmodule->error();

    my $running_conf = {
        accept   => $accept,
        all      => $all,
        binmode  => $binmode,
        config   => $config,
        copy     => $copy,
        copy_dir => $copy_dir,
        depends  => $depends,
        destdir  => $destdir,
        dryrun   => $dryrun,
        ignore   => $ignore,
        libdir   => $libdir,
        link     => $link,
        n_copy   => \$n_copy,
        n_link   => \$n_link,
        n_mkdir  => \$n_mkdir,
        n_proc   => \$n_proc,
        n_skip   => \$n_skip,
        n_unmod  => \$n_unmod,
        preserve => $preserve,
        recurse  => $recurse,
        replace  => $replace,
        srcdir   => $srcdir,
        suffix   => $suffix,
        template => $template,
        verbose  => $verbose,
    };

    if (@ARGV) {
        # explicitly process files specified on command lines
        foreach my $file (@ARGV) {
            my $path = $srcdir ? File::Spec->catfile($srcdir, $file) : $file;
            if ( -d $path ) {
                $self->process_tree($file, $running_conf);
            }
            else {
                $self->process_file($file, $path, $running_conf, force => 1);
            }
        }
    }
    else {
        # implicitly process all file in source directory
        $self->process_tree(undef, $running_conf);
    }

    if ($summary || $verbose) {
        my $format  = "%13d %s %s\n";
        $self->emit_log( "\n" ) if $verbose > 1;
        $self->emit_log(
            "     Summary: ",
            $dryrun ? red("This was a dry run.  Nothing was actually done\n") : "\n",
            green(sprintf($format, $n_proc,  $n_proc  == 1 ? 'file' : 'files', 'processed')),
            green(sprintf($format, $n_copy,  $n_copy  == 1 ? 'file' : 'files', 'copied')),
            green(sprintf($format, $n_link,  $n_link  == 1 ? 'file' : 'files', 'linked')),
            green(sprintf($format, $n_mkdir, $n_mkdir == 1 ? 'directory' : 'directories', 'created')),
            yellow(sprintf($format, $n_unmod, $n_unmod == 1 ? 'file' : 'files', 'skipped (not modified)')),
            yellow(sprintf($format, $n_skip,  $n_skip  == 1 ? 'file' : 'files', 'skipped (ignored)'))
        );
    }

}



#========================================================================
# END
#========================================================================


#------------------------------------------------------------------------
# $self->process_tree($dir)
#
# Walks the directory tree starting at $dir or the current directory
# if unspecified, processing files as found.
#------------------------------------------------------------------------

sub process_tree {
    my $self = shift;
    my $dir = shift;
    my $running_conf = shift;

    my(
        $destdir,
        $dryrun,
        $ignore,
        $n_mkdir,
        $n_skip,
        $recurse,
        $srcdir,
        $verbose,
    ) = @{ $running_conf }{ qw(
        destdir
        dryrun
        ignore
        n_mkdir
        n_skip
        recurse
        srcdir
        verbose
    )};

    my ($file, $path, $abspath, $check);
    my $target;
    local *DIR;

    my $absdir = join('/', $srcdir ? $srcdir : (), defined $dir ? $dir : ());
    $absdir ||= '.';

    opendir(DIR, $absdir) || do { $self->emit_warn("$absdir: $!\n"); return undef; };

    FILE: while (defined ($file = readdir(DIR))) {
        next if $file eq '.' || $file eq '..';
        $path = defined $dir ? "$dir/$file" : $file;
        $abspath = "$absdir/$file";

        next unless -e $abspath;

        # check against ignore list
        foreach $check (@$ignore) {
            if ($path =~ /$check/) {
                $self->emit_log( yellow(sprintf "  - %-32s (ignored, matches /$check/)\n", $path ) )
                    if $verbose > 1;
                $$n_skip++;
                next FILE;
            }
        }

        if (-d $abspath) {
            if ($recurse) {
                my ($uid, $gid, $mode);

                (undef, undef, $mode, undef, $uid, $gid, undef, undef,
                 undef, undef, undef, undef, undef)  = stat($abspath);

                # create target directory if required
                $target = "$destdir/$path";
                unless (-d $target || $dryrun) {
                    mkpath($target, $verbose, $mode) or
                        die red("Could not mkpath ($target): $!\n");

                    # commented out by abw on 2000/12/04 - seems to raise a warning?
                    # chown($uid, $gid, $target) || warn "chown($target): $!\n";

                    $$n_mkdir++;
                    $self->emit_log( green( sprintf "  + %-32s (created target directory)\n", $path ) )
                        if $verbose;
                }
                # recurse into directory
                $self->process_tree($path, $running_conf);
            }
            else {
                $$n_skip++;
                $self->emit_log( yellow(sprintf "  - %-32s (directory, not recursing)\n", $path ) )
                    if $verbose > 1;
            }
        }
        else {
            $self->process_file($path, $abspath, $running_conf);
        }
    }
    closedir(DIR);
}


#------------------------------------------------------------------------
# $self->process_file()
#
# File filtering and processing sub-routine called by $self->process_tree()
#------------------------------------------------------------------------

sub process_file {
    my $self = shift;
    my ($file, $absfile, $running_conf, %options) = @_;

    my(
        $accept,
        $all,
        $binmode,
        $config,
        $copy,
        $copy_dir,
        $depends,
        $destdir,
        $dryrun,
        $libdir,
        $link,
        $n_copy,
        $n_link,
        $n_proc,
        $n_skip,
        $n_unmod,
        $preserve,
        $replace,
        $srcdir,
        $suffix,
        $template,
        $verbose,
    ) = @{ $running_conf }{ qw(
        accept
        all
        binmode
        config
        copy
        copy_dir
        depends
        destdir
        dryrun
        libdir
        link
        n_copy
        n_link
        n_proc
        n_skip
        n_unmod
        preserve
        replace
        srcdir
        suffix
        template
        verbose
    )};

    my ($dest, $destfile, $filename, $check,
        $srctime, $desttime, $mode, $uid, $gid);
    my ($old_suffix, $new_suffix);
    my $is_dep = 0;
    my $copy_file = 0;
    my $link_file = 0;

    $absfile ||= $file;
    $filename = basename($file);
    $destfile = $file;

    # look for any relevant suffix mapping
    if (%$suffix) {
        if ($filename =~ m/\.(.+)$/) {
            $old_suffix = $1;
            if ($new_suffix = $suffix->{ $old_suffix }) {
                $destfile =~ s/$old_suffix$/$new_suffix/;
            }
        }
    }
    $dest = $destdir ? "$destdir/$destfile" : $destfile;

#    $self->emit_log( "proc $file => $dest\n" );

    unless ($link_file) {
	# check against link list
	foreach my $link_pattern (@$link) {
	    if ($filename =~ /$link_pattern/) {
		$link_file = $copy_file = 1;
		$check = "/$link_pattern/";
		last;
	    }
	}
    }

    unless ($link_file) {
	foreach my $prefix (@$copy_dir) {
	    if ( index($file, "$prefix/") == 0 ) {
		$copy_file = 1;
		$check = "copy_dir: $prefix";
		last;
	    }
	}
    }

    unless ($copy_file) {
        # check against copy list
        foreach my $copy_pattern (@$copy) {
            if ($filename =~ /$copy_pattern/) {
                $copy_file = 1;
                $check = "/$copy_pattern/";
                last;
            }
        }
    }

    # check against acceptance list
    if (not $copy_file and @$accept) {
        unless (grep { $filename =~ /$_/ } @$accept) {
            $self->emit_log( yellow( sprintf "  - %-32s (not accepted)\n", $file ) )
                if $verbose > 1;
            $$n_skip++;
            return;
        }
    }

    # stat the source file unconditionally, so we can preserve
    # mode and ownership
    ( undef, undef, $mode, undef, $uid, $gid, undef,
      undef, undef, $srctime, undef, undef, undef ) = stat($absfile);

    # test modification time of existing destination file
    if (! $all && ! $options{ force } && -f $dest) {
        $desttime = ( stat($dest) )[9];

        if (defined $depends and not $copy_file) {
            my $deptime  = $self->depend_time($file, $depends, $config, $libdir, $srcdir);
            if (defined $deptime && ($srctime < $deptime)) {
                $srctime = $deptime;
                $is_dep = 1;
            }
        }

        if ($desttime >= $srctime) {
            $self->emit_log( yellow( sprintf "  - %-32s (not modified)\n", $file ) )
                if $verbose > 1;
            $$n_unmod++;
            return;
        }
    }

    # check against link list
    if ($link_file) {
        unless ($dryrun) {
            if (link($absfile, $dest) == 1) {
                $copy_file = 0;
            }
            else {
                $self->emit_warn( red("Could not link ($absfile to $dest) : $!\n") );
            }
        }

        unless ($copy_file) {
            $$n_link++;
            $self->emit_log( green( sprintf "  > %-32s (linked, matches $check)\n", $file ) )
                if $verbose;
            return;
        }
    }

    # check against copy list
    if ($copy_file) {
        $$n_copy++;
        unless ($dryrun) {
            copy($absfile, $dest) or die red("Could not copy ($absfile to $dest) : $!\n");

            if ($preserve) {
                chown($uid, $gid, $dest) || $self->emit_warn( red("chown($dest): $!\n") );
                chmod($mode, $dest) || $self->emit_warn( red("chmod($dest): $!\n") );
            }
        }

        $self->emit_log( green( sprintf "  > %-32s (copied, matches $check)\n", $file ) )
            if $verbose;

        return;
    }

    $$n_proc++;

    if ($verbose) {
        $self->emit_log( green( sprintf "  + %-32s", $file) );
        $self->emit_log( green( sprintf " (changed suffix to $new_suffix)") ) if $new_suffix;
        $self->emit_log( "\n" );
    }

    # process file
    unless ($dryrun) {
        $template->process($file, $replace, $destfile,
            $binmode ? {binmode => $binmode} : {})
            || $self->emit_log(red("  ! "), $template->error(), "\n");

        if ($preserve) {
            chown($uid, $gid, $dest) || $self->emit_warn( red("chown($dest): $!\n") );
            chmod($mode, $dest) || $self->emit_warn( red("chmod($dest): $!\n") );
        }
    }
}


#------------------------------------------------------------------------
# $self->dependencies($file, $depends)
#
# Read the dependencies from $file, if defined, and merge in with
# those passed in as the hash array $depends, if defined.
#------------------------------------------------------------------------

sub dependencies {
    my $self = shift;
    my ($file, $depend) = @_;
    my %depends = ();

    if (defined $file) {
        my ($fh, $text, $line);
        open $fh, $file or die "Can't open $file, $!";
        local $/ = undef;
        $text = <$fh>;
        close($fh);
        $text =~ s[\\\n][]mg;

        foreach $line (split("\n", $text)) {
            next if $line =~ /^\s*(#|$)/;
            chomp $line;
            my ($file, @files) = quotewords('\s*:\s*', 0, $line);
            $file =~ s/^\s+//;
            @files = grep(defined, quotewords('(,|\s)\s*', 0, @files));
            $depends{$file} = \@files;
        }
    }

    if (defined $depend) {
        foreach my $key (keys %$depend) {
            $depends{$key} = [ quotewords(',', 0, $depend->{$key}) ];
        }
    }

    return \%depends;
}



#------------------------------------------------------------------------
# $self->depend_time($file, \%depends)
#
# Returns the mtime of the most recent in @files.
#------------------------------------------------------------------------

sub depend_time {
    my $self = shift;
    my ($file, $depends, $config, $libdir, $srcdir) = @_;
    my ($deps, $absfile, $modtime);
    my $maxtime = 0;
    my @pending = ($file);
    my @files;
    my %seen;

    my $DEP_DEBUG = $config->depend_debug();

    # push any global dependencies onto the pending list
    if ($deps = $depends->{'*'}) {
        push(@pending, @$deps);
    }

    $self->emit_log( "    # checking dependencies for $file...\n" )
        if $DEP_DEBUG;

    # iterate through the list of pending files
    while (@pending) {
        $file = shift @pending;
        next if $seen{ $file }++;

        if (File::Spec->file_name_is_absolute($file) && -f $file) {
            $modtime = (stat($file))[9];
            $self->emit_log( "    #   $file [$modtime]\n" )
                if $DEP_DEBUG;
        }
        else {
            $modtime = 0;
            foreach my $dir ($srcdir, @$libdir) {
                $absfile = File::Spec->catfile($dir, $file);
                if (-f $absfile) {
                    $modtime = (stat($absfile))[9];
                    $self->emit_log( "    #   $absfile [$modtime]\n" )
                        if $DEP_DEBUG;
                    last;
                }
            }
        }
        $maxtime = $modtime
            if $modtime > $maxtime;

        if ($deps = $depends->{ $file }) {
            push(@pending, @$deps);
            $self->emit_log( "    #     depends on ", join(', ', @$deps), "\n" )
                if $DEP_DEBUG;
        }
    }

    return $maxtime;
}


#------------------------------------------------------------------------
# read_config($file)
#
# Handles reading of config file and/or command line arguments.
#------------------------------------------------------------------------

sub read_config {
    my $self    = shift;
    my $file    = shift;

    my $NAME    = $self->_get_myname();
    my $verbose = 0;
    my $verbinc = sub {
        my ($state, $var, $value) = @_;
        $state->{ VARIABLE }->{ verbose } = $value ? ++$verbose : --$verbose;
    };
    my $config  = AppConfig->new(
        {
            ERROR  => sub { die(@_, "\ntry `$NAME --help'\n") }
        },
        'help|h'      => { ACTION => sub { $self->help } },
        'src|s=s'     => { EXPAND => EXPAND_ALL },
        'dest|d=s'    => { EXPAND => EXPAND_ALL },
        'lib|l=s@'    => { EXPAND => EXPAND_ALL },
        'cfg|c=s'     => { EXPAND => EXPAND_ALL, DEFAULT => '.' },
        'verbose|v'   => { DEFAULT => 0, ACTION => $verbinc },
        'recurse|r'   => { DEFAULT => 0 },
        'nothing|n'   => { DEFAULT => 0 },
        'preserve|p'  => { DEFAULT => 0 },
        'absolute'    => { DEFAULT => 0 },
        'relative'    => { DEFAULT => 0 },
        'colour|color'=> { DEFAULT => 0 },
        'summary'     => { DEFAULT => 0 },
        'all|a'       => { DEFAULT => 0 },
        'define=s%',
        'suffix=s%',
        'binmode=s',
        'ignore=s@',
        'copy=s@',
        'link=s@',
        'accept=s@',
        'depend=s%',
        'depend_debug|depdbg',
        'depend_file|depfile=s' => { EXPAND => EXPAND_ALL },
        'copy_dir=s@',
        'template_module|module=s',
        'template_anycase|anycase',
        'template_encoding|encoding=s',
        'template_eval_perl|eval_perl',
        'template_load_perl|load_perl',
        'template_interpolate|interpolate',
        'template_pre_chomp|pre_chomp|prechomp',
        'template_post_chomp|post_chomp|postchomp',
        'template_trim|trim',
        'template_pre_process|pre_process|preprocess=s@',
        'template_post_process|post_process|postprocess=s@',
        'template_process|process=s',
        'template_wrapper|wrapper=s',
        'template_recursion|recursion',
        'template_expose_blocks|expose_blocks',
        'template_default|default=s',
        'template_error|error=s',
        'template_debug|debug=s',
        'template_strict|strict',
        'template_start_tag|start_tag|starttag=s',
        'template_end_tag|end_tag|endtag=s',
        'template_tag_style|tag_style|tagstyle=s',
        'template_compile_ext|compile_ext=s',
        'template_compile_dir|compile_dir=s' => { EXPAND => EXPAND_ALL },
        'template_plugin_base|plugin_base|pluginbase=s@' => { EXPAND => EXPAND_ALL },
        'perl5lib|perllib=s@' => { EXPAND => EXPAND_ALL },
    );

    # add the 'file' option now that we have a $config object that we
    # can reference in a closure
    $config->define(
        'file|f=s@' => {
            EXPAND => EXPAND_ALL,
            ACTION => sub {
                my ($state, $item, $file) = @_;
                $file = $state->cfg . "/$file"
                    unless $file =~ /^[\.\/]|(?:\w:)/;
                $config->file($file) }
        }
    );

    # process main config file, then command line args
    $config->file($file) if -f $file;
    $config->args();

    $config;
}


sub ANSI_escape {
    my $attr = shift;
    my $text = join('', @_);
    return join("\n",
        map {
            # look for an existing escape start sequence and add new
            # attribute to it, otherwise add escape start/end sequences
            s/ \e \[ ([1-9][\d;]*) m/\e[$1;${attr}m/gx
                ? $_
                : "\e[${attr}m" . $_ . "\e[0m";
        }
        split(/\n/, $text, -1)   # -1 prevents it from ignoring trailing fields
    );
}

sub _red(@)    { ANSI_escape(31, @_) }
sub _green(@)  { ANSI_escape(32, @_) }
sub _yellow(@) { ANSI_escape(33, @_) }
sub _blue(@)   { ANSI_escape(34, @_) }
sub _white(@)  { @_ }                   # nullop


#------------------------------------------------------------------------
# $self->write_config($file)
#
# Writes a sample configuration file to the filename specified.
#------------------------------------------------------------------------

sub write_config {
    my $self = shift;
    my $file = shift;

    my $NAME = $self->_get_myname();

    open(CONFIG, ">", $file) || die "failed to create $file: $!\n";
    print(CONFIG <<END_OF_CONFIG);
#------------------------------------------------------------------------
# sample .ttreerc file created automatically by $NAME version $VERSION
#
# This file originally written to $file
#
# For more information on the contents of this configuration file, see
#
#     perldoc ttree
#     ttree -h
#
#------------------------------------------------------------------------

# The most flexible way to use ttree is to create a separate directory
# for configuration files and simply use the .ttreerc to tell ttree where
# it is.
#
#     cfg = /path/to/ttree/config/directory

# print summary of what's going on
verbose

# recurse into any sub-directories and process files
recurse

# regexen of things that aren't templates and should be ignored
ignore = \\b(CVS|RCS)\\b
ignore = ^#

# ditto for things that should be copied rather than processed.
copy = \\.png\$
copy = \\.gif\$

# ditto for things that should be linked rather than copied / processed.
# link = \\.flv\$

# by default, everything not ignored or copied is accepted; add 'accept'
# lines if you want to filter further. e.g.
#
#    accept = \\.html\$
#    accept = \\.tt2\$

# options to rewrite files suffixes (htm => html, tt2 => html)
#
#    suffix htm=html
#    suffix tt2=html

# options to define dependencies between templates
#
#    depend *=header,footer,menu
#    depend index.html=mainpage,sidebar
#    depend menu=menuitem,menubar
#

#------------------------------------------------------------------------
# The following options usually relate to a particular project so
# you'll probably want to put them in a separate configuration file
# in the directory specified by the 'cfg' option and then invoke tree
# using '-f' to tell it which configuration you want to use.
# However, there's nothing to stop you from adding default 'src',
# 'dest' or 'lib' options in the .ttreerc.  The 'src' and 'dest' options
# can be re-defined in another configuration file, but be aware that 'lib'
# options accumulate so any 'lib' options defined in the .ttreerc will
# be applied every time you run ttree.
#------------------------------------------------------------------------
# # directory containing source page templates
# src = /path/to/your/source/page/templates
#
# # directory where output files should be written
# dest = /path/to/your/html/output/directory
#
# # additional directories of library templates
# lib = /first/path/to/your/library/templates
# lib = /second/path/to/your/library/templates

END_OF_CONFIG

    close(CONFIG);
    $self->emit_log( "$file created.  Please edit accordingly and re-run $NAME\n" );
}


#------------------------------------------------------------------------
# help()
#
# Prints help message and exits.
#------------------------------------------------------------------------

sub help {
    my $self = shift;
    my $NAME = $self->_get_myname();
    print<<END_OF_HELP;
$NAME $VERSION (Template Toolkit version $Template::VERSION)

usage: $NAME [options] [files]

Options:
   -a      (--all)          Process all files, regardless of modification
   -r      (--recurse)      Recurse into sub-directories
   -p      (--preserve)     Preserve file ownership and permission
   -n      (--nothing)      Do nothing, just print summary (enables -v)
   -v      (--verbose)      Verbose mode. Use twice for more verbosity: -v -v
   -h      (--help)         This help
   -s DIR  (--src=DIR)      Source directory
   -d DIR  (--dest=DIR)     Destination directory
   -c DIR  (--cfg=DIR)      Location of configuration files
   -l DIR  (--lib=DIR)      Library directory (INCLUDE_PATH)  (multiple)
   -f FILE (--file=FILE)    Read named configuration file     (multiple)

Display options:
   --colour / --color       Enable colo(u)rful verbose output.
   --summary                Show processing summary.

File search specifications (all may appear multiple times):
   --ignore=REGEX           Ignore files matching REGEX
   --copy=REGEX             Copy files matching REGEX
   --link=REGEX             Link files matching REGEX
   --copy_dir=DIR           Copy files in dir DIR (recursive)
   --accept=REGEX           Process only files matching REGEX

File Dependencies Options:
   --depend foo=bar,baz     Specify that 'foo' depends on 'bar' and 'baz'.
   --depend_file FILE       Read file dependancies from FILE.
   --depend_debug           Enable debugging for dependencies

File suffix rewriting (may appear multiple times)
   --suffix old=new         Change any '.old' suffix to '.new'

File encoding options
   --binmode=value          Set binary mode of output files
   --encoding=value         Set encoding of input files

Additional options to set Template Toolkit configuration items:
   --define var=value       Define template variable
   --interpolate            Interpolate '\$var' references in text
   --anycase                Accept directive keywords in any case.
   --pre_chomp              Chomp leading whitespace
   --post_chomp             Chomp trailing whitespace
   --trim                   Trim blank lines around template blocks
   --eval_perl              Evaluate [% PERL %] ... [% END %] code blocks
   --load_perl              Load regular Perl modules via USE directive
   --absolute               Enable the ABSOLUTE option
   --relative               Enable the RELATIVE option
   --pre_process=TEMPLATE   Process TEMPLATE before each main template
   --post_process=TEMPLATE  Process TEMPLATE after each main template
   --process=TEMPLATE       Process TEMPLATE instead of main template
   --wrapper=TEMPLATE       Process TEMPLATE wrapper around main template
   --default=TEMPLATE       Use TEMPLATE as default
   --error=TEMPLATE         Use TEMPLATE to handle errors
   --debug=STRING           Set TT DEBUG option to STRING
   --start_tag=STRING       STRING defines start of directive tag
   --end_tag=STRING         STRING defined end of directive tag
   --tag_style=STYLE        Use pre-defined tag STYLE
   --plugin_base=PACKAGE    Base PACKAGE for plugins
   --compile_ext=STRING     File extension for compiled template files
   --compile_dir=DIR        Directory for compiled template files
   --perl5lib=DIR           Specify additional Perl library directories
   --template_module=MODULE Specify alternate Template module

See 'perldoc ttree' for further information.

END_OF_HELP

    exit(0);
}

1;

__END__

=head1 NAME

Template::App::ttree - Backend of ttree

=head1 SYNOPSIS

See L<Template::Tools::ttree|ttree>.

=head1 DESCRIPTION

See L<Template::Tools::ttree|ttree>.

=head1 AUTHORS

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://www.wardley.org>

With contributions from Dylan William Hardison (support for
dependencies), Bryce Harrington (C<absolute> and C<relative> options),
Mark Anderson (C<suffix> and C<debug> options), Harald Joerg and Leon
Brocard who gets everywhere, it seems.

=head1 COPYRIGHT

Copyright (C) 1996-2007 Andy Wardley.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Tools::ttree|ttree>

=cut
