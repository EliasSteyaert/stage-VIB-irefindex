-- Definitively assign sequences to interactors.

-- Copyright (C) 2011, 2012, 2013 Ian Donaldson <ian.donaldson@biotek.uio.no>
-- Original author: Paul Boddie <paul.boddie@biotek.uio.no>
--
-- This program is free software; you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the Free Software
-- Foundation; either version 3 of the License, or (at your option) any later
-- version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
-- PARTICULAR PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along
-- with this program.  If not, see <http://www.gnu.org/licenses/>.

begin;

-- Ambiguous references.
-- For each reference type for each interactor, note the ambiguity of the
-- references.

insert into irefindex_ambiguity
    select source, filename, entry, interactorid, reftype,
        count(distinct refsequence) as refsequences,        -- number of different sequences
        count(distinct reftaxid) as reftaxids               -- number of different taxids
    from xml_xref_interactor_sequences
    group by source, filename, entry, interactorid, reftype;

create index irefindex_ambiguity_reftype_sequences on irefindex_ambiguity (reftype, refsequences);

analyze irefindex_ambiguity;

-- Unambiguous primary and secondary references.

create temporary table tmp_unambiguous_references as
    select distinct I.source, I.filename, I.entry, I.interactorid, I.taxid as originaltaxid,
        refsequence as sequence, reftaxid as taxid,
        sequencelink, I.reftype, I.reftypelabel, I.dblabel, I.refvalue,
        originaldblabel, originalrefvalue,
        coalesce(finaldblabel, I.dblabel) as finaldblabel, coalesce(finalrefvalue, I.refvalue) as finalrefvalue,
        missing,
        cast('unambiguous' as varchar) as method
    from xml_xref_interactor_sequences as I
    inner join irefindex_ambiguity as A
        on (I.source, I.filename, I.entry, I.interactorid, I.reftype)
            = (A.source, A.filename, A.entry, A.interactorid, A.reftype)
    where A.refsequences = 1
        and A.reftaxids = 1
        and refsequence is not null;

analyze tmp_unambiguous_references;

-- Primary and secondary references with unambiguous sequence information and
-- ambiguous taxonomy information disambiguated by taxonomy.

create temporary table tmp_unambiguous_matching_taxonomy_references as
    select distinct I.source, I.filename, I.entry, I.interactorid, I.taxid as originaltaxid,
        refsequence as sequence, reftaxid as taxid,
        sequencelink, I.reftype, I.reftypelabel, I.dblabel, I.refvalue,
        originaldblabel, originalrefvalue,
        coalesce(finaldblabel, I.dblabel) as finaldblabel, coalesce(finalrefvalue, I.refvalue) as finalrefvalue,
        missing,
        cast('matching taxonomy' as varchar) as method
    from xml_xref_interactor_sequences as I
    inner join irefindex_ambiguity as A
        on (I.source, I.filename, I.entry, I.interactorid, I.reftype)
            = (A.source, A.filename, A.entry, A.interactorid, A.reftype)
    where A.refsequences = 1
        and A.reftaxids > 1
        and taxid = reftaxid
        and refsequence is not null;

create index tmp_unambiguous_matching_taxonomy_references_index on
    tmp_unambiguous_matching_taxonomy_references (source, filename, entry, interactorid);

analyze tmp_unambiguous_matching_taxonomy_references;

-- Ambiguous primary and secondary references disambiguated by interactor
-- sequence information.

-- Since interactor descriptions should only provide a single sequence, at most
-- one ambiguous sequence database sequence can match. This will potentially
-- provide one correspondence per reference type (one primary reference and one
-- secondary reference) involving a matching sequence.

create temporary table tmp_unambiguous_matching_sequence_references as
    select distinct I.source, I.filename, I.entry, I.interactorid, I.taxid as originaltaxid,
        refsequence as sequence, reftaxid as taxid,
        sequencelink, I.reftype, I.reftypelabel, I.dblabel, I.refvalue,
        originaldblabel, originalrefvalue,
        coalesce(finaldblabel, I.dblabel) as finaldblabel, coalesce(finalrefvalue, I.refvalue) as finalrefvalue,
        missing,
        cast('matching sequence' as varchar) as method
    from xml_xref_interactor_sequences as I
    inner join irefindex_ambiguity as A
        on (I.source, I.filename, I.entry, I.interactorid, I.reftype)
            = (A.source, A.filename, A.entry, A.interactorid, A.reftype)
    where A.refsequences > 1
        and A.reftaxids = 1
        and sequence = refsequence;

create index tmp_unambiguous_matching_sequence_references_index on
    tmp_unambiguous_matching_sequence_references (source, filename, entry, interactorid);

analyze tmp_unambiguous_matching_sequence_references;

-- Null primary and secondary references where an interactor sequence is
-- available but not any sequence database sequence.

create temporary table tmp_unambiguous_null_references as
    select I.source, I.filename, I.entry, I.interactorid, I.taxid as originaltaxid,
        I.sequence, taxid,
        cast('null' as varchar) as sequencelink, I.reftype, I.reftypelabel, I.dblabel, I.refvalue,
        originaldblabel, originalrefvalue,
        coalesce(finaldblabel, I.dblabel) as finaldblabel, coalesce(finalrefvalue, I.refvalue) as finalrefvalue,
        missing,
        cast('interactor sequence' as varchar) as method
    from xml_xref_interactor_sequences as I
    inner join irefindex_ambiguity as A
        on (I.source, I.filename, I.entry, I.interactorid, I.reftype)
            = (A.source, A.filename, A.entry, A.interactorid, A.reftype)
    where A.refsequences = 0
        and I.sequence is not null;

analyze tmp_unambiguous_null_references;

-- Arbitrarily assigned references.

-- NOTE: This will eventually need to distinguish between gene and non-gene
-- NOTE: references and to exclude gene references for which the canonical
-- NOTE: representative will instead be chosen.
-- NOTE: To choose a canonical representative, the combined sequence and taxid
-- NOTE: would be matched against the irefindex_rogids_canonical table.

create temporary table tmp_arbitrary_references as
    select distinct S.source, S.filename, S.entry, S.interactorid, S.taxid as originaltaxid,
        refdetails[1] as sequence, cast(refdetails[2] as integer) as taxid,
        sequencelink, S.reftype, S.reftypelabel, S.dblabel, S.refvalue,
        originaldblabel, originalrefvalue,
        coalesce(finaldblabel, S.dblabel) as finaldblabel, coalesce(finalrefvalue, S.refvalue) as finalrefvalue,
        missing,
        cast('arbitrary' as varchar) as method
    from (

        -- Get the highest sorted sequence for each ambiguous reference.
        -- Note that this requires an appropriate locale so that the appropriate
        -- result is obtained from the max function.

        select S.source, S.filename, S.entry, S.interactorid, S.reftype,
            max(array[refsequence, cast(reftaxid as varchar)]) as refdetails
        from xml_xref_interactor_sequences as S
        inner join irefindex_ambiguity as A
            on (S.source, S.filename, S.entry, S.interactorid, S.reftype) =
                (A.source, A.filename, A.entry, A.interactorid, A.reftype)
        where refsequences > 1
            and refsequence is not null
        group by S.source, S.filename, S.entry, S.interactorid, S.reftype

        ) as X
    inner join xml_xref_interactor_sequences as S
        on (S.source, S.filename, S.entry, S.interactorid, S.reftype, S.refsequence) =
            (X.source, X.filename, X.entry, X.interactorid, X.reftype, refdetails[1]);

-- Combine the different interactors.

create temporary table tmp_primary_references as
    select *
    from tmp_unambiguous_references
    where reftype = 'primaryRef'
    union all
    select *
    from tmp_unambiguous_matching_sequence_references
    where reftype = 'primaryRef'
    union all
    select *
    from tmp_unambiguous_matching_taxonomy_references
    where reftype = 'primaryRef';

analyze tmp_primary_references;

create temporary table tmp_secondary_references as
    select *
    from tmp_unambiguous_references
    where reftype = 'secondaryRef'
    union all
    select *
    from tmp_unambiguous_matching_sequence_references
    where reftype = 'secondaryRef'
    union all
    select *
    from tmp_unambiguous_matching_taxonomy_references
    where reftype = 'secondaryRef';

analyze tmp_secondary_references;



-- Build the assignments table from the different components.

-- Take unambiguous primary reference assignments and all additional secondary
-- references.

insert into irefindex_assignments
    select *
    from tmp_primary_references
    union all
    select S.*
    from tmp_secondary_references as S
    left outer join tmp_primary_references as P
        on (S.source, S.filename, S.entry, S.interactorid) =
            (P.source, P.filename, P.entry, P.interactorid)
    where P.interactorid is null;

analyze irefindex_assignments;

-- Take additional unambiguous primary references employing an interaction
-- record sequence.

insert into irefindex_assignments
    select N.*
    from tmp_unambiguous_null_references as N
    left outer join irefindex_assignments as A
        on (N.source, N.filename, N.entry, N.interactorid) =
            (A.source, A.filename, A.entry, A.interactorid)
    where N.reftype = 'primaryRef'
        and A.interactorid is null;

-- Take additional unambiguous secondary references employing an interaction
-- record sequence.

insert into irefindex_assignments
    select N.*
    from tmp_unambiguous_null_references as N
    left outer join irefindex_assignments as A
        on (N.source, N.filename, N.entry, N.interactorid) =
            (A.source, A.filename, A.entry, A.interactorid)
    where N.reftype = 'secondaryRef'
        and A.interactorid is null;

analyze irefindex_assignments;

-- Take additional arbitrarily assigned primary references.

insert into irefindex_assignments
    select N.*
    from tmp_arbitrary_references as N
    left outer join irefindex_assignments as A
        on (N.source, N.filename, N.entry, N.interactorid) =
            (A.source, A.filename, A.entry, A.interactorid)
    where N.reftype = 'primaryRef'
        and A.interactorid is null;

-- Take additional arbitrarily assigned secondary references.

insert into irefindex_assignments
    select N.*
    from tmp_arbitrary_references as N
    left outer join irefindex_assignments as A
        on (N.source, N.filename, N.entry, N.interactorid) =
            (A.source, A.filename, A.entry, A.interactorid)
    where N.reftype = 'secondaryRef'
        and A.interactorid is null;

analyze irefindex_assignments;



-- Remaining unassigned interactors.

insert into irefindex_unassigned
    select I.source, I.filename, I.entry, I.interactorid, I.taxid, I.sequence,
        count(distinct refsequence) as refsequences
    from xml_xref_interactor_sequences as I
    left outer join irefindex_assignments as A
        on (I.source, I.filename, I.entry, I.interactorid) =
            (A.source, A.filename, A.entry, A.interactorid)
    where A.interactorid is null
    group by I.source, I.filename, I.entry, I.interactorid, I.taxid, I.sequence;


UPDATE irefindex_assignments
SET taxid = foo.taxid
FROM (
        SELECT  distinct refvalue,taxid
        FROM    irefindex_assignments
        WHERE   taxid is not null
        ) as foo
WHERE irefindex_assignments.refvalue = foo.refvalue and irefindex_assignments.taxid is null
;


UPDATE irefindex_assignments
SET taxid = foo.originaltaxid
FROM (
        SELECT  distinct refvalue,originaltaxid
        FROM    irefindex_assignments
        WHERE   originaltaxid is not null
        ) as foo
WHERE irefindex_assignments.refvalue = foo.refvalue and irefindex_assignments.taxid is null
;

analyze irefindex_unassigned;



-- Preferred assignments.
-- The above assignments include potentially multiple paths to the same
-- sequence for each interactor. By nominating preferred sequence links, a
-- single path can be chosen.
-- This should create a table mapping sequence links to priorities like the
-- following:

-- refseq                      A
-- uniprotkb                   A
-- refseq/entrezgene           B
-- uniprotkb/entrezgene-symbol B

-- Selecting the first/best priority (A as opposed to B in the above above
-- illustration) permits more appropriate identifiers to be chosen.

create temporary table tmp_sequencelinks as
    select distinct sequencelink, priority
    from (
        select sequencelink, case when sequencelink like '%entrezgene%' then 'B' else 'A' end as priority
        from irefindex_assignments
        ) as X;

insert into irefindex_assignments_preferred
    select source, filename, entry, interactorid, preferred[2] as sequencelink, preferred[3] as finaldblabel, preferred[4] as finalrefvalue,
        preferred[5] as dblabel, preferred[6] as refvalue, preferred[7] as originaldblabel, preferred[8] as originalrefvalue
    from (

        -- Use the priority ordering defined above to select a minimum (best)
        -- priority, selecting an arbitrary identifier where multiple paths to
        -- the sequence have the same priority.

        select source, filename, entry, interactorid, min(array[priority, A.sequencelink, finaldblabel, finalrefvalue, dblabel, refvalue, originaldblabel, originalrefvalue]) as preferred
        from irefindex_assignments as A
        inner join tmp_sequencelinks as S
            on A.sequencelink = S.sequencelink
        group by source, filename, entry, interactorid
        ) as P;

analyze irefindex_assignments_preferred;



-- Scoring of assignments.
-- For each interactor, its properties are collected into an array corresponding
-- to the "scoring bitmap" mentioned in the literature.

insert into irefindex_assignment_scores
    select distinct A.source, A.filename, A.entry, A.interactorid,
        array_to_string(array[
            case when reftype               = 'primaryRef'                                                              then 'P' else '' end,
            case when reftype               = 'secondaryRef'                                                            then 'S' else '' end,
            case when P.sequencelink        in ('uniprotkb/non-primary', 'uniprotkb/isoform-non-primary-unexpected',
                                                'archived/uniprotkb/non-primary', 'archived/uniprotkb/isoform-non-primary-unexpected')
                                                                                                                        then 'U' else '' end,
            case when P.sequencelink        in ('refseq/version-discarded', 'archived/refseq/version-discarded')        then 'V' else '' end,
            case when originaltaxid         <> taxid                                                                    then 'T' else '' end,
            case when P.sequencelink        like '%entrezgene%'                                                         then 'G' else '' end,
            case when P.originaldblabel     <> P.finaldblabel                                                           then 'D' else '' end,
            -- NOTE: M currently not generally tracked (typographical modification).
            case when P.sequencelink        like '%uniprotkb/sgd%'                                                      then 'M' else '' end,
            case when method                <> 'unambiguous'                                                            then '+' else '' end,
            case when method                = 'matching sequence'                                                       then 'O' else '' end,
            case when method                = 'matching taxonomy'                                                       then 'X' else '' end,
            '', -- ?
            case when method                = 'arbitrary'                                                               then 'L' else '' end,
            case when P.finaldblabel        = 'genbank_protein_gi'                                                      then 'I' else '' end,
            case when missing                                                                                           then 'E' else '' end,
            case when P.sequencelink        like 'archived/%'                                                           then 'Y' else '' end,
            -- NOTE: N refers to "new assignment", but this appears to be specific to interaction record sequences.
            case when method                = 'interactor sequence'                                                     then 'N' else '' end,
            case when reftypelabel          = 'see-also'                                                                then 'Q' else '' end
            ], '') as score
    from irefindex_assignments_preferred as P
    inner join irefindex_assignments as A
        on (A.source, A.filename, A.entry, A.interactorid, A.sequencelink, A.dblabel, A.refvalue, A.finaldblabel, A.finalrefvalue) =
           (P.source, P.filename, P.entry, P.interactorid, P.sequencelink, P.dblabel, P.refvalue, P.finaldblabel, P.finalrefvalue);

analyze irefindex_assignment_scores;



-- ROG identifiers.
-- Since more than one link to a sequence database may exist, the records must
-- be made distinct. The taxid is exposed here for convenience since it can be
-- useful to be able to map interactors to taxids directly without having to
-- extract them from ROG identifiers.

insert into irefindex_rogids
    select distinct source, filename, entry, interactorid, sequence || taxid as rogid,
        taxid, method
    from irefindex_assignments
    where sequence is not null
        and taxid is not null;

create index irefindex_rogids_rogid on irefindex_rogids(rogid);
analyze irefindex_rogids;

-- Make a mapping from ROG identifiers to canonical ROG identifiers.
-- Since the mapping from RGGs to canonical ROGs may not provide a canonical
-- UniProt or RefSeq representative, a ROG identifier is mapped to itself here
-- in such cases in order to provide a complete mapping.

insert into irefindex_rogids_canonical
    select distinct I.rogid, coalesce(C.crogid, I.rogid) as crogid
    from irefindex_rogids as I
    left outer join irefindex_sequence_rogids_canonical as C
        on I.rogid = C.rogid;

analyze irefindex_rogids_canonical;

-- Database identifiers corresponding to ROG identifiers.
-- The identifier sequences table is used to get a wide selection of identifiers
-- instead of only the identifiers actually used in the interaction data.

insert into irefindex_rogid_identifiers
    select distinct rogid, finaldblabel, finalrefvalue, 'A' as priority
    from irefindex_rogids as R
    inner join xml_xref_sequences as I
        on rogid = refsequence || reftaxid
    where refsequence is not null
        and reftaxid is not null;

analyze irefindex_rogid_identifiers;

-- Add extra records for canonical identifiers.

insert into irefindex_rogid_identifiers
    select distinct crogid, finaldblabel, finalrefvalue, 'A' as priority
    from irefindex_rogids_canonical as R
    inner join xml_xref_sequences as I
        on crogid = refsequence || reftaxid
    left outer join irefindex_rogid_identifiers as P
        on crogid = P.rogid
    where refsequence is not null
        and reftaxid is not null
        and P.rogid is null;

analyze irefindex_rogid_identifiers;

-- Add things like original references (which may be have been gene identifiers
-- that were mapped to protein identifiers).
-- These should only be chosen to refer to an interactor if no better identifier
-- exists.

insert into irefindex_rogid_identifiers
    select distinct R.rogid, I.dblabel, I.refvalue, 'B' as priority
    from irefindex_rogids as R
    inner join xml_xref_sequences as I
        on R.rogid = refsequence || reftaxid
    left outer join irefindex_rogid_identifiers as RI
        on R.rogid = RI.rogid
        and I.dblabel = RI.dblabel
        and I.refvalue = RI.refvalue
    where refsequence is not null
        and reftaxid is not null
        and RI.rogid is null;

analyze irefindex_rogid_identifiers;

-- Add extra records for canonical identifiers.

insert into irefindex_rogid_identifiers
    select distinct R.crogid as rogid, I.dblabel, I.refvalue, 'B' as priority
    from irefindex_rogids_canonical as R
    inner join xml_xref_sequences as I
        on R.crogid = refsequence || reftaxid
    left outer join irefindex_rogid_identifiers as RI
        on R.crogid = RI.rogid
        and I.dblabel = RI.dblabel
        and I.refvalue = RI.refvalue
    where refsequence is not null
        and reftaxid is not null
        and RI.rogid is null;

analyze irefindex_rogid_identifiers;

-- Add gene identifiers based on the known mappings from proteins to genes.

insert into irefindex_rogid_identifiers
    select distinct R.rogid, 'entrezgene/locuslink' as dblabel, cast(geneid as varchar) as refvalue, 'C' as priority
    from irefindex_rogids as R
    inner join irefindex_gene2rog as G
        on R.rogid = G.rogid
    left outer join irefindex_rogid_identifiers as RI
        on R.rogid = RI.rogid
        and RI.dblabel = 'entrezgene/locuslink'
        and cast(geneid as varchar) = RI.refvalue
    where RI.rogid is null;

analyze irefindex_rogid_identifiers;

-- Add extra records for canonical identifiers.

insert into irefindex_rogid_identifiers
    select distinct R.crogid as rogid, 'entrezgene/locuslink' as dblabel, cast(geneid as varchar) as refvalue, 'C' as priority
    from irefindex_rogids_canonical as R
    inner join irefindex_gene2rog as G
        on R.crogid = G.rogid
    left outer join irefindex_rogid_identifiers as RI
        on R.crogid = RI.rogid
        and RI.dblabel = 'entrezgene/locuslink'
        and cast(geneid as varchar) = RI.refvalue
    where RI.rogid is null;

analyze irefindex_rogid_identifiers;

-- Define the preferred identifiers as those provided by UniProt or RefSeq, with
-- ROG identifiers used otherwise. These identifiers are used in the uid columns
-- of the MITAB output and can be any identifiers referring to a protein
-- sequence, not just those used in the context of an interaction.

insert into irefindex_rogid_identifiers_preferred
    select rogid,
        coalesce(uniprotacc[2], refseqacc[2], 'rogid') as dblabel,
        coalesce(uniprotacc[3], refseqacc[3], rogid) as refvalue
    from (
        select I.rogid,
            min(array[U.priority, U.dblabel, U.refvalue]) as uniprotacc,
            min(array[R.priority, R.dblabel, R.refvalue]) as refseqacc
        from (
            select rogid from irefindex_rogids
            union
            select crogid as rogid from irefindex_rogids_canonical
            ) as I
        left outer join irefindex_rogid_identifiers as U
            on I.rogid = U.rogid
            and U.dblabel = 'uniprotkb'
        left outer join irefindex_rogid_identifiers as R
            on I.rogid = R.rogid
            and R.dblabel = 'refseq'
        group by I.rogid
        ) as X;

analyze irefindex_rogid_identifiers_preferred;

-- Determine the complete interactions.
-- Interactions where one or more participants are missing are considered
-- incomplete and cannot be used to construct meaningful RIG identifiers.

insert into irefindex_interactions_complete
    select I.source, I.filename, I.entry, I.interactionid,
        count(I.interactorid) = count(R.rogid) as complete
        from xml_interactors as I
        left outer join irefindex_rogids as R
            on (I.source, I.filename, I.entry, I.interactorid) =
               (R.source, R.filename, R.entry, R.interactorid)
        group by I.source, I.filename, I.entry, I.interactionid;

analyze irefindex_interactions_complete;

commit;
