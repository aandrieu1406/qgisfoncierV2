CREATE OR REPLACE FUNCTION public.__9_typologie_prop(
	schema_prod text,
	idcom text
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$

BEGIN

	-- Typologie des propriétaires - travail avec les champs catpro2 et catpro2txt
	-- récupération des valeurs catpro2 et catpro2txt depuis la table TUP
	-- Foncier mutable type 1 et 2
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN catpro2 varchar(20)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET catpro2=(SELECT catpro2 FROM ' || schema_prod || '.gf_tup_' || idcom || ' b WHERE a.idtup=b.idtup AND type IN (''type 1'',''type 2''))';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN catpro2txt varchar(100)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET catpro2txt=(SELECT catpro2txt FROM ' || schema_prod || '.gf_tup_' || idcom || ' b WHERE a.idtup=b.idtup AND type IN (''type 1'',''type 2''))';


	-- création de l'attribut typologie_prop
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN typologie_prop varchar(100)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET typologie_prop=
		CASE 
			WHEN catpro2 = ''99'' THEN ''PAS DE PROPRIETAIRE''
			WHEN catpro2 LIKE ''A1%'' OR catpro2 LIKE ''A2%'' OR catpro2 LIKE ''A3%'' OR catpro2 LIKE ''A5%'' THEN ''STRUCTURE AGRICOLE ET/OU FORESTIERE''
			WHEN catpro2 LIKE ''A4%'' THEN ''SAFER''
			WHEN catpro2 LIKE ''E%'' THEN ''UNIVERSITE ET ETABLISSEMENT SCOLAIRE''
			WHEN catpro2 LIKE ''F1%'' THEN ''ORGANISME DE LOGEMENT SOCIAL''
			WHEN catpro2 LIKE ''F2%'' THEN ''EPF''
			WHEN catpro2 LIKE ''F4%'' THEN ''SEM''
			WHEN catpro2 LIKE ''F5%'' OR catpro2 LIKE ''F6%'' OR catpro2 LIKE ''F7%'' THEN ''PROMOTEUR AMENAGEUR INVESTISSEUR''
			WHEN catpro2 LIKE ''P1%'' THEN ''ETAT''
			WHEN catpro2 LIKE ''P2%'' THEN ''REGION''
			WHEN catpro2 LIKE ''P3%'' THEN ''DEPARTEMENT''
			WHEN catpro2 LIKE ''P4%'' THEN ''INTERCOMMUNALITE''
			WHEN catpro2 LIKE ''P5%'' THEN ''COMMUNE''
			WHEN catpro2 LIKE ''P5%'' THEN ''COLLECTIVITE TERRITORIALE AUTRE''
			WHEN catpro2 LIKE ''R%'' THEN ''INFRASTRUCTURE ET RESEAU''
			WHEN catpro2 =''X1'' THEN ''PERSONNE PHYSIQUE''
			ELSE ''AUTRES''
			END';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN nb_prop VARCHAR(10)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET nb_prop=
		CASE 
			WHEN catpro2 = ''99'' THEN ''0''
			WHEN length(catpro2) = 2 AND catpro2 != ''99'' THEN ''1''
			WHEN length(catpro2) = 5 THEN ''2''
			ELSE ''3 ou +''
		END';

END;
$BODY$;

-- SELECT public.__9_typologie_prop('public','33003');
