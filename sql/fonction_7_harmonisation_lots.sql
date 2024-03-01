CREATE OR REPLACE FUNCTION public.__7_harmonisation_lots(
	schema_prod text,
	idcom text
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$

BEGIN

	-- lots 1
	-- récupération des géométries originales (sans arrondis des buffers)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_def_lot1_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_def_lot1_' || idcom || ' AS
		SELECT 
			b.gid, a.idtup, a.idcom, a.dcntpa as surface,densite,
			b.nb_acces, b.types_acces, b.cl_admin, b.acces_indirect, a.geom 
		FROM 
			' || schema_prod || '.gf_tup_' || idcom || ' as a,
			' || schema_prod || '.gf_uf_lot1_acces_' || idcom || ' as b
		WHERE a.idtup=b.idtup';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_def_lot1_' || idcom || ' add constraint gf_uf_def_lot1_' || idcom || '_pkey primary key(gid)';

	--Lot 2
	-- harmonisation des tables des lots (même structure que lot1)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_def_lot2_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_def_lot2_' || idcom || ' AS
		SELECT 
			gid, idtup, ''' || idcom || '''::varchar(5) AS idcom, surface,densite,
			nb_acces, types_acces, cl_admin, acces_indirect, geom 
		FROM 
			' || schema_prod || '.gf_uf_lot2_acces_' || idcom || '';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_def_lot2_' || idcom || ' add constraint gf_uf_def_lot2_' || idcom || '_pkey primary key(gid)';

	-- Lots 3
	-- harmonisation des tables des lots (même structure lot1)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_def_lot3_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_def_lot3_' || idcom || ' AS
		SELECT 
			gid, ''multi''::varchar as idtup, ''' || idcom || '''::varchar(5) AS idcom, surface,densite,
			nb_acces, types_acces, cl_admin, acces_indirect, geom 
		FROM 
			' || schema_prod || '.gf_uf_lot3_acces_' || idcom || '';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_def_lot3_' || idcom || ' add constraint gf_uf_def_lot3_' || idcom || '_pkey primary key(gid)';

	-- Unification des 3 tables lots
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp AS
		SELECT 
			''type 1'' as type, idtup, idcom, surface,densite,
			nb_acces, types_acces, cl_admin, acces_indirect, geom 
		FROM 
			' || schema_prod || '.gf_uf_def_lot1_' || idcom || '
		UNION
		SELECT 
			''type 2'' as type, idtup, idcom, surface,densite,
			nb_acces, types_acces, cl_admin, acces_indirect, geom 
		FROM 
			' || schema_prod || '.gf_uf_def_lot2_' || idcom || '
		UNION
		SELECT 
			''type 3'' as type, idtup, idcom, surface,densite,
			nb_acces, types_acces, cl_admin, acces_indirect, geom 
		FROM 
			' || schema_prod || '.gf_uf_def_lot3_' || idcom || '';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.temp ALTER COLUMN geom type geometry(MultiPolygon, 2154) using ST_Multi(geom)';

	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.temp using GIST (geom)';

	--Croisement avec l'enveloppe urbaine pour supprimer les gisements hors enveloppe urbaine. On en econserve que les gisement supérieurs à 300m2
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_foncier_mutable_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' AS
		WITH temp1 AS
			(SELECT ST_Union(geom) AS geom FROM ' || schema_prod || '.gf_envurb_' || idcom || ')
		SELECT 
			type, idtup, idcom, surface,densite,
			nb_acces, types_acces, cl_admin, acces_indirect,
			st_multi(st_collectionextract(st_forcecollection(st_makevalid(ST_Intersection(a.geom,b.geom))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.temp a,temp1 b
		WHERE ST_Intersects(a.geom,b.geom)';

	EXECUTE 'DELETE FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' WHERE ST_area(geom)<300';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN gid serial';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' add constraint gf_foncier_mutable_' || idcom || '_pkey primary key(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' using GIST (geom)';
	
	--suppression tables temporaires	
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_def_lot1_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_def_lot2_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_def_lot3_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_acces_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_acces_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot3_acces_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot3_' || idcom || ' CASCADE';

END;
$BODY$;

-- SELECT public.__7_harmonisation_lots('public','33003');
