use strict;
use warnings;
use Module::Build;

{ # define a handy rscan_dir function
    my $manifest_skip = qr/(?!)/; # this regex always fails 
    if (open my $fh, '<', 'MANIFEST.SKIP')
    {
        # map /.*/ chomps newlines, since . doesn't match EOLs
        $manifest_skip = join '|', map /(.*)/, <$fh>;
        close $fh;
        $manifest_skip = qr/$manifest_skip/;
    }

    sub rscan_dir
    {
        grep !/$manifest_skip/, @{ Module::Build->rscan_dir(@_) };
    }
}

my $builder = Module::Build->new
    (module_name         => 'Net::SSH::Mechanize',
     license             => 'artistic',
     dist_author         => 'Nick Stokoe <npw@cpan.org>',
     dist_version_from   => 'lib/Net/SSH/Mechanize.pm',
     dist_abstract       => 'Asynchronous ssh command invocation',
     create_readme       => 1,
     create_makefile_pl  => 'traditional',
     configure_requires => 
     {
         'Module::Build' => 0.28,
     },
     build_requires => 
     {
         'Module::Build' => 0.28,
     },
     requires => 
     {
         'Test::More' => 0,
         'version'    => 0.77,
         'Moose' => 0,
         'MooseX::Params::Validate' => 0,
         'AnyEvent' => 0,
         'AnyEvent::Subprocess' => 0,
         'Coro' => 0, # for Multi
     },
     recommends => 
     {
         'Test::Pod' => 1.14,
         'Test::Pod::Coverage' => 1.04,
     },
     test_files         => [ rscan_dir('t', '\.t$'),
                             rscan_dir('xt', '\.t$') ],
     add_to_cleanup      => [ 'Net-SSH-Mechanize-*' ],
    );

$builder->create_build_script();
