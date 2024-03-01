CREATE OR REPLACE FUNCTION public.__1_envurb_sansplu(
	schema_prod text,
	schema_data text,
	schema_bdtopo text,
	idcom text,
	bdt_com text,
	nom_envurb text,
	nom_plu text,
	surf_min_zone integer,
	surf_comblement integer	
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$
	
begin
  
	--Import du PLU de la commune
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_plu_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_plu_' || idcom || ' AS
		WITH 
			com AS 
				(SELECT cast(' || idcom || ' as char(5)) as idcom,ST_Buffer(geom,200) as geom 
				FROM ' || schema_bdtopo || '.' || bdt_com || ' WHERE insee_com = ''' || idcom || '''),
			plu AS
				(SELECT row_number() over() as gid,libelle,typezone,st_buffer(a.geom,0) as geom 
				FROM ' || schema_data || '.' || nom_plu || ' a,com where st_intersects(a.geom,com.geom))
		SELECT 
			gid,libelle,typezone,idcom,
			ST_Intersection(plu.geom,com.geom) as geom --buffer de 200m autour de la commune pour éviter l''effet de bord
		FROM com,plu
		WHERE ST_Intersects(plu.geom,com.geom)';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_plu_' || idcom || ' ALTER COLUMN geom type geometry(MultiPolygon, 2154) using ST_Multi(geom)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_plu_' || idcom || ' USING gist(geom)';

	--Import de l'enveloppe urbaine
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp1';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp1 AS
		SELECT ST_Makevalid(ST_Intersection(a.geom,ST_BUFFER(b.geom,10))) AS geom
		FROM ' || schema_data || '.' || nom_envurb || ' a,' || schema_bdtopo || '.' || bdt_com || ' b
		WHERE insee_com = ''' || idcom || ''' AND ST_Intersects(a.geom,b.geom)';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp2';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp2 AS
		SELECT (ST_DUMP(ST_UNION(geom))).geom AS geom
		FROM ' || schema_prod || '.temp1';
		
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.temp2 USING gist(geom)';

	--Suppression des zones très petites (<500m²)
	EXECUTE 'DELETE FROM ' || schema_prod || '.temp2 WHERE ST_AREA(geom)< ' || surf_min_zone ||'';

	--Comblement des très petits trous au sein de l'enveloppe urbaine
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp2';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_50';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_50 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp2),
		decompte_trou AS (
			SELECT id, geom, ST_NumInteriorRings(geom) as nb_trou
			FROM tache_anneaux_poly),
		creation_des_anneaux AS (
			SELECT id, n as num_trou, st_makepolygon(st_interiorringn(geom,n)) as geom
			FROM decompte_trou
			CROSS JOIN generate_series(1,nb_trou) as n
			WHERE nb_trou>0)
	SELECT *
	FROM creation_des_anneaux
	WHERE st_area(geom)> ' || surf_comblement || '';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_50 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.temp
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.temp as t2
		WHERE st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';
		
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_envurb_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_envurb_' || idcom || ' AS
		SELECT 
			row_number() over() as gid,
			geom from
			(select st_buffer(st_buffer((ST_DUMP(geom)).geom,0.1),-0.1)  AS geom from ' || schema_prod || '.temp) a'	;

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_envurb_' || idcom || ' ALTER COLUMN geom type geometry(MultiPolygon, 2154) using ST_Multi(geom)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_envurb_' || idcom || ' ADD CONSTRAINT gf_envurb_' || idcom || '_pkey primary key(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_envurb_' || idcom || ' USING gist(geom)';

	--suppression tables temporaires	
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_50 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp1 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp2 CASCADE';	

END;
$BODY$;

--SELECT public.__1_envurb_sansplu('public','r_ign_bdtopo','33001','commune_d33','envurb_33','plu_33',500,50);