CREATE OR REPLACE FUNCTION public.__8_croisement_plu(
	schema_prod text,
	idcom text
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$

BEGIN

	--Croisement avec le PLU
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.inter_plu';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.inter_plu AS
		SELECT
			t1.gid,t1.libelle,t1.typezone,t1.surf_libelle,
			t1.part_surf_lib,nb_lib,t2.libelle as libelle_maj
		FROM	
			(SELECT
				gid,ARRAY_AGG(libelle) as libelle,
				ARRAY_AGG(typezone) as typezone,
				ARRAY_AGG(surf_inter::integer) as surf_libelle,
				ARRAY_AGG(((surf_inter/surf)*100)::integer) as part_surf_lib,
				count(libelle) as nb_lib,
				MAX(surf_inter) AS surf_maj
			FROM
				(SELECT
					a.gid, ST_AREA(ST_Intersection(a.geom,b.geom)) as surf_inter,
					ST_AREA(a.geom) as surf,ST_AREA(a.geom)-ST_AREA(ST_Intersection(a.geom,st_buffer(b.geom,0))) as dif,
					b.libelle,b.typezone
				FROM
					' || schema_prod || '.gf_foncier_mutable_' || idcom || ' as a,
					' || schema_prod || '.gf_plu_' || idcom || ' as b
				WHERE 
					ST_Intersects(a.geom,b.geom) AND ST_AREA(ST_Intersection(a.geom,st_buffer(b.geom,0)))>50) a
			GROUP BY gid) as t1,
			(SELECT
				a.gid, b.libelle,b.typezone, ST_AREA(ST_Intersection(a.geom,st_buffer(b.geom,0))) as surf_inter
			FROM
				' || schema_prod || '.gf_foncier_mutable_' || idcom || ' as a,
				' || schema_prod || '.gf_plu_' || idcom || ' as b
			WHERE 
				ST_Intersects(a.geom,b.geom) AND ST_AREA(ST_Intersection(a.geom,st_buffer(b.geom,0)))>1
			) as t2
		WHERE t1.gid=t2.gid AND t1.surf_maj=t2.surf_inter';

	-- Maj table foncier mutable
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN plu_lib varchar(200)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET plu_lib=(SELECT cast(libelle as varchar(200)) FROM ' || schema_prod || '.inter_plu b WHERE a.gid=b.gid limit 1)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN plu_typezone varchar(200)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET plu_typezone=(SELECT cast(typezone as varchar(200)) FROM ' || schema_prod || '.inter_plu b WHERE a.gid=b.gid limit 1)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN nb_plu_lib integer';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET nb_plu_lib=(SELECT nb_lib FROM ' || schema_prod || '.inter_plu b WHERE a.gid=b.gid limit 1)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN plu_lib_maj varchar(100)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET plu_lib_maj=(SELECT libelle_maj FROM ' || schema_prod || '.inter_plu b WHERE a.gid=b.gid limit 1)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN surf_plu_lib varchar(200)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET surf_plu_lib=(SELECT cast(surf_libelle as varchar(200)) FROM ' || schema_prod || '.inter_plu b WHERE a.gid=b.gid limit 1)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN tx_surf_plu_lib varchar(200)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET tx_surf_plu_lib=(SELECT cast(part_surf_lib as varchar(200)) FROM ' || schema_prod || '.inter_plu b WHERE a.gid=b.gid limit 1)';

	-- Suppression tables temporaires
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.inter_plu CASCADE';

END;
$BODY$;

-- SELECT public.__8_croisement_plu('public','33003');
