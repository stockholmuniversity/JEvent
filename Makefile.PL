use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'JEvent',
    'VERSION_FROM'	=> 'JEvent.pm', # finds $VERSION
    'PREREQ_PM'		=> {Net::SPOCP => '0.10', Data::UUID => 0, XML::Stream => '1.22-1', Net::XMPP => '1.0-1'},
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'JEvent.pm', # retrieve abstract from module
       AUTHOR     => 'Leif Johansson <leifj@it.su.se>') : ()),
);
