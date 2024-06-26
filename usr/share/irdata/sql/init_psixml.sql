create table xml_experiments (
    source varchar not null,
    filename varchar not null,
    entry integer not null,
    experimentid varchar not null, -- integer for PSI MI XML 2.5
    interactionid varchar not null -- integer for PSI MI XML 2.5
);

create table xml_interactors (
    source varchar not null,
    filename varchar not null,
    entry integer not null,
    interactorid varchar not null, -- integer for PSI MI XML 2.5
    participantid varchar not null, -- integer for PSI MI XML 2.5
    interactionid varchar not null -- integer for PSI MI XML 2.5
);

create table xml_names (
    source varchar not null,
    filename varchar not null,
    entry integer not null,
    scope varchar not null,
    parentid varchar not null, -- integer for PSI MI XML 2.5
    property varchar not null,
    nametype varchar not null,
    typelabel varchar,
    typecode varchar,
    name varchar -- some names can actually be unspecified
);

create table xml_xref (
    source varchar not null,
    filename varchar not null,
    entry integer not null,
    scope varchar not null,
    parentid varchar not null, -- integer for PSI MI XML 2.5
    property varchar not null,
    reftype varchar not null,
    refvalue varchar, -- MIPS omits some refvalues
    dblabel varchar,
    dbcode varchar,
    reftypelabel varchar,
    reftypecode varchar
);


create table xml_xref_unassigned (
    source varchar not null,
    filename varchar not null,
    entry integer not null,
    scope varchar not null,
    parentid varchar not null, -- integer for PSI MI XML 2.5
    property varchar not null,
    reftype varchar not null,
    refvalue varchar, -- MIPS omits some refvalues
    dblabel varchar,
    dbcode varchar,
    reftypelabel varchar,
    reftypecode varchar
);


create table xml_organisms (
    source varchar not null,
    filename varchar not null,
    entry integer not null,
    scope varchar not null,
    parentid varchar not null, -- integer for PSI MI XML 2.5
    taxid integer not null
);

create table xml_sequences (
    source varchar not null,
    filename varchar not null,
    entry integer not null,
    scope varchar not null,
    parentid varchar not null, -- integer for PSI MI XML 2.5
    sequence varchar not null
);

create table xml_sequences_original (
    "sequence" varchar not null,        -- the digest representing the sequence
    actualsequence varchar not null,    -- the original sequence
    primary key("sequence")
);
