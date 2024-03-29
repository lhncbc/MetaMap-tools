% File:     filter_mrconso.pl
% Module:   Filter Mrconso
% Author:   Lan
% Purpose:  Create less redundant versions of (English) mrcon by filtering
%           mrconso (essentially mrcon with source information).
%
%           Basic (lexical) filtering consists of removing strings for a concept
%           which are effectively the same as another string for the concept.
%           The normalization process consists of the following steps:
%             1. removal of (left []) parentheticals;
%             2. removal of multiple meaning designators (<n>);
%             3. NOS normalization;
%             4. syntactic uninversion;
%             5. conversion to lowercase;
%             6. replacement of hyphens with spaces; and
%             7. stripping of possessives.
%           Some right parentheticals used to be stripped, but no longer are.
%           Lexical Filtering Examples:
%           The concept "Abdomen" has strings "ABDOMEN" and "Abdomen, NOS".
%           Similarly, the concept "Lung Cancer" has string "Cancer, Lung".
%           And the concept "1,4-alpha-Glucan Branching Enzyme" has a string
%           "1,4 alpha Glucan Branching Enzyme".
%
%           Term-Status filtering filters out all lines whose Term Status
%           is either "s" (suppressible synonym) or "p" (suppressible preferred name).
%           Concepts with Term Status of "s" are filtered out regardless of whether
%           the "s" was originally assigned by the Metathesaurus developers or the
%           suppressing Java code, which now takes into account the RRF suppression.
%           This filtering should be done for both the strict and relaxed models,
%           and is invoked with the "s" flag.
%
%           Strict filtering additionally involves filtering out terms by syntax:
%           Concepts which parse into more than one MSU (minimal syntactic unit), i.e.,
%           more than one phrase (with certain exceptions involving prepositional
%           phrases -- see is_syntactically_simple/2).
%           Alternative criteria may be considered.
%           These concepts are filtered out because they would never be identified by MetaMap.
%
%           Term-Type filtering is no longer done.

:- module(filter_mrconso,[
	go/0,
	stop_filter_mrconso/0
    ]).

:- use_module(skr_lib(addportray),[
	add_portray/1
    ]).

:- use_module(skr_lib(server_choice), [
	get_server_streams/1
   ]).

:- use_module(skr_db(db_access),[
	default_release/1,
	initialize_db_access/0
    ]).

% :- use_module(lexicon(lex_access),[
% 	initialize_lexicon/2
%     ]).

:- use_module(tagger(tagger_access),[
	tag_text/5
    ]).

:- use_module(metamap(metamap_parsing), [
	generate_syntactic_analysis_plus/4
    ]).

:- use_module(metamap(metamap_tokenization), [
	get_phrase_item_name/2,
	get_phrase_item_feature/3
    ]).

:- use_module(mm_tools_lib(mwi_utilities),[
	announce_lines/4,
	compute_unique_filename/3,
	fget_non_null_line/2,
	get_progress_bar_interval/1,
	get_total_lines/1,
	normalize_meta_string/3,
	parse_record/3
    ]).

:- use_module(skr_lib(nls_strings), [
	split_string_completely/3
    ]).

:- use_module(skr_lib(nls_system), [
	get_control_options_for_modules/2,				    
	toggle_control_options/1,
	set_control_values/2,
	display_control_options_for_modules/2,
	display_current_control_options/2,
	control_option/1,
	control_value/2,
	parse_command_line/1,
	interpret_options/4,
	interpret_args/4,
	get_from_iargs/4
    ]).

% :- use_module(skr_lib(efficiency),[
% 	maybe_atom_gc/3
%     ]).


:- use_module(skr_lib(nls_strings),[
	atom_codes_list/2,
	portray_strings_double_quoted/1
    ]).

:- use_module(skr_lib(sicstus_utils),[
        ttyflush/0
    ]).

:- use_module(library(between),[
	between/3
   ]).

:- use_module(library(file_systems),[
	close_all_streams/0
    ]).

:- use_module(library(lists),[
	append/2,
	last/2,
	rev/2,
	selectchk/3
    ]).

/* go
   go(+HaltFlag)
   go(+HaltFlag, +CommandLineTerm)

go/0 is the executive predicate for filter_mrconso.
go/0 uses go/1 with HaltFlag set to halt.
go/1 parses the command line and calls go/2 which controls the processing.  */

go :-
	go(halt).

go(HaltOption) :-
	parse_command_line(CLTerm),
	go(HaltOption, CLTerm).

go(HaltOption, command_line(Options,Args)) :-
	add_portray(portray_strings_double_quoted),
	( initialize_filter_mrconso(Options,Args,InterpretedArgs) ->
	       ( filter_mrconso(InterpretedArgs) ->
	         true
	       ; true
	       )
	; usage
	),
	stop_filter_mrconso,
	( HaltOption == halt ->
	  halt
	; true
	).


/* initialize_filter_mrconso(+Options, +Args, -InterpretedArgs)

initialize_filter_mrconso/3 interprets command line options and arguments
(opening files as necessary), and sets and displays the Filter Mrconso
control options discovered.  It returns InterpretedArgs for later use
(e.g., the stream associated with a file).  */

initialize_filter_mrconso(Options, Args, InterpretedArgs) :-
	get_control_options_for_modules([filter_mrconso], AllOptions),
	interpret_options(Options, AllOptions, filter_mrconso, IOptions),
	\+ memberchk(iopt(help,_), IOptions),
	ArgSpec = [aspec(infile,mandatory,file,read,no_default,
			 'Input file similar to mrconso.'),
		   aspec(outfile,mandatory,file,write,no_default,
			 'Output file')
		  ],
	interpret_args(IOptions, ArgSpec, Args, InterpretedArgs),
	toggle_control_options(IOptions),
	set_control_values(IOptions, InterpretedArgs),
	default_release(Release),
	display_current_control_options(filter_mrconso, Release),
	initialize_filter_mrconso,
	!.

initialize_filter_mrconso :-
	(( control_option(strict_filtering)
	 ; control_option(dump_syntax_only)
	 ) ->
	   % initialize_lexicon(_,_),
	   initialize_db_access
	 ; true
	),
	% compile_mrrank_file,
	!.
initialize_filter_mrconso :-
	format('~NERROR: initialize_filter_mrconso/0 failed.~n', []),
	!,
	stop_filter_mrconso,
	fail.

% compile_mrrank_file :-
% 	( control_value(mrrank_file, FileName) ->
% 	  compile(FileName)
% 	; format(user_output, 'Must specify mrrank file with -R option.\n', []),
% 	  flush_output(user_output),
% 	  abort
% 	).
	

stop_filter_mrconso :- close_all_streams.


/* usage

usage/0 displays filter_mrconso usage.  */

usage :-
	format('~nUsage: filter_mrconso [<options>] <infile> <outfile>~n~n', []),
	format('  <infile> should normally be mrconso.eng.0 or the like, and~n', []),
	format('  <outfile> is <infile> filtered.~n~n', []),
	display_control_options_for_modules(filter_mrconso, []).

/* filter_mrconso(+InterpretedArgs)

filter_mrconso/1 controls all filter_mrconso processing.  */

filter_mrconso(InterpretedArgs) :-
	get_from_iargs(infile,  name,   InterpretedArgs, InputFile),
	get_from_iargs(infile,  stream, InterpretedArgs, InputStream),
	get_from_iargs(outfile, name,   InterpretedArgs, OutputFile),
	get_from_iargs(outfile, stream, InterpretedArgs, OutputStream),
	get_progress_bar_interval(Interval),
	get_total_lines(TotalLines),
	get_server_streams(TaggerServerStream-_WSDServerStream),
	format('Processing ~a --> ~a.~n', [InputFile,OutputFile]),
	process_input(InputStream, InputFile, TaggerServerStream, OutputStream,
		      Interval, TotalLines,
		      NormCounts, TSCounts, SyntaxCounts),
	write_normalization_counts(NormCounts, OutputStream),
	write_term_status_counts(TSCounts, OutputStream),
	write_syntax_counts(SyntaxCounts, OutputStream),
	( control_option(end_of_processing) ->
	  format(OutputStream, '<<< EOT >>>~n', [])
	; true
	),
	close(OutputStream),
	close(InputStream),
	close(TaggerServerStream),
	!.

/* process_input(+InputStream, +OutputStream)

process_input/2 reads lines from InputStream and writes filtered lines to
OutputStream.  */

process_input(InputStream, InputFile, TaggerServerStream, OutputStream,
	      Interval, TotalLines,
	      NormCountsOut, TSCountsOut, SyntaxCountsOut) :-
	fget_non_null_line(InputStream, Line0),
	parse_line(Line0, CUI0, LineTerm),
	NumLines is 1,
	NormCountsIn = [],
	TSCountsIn = [p-0,s-0],
	SyntaxCountsIn = [pref-0,synt-0],
	process_cui_lui(InputStream, InputFile, TaggerServerStream, OutputStream,
			NumLines, Interval, TotalLines,
			CUI0, [LineTerm],
			NormCountsIn, NormCountsOut,
			TSCountsIn, TSCountsOut,
			SyntaxCountsIn, SyntaxCountsOut).

/* parse_line(+Line, -CUI, -LUI, -TS, -STT, -TTY, -STR, -SAB, -CODE)

parse_line/9 extracts CUI, ... from Line.  */

parse_line(LineString, CUIAtom, LineTerm) :-
	% parse_record(LineString, "|",
	%	     [CLSString,_N,TSString,STTString,STRString,SABString,TTYString,CODEString]),
	parse_record(LineString, "|",
		     [CUIString,_LATString,TSString,LUIString,STTString,
		      SUIString,_ISPREFString,AUIString,_SAUIString,
		      _SCUIString,_SDUIString,SABString,TTYString,CODEString,
		      STRString,_SRLString,_SUPPRESSString,_CVFString]),
	atom_codes_list([TSAtom,STTAtom,SABAtom,TTYAtom,CODEAtom],
			[TSString,STTString,SABString,TTYString,CODEString]),
	atom_codes_list([CUIAtom,LUIAtom,SUIAtom,AUIAtom],
			[CUIString,LUIString,SUIString,AUIString]),
	normalize_meta_string(STRString, NormSTRString, NMTypes),
	atom_codes(STRAtom, STRString),
	atom_codes(NormSTRAtom, NormSTRString),
	% get_mrrank(SABAtom, TTYAtom, LineString, MRRank),
	line_term(NormSTRAtom,CUIAtom,SABAtom,LUIAtom,SUIAtom,AUIAtom,LineString,
		  TSAtom,STTAtom,TTYAtom,STRAtom,CODEAtom,NMTypes,
		  LineTerm),
	!.
parse_line(LineString, _CUIAtom, _LineTerm) :-
	format('~NFatal error: Bad input ~s~n', [LineString]),
	stop_filter_mrconso,
	halt.

% encapsulate the clinfo/13 structure
line_term(NormSTRAtom,CUIAtom,SABAtom,LUIAtom,SUIAtom,AUIAtom,LineString,
	  TSAtom,STTAtom,TTYAtom,STRAtom,CODEAtom,NMTypes,
	  clinfo(NormSTRAtom,CUIAtom,SABAtom,LUIAtom,SUIAtom,AUIAtom,LineString,
		 TSAtom,STTAtom,TTYAtom,STRAtom,CODEAtom,NMTypes)).

/* process_cui_lui(+InputStream, +OutputStream, +CUI, +LUI, +CLInfoLines)

   
   ***     WARNING     WARNING     WARNING     WARNING     WARNING     ***
   
      The current implementation processes according to CUI only.
      This should have the effect of filtering out more strings at the expense
      of not necessarily having a representative for each LUI.
   
   ***     WARNING     WARNING     WARNING     WARNING     WARNING     ***

   
   process_cui_lui/6 accumulates CLInfoLines (clinfo/13 terms) by
   reading Line from InputStream, extracting some fields, forming the
   normalized Meta string NMSTR) with the same concept id (CUI) and
   term id (LUI) as the input.  When a new CUI,LUI pair is encountered, the
   accumulated information is filtered "removing" duplicate NMSTRs and written to
   OutputStream (prefixed by y to indicate survival from filtering).
   Duplicates are written to OutputStream with a n prefix.
   The information from the current line is saved for further processing.
*/


process_cui_lui(InputStream, InputFile, TaggerServerStream, OutputStream,
		NumLinesIn, Interval, TotalLines,
		CUI0, CLInfoLines0,
		NormCountsIn, NormCountsOut,
		TSCountsIn, TSCountsOut,
		SyntaxCountsIn, SyntaxCountsOut) :-
	( fget_non_null_line(InputStream, Line) ->
	  NumLinesNext is NumLinesIn + 1,
	  % format(user_output, '~d:~a~n', [NumLinesNext,Line]),
	  announce_lines(NumLinesNext, Interval, TotalLines, InputFile),
	  parse_line(Line, CUI, NextLineTerm),
	  % LAT="ENG",   % limit to English; no need with mrconso.eng
	  % atom_codes(STR, STRString),
	  % normalize_meta_string(STRString, NMSTRString, NMTypes),
	  % format(user_output,
	  %	 'NORM|~w|~w|~w|~s|~s|~w~n',
	  %	 [CUI,LUI,SUI,STRString, NMSTRString, NMTypes]),
	  % atom_codes(NMSTR, NMSTRString),
	  % MRRANK is no longer used because we 
	  % Include the MRRANK score in the clinfo/13 term
	  % get_mrrank(SAB, TTY, Line, MRRank),
	  % format(user_output, '~n~w~n', [NextLine]),
	  ( CUI == CUI0 ->
	    process_cui_lui(InputStream, InputFile, TaggerServerStream, OutputStream,
			    NumLinesNext, Interval, TotalLines,
			    CUI0, [NextLineTerm|CLInfoLines0],
			    NormCountsIn, NormCountsOut,
			    TSCountsIn, TSCountsOut,
			    SyntaxCountsIn, SyntaxCountsOut)
	  ; filter_and_write(TaggerServerStream, OutputStream, CLInfoLines0,
			     NormCountsIn, NormCountsNext,
			     TSCountsIn, TSCountsNext,
			     SyntaxCountsIn, SyntaxCountsNext),			     
	    process_cui_lui(InputStream, InputFile, TaggerServerStream, OutputStream,
			    NumLinesNext, Interval, TotalLines,
			    CUI, [NextLineTerm],
			    NormCountsNext, NormCountsOut,
			    TSCountsNext, TSCountsOut,
			    SyntaxCountsNext, SyntaxCountsOut)
	  )
	  % If there are no more lines to read, simply write out what's been accumulated.
	; filter_and_write(TaggerServerStream, OutputStream, CLInfoLines0,
			   NormCountsIn, NormCountsOut,
			   TSCountsIn, TSCountsOut,
			   SyntaxCountsIn, SyntaxCountsOut)
	).


/* filter_and_write(+OutputStream, +CLInfoLines)

filter_and_write/3 removes entries (clinfo/13 terms) from CLInfoLines
according to several criteria:
  strings with the same normalized Meta string (NMSTR),
  strings with particular term types (unless 'X' is specified;
  Note: this option is now obsolete, because we no longer do term-type filtering!
  strings with particular term status, and
  strings with complex syntax (several phrases rather than one)
Every entry is written to OutputStream with an initial y or n
indicating if it survived filtering. */

filter_and_write(TaggerServerStream, OutputStream,   CLInfoLines0,
		 NormCountsIn,   NormCountsOut,
		 TSCountsIn,     TSCountsOut,
		 SyntaxCountsIn, SyntaxCountsOut) :-
	% First, find the CUI for this group of lines
	CLInfoLines0 = [First|_],
	line_term(_NMSTR,CUI,_SAG,_LUI,_SUI,_AUI,_LineData,
		  _TS,_STT,_TTY,_STR,_CODE,_NMTypes,
		  First),
	% Next, find all the preferred names of the CUI.
	find_all_preferred(CLInfoLines0, CUI, [], AllPreferred0),
	sort(AllPreferred0, AllPreferred1),
	length(AllPreferred0, AllPreferred0Count),
	% format(user_output, '~w has ~d original preferred string(s)~n', [CUI,AllPreferred0Count]),
	% filter out preferred names, keeping only one per SAB.
	filter_nmstr_dups(AllPreferred1, OutputStream,_NCI, _NCN, _NE0, AllPreferred),
	length(AllPreferred, AllPreferredCount),
	format(user_output, '~w preferred string counts: ~d/~d~n',
	       [CUI,AllPreferred0Count,AllPreferredCount]),
	% Next, do term-status filtering
	% ntss
	filter_by_term_status(CLInfoLines0,  OutputStream,
			      TSCountsIn,    TSCountsNext,
			      TSExclusions0, CLInfoLines1),
	% then do lexical filtering
	% (type filtering is done first to prevent the filtering out of a good
	% lexical representative with a bad type)
	% nnorm
	sort(CLInfoLines1, CLInfoLines2),
	% CLInfoLines2 = CLInfoLines1,
	% filtering out duplicate strings is no longer done.
	% This change was due to Sina Madani and Safa Fathiamini's concern
	% that many strings in the NCI/CCN termgroup were filtered out.
	filter_nmstr_dups(CLInfoLines2, OutputStream,
			   NormCountsIn, NormCountsNext, NormExclusions0, CLInfoLines3),
	% NormExclusions0 = [],
	% NormCountsNext = NormCountsIn,
	( ( control_option(strict_filtering)
	  ;  control_option(dump_syntax_only)
	  ) ->
	  % finally do syntactic filtering
	  % nsynt
	  filter_syntactically(CLInfoLines3, TaggerServerStream, OutputStream,
			       SyntaxCountsIn, SyntaxCountsNext, SyntaxExclusions0, CLInfoLines4)
	; CLInfoLines4 = CLInfoLines3,
	  SyntaxCountsNext = SyntaxCountsIn,
	  SyntaxExclusions0 = []
	),
	% further filtering?
	( control_option(dump_syntax_only) ->
	  SyntaxCountsOut = SyntaxCountsNext
	  % Find all excluded preferred terms, i.e., those that are NOT in CLInfoLines.
	; find_excluded_preferred(AllPreferred, CLInfoLines4, ExcludedPreferred),
	  restore_all_preferred(CLInfoLines4, ExcludedPreferred, CLInfoLines5,
				TSCountsNext,     TSCountsOut,
				NormCountsNext,   NormCountsOut,
				SyntaxCountsNext, SyntaxCountsOut,
				TSExclusions0, NormExclusions0, SyntaxExclusions0,
				TSExclusions1, NormExclusions1, SyntaxExclusions1),
	  sort(CLInfoLines5, CLInfoLines6), 
	  write_exclusions(OutputStream, TSExclusions1, NormExclusions1, SyntaxExclusions1),
	  write_clinfo_lines(CLInfoLines6, OutputStream)
	),
	!.

write_exclusions(OutputStream, TSExclusions, NormExclusions, SyntaxExclusions) :-
%	  write_term_status_exclusions(TSExclusions, OutputStream),
%	  write_normalization_exclusions(NormExclusions, OutputStream),
%	  write_syntax_exclusions(SyntaxExclusions, OutputStream).
	write_exclusions(TSExclusions,     tss, OutputStream),
	write_exclusions(NormExclusions,   norm, OutputStream),
	write_exclusions(SyntaxExclusions, synt, OutputStream).

write_exclusions([], _ExclusionType, _OutputStream).
write_exclusions([FirstCLInfoTerm|RestCLInfoTerms], ExclusionType, OutputStream) :-
	line_term(NMSTR,_CUI,_SAB,_LUI,_SUI,_AUI,LineData,
		  _TS,_STT,_TTY,_STR,_CODE,NMTypes,
		  FirstCLInfoTerm),	
	format(OutputStream, 'n~a|~s|~p|~a~n', [ExclusionType,LineData,NMTypes,NMSTR]),
	write_exclusions(RestCLInfoTerms, ExclusionType, OutputStream).
	
%%% write_term_status_exclusions([], _OutputStream).
%%% write_term_status_exclusions([CLInfoLine|Rest], OutputStream) :-
%%% 	line_term(NMSTR,_CUI,_LUI,_SUI,LineData,
%%% 		  _TS,_STT,_TTY,_STR,_SAB,_CODE,NMTypes,
%%% 		  CLInfoLine),
%%% 	format(OutputStream, 'ntss|~s|~p|~a~n', [LineData,NMTypes,NMSTR]),
%%% 	write_term_status_exclusions(Rest, OutputStream).
%%% 
%%% write_normalization_exclusions([], _OutputStream).
%%% write_normalization_exclusions([CLInfoLine|Rest], OutputStream) :-
%%% 	line_term(NMSTR,_CUI,_LUI,_SUI,LineData,
%%% 		  _TS,_STT,_TTY,_STR,_SAB,_CODE,NMTypes,
%%% 		  CLInfoLine),
%%% 	format(OutputStream, 'nnorm|~s|~p|~a~n', [LineData,NMTypes,NMSTR]),
%%% 	write_normalization_exclusions(Rest, OutputStream).
%%% 
%%% write_syntax_exclusions([], _OutputStream).
%%% write_syntax_exclusions([CLInfoLine|Rest], OutputStream) :-
%%% 	line_term(NMSTR,_CUI,_LUI,_SUI,LineData,
%%% 		  _TS,_STT,_TTY,_STR,_SAB,_CODE,NMTypes,
%%% 		  CLInfoLine),
%%% 	format(OutputStream, 'nsynt|~s|~p|~a~n', [LineData,NMTypes,NMSTR]),          
%%% 	write_syntax_exclusions(Rest, OutputStream).

% CLInfoLines is the list of remaining strings after term-status filtering,
% lexical (normalization) filtering, and syntactic filtering.
% If at least one string remains (which is the case if CLInfoLines unifies with [H|T]),
% but the preferred name was excluded i.e., \+ memberchk(Preferred, CLInfoLines3),
% then restore the preferred concept.
% Also delete it from whichever exclusion list it was in,
% and update the counts accordingly.

% If no strings in this CUI remain, do not restore any of the preferred names.
restore_all_preferred([], AllPreferred, [],
		      TSCounts,     TSCounts,
		      NormCounts,   NormCounts,
		      SyntaxCounts, SyntaxCounts,
		      TSExclusions, NormExclusions, SyntaxExclusions,
		      TSExclusions, NormExclusions, SyntaxExclusions) :-
	announce_no_restore(AllPreferred).
% Some strings in the CUI remain, so restore the excluded preferred names.
restore_all_preferred([H|T], ExcludedPreferred, CLInfoLinesOut,
		      TSCountsIn,     TSCountsOut,
		      NormCountsIn,   NormCountsOut,
		      SyntaxCountsIn, SyntaxCountsOut,
		      TSExclusionsIn, NormExclusionsIn, SyntaxExclusionsIn,
		      TSExclusionsOut, NormExclusionsOut, SyntaxExclusionsOut) :-
		CLInfoLinesIn = [H|T],
		restore_all_preferred_aux(ExcludedPreferred, CLInfoLinesIn, CLInfoLinesOut,
					  TSCountsIn,     TSCountsOut,
					  NormCountsIn,   NormCountsOut,
					  SyntaxCountsIn, SyntaxCountsOut,
					  TSExclusionsIn, NormExclusionsIn, SyntaxExclusionsIn,
					  TSExclusionsOut, NormExclusionsOut, SyntaxExclusionsOut).

restore_all_preferred_aux([], CLInfoLines, CLInfoLines,
			  TSCounts,     TSCounts,
			  NormCounts,   NormCounts,
			  SyntaxCounts, SyntaxCounts,
			  TSExclusions, NormExclusions, SyntaxExclusions,
			  TSExclusions, NormExclusions, SyntaxExclusions).
restore_all_preferred_aux([FirstExcludedPreferred|RestExcludedPreferred],
			  CLInfoLinesIn, CLInfoLinesOut,
			  TSCountsIn,     TSCountsOut,
			  NormCountsIn,   NormCountsOut,
			  SyntaxCountsIn, SyntaxCountsOut,
			  TSExclusionsIn, NormExclusionsIn, SyntaxExclusionsIn,
			  TSExclusionsOut, NormExclusionsOut, SyntaxExclusionsOut) :-
	restore_one_preferred(FirstExcludedPreferred,
			      CLInfoLinesIn, CLInfoLinesNext,
			      TSCountsIn,     TSCountsNext,
			      NormCountsIn,   NormCountsNext,
			      SyntaxCountsIn, SyntaxCountsNext,
			      TSExclusionsIn, NormExclusionsIn, SyntaxExclusionsIn,
			      TSExclusionsNext, NormExclusionsNext, SyntaxExclusionsNext),
	restore_all_preferred_aux(RestExcludedPreferred,
				  CLInfoLinesNext, CLInfoLinesOut,
				  TSCountsNext,     TSCountsOut,
				  NormCountsNext,   NormCountsOut,
				  SyntaxCountsNext, SyntaxCountsOut,
				  TSExclusionsNext, NormExclusionsNext, SyntaxExclusionsNext,
				  TSExclusionsOut, NormExclusionsOut, SyntaxExclusionsOut).

restore_one_preferred(FirstExcludedPreferred,
		      CLInfoLinesIn, CLInfoLinesNext,
		      TSCountsIn,     TSCountsNext,
		      NormCountsIn,   NormCountsNext,
		      SyntaxCountsIn, SyntaxCountsNext,
		      TSExclusionsIn, NormExclusionsIn, SyntaxExclusionsIn,
		      TSExclusionsNext, NormExclusionsNext, SyntaxExclusionsNext) :-
	line_term(NMSTR,CUI,SAB,LUI,SUI,AUI,OrigLineData,
		  _OrigTermStatus,STT,TTY,STR,CODE,NMTypes,
		  FirstExcludedPreferred),
	update_syntax_count(pref, 1, SyntaxCountsIn, SyntaxCountsInOut),
	RestoredTermStatus = 'P',
	% change '|p|' to '|P|' in the LineData
	update_term_status(OrigLineData, RestoredLineData),
	% RestoredPreferred is a copyh of FirstExcludedPreferred,
	% other than that the Term Status is changed from "p" to "P"
	line_term(NMSTR,CUI,SAB,LUI,SUI,AUI,RestoredLineData,
		  RestoredTermStatus,STT,TTY,STR,CODE,NMTypes,
		  RestoredPreferred),
	% put the preferred concept back into the CLInfoLines
	CLInfoLinesNext = [RestoredPreferred|CLInfoLinesIn],
	% The first argument here must be FirstExcludedPreferred, and not RestoredPreferred,
	% because we must search for a clinfo/13 term containing
	% the original LineData with '|p|',
	% and not a clinfo/13 term containing the updated LineData with '|P|'.
	delete_pref_from_exclusions(FirstExcludedPreferred,
				    TSExclusionsIn, NormExclusionsIn, SyntaxExclusionsIn,
				    TSCountsIn,      TSCountsNext,
				    NormCountsIn,    NormCountsNext,
				    SyntaxCountsInOut, SyntaxCountsNext,
				    TSExclusionsNext, NormExclusionsNext, SyntaxExclusionsNext,
				    Reason),
	format(user_output,
	       '~NRestored "~s" previously deleted because of ~w~n', [OrigLineData,Reason]).


announce_no_restore([]).
announce_no_restore([FirstPreferred|RestPreferred]) :-
	line_term(_NormSTRAtom,_CUIAtom,_SABAtom,_LUIAtom,_SUIAtom,_AUIAtom,LineString,
		  _TSAtom,_STTAtom,_TTYAtom,_STRAtom,_CODEAtom,_NMTypes,
		  FirstPreferred),
	format(user_output,
	       '~NDID NOT RESTORE "~s" because all concepts filtered out~n', [LineString]),
	announce_no_restore(RestPreferred).

% Find all excluded preferred terms, i.e., those that are NOT in CLInfoLines.
find_excluded_preferred([], _CLInfoLines, []).
find_excluded_preferred([FirstPreferred|RestPreferred], CLInfoLines, ExcludedPreferred) :-
	( memberchk(FirstPreferred, CLInfoLines) ->
	  ExcludedPreferred = RestExcludedPreferred
	; ExcludedPreferred = [FirstPreferred|RestExcludedPreferred]
	),
	find_excluded_preferred(RestPreferred, CLInfoLines, RestExcludedPreferred).

update_term_status(OrigLineData, RestoredLineData) :-
	( append([Before,"|p|",After], OrigLineData) ->
	  append([Before,"|P|",After], RestoredLineData)
	; RestoredLineData = OrigLineData
	).

delete_pref_from_exclusions(Preferred,
			    TSExclusionsIn,   NormExclusionsIn,  SyntaxExclusionsIn,
			    TSCountsIn,       TSCountsOut,
			    NormCountsIn,     NormCountsOut,
			    SyntaxCountsIn,   SyntaxCountsOut,
			    TSExclusionsOut,  NormExclusionsOut, SyntaxExclusionsOut,
			    Reason) :-
	line_term(_NMSTR,_CUI,_SAB,_LUI,_SUI,_AUI,_LineData,
		  TS,_STT,_TTY,_STR,_CODE,_NMTypes,
		  Preferred),
	  % Was the preferred concept excluded because of term status?
	( selectchk(Preferred, TSExclusionsIn,  TSExclusionsOut) ->
	  Reason = 'term status',
	  % Decrement the appropriate term status count,
	  update_term_status_count(TS, -1, TSCountsIn, TSCountsOut),
	  % leave the normalization counts unchanged
	  NormCountsOut       = NormCountsIn,
	  % leave the syntax counts unchanged
	  SyntaxCountsOut     = SyntaxCountsIn,
	  % leave the normalization exclusions unchanged
	  NormExclusionsOut   = NormExclusionsIn,
	  % leave the syntax exclusions unchanged
	  SyntaxExclusionsOut = SyntaxExclusionsIn
	  % Was the preferred concept excluded because of normalization?
	; selectchk(Preferred, NormExclusionsIn, NormExclusionsOut) ->
	  Reason = normalization,
	  % Decrement all the appropriate normalization counts
	  % update_all_normalization_counts([NMTypes|NMTypes], -1, NormCountsIn, NormCountsOut),
	  NormCountsOut = NormCountsIn,
	  % leave the term-status counts unchanged
	  TSCountsOut         = TSCountsIn,
	  % leave the syntax counts unchanged
	  SyntaxCountsOut     = SyntaxCountsIn,
	  % leave the term-status exclusions unchanged
	  TSExclusionsOut     = TSExclusionsIn,
	  % leave the syntax exclusions unchanged
	  SyntaxExclusionsOut = SyntaxExclusionsIn
	  % Was the preferred concept excluded because of syntax?
	; selectchk(Preferred, SyntaxExclusionsIn, SyntaxExclusionsOut) ->
	  Reason = syntax,
	  % Decrement the synt syntax count
	  update_syntax_count(synt, -1, SyntaxCountsIn, SyntaxCountsOut),
	  % leave the term-status counts unchanged
	  TSCountsOut         = TSCountsIn,
	  % leave the normalization counts unchanged
	  NormCountsOut       = NormCountsIn,
	  % leave the term-status exclusions unchanged
	  TSExclusionsOut     = TSExclusionsIn,
	  % leave the normalization exclusions unchanged
	  NormExclusionsOut   = NormExclusionsIn
	).

% Strenghten the test to allow any clinfo/13 structure containing
% * the original Preferred Name's NMSTR and preferred TS ('p' or 'P') and STT ('PF')
% * a preferred TS ('p' or 'P'), and
% * the preferred STT ('PF')
% to count as a Preferred Name

find_all_preferred([], CUI, Preferred, Preferred) :-
	( Preferred \== [] ->
	  true
	; format(user_output, '~NNo preferred form found for CUI ~w~n', [CUI])
	).
find_all_preferred([FirstCLInfoLine|RestCLInfoLines], CUI, PreferredIn, PreferredOut) :-
	  line_term(_NMSTR,CUI,_SAB,_LUI,_SUI,_AUI,_LineData,
		    TS,STT,_TTY,_STR,_CODE,_NMTypes,
		    FirstCLInfoLine),
	  ( preferred_TS_STT(TS, STT) ->
	    PreferredNext = [FirstCLInfoLine|PreferredIn]
	  ; PreferredNext = PreferredIn
	  ),
	  find_all_preferred(RestCLInfoLines, CUI, PreferredNext, PreferredOut).

preferred_TS_STT('P', 'PF').
preferred_TS_STT(p,   'PF').

/* filter_nmstr_dups(+CLInfoLines, +OutputStream,
   		     -NormCountsIn, -NormCountsOut,
		     -NormExclusions, -FilteredCLInfoLines)

filter_nmstr_dups/6.  See filter_and_write/1.  */

% We now keep one normalized string per CUI and per SAB.

filter_nmstr_dups([], _, NormCounts, NormCounts, [], []).
filter_nmstr_dups([CLInfoLine|RestInfoLines], OutputStream, 
		  NormCountsIn, NormCountsOut,
		  [CLInfoLine|RestExcluded], FilteredRest) :-
	nmstr_is_duplicate(RestInfoLines, CLInfoLine),
	!,
        line_term(_NMSTR,_CUI,_SAB,_LUI,_SUI,_AUI,_LineData,
		  _TS,_STT,_TTY,_STR,_CODE,NMTypes,
		  CLInfoLine),
	announce_exclusion(RestInfoLines, CLInfoLine),
	flush_output(user_output),
	% format(user_output, 'DUPLICATE: ~a ~a ~a ~a~n', [STR,NMSTR,SAB,TTY]),
	% We want to update the normalization counts for
	% (1) the entire list of NMTypes, e.g., [case,hyphen,poss] and
	% (2) each individual type e.g., case, hyphen, and poss.
	% Creating the list [NMTypes|NMTypes] enables a simple way of doing this.
	% Suppose as above that NMTypes = [case,hyphen,poss];
	% Then [NMTypes|NMTypes] = will be [[case,hyphen,poss],case,hypen,poss],
	% and we just have to update the normalization count for each element of that list!
	update_all_normalization_counts([NMTypes|NMTypes], 1, NormCountsIn, NormCountsNext),
	filter_nmstr_dups(RestInfoLines, OutputStream,
			  NormCountsNext, NormCountsOut, RestExcluded, FilteredRest).

filter_nmstr_dups([First|Rest], OutputStream,
		  NormCountsIn, NormCountsOut, Excluded, [First|FilteredRest]) :-
	filter_nmstr_dups(Rest, OutputStream,
			  NormCountsIn, NormCountsOut, Excluded, FilteredRest).

announce_exclusion([ExcludingLine|_Rest], ExcludedLine) :-
	line_term(_NMSTR2,CUI2,SAB2,LUI2,SUI2,AUI2,_LineData2,
		  _TS2,_STT2,TTY2,STR2,_CODE2,_NMTypes2,
		  ExcludingLine),
	line_term(_NMSTR1,CUI1,SAB1,LUI1,SUI1,AUI1,_LineData1,
		  _TS1,_STT1,TTY1,STR1,_CODE1,_NMTypes1,
		  ExcludedLine),
	% XXX|187|NCI|AB|C0439208:L1224124:S1086283|g|>>|37|CHV|SY|C0439208:L1224124:S1086283|g
	% Diagnostic output indicating that the Excluding string
	% 187|NCI|AB|C0439208:L1224124:S1086283|g
	% has excluded the Excluded string
	% 37|CHV|SY|C0439208:L1224124:S1086283|g
	format(user_output, 'XXX|~w|~w|~w|~w|~w|~s|~s|>>|~w|~w|~w|~w|~w|~s|~s~n',
	       		    [SAB2,TTY2,CUI2,LUI2,SUI2,AUI2,STR2,
			     SAB1,TTY1,CUI1,LUI1,SUI1,AUI1,STR1]).
			     

update_all_normalization_counts([], _Increment, NormCounts, NormCounts).
update_all_normalization_counts([H|T], Increment, NormCountsIn, NormCountsOut) :-
	update_one_normalization_count(NormCountsIn, H, Increment, NormCountsNext),
	update_all_normalization_counts(T, Increment, NormCountsNext, NormCountsOut).

% If we've reached the end of the counts list,
% then the normaliztion type we're looking at is not yet in the list,
% so add it with a count of 1.
update_one_normalization_count([], NormType, _Increment, [NormType-1]).
update_one_normalization_count([H|T], NormType, Increment, NormCountsNext) :-
	( H = NormType-Count ->
	  NextCount is Count + Increment,
	  NormCountsNext = [NormType-NextCount|T]
	; NormCountsNext = [H|UpdatedT],
	  update_one_normalization_count(T, NormType, Increment, UpdatedT)
	).

/* nmstr_is_duplicate(+NMSTR, +CLInfoLines)

nmstr_is_duplicate/2 succeeds if NMSTR occurs in one of the CLInfoLines.  */

%%% % This explanation is out of date, and refers to the former logic
%%% % of keeping only one version of each normalized string, period.
%%% % The MRRANK table contains the following fields:
%%% % Rank|SAB|TTY|Suppress
%%% % The clinfo/13 terms come in to nmstr_is_duplicate/2 sorted in increasing order by
%%% % (1) normalized string (NMSTR), and then
%%% % (2) MRRANK
%%% % A clinfo/13 term should be excluded by normalization iff
%%% % another clinfo/13 term with the same NMSTR has a higher MRRANK.
%%% % Since all clinfo/13 terms with the same NMSTR will be adjacent,
%%% % the exclusion logic is very simple:
%%% % (1) If Line1 and Line2 have the same NMSTR,
%%% %     because the clinfo/13 terms are sorted,
%%% %     Line2's MRRANK will necessarily be higher than Line1's,
%%% %     so exclude Line1. There is no need to compare the two MRRANKs.
%%% % (2) Otherwise (if Line1 and Line2 have different NMSTRs),
%%% %     Line1 should *not* be excluded, because there is no other clinfo/13 term
%%% %     with the same NMSTR and a higher score,
%%% %     so there's no need to recurse on the rest of the clinfo/13 terms!


% The updated explanation of the logic of nmstr_is_duplicate:
% The clinfo/13 terms come in to nmstr_is_duplicate/2 sorted in increasing order by
% (1) normalized string (NMSTR),
% (2) CUI, and
% (2) SAB
% A clinfo/13 term should be excluded by normalization iff there exists
% another clinfo/13 term with the same NMSTR in the same CUI and the same SAB.
% Since all clinfo/13 terms with the same NMSTR will be adjacent,
% the exclusion logic is very simple:
% (1) If Line1 and Line2 have the same NMSTR, CUI, and SAB, exclude Line1.
% (2) Otherwise (if Line1 and Line2 have different NMSTRs, CUIs or SABs),
%     Line1 should *not* be excluded, because there is no other clinfo/13 term
%     with the same NMSTR, CUI, and SAB.

% We now want to keep only one version of each normalized string for each CUI and SAB.

nmstr_is_duplicate([Line2|_RestLines], Line1) :-
	line_term(NMSTR1,CUI1,SAB1,_LUI1,_SUI1,_AUI1,_LineData1,
		  _TS1,_STT1,_TTY1,_STR1,_CODE1,_NMTypes1,
		  Line1),
	line_term(NMSTR2,CUI2,SAB2,_LUI2,_SUI2,_AUI2,_LineData2,
		  _TS2,_STT2,_TTY2,_STR2,_CODE2,_NMTypes2,
		  Line2),
	NMSTR2 == NMSTR1,
	CUI2 == CUI1,
	SAB2 == SAB1.

% filter_by_term_status(+CLInfoLines, +OutputStream, -FilteredCLInfoLines)
% filters out and writes with "ntss" prefix lines whose Term Status is "s" or "p"

filter_by_term_status([], _OutputStream, TSCounts, TSCounts, [], []).
filter_by_term_status([CLInfoLine|RestCLInfoLines], OutputStream,
		      TSCountsIn, TSCountsOut,
		      [CLInfoLine|RestExcluded], FilteredRest) :-
	line_term(_NMSTR,_CUI,_SAB,_LUI,_SUI,_AUI,_LineData,
		  TS,_STT,_TTY,_STR,_CODE,_NMTypes,
		  CLInfoLine),
	excluded_term_status(TS),
	!,
	update_term_status_count(TS, 1, TSCountsIn, TSCountsNext),
	filter_by_term_status(RestCLInfoLines, OutputStream,
			      TSCountsNext, TSCountsOut,
			      RestExcluded, FilteredRest).
filter_by_term_status([First|Rest], OutputStream,
		      TSCountsIn, TSCountsOut, Excluded, [First|FilteredRest]) :-
	filter_by_term_status(Rest, OutputStream,
			      TSCountsIn, TSCountsOut, Excluded, FilteredRest).

excluded_term_status(p).
excluded_term_status(s).

update_term_status_count(p, Increment,
			 [p-PCountIn,s-SCount],
			 [p-PCountNext,s-SCount]) :-
	PCountNext is PCountIn + Increment.
update_term_status_count(s, Increment,
			 [p-PCount,s-SCountIn],
			 [p-PCount,s-SCountNext]) :-
	SCountNext is SCountIn + Increment.

update_syntax_count(pref, Increment,
		    [pref-PrefCountIn,   synt-SyntCount],
		    [pref-PrefCountNext, synt-SyntCount]) :-
	PrefCountNext is PrefCountIn + Increment.
update_syntax_count(synt, Increment,
		    [pref-PrefCount, synt-SyntCountIn],
		    [pref-PrefCount, synt-SyntCountNext]) :-
	SyntCountNext is SyntCountIn + Increment.

/* filter_syntactically(+CLInfoLines, +OutputStream, -SyntaxExclusions, -FilteredCLInfoLines)

filter_syntactically/4.  See filter_and_write/1.  */

filter_syntactically([], _TaggerServerStream, _OutputStream, SyntaxCounts, SyntaxCounts, [], []).
% The first recursive clause of filter_syntactically/4 handles complex phrases
% that are excluded, and therefore added to the third argument.
filter_syntactically([CLInfoLine|Rest], TaggerServerStream, OutputStream,
		     SyntaxCountsIn, SyntaxCountsOut,
		     [CLInfoLine|RestExcluded], FilteredRest) :-
	line_term(NMSTR,CUI,SAB,_LUI,_SUI,_AUI,_LineData,
		  _TS,_STT,_TTY,_STR,CODE,_NMTypes,
		  CLInfoLine),
	atom_codes(NMSTR, NMSTRString),
	parse_it(NMSTRString, TaggerServerStream, minimal_syntax(Phrases)),
	length(Phrases, MSUCount), % number of minimal syntactic units (i.e., phrases)
	( control_option(dump_syntax_only) ->
	  simplify_all_phrases(Phrases, SUs0),
	  append(SUs0, SUs),
	  length(SUs, SyntaxCount), % number of syntactic items (e.g., shapes, mod, ...)
	  generate_dump_syntax_only_output(SyntaxCount, MSUCount, CUI, CODE, SAB, OutputStream)
	; \+ is_syntactically_simple(Phrases, MSUCount),   % do the filtering
	  update_syntax_count(synt, 1, SyntaxCountsIn, SyntaxCountsNext)
	),
	!,
	filter_syntactically(Rest, TaggerServerStream, OutputStream,
			     SyntaxCountsNext, SyntaxCountsOut, RestExcluded, FilteredRest).
% The second recursive clause of filter_syntactically/4 handles simple phrases
% that are not excluded, and therefore added to the fourth argument.
filter_syntactically([First|Rest], TaggerServerStream, OutputStream,
		     SyntaxCountsIn, SyntaxCountsOut, Excluded, [First|FilteredRest]) :-
	filter_syntactically(Rest, TaggerServerStream, OutputStream,
			     SyntaxCountsIn, SyntaxCountsOut, Excluded, FilteredRest).

generate_dump_syntax_only_output(SyntaxCount, MSUCount, CUI, CODE, SAB, OutputStream) :-
	( SyntaxCount =:= 0 ->
	  format(OutputStream,
		 '1|1|~a|~a|~a|~a|~p~n',
		 [CUI,SAB,CODE,NMSTR,SUs0]),
	  flush_output(OutputStream)
	; format(OutputStream,
		 '~d|~d|~a|~a|~a|~a|~p~n',
		 [MSUCount,SyntaxCount,CUI,SAB,CODE,NMSTR,SUs0]),
	  flush_output(OutputStream)
	).

/* is_syntactically_simple/2(+Phrases, +MSUCount)

is_syntactically_simple/2 succeeds if either MSUCount (the number of minimal
syntactic units) is 1 or Phrases is of the form 'a <prep> b' or
'a <prep> b of c of ...'. */

is_syntactically_simple(Phrases, Length) :-
	( Length =:= 1 ->
	  true
	; Phrases = [_First,Second|Rest],
	  is_prep_phrase(Second),
	  are_of_phrases(Rest)
	).

is_prep_phrase([FirstItem,_NextItem|_]) :- % there must be something after the
	get_phrase_item_name(FirstItem, Name),  % the prep
	!,
	Name == prep.

are_of_phrases([]).
are_of_phrases([First|Rest]) :-
	is_of_phrase(First),
	are_of_phrases(Rest).

is_of_phrase([FirstItem,_NextItem|_]) :- % there must be something after 'of'
	get_phrase_item_name(FirstItem, Name),
	get_phrase_item_feature(FirstItem, inputmatch, InputMatch),
	% format('~p~n~p~n',[Name,InputMatch]),
	!,
	Name == prep,
	InputMatch == [of].

% Try tagging and parsing five times, and quit if still unsuccessful.
parse_it(NMSTR, TaggerServerStream, SyntacticAnalysis) :-
	between(1, 5, _),
	   tag_text(NMSTR, TaggerServerStream, _FullTagList, TagList, _),
	   generate_syntactic_analysis_plus(NMSTR, TagList, SyntacticAnalysis, _Definitions),
	!.
parse_it(NMSTR, _TaggerServeerStream, minimal_syntax([[]])) :-
	format('~NError: Cannot parse "~s" after 5 attempts~n', [NMSTR]),
	ttyflush,
	halt.

simplify_all_phrases([], []).
simplify_all_phrases([First|Rest], [SFirst|SRest]) :-
	simplify_one_phrase(First, SFirst),
	simplify_all_phrases(Rest, SRest).

simplify_one_phrase([], []).
simplify_one_phrase([First|Rest], [Cat|SRest]) :-
	functor(First, Cat, _),
	simplify_one_phrase(Rest, SRest).


/* write_clinfo_lines(+CLInfoLines, +OutputStream)

write_clinfo_lines/2.  See filter_and_write/2.  */

write_clinfo_lines([], _).
write_clinfo_lines([CLInfoLine|Rest], OutputStream) :-
	line_term(_NMSTR,_CUI,_SAB,_LUI,_SUI,_AUI,LineData,
		  _TS,_STT,_TTY,_STR,_CODE,_NMTypes,
		  CLInfoLine),
	% y == "yes": the line survived filtering
	format(OutputStream, 'y|~s~n', [LineData]),
	flush_output(OutputStream),
	write_clinfo_lines(Rest, OutputStream).

% NormCounts0 is a list of terms of the form NormTypes-Count,
% where NormTypes is either
% * a single NormCount, which is an atom, e.g., uninv, case, hyphen, or
% * a list or NormTypes, e.g., [uninv,case], [uninv,case,hyphen].

% A typical NormCounts0 is
% [[uninv,case]-10,uninv-17,case-61,[case]-28,[uninv,case,hyphen]-7,hyphen-23,[case,hyphen]-16]

write_normalization_counts(NormCounts0, OutputStream) :-
	% Sorting and then reversing NormCounts0 ensures that
	% the NormType lists (compound normalization counts)
	% appear in the list before
	% the NormType atoms (base normalization counts).
	sort(NormCounts0, SortedNormCounts),
	rev(SortedNormCounts, NormCounts),
	write_normalization_counts_1(NormCounts, OutputStream).

write_normalization_counts_1([], _OutputStream).
write_normalization_counts_1([H|T], OutputStream) :-
	H = NormalizationTypes-Count,
	get_normalization_count_indicator(NormalizationTypes, IndicatorLetter),
	format(OutputStream, '~Ni~wn|~d|~w~n', [IndicatorLetter,Count,NormalizationTypes]),
	flush_output(OutputStream),
	write_normalization_counts_1(T, OutputStream).

get_normalization_count_indicator(H, IndicatorLetter) :-
	( H = [_|_] ->
	  % Compound Normalization Count
	  IndicatorLetter = 'c'
	; H == [] ->
	  % Compound Normalization Count
	  IndicatorLetter = 'c'
	  % Base Normalization Count
	; IndicatorLetter = 'b'
	).

write_term_status_counts([p-PCount,s-SCount], OutputStream) :-
	format(OutputStream, '~Nit|~d|p~n', [PCount]),
	format(OutputStream, '~Nit|~d|s~n', [SCount]),
	flush_output(OutputStream).

write_syntax_counts([pref-PrefCount,synt-SyntCount], OutputStream) :-
	format(OutputStream, '~Nis|~d|pref~n', [PrefCount]),
	format(OutputStream, '~Nis|~d|synt~n', [SyntCount]),
	flush_output(OutputStream).

% get_mrrank(SAB, TTY, Line, MRRank) :-
% 	% MMSubSyn is the synthetic MetaMap Subsynonymy vocabulary,
% 	% that is manually added to the local mrrank_VERSION.pl Prolog file
% 	% by create_mrrank; that script gives NLMSubSyn an MRRANK of 0, simply because
% 	% (1) No SubSyn string (by construction) occurs in any UMLS vocabulary, and
% 	% (2) Each Sybsyn string is found only once in any CUI in the MMSubSyn vocabulary.
% 	( mrrank(SAB, TTY, MRRank, _SUPPRESS) ->
% 	  true
% 	; control_value(mrrank_file, FileName),
% 	  format(user_output,
% 		 '### ERROR: SAB/TTY ~w/~w in line~n~*c~s~n~*cnot defined in MRRANK file ~w.~n',
% 		 [SAB,TTY,11,32,Line,11,32,FileName]),
% 	  abort
% 	).
