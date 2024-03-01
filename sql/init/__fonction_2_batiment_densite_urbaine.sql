CREATE OR REPLACE FUNCTION public.__2_batiment_densite_urbaine(
	schema_prod text,
	schema_bdtopo text,
	schema_ff text,
	nom_ff_tup text,
	nom_geom_tup text,
	idcom text,
	bdt_com text,
	bdt_bat text,
	surfminbat float,
	surf_comblement float,
	reserve_dense float,
	reserve_groupe float,
	reserve_diffus float,
	reserve_isole float
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$
	
BEGIN

	--1. extraction des TUP sur la commune
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_tup_' || idcom || ''; 
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_tup_' || idcom || ' as
		SELECT idcom,idtup,nlocdep,nloccom,dcntpa,catpro2,catpro2txt,dcntarti,' || nom_geom_tup || ' as geom
		FROM ' || schema_ff || '.' || nom_ff_tup || '
		WHERE idcom = ''' || idcom || ''' and ncontour>0';

	--2. extraction du contour de la commune
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_com_' || idcom || ''; 
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_com_' || idcom || ' as
		SELECT * FROM ' || schema_bdtopo || '.' || bdt_com || ' WHERE insee_com = ''' || idcom || '''';

	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_com_' || idcom || ' USING gist(geom)';

	--3. extraction des bâtiments sur la commune d'étude
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_bati_' || idcom || ' AS
		SELECT bat.* FROM ' || schema_bdtopo || '.' || bdt_bat || ' bat,' || schema_prod || '.gf_com_' || idcom || ' com
		WHERE ST_Contains(com.geom,bat.geom)
		AND ST_Area(bat.geom) >= ' || surfminbat || '';
		
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' ADD COLUMN geom2 geometry(MultiPolygon, 2154)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_bati_' || idcom || ' SET geom2 = ST_Force2D(geom)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' DROP COLUMN geom';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' RENAME COLUMN geom2 TO geom';
	
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' ADD COLUMN centroid geometry';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_bati_' || idcom || ' SET centroid=ST_Centroid(geom)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' ALTER COLUMN geom type geometry(MultiPolygon, 2154) using ST_Multi(geom)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' ALTER COLUMN centroid type geometry(Point, 2154)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' ADD CONSTRAINT gf_bati_' || idcom || '_pkey PRIMARY KEY (id)';


	--création d'un polygone de bâtiment plus petit pour éviter que les parcelles non bâties intersectent des bâtiments en limite de parcelle
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' ADD COLUMN geom2 geometry(MultiPolygon, 2154)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_bati_' || idcom || ' SET geom2=St_Multi(ST_Buffer(geom,-1))';

	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_bati_' || idcom || ' USING gist(geom)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_bati_' || idcom || ' USING gist(centroid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_bati_' || idcom || ' USING gist(geom2)';

	--5.Calcul de la densité urbaine
	--5a. constructions isolees
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_isole_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_bati_isole_' || idcom || ' AS 
		WITH 
			a AS (SELECT row_number() over() as gid,(ST_Dump(ST_Union(ST_Buffer(geom,40)))).geom AS geom FROM ' || schema_prod || '.gf_bati_' || idcom || '),
			b AS (SELECT Count(*) as nb,a.gid,a.geom FROM a,' || schema_prod || '.gf_bati_' || idcom || ' AS bat WHERE ST_Intersects(a.geom,bat.centroid) GROUP BY a.gid,a.geom),
			c AS (SELECT distinct id,nb FROM b,' || schema_prod || '.gf_bati_' || idcom || ' AS bat WHERE ST_Intersects(b.geom,bat.geom))
		SELECT
			bat.id,bat.geom,bat.geom2,bat.centroid,
			CASE WHEN nb < 5 THEN ''isolee''
			END::varchar(10) AS densite
		FROM ' || schema_prod || '.gf_bati_' || idcom || ' AS bat
		LEFT JOIN c ON bat.id=c.id'
		;

	--5b. Constructions diffuses et groupees (part1)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_diffuse_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_bati_diffuse_' || idcom || ' AS 
		WITH 
			a AS (SELECT row_number() over() as gid,(ST_Dump(ST_Union(ST_Buffer(geom,20)))).geom AS geom FROM ' || schema_prod || '.gf_bati_isole_' || idcom || ' WHERE densite IS NULL),
			b AS (SELECT Count(*) as nb,a.gid,a.geom FROM a,' || schema_prod || '.gf_bati_isole_' || idcom || ' AS bat WHERE ST_Intersects(a.geom,bat.centroid) AND densite IS NULL GROUP BY a.gid,a.geom),
			c AS (SELECT distinct id,nb FROM b,' || schema_prod || '.gf_bati_isole_' || idcom || ' AS bat WHERE densite IS NULL AND ST_Intersects(b.geom,bat.geom))
		SELECT
			bat.id,bat.geom,bat.geom2,bat.centroid,
			CASE 
				WHEN nb < 5 THEN ''diffuse''
				WHEN nb >= 5 AND nb <= 9 THEN ''groupee''
			END::varchar(10) AS densite
		FROM ' || schema_prod || '.gf_bati_isole_' || idcom || ' AS bat
		LEFT JOIN c ON bat.id=c.id
		WHERE densite IS NULL'
		; 

	--5c. Constructions denses et groupees (part2)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_groupe_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_bati_groupe_' || idcom || ' AS 
		WITH 
			a AS (SELECT row_number() over() as gid,(ST_Dump(ST_Union(ST_Buffer(geom,10)))).geom AS geom FROM ' || schema_prod || '.gf_bati_diffuse_' || idcom || ' WHERE densite IS NULL),
			b AS (SELECT Count(*) as nb,a.gid,a.geom FROM a,' || schema_prod || '.gf_bati_diffuse_' || idcom || ' AS bat WHERE ST_Intersects(a.geom,bat.centroid) AND densite IS NULL GROUP BY a.gid,a.geom),
			c AS (SELECT distinct id,nb FROM b,' || schema_prod || '.gf_bati_diffuse_' || idcom || ' AS bat WHERE densite IS NULL AND ST_Intersects(b.geom,bat.geom))
		SELECT
			bat.id,bat.geom,bat.geom2,bat.centroid,
			CASE 
				WHEN nb <= 5 THEN ''groupee''
				WHEN nb > 5 THEN ''dense''
			END::varchar(10) AS densite
		FROM ' || schema_prod || '.gf_bati_diffuse_' || idcom || ' AS bat
		LEFT JOIN c ON bat.id=c.id
		WHERE densite IS NULL'
		; 

	--5d. création couche bâti densité urbaine
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_dense_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_bati_dense_' || idcom || ' AS 
		SELECT id,densite,geom2,geom FROM ' || schema_prod || '.gf_bati_isole_' || idcom || ' WHERE densite IS NOT NULL
		UNION
		SELECT id,densite,geom2,geom FROM ' || schema_prod || '.gf_bati_diffuse_' || idcom || ' WHERE densite IS NOT NULL
		UNION
		SELECT id,densite,geom2,geom FROM ' || schema_prod || '.gf_bati_groupe_' || idcom || ' WHERE densite IS NOT NULL';

	--5e. ajout du champ tampon du bati
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_dense_' || idcom || ' ADD COLUMN tampon_bat INTEGER';

	EXECUTE 'UPDATE ' || schema_prod || '.gf_bati_dense_' || idcom || ' SET tampon_bat = 
		(CASE 
			WHEN densite=''dense'' THEN ' || reserve_dense || '
			WHEN densite=''groupee'' THEN ' || reserve_groupe || '
			WHEN densite=''diffuse'' THEN ' || reserve_diffus || '
			WHEN densite=''isolee'' THEN ' || reserve_isole || '		
		END)';
		
	--5f. ajout du champ code_densite 1=dense, 2=groupee, 3=diffuse, 4=isolee
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_dense_' || idcom || ' ADD COLUMN code_densite INTEGER';

	EXECUTE 'UPDATE ' || schema_prod || '.gf_bati_dense_' || idcom || ' SET code_densite = 
		(CASE 
			WHEN densite=''dense'' THEN 1
			WHEN densite=''groupee'' THEN 2
			WHEN densite=''diffuse'' THEN 3
			WHEN densite=''isolee'' THEN 4
			
		END)';	
		
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_bati_dense_' || idcom || ' using GIST (geom)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_bati_dense_' || idcom || ' using GIST (geom2)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_dense_' || idcom || ' ADD CONSTRAINT gf_bati_dense_' || idcom || '_pkey PRIMARY KEY(id)';

	--6.Création des aires de densité. Le traitement se fait en 7 étapes
	--6a. phase 1 : dense (bouchage des trous <2500m², buffer de 15 mètres autour des bâtiments)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,
			(ST_DUMP(ST_Union(St_Buffer(geom,15)))).geom as geom 
		FROM ' || schema_prod || '.gf_bati_dense_' || idcom || ' 
		WHERE densite=''dense''';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_dense';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.aire_dense AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.aire_dense
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.aire_dense as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';

	--6b. phase 2 : groupee (bouchage des trous <2500m², buffer de 30 mètres autour des bâtiments))
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,
			(ST_DUMP(ST_Union(St_Buffer(geom,30)))).geom as geom 
		FROM ' || schema_prod || '.gf_bati_dense_' || idcom || ' 
		WHERE densite=''groupee''';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_groupee';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.aire_groupee AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.aire_groupee
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.aire_groupee as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';
		

	--6c. phase 3 : diffuse (bouchage des trous <2500m², buffer de 45 mètres autour des bâtiments)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,
			(ST_DUMP(ST_Union(St_Buffer(geom,45)))).geom as geom 
		FROM ' || schema_prod || '.gf_bati_dense_' || idcom || ' 
		WHERE densite=''diffuse''';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_diffuse';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.aire_diffuse AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.aire_diffuse
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.aire_diffuse as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';


	--6d. phase 4 : dense/groupee (bouchage des trous <2500m², buffer de 25 mètres autour des bâtiments)

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,
			(ST_DUMP(ST_Union(St_Buffer(geom,25)))).geom as geom 
		FROM ' || schema_prod || '.gf_bati_dense_' || idcom || ' 
		WHERE densite IN (''dense'',''groupee'')';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_dense_groupe';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.aire_dense_groupe AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.aire_dense_groupe
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.aire_dense_groupe as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';
		
		
	--6e. phase 5 : groupee/diffuse (bouchage des trous <2500m², buffer de 30 mètres autour des bâtiments)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,
			(ST_DUMP(ST_Union(St_Buffer(geom,30)))).geom as geom 
		FROM ' || schema_prod || '.gf_bati_dense_' || idcom || ' 
		WHERE densite IN (''diffuse'',''groupee'')';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_groupe_diffuse';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.aire_groupe_diffuse AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.aire_groupe_diffuse
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.aire_groupe_diffuse as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';
		
	--6f. phase 6 : diffuse/isolee (bouchage des trous <2500m², buffer de 45 mètres autour des bâtiments)

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,
			(ST_DUMP(ST_Union(St_Buffer(geom,45)))).geom as geom 
		FROM ' || schema_prod || '.gf_bati_dense_' || idcom || ''
		;

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_diffuse_isolee';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.aire_diffuse_isolee AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.aire_diffuse_isolee
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.aire_diffuse_isolee as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';

	--6g. Regroupement : dense->dense, groupee+dense/groupee->groupee, diffus+groupee/diffuse+diffuse/isolee->diffuse

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp11';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp11 as
		SELECT ST_Union(geom) as geom FROM ' || schema_prod || '.aire_dense';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp2';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp2 as
		SELECT ST_Union(geom) as geom FROM
			(SELECT * FROM ' || schema_prod || '.aire_dense
			UNION
			SELECT * FROM ' || schema_prod || '.aire_groupee
			UNION
			SELECT * FROM ' || schema_prod || '.aire_dense_groupe
			) a';

	--suppression des trous <2500m²
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,(ST_dump(geom)).geom as geom 
		FROM ' || schema_prod || '.temp2';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp22';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp22 AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),		(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.temp22
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.temp22 as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp222';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp222 as
		SELECT ST_Union(geom) as geom FROM ' || schema_prod || '.temp22';

		
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp3';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp3 as
		SELECT ST_Union(geom) as geom FROM
			(SELECT * FROM ' || schema_prod || '.aire_dense
			UNION
			SELECT * FROM ' || schema_prod || '.aire_groupee
			UNION
			SELECT * FROM ' || schema_prod || '.aire_diffuse
			UNION
			SELECT * FROM ' || schema_prod || '.aire_dense_groupe
			UNION
			SELECT * FROM ' || schema_prod || '.aire_groupe_diffuse
			UNION
			SELECT * FROM ' || schema_prod || '.aire_diffuse_isolee
			) a';
		
	--suppression des trous <2500m²
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp as
		SELECT row_number() over() as gid,(ST_dump(geom)).geom as geom 
		FROM ' || schema_prod || '.temp3';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT gid, st_makepolygon(st_exteriorring(geom)) as geom
		FROM ' || schema_prod || '.temp';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_2500 AS
	WITH
		tache_anneaux_poly AS(
			SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
			FROM ' || schema_prod || '.temp),
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
	WHERE st_area(geom)>2500';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp33';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp33 AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.anneaux_sup_2500 as t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.temp33
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous as t1, ' || schema_prod || '.temp33 as t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp333';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp333 AS
		SELECT ST_Union(geom) AS geom FROM ' || schema_prod || '.temp33';

	-- création de la couche aire densité avec les 3 zones dense, groupee et diffuse

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_aires_densite_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_aires_densite_' || idcom || ' AS 
		SELECT geom AS geom,''dense''::VARCHAR(10) AS densite FROM ' || schema_prod || '.aire_dense
		UNION
		SELECT (ST_DUMP(ST_Difference(a.geom,b.geom))).geom AS geom,''groupee''::VARCHAR(10) AS densite FROM ' || schema_prod || '.temp222 a,' || schema_prod || '.temp11 b
		UNION
		SELECT (ST_DUMP(ST_Difference(a.geom,b.geom))).geom AS geom,''diffuse''::VARCHAR(10) AS densite FROM ' || schema_prod || '.temp333 a,' || schema_prod || '.temp222 b'
		;

	-- Ajout à la couche aire densité de la zone "isolee" (différence entre enveloppe urbaine et couche densité 3 zones)
	EXECUTE 'WITH 
		a AS (SELECT ST_UNION(geom) as geom FROM ' || schema_prod || '.gf_aires_densite_' || idcom || '),
		b AS (SELECT (ST_DUMP(ST_DIFFERENCE(env_com.geom,a.geom))).geom as geom,''isolee''::VARCHAR(10) AS densite FROM ' || schema_prod || '.gf_com_' || idcom || ' AS env_com,a)
	INSERT INTO ' || schema_prod || '.gf_aires_densite_' || idcom || ' SELECT * from b';
		
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_aires_densite_' || idcom || ' using GIST (geom)';


	--création de la couche de bâtiment nette
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_net_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_bati_net_' || idcom || ' AS 
		WITH a AS (SELECT a.id,a.densite,a.code_densite,a.tampon_bat, b.idtup, st_intersection(a.geom,b.geom) AS geom
				FROM ' || schema_prod || '.gf_bati_dense_' || idcom || ' AS a, ' || schema_prod || '.gf_tup_' || idcom || ' AS b
				WHERE st_intersects(geom2, b.geom) and st_isvalid(b.geom) and st_isvalid(a.geom))
		SELECT * FROM a';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_net_' || idcom || ' ADD COLUMN gid serial';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_net_' || idcom || ' ADD CONSTRAINT gf_bati_net_' || idcom || '_pkey PRIMARY KEY(gid)';

	--regroupement des bâtiments par unité foncière
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bat_union_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_bat_union_' || idcom || ' AS 
		SELECT idtup,MIN(tampon_bat) as tampon_bat,MIN(code_densite) as code_densite,ST_UNION(ST_BUFFER(geom,0)) AS geom FROM ' || schema_prod || '.gf_bati_net_' || idcom || ' GROUP BY idtup';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bat_union_' || idcom || ' ADD COLUMN gid serial';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bat_union_' || idcom || ' ADD CONSTRAINT gf_bat_union_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bat_union_' || idcom || ' ADD COLUMN densite varchar(20)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_bat_union_' || idcom || ' SET densite=
		CASE 
			WHEN code_densite=1 THEN ''dense''
			WHEN code_densite=2 THEN ''groupee''
			WHEN code_densite=3 THEN ''diffuse''
			WHEN code_densite=4 THEN ''isolee''
		END';

	--Mise à jour de la table gf_bati avec suppression des géométries geom2 et centroid
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' DROP COLUMN geom2';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' DROP COLUMN centroid';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_bati_' || idcom || ' DROP COLUMN geomloc';
	
	--suppression tables temporaires pour la phase de création des aires de densité:
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp11 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp2 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp22 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp222 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp3 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp33 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp333 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_2500 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_dense CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_groupee CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_diffuse CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_dense_groupe CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_groupe_diffuse CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.aire_diffuse_isolee CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_dense_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_isole_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_diffuse_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_groupe_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bati_net_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_aire_densite_' || idcom || ' CASCADE';

	--Fin de la partie traitement des batiments et de la densité urbaine via la couche des batiments
END;
$BODY$;

--SELECT public.__2_batiment_densite_urbaine('public','r_ign_bdtopo','ff2021','ffta_2021_tup','33003','commune_d33','batiment_d33',25,50,10,15,25,35)