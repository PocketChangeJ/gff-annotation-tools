#!/usr/bin/perl
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use Parallel::ForkManager;
use List::Util qw/max/;
use strict;

pod2usage("\nAnnotates GFF file with statistics of distances between nucleosome positions identified using DANPOS2 dpos command. Requires a list of *.smooth.positions.xls outputs from DANPOS2 with corresponding sample names. NB. Not to be used with differential DANPOS2 files ie ref_adjust or integrative.xls\n
			 Usage: -gff <9column GFF file> -file <Tab delimited file with list of *.smooth.positions.xls files and labels> -nproc <number of processors>\n") if (($#ARGV<0) && (-t STDIN));

&GetOptions ("file=s"=> \my $listfile,
             "gff=s"=> \my $gff,
				"nproc=s"=> \my $nproc,
	          );

my $fork= new Parallel::ForkManager($nproc);
my $max_processors = $nproc;
`mkdir TMP/`;
`mkdir TMP.OUTPUT/`;
`mkdir TMP.BED/`;

my $gffname = $gff;
   $gffname =~ s/.gff//;           

##Make output file
my $output = "$gffname.DyadCentre.ANNOTATED.gff";   

#Split GFF file into separate files for parallelization
	my $number_of_entries_in_your_dataset = `wc -l $gff`;
	my $number_split = int($number_of_entries_in_your_dataset/$max_processors);
	my $split_Files = `split -d -l $number_split $gff TMP/tmp`;

##Extract full list of nucmap files and compile filenames and counts into arrays
	open(FILELIST, "$listfile") or die "Could not open $listfile";
	my @namearray = ();
	my @filearray = ();
            
	while(my $line = <FILELIST>){
		chomp $line;		
		my ($nucmapfile,$label)=split (/\t+/,$line);
		push(@filearray,$nucmapfile);
		push(@namearray,$label);
	}
	close FILELIST;


#Length of array
my $arraySize = @filearray;

##Open TMP directory and open fork for different files within directory
opendir(DIRECTORY, "TMP/") or die $!; ### open the directory

my $superfork= new Parallel::ForkManager($max_processors);


my $awkcol1 = '$1';
my $awkcol4 = '$4';


while (my $file = readdir(DIRECTORY)) { ### read the directory
	if($file=~/^\./){next;
	}

	#Fork to next file
	my $pid= $superfork->start and next;

	open(IN, "TMP/$file") or die "Could not open TMP/$file";
	open(TEMPOUT, ">TMP.OUTPUT/$file.gff") or die "Could not open TMP.OUTPUT/$file.gff";

	##Read through each individual GFF file as normal
        while(my $gffline = <IN>){
		chomp $gffline;
		my ($col1, $col2, $col3, $col4, $col5, $col6, $col7, $col8, $col9)=split (/\t+/,$gffline);
		
		#Make bed file for each individual interval
		my $tempbedfile = "TMP.BED/$col1.$col4.$col5.bed";
		open(TEMP, ">$tempbedfile") or die "Could not open $tempbedfile";
		print TEMP "$col1\t$col4\t$col5\n";

		print TEMPOUT "$col1\t$col2\t$col3\t$col4\t$col5\t$col6\t$col7\t$col8\t$col9";

                ##Intersect with each nucmap file and calculate inter-dyad distances
                	foreach(my $i = 0; $i <= $arraySize - 1; $i += 1){
				my $label = $namearray[$i];
					chomp $label;
				my $intersectcommand =  `grep -v "start" $filearray[$i] | intersectBed -a - -b $tempbedfile | awk '{print $awkcol1 "\t" $awkcol4 "\t" $awkcol4}' > $tempbedfile.$label.bed`;
		
				#Calculate distances between nucleosomes within that GFF interval
				my $distancecommand =  `bedtools closest -d -io -a $tempbedfile.$label.bed -b $tempbedfile.$label.bed | cut -f 7 | st --complete | sed -n 2p`;
				chomp $distancecommand;
				my ($number, $min, $q1, $median, $q3, $max, $sum, $mean, $stddev, $stderr)=split (/\t+/,$distancecommand); 
			


				##Only keep counts that have 2 or more dyads identified
				if($number >= 2){
				print TEMPOUT ";$label\_NucleosomeDyads=$number;$label\_InterDyadDistance.Median=$median;$label\_InterDyadDistance.Mean=$mean;$label\_InterDyadDistance.Stdev=$stddev";
				}
				else{
				print TEMPOUT ";$label\_NucleosomeDyads=NA;$label\_InterDyadDistance.Median=NA;$label\_InterDyadDistance.Mean=NA;$label\_InterDyadDistance.Stdev=NA";
				}

				`rm $tempbedfile.$label.bed`;
			}

		print TEMPOUT "\n";
		`rm $tempbedfile`;
	}
                    

######### end fork ###############
$superfork->finish;
}
$superfork->wait_all_children;


## Concatenate all sub-GFF files
`cat TMP.OUTPUT/*.gff | sort -k 1 > $output`;

#Delete folder with temp files
`rm -r TMP/`;
`rm -r TMP.BED/`;
`rm -r TMP.OUTPUT`;
