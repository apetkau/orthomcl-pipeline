Installing the OrthoMCL Pipeline
================================

Installing the OrthoMCL Pipeline can be accomplished by downloading the code with the following command and then installing any neccessary dependencies.

	$ git clone https://github.com/apetkau/orthomcl-pipeline.git

Dependencies
------------

In order to install the OrthoMCL Pipeline the following dependencies should be installed.

* [OrthoMCL](http://orthomcl.org/common/downloads/software/v2.0/)
   * [BLAST](http://blast.ncbi.nlm.nih.gov/Blast.cgi?CMD=Web&PAGE_TYPE=BlastDocs&DOC_TYPE=Download) (blastall, formatdb)
   * [MCL](http://www.micans.org/mcl/index.html)
* [MySQL Server](http://www.mysql.com/)
* [Perl](www.perl.org/docs.html)
* SGE or some other [DRMAAc](http://search.cpan.org/~tharsch/Schedule-DRMAAc-0.81/Schedule_DRMAAc.pod) grid scheduler if using SGE Scheduler (set in etc/orthomcl-pipeline.conf)

In addition, the following Perl libraries should be installed.

* BioPerl
* DBD::mysql
* DBI
* Parallel::ForkManager
* Schedule::DRMAAc
* YAML::Tiny

Libraries can all be installed using CPAN or CPANM with:

	$ cpanm BioPerl DBD::mysql DBI Parallel::ForkManager YAML::Tiny

Schedule::DRMAAc needs to be installed manually.

Need to modify parameters in **etc/orthomcl-pipeline.conf.default** and rename to **etc/orthomcl-pipeline.conf**

Need to modify **bin/orthomcl-pipeline.example** to setup environment variables, and rename to **bin/orthomcl-pipeline**.

Need to add **bin/** to the PATH.
