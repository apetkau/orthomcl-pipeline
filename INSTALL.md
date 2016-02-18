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
* Set::Scalar
* Text::Table
* Moose
* SVG
* Algorithm::Combinatorics

These can be installed with [cpanm](http://search.cpan.org/dist/App-cpanminus/lib/App/cpanminus.pm) using:

	$ cpanm BioPerl DBD::mysql DBI Parallel::ForkManager YAML::Tiny Set::Scalar Text::Table Exception::Class Test::Most Test::Warn Test::Exception Test::Deep Moose SVG Algorithm::Combinatorics
	
If you wish to use a grid engine to submit jobs then [Schedule::DRMAAc](http://search.cpan.org/~tharsch/Schedule-DRMAAc-0.81/Schedule_DRMAAc.pod) must be installed and the parameter **sge** must be used for the scheduler in the config file and tests.  This must be done manually and requires installing a grid engine.  A useful guide for how to install a grid engine on Ubuntu can be found at http://scidom.wordpress.com/2012/01/18/sge-on-single-pc/.


Step 2: Other Dependencies
--------------------------

Additional software dependencies for the pipeline are as follows:

* [OrthoMCL](http://orthomcl.org/common/downloads/software/v2.0/) or [OrthoMCL Custom](https://github.com/apetkau/orthomclsoftware-custom) (changes to characters defining sequence identifiers)
   * [BLAST](http://blast.ncbi.nlm.nih.gov/Blast.cgi?CMD=Web&PAGE_TYPE=BlastDocs&DOC_TYPE=Download) (blastall, formatdb).  We have found version `2.2.26` to work best.  Older verions may not work correctly (see issue #7).
   * [MCL](http://www.micans.org/mcl/index.html)

The paths to the software dependencies must be setup within the **etc/orthomcl-pipeline.conf** file.  These software dependencies can be checked and the configuration file created using the **scripts/setup.pl** script as below:

	$ perl scripts/orthomcl-pipeline-setup.pl
	Checking for Software dependencies...
	Checking for OthoMCL ... OK
	Checking for formatdb ... OK
	Checking for blastall ... OK
	Checking for mcl ... OK
	Wrote new configuration to orthomcl-pipeline/scripts/../etc/orthomcl-pipeline.conf
	Wrote executable file to orthomcl-pipeline/scripts/../bin/orthomcl-pipeline
	Please add directory orthomcl-pipeline/scripts/../bin to PATH
	
The configuration file **etc/orthomcl-pipeline.conf** generated looks like:

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
split: 4
```

The parameters in this file can be adjusted to fine-tune the pipeline.  In particular, you may want to adjust the **split: 4** parameter to a reasonable value.  This corresponds to the default number of processing cores to use for the BLAST stage (defines the number of chunks to split the FASTA file into).

You may also want to adjust the **scheduler: fork** to **scheduler: sge** if you are attempting to use a grid scheduler (with DRMAAc) to run OrthoMCL.

Step 3: Database Setup
----------------------

The OrthoMCL also requires a [MySQL](http://www.mysql.com/) database to be setup in order to load and process some of the results.  An account needs to be created specifically for OrthoMCL. A special OrthoMCL configuration file needs to be generated with parameters and database connection information.  This can be generated automatically with the script **scripts/setup_database.pl**. There are two options for running this script as outlined below:

Option 1: If you have a previously created database you can run the script with the option: --no-create-database

	$ perl scripts/orthomcl-setup-database.pl --user orthomcl --password orthomcl --host localhost --database orthomcl --outfile orthomcl.conf --no-create-database
	Connecting to database orthmcl on host orthodb with user orthomcl ...
	OK
	Config file **orthomcl.conf** created.

Option 2: 
	If you want the script to create the datbase for you, run the script without --no-create-database. Prior to running the script the OrthoMCL account must be granted SELECT, INSERT, UPDATE, DELETE, CREATE, CREATE VIEW, INDEX and DROP permissions by logging into the MySQL server as root and executing the following command:
	
	mysql> GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, CREATE VIEW, INDEX, DROP on *.* to orthomcl;

Once the user account is setup, the database can be generated with the same script that creates the configuration file as follows:

	$ perl scripts/orthomcl-setup-database.pl --user orthomcl --password orthomcl --host localhost --database orthomcl --outfile orthomcl.conf
	Connecting to mysql and creating database **orthmcldb** on host orthodb with user orthomcl ...
	OK
	database orthmcl created ...OK
	Config file **orthomcl.conf** created.
	
Either option will generate a file **orthomcl.conf** with database connection information and other parameters.  This file looks like:

```
coOrthologTable=CoOrtholog
dbConnectString=dbi:mysql:orthomcl:localhost:mysql_local_infile=1
dbLogin=orthomcl
dbPassword=orthomcl
dbVendor=mysql 
evalueExponentCutoff=-5
inParalogTable=InParalog
interTaxonMatchView=InterTaxonMatch
oracleIndexTblSpc=NONE
orthologTable=Ortholog
percentMatchCutoff=50
similarSequencesTable=SimilarSequences
```

Step 4: Testing
---------------

Once the OrthoMCL configuration file is generated a full test of the pipeline can be run as follows:

	$ perl t/test_pipeline.pl -m orthomcl.conf -s fork -t /tmp
	Test using scheduler fork
	
	TESTING NON-COMPLIANT INPUT
	TESTING FULL PIPELINE RUN 3
	README:
	Tests case of one gene (in 1.fasta and 2.fasta) not present in other files.
	ok 1 - Expected matched returned groups file
	...

Once all tests have passed then you are ready to start using the OrthoMCL pipeline.  If you wish to test the grid scheduler mode of the pipeline please change **-s fork** to **-s sge** and re-run the tests.

Step 5: Running
---------------

You should now be able to run the pipeline with:

	$ ./bin/orthomcl-pipeline
	Error: no input-dir defined
	Usage: orthomcl-pipeline -i [input dir] -o [output dir] -m [orthmcl config] [Options]
	...

You can now follow the main instructions for how to perform OrthoMCL analyses.
