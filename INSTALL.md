Installing the OrthoMCL Pipeline
================================

Installing the OrthoMCL Pipeline can be accomplished by downloading the code with the following command and then following the steps below.

	$ git clone https://github.com/apetkau/orthomcl-pipeline.git

Step 1: Perl Dependencies
-------------------------

The OrthoMCL Pipeline requires Perl as well as the following Perl modules.

* BioPerl
* DBD::mysql
* DBI
* Parallel::ForkManager
* Schedule::DRMAAc
* YAML::Tiny

These can be installed with [cpanm](http://search.cpan.org/dist/App-cpanminus/lib/App/cpanminus.pm) using:

	$ cpanm BioPerl DBD::mysql DBI Parallel::ForkManager YAML::Tiny
	
If you wish to use a grid engine to submit jobs then [Schedule::DRMAAc](http://search.cpan.org/~tharsch/Schedule-DRMAAc-0.81/Schedule_DRMAAc.pod) must be installed.  This must be done manually.


Step 2: Other Dependencies
--------------------------

Additional software dependencies for the pipeline are as follows:

* [OrthoMCL](http://orthomcl.org/common/downloads/software/v2.0/)
   * [BLAST](http://blast.ncbi.nlm.nih.gov/Blast.cgi?CMD=Web&PAGE_TYPE=BlastDocs&DOC_TYPE=Download) (blastall, formatdb)
   * [MCL](http://www.micans.org/mcl/index.html)

The paths to the software dependencies must be setup within the **etc/orthomcl-pipeline.conf** file.  These software dependencies can be checked and the configuration file created using the **scripts/setup.pl** script as below:

	$ perl scripts/setup.pl
	Checking for Software dependencies...
	Checking for OthoMCL ... OK
	Checking for formatdb ... OK
	Checking for blastall ... OK
	Checking for mcl ... OK
	Wrote new configuration to orthomcl-pipeline/scripts/../etc/orthomcl-pipeline.conf
	
The configuration file generated looks like:

```
---
blast:
  F: 'm S'
  b: 100000
  e: 1e-5
  v: 100000
filter:
  max_percent_stop: 20
  min_length: 10
mcl:
  inflation: 1.5
path:
  blastall: '/usr/bin/blastall'
  formatdb: '/usr/bin/formatdb'
  mcl: '/usr/local/bin/mcl'
  orthomcl: '/home/aaron/software/orthomcl/bin'
scheduler: fork
split: 480
```

Step 3: Database Setup
----------------------

The OrthoMCL also requires a SQL database such as [MySQL](http://www.mysql.com/) to be setup in order to load and process some of the results.  Both an account and a separate database need to be created specifically for OrthoMCL.

Once the database is setup, a special OrthoMCL configuration file needs to be generated with parameters and database connection information.  This can be generated automatically with the script **scripts/setup_database.pl**.
