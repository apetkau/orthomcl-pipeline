OrthoMCL Pipeline
=================

Automates running of OrthoMCL software from http://orthomcl.org/orthomcl/

Usage
-----

The brief overview of running the OrthoMCL pipeline is as follows:

1. Setup MySQL database for OrthoMCL.  Please see the [OrthoMCL Documentation](http://orthomcl.org/common/downloads/software/v2.0/UserGuide.txt) for more information.

2. Run the following command to verify the database setup and generate an OrthoMCL configuration file.

   ```bash
   perl scripts/orthomcl-setup-database.pl --user orthomcl_database_user --password orthomcl_database_password --host orthomcl_database_host --database orthomcl_database > orthomcl.conf
   ```

3. Run the following command to start OrthoMCL.

   ```bash
   perl scripts/orthomcl-pipeline.pl -i input/ -o output/ -m orthomcl.conf --nocompliant
   ```

   Where `input/` contains a set of gene annotations in FASTA format, one file per genome (e.g. `genome1.fasta`, `genome2.fasta`, must end in .fasta), `output/` is the location to store the OrthoMCL output files, `orthomcl.conf` is the OrthoMCL configuration file generated in step 2, and `--nocompliant` adjusts gene names in fasta files to make them unique.

A walkthrough of using the OrthoMCL pipeline on example data can be found at https://github.com/apetkau/microbial-informatics-2014/tree/master/labs/orthomcl and a virtual machine containing a pre-installed version of the OrthoMCL pipeline can be found at https://www.corefacility.ca/wiki/bin/view/BioinformaticsWorkshop/Software2014.

Installation
------------

Please see the [Installation](INSTALL.md) documentation for details on how to install.

Detailed Usage
--------------

```
Usage: orthomcl-pipeline -i [input dir] -o [output dir] -m [orthmcl config] [Options]
	Options:
	-i|--input-dir: The input directory containing the files to process.
	-o|--output-dir: The output directory for the job.
	-s|--split:  The number of times to split the fasta files for blasting
	-c|--config:  The main config file (optional, overrides default config).
	-m|--orthomcl-config:  The orthomcl config file
	--compliant:  If fasta data is already compliant (headers match, etc) (default).
	--nocompliant:  If fasta data is not already compliant (headers match, etc).
	--print-config: Prints default config file being used.
	--print-orthomcl-config:  Prints example orthomcl config file.
	--yes: Automatically answers yes to every question (could overwrite/delete old data).
	--scheduler: Defined scheduler (sge or fork).
	--no-cleanup: Does not remove temporary tables from database.
	-h|--help:  Show help.

	Examples:
	orthomcl-pipeline -i input/ -o output/ -m orthomcl.config
		Runs orthomcl using the input fasta files under input/ and orthomcl.confg as config file.
		Places data in output/.  Gets other parameters (blast, etc) from default config file.

	orthomcl-pipeline -i input/ -o output/ -m orthomcl.config -c orthomcl-pipeline.conf
		Runs orthomcl using the given input/output directories.  Overrides parameters (blast, etc)
		from file orthomcl-pipeline.conf.

	orthomcl-pipeline --print-config
		Prints default orthomcl-pipeline.conf config file (which can then be changed).

	orthomcl-pipeline --print-orthomcl-config
		Prints orthomcl example config file which must be changed to properly run.

	orthomcl-pipeline -i input/ -o output/ -m orthomcl.confg --compliant
		Runs orthmcl with the given input/output/config files.
		Skips the orthomclAdjustFasta stage on input files.

	orthomcl-pipeline -i input/ -o output/ -m orthomcl.confg --no-cleanup
		Runs orthmcl with the given input/output/config files.
		Does not cleanup temporary tables.
```
