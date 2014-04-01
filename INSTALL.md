The OrthoMCL Pipeline is used to automate running of OrthoMCL

Dependencies:

* OrthoMCL
   * BLAST (blastall, formatdb)
   * MCL
* Perl
* SGE if using SGE Scheduler (set in etc/orthomcl-pipeline.conf)

Perl Libraries to install:

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
