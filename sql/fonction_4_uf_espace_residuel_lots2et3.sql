CREATE OR REPLACE FUNCTION public.__4_uf_espace_residuel_lots2et3(
	schema_prod text,
	idcom text,
	largeur_min integer,
	surf_dense integer
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$

DECLARE
	dep varchar := left(idcom,2);
	surf_groupee integer :=round(surf_dense*1.66);
	surf_diffuse integer :=round(surf_dense*3.33);
BEGIN

	--calcul des aplats - sous parties
	--à partir de la table espace_residuel nettoyage des petits morceaux de largeur inférieure à 6m (tampon négatif de 3m suivi d'un tampon positif de 3m)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_aplat_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_aplat_' || idcom || ' AS
		SELECT gid,idtup,code_densite,densite,st_buffer(st_buffer(geom, -(' || largeur_min || '/2)), ' || largeur_min || '/2) AS geom_ap
		FROM ' || schema_prod || '.gf_uf_bati_trou_' || idcom || '';
		
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_aplat_' || idcom || ' ADD CONSTRAINT gf_aplat_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_aplat_' || idcom || ' using GIST (geom_ap)';

	--sous parties dégroupees (multipolygone vers polygone)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_ap_deg_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_ap_deg_' || idcom || ' AS
		SELECT idtup,code_densite,densite, (st_dump(geom_ap)).geom AS geom_ap_dgrp
		FROM ' || schema_prod || '.gf_aplat_' || idcom || '';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_ap_deg_' || idcom || ' ADD COLUMN gid_ap serial';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_ap_deg_' || idcom || ' ADD CONSTRAINT gf_ap_deg_' || idcom || '_pkey PRIMARY KEY(gid_ap)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_ap_deg_' || idcom || ' using GIST(geom_ap_dgrp)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_ap_deg_' || idcom || ' using btree(idtup)';

	--aplat_[idcom]_[millesime] max
	--typage des résidus : clASsement des sous-parties selon leur taille (principal ou secondaire avec la surface)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_ap_deg_max_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' AS
		WITH a AS (SELECT gid_ap, idtup,code_densite,densite, st_area(geom_ap_dgrp) AS surface, max(st_area(geom_ap_dgrp)) over (partition by idtup) AS surf_ap_max
		FROM ' || schema_prod || '.gf_ap_deg_' || idcom || '),
			jonction AS (SELECT b.*, a.surface, a.surf_ap_max
				FROM ' || schema_prod || '.gf_ap_deg_' || idcom || ' AS b, a
				where a.gid_ap = b.gid_ap)
		SELECT *,
			CASE
				when  surface = surf_ap_max then ''principal''
				when  surface != surf_ap_max then ''secondaire''
			end AS type_applet
		FROM jonction';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' ADD CONSTRAINT gf_ap_deg_max_' || idcom || '_pkey PRIMARY KEY(gid_ap)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' using GIST (geom_ap_dgrp)';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' ADD COLUMN gravelius NUMERIC';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' SET gravelius = 0.28*(ST_PERIMETER(geom_ap_dgrp)/SQRT(ST_AREA(geom_ap_dgrp)))';

	--Classement des espaces résiduels en fonction des critères de surfaces et du coeff de Gravelius cf tableau p 15
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' ADD COLUMN constructible VARCHAR(1)';

	EXECUTE 'UPDATE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= (' || surf_dense || ' * 5) THEN ''O''
			WHEN surface >= (' || surf_dense || ' * 1.5) AND surface < (' || surf_dense || ' * 5) AND gravelius < 1.95 THEN ''O''
			WHEN surface >= (' || surf_dense || ') AND surface < (' || surf_dense || ' * 1.5) AND gravelius < 1.4 THEN ''O''
			ELSE ''N''
		END) WHERE code_densite = 1';
		
	EXECUTE 'UPDATE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= ' || surf_groupee || ' * 4 THEN ''O''
			WHEN surface >= (' || surf_groupee || ' * 2) AND surface < (' || surf_groupee || ' * 4) AND gravelius < 2.05 THEN ''O''
			WHEN surface >= (' || surf_groupee || ') AND surface < (' || surf_groupee || ' * 2) AND gravelius < 1.5 THEN ''O''
			ELSE ''N''
		END) WHERE code_densite = 2';
		
	EXECUTE 'UPDATE ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= ' || surf_diffuse || ' * 3 THEN ''O''
			WHEN surface >= (' || surf_diffuse || ' * 1.5) AND surface < (' || surf_diffuse || ' * 3) AND gravelius < 2.25 THEN ''O''
			WHEN surface >= (' || surf_diffuse || ') AND surface < (' || surf_diffuse || ' * 1.5) AND gravelius < 1.75 THEN ''O''
			ELSE ''N''
		END) WHERE code_densite IN (3,4)';

	-- ensemble des sous parties répondant aux critères (lot2)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot2_' || idcom || ' AS
		SELECT row_number() over() AS gid,gid_ap,idtup,code_densite,densite,surface,surf_ap_max,type_applet,geom_ap_dgrp AS geom
		FROM ' || schema_prod || '.gf_ap_deg_max_' || idcom || '
		where constructible=''O''';
		
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot2_' || idcom || ' ADD CONSTRAINT gf_uf_lot2_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_lot2_' || idcom || ' using GIST (geom)';

	-- ensemble des sous parties ne répondant pas aux critères (reliquat lot2)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_reliquats_lots1_2_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_reliquats_lots1_2_' || idcom || ' AS
		SELECT row_number() over() AS gid,gid_ap,idtup,code_densite,densite,surface,surf_ap_max,type_applet,geom_ap_dgrp AS geom
		FROM ' || schema_prod || '.gf_ap_deg_max_' || idcom || '
		where constructible=''N''';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_reliquats_lots1_2_' || idcom || ' ADD CONSTRAINT gf_reliquats_lots1_2_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_reliquats_lots1_2_' || idcom || ' using GIST (geom)';

	--création de la table unifiée des espaces résiduels insuffisant (reliquats lot1 et lot2)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_bat_lot3_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_bat_lot3_' || idcom || ' AS
		SELECT idtup,geom
		FROM ' || schema_prod || '.gf_reliquats_lots1_2_' || idcom || '
		UNION
		SELECT idtup, geom
		FROM ' || schema_prod || '.gf_uf_non_bat_ti_' || idcom || '';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bat_lot3_' || idcom || ' ADD COLUMN gid serial';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bat_lot3_' || idcom || ' ADD CONSTRAINT gf_uf_bat_lot3_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_bat_lot3_' || idcom || ' using GIST (geom)';

	-- union des sous parties issues de l'union des reliquats
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' AS
		SELECT a.geom,ARRAY_AGG(idtup) AS idtup FROM
			(SELECT (ST_DUMP(ST_Makevalid(ST_BUFFER(ST_Makevalid(ST_BUFFER(ST_UNION(geom),0.1)),-0.1)))).geom AS geom
			FROM ' || schema_prod || '.gf_uf_bat_lot3_' || idcom || ') a,' || schema_prod || '.gf_uf_bat_lot3_' || idcom || ' b
		WHERE ST_Intersects(a.geom,b.geom)
		GROUP BY a.geom';

	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' using GIST (geom)';

	--Suppression des très petits trous dans les zones (< à 10m²)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.tache_sans_trous AS
		SELECT st_makepolygon(st_exteriorring(geom)) AS geom
		FROM ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || '';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_50';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.anneaux_sup_50 AS
		WITH
			tache_anneaux_poly AS(
				SELECT row_number() over () AS id, st_geometryN(geom,1) AS geom
				FROM ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || '),
			decompte_trou AS (
				SELECT id, geom, ST_NumInteriorRings(geom) AS nb_trou
				FROM tache_anneaux_poly),
			creation_des_anneaux AS (
				SELECT id, n AS num_trou, st_makepolygon(st_interiorringn(geom,n)) AS geom
				FROM decompte_trou
				CROSS JOIN generate_series(1,nb_trou) AS n
				WHERE nb_trou>0)
		SELECT *
		FROM creation_des_anneaux
		WHERE st_area(geom)>10';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp AS
		SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) AS geom
		FROM ' || schema_prod || '.tache_sans_trous AS t1, ' || schema_prod || '.anneaux_sup_50 AS t2
		WHERE st_intersects(t1.geom,t2.geom)';

	EXECUTE 'INSERT INTO ' || schema_prod || '.temp
		SELECT st_multi(t1.geom)
		FROM ' || schema_prod || '.tache_sans_trous AS t1, ' || schema_prod || '.temp AS t2
		where st_intersects(t1.geom,t2.geom) IS FALSE OR t2.geom is NULL';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.temp ADD COLUMN idtup VARCHAR[]';
	EXECUTE 'UPDATE ' || schema_prod || '.temp a SET idtup=(SELECT idtup FROM ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' b WHERE ST_INTERSECTS(a.geom,st_centroid(b.geom)) LIMIT 1)';

	--suppression des zones de largeur inférieure à 6m
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp2';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp2 AS
		SELECT idtup,ST_BUFFER(ST_BUFFER(geom, -(' || largeur_min || '/2)), ' || largeur_min || '/2) AS geom 
		FROM ' || schema_prod || '.temp';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.temp2 ADD COLUMN surface double precision';
	EXECUTE 'UPDATE ' || schema_prod || '.temp2 SET surface=ST_AREA(geom)';
	EXECUTE 'DELETE FROM ' || schema_prod || '.temp2 WHERE surface is null';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' AS
		SELECT idtup,surface,geom
		FROM ' || schema_prod || '.temp2';

	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' using GIST (geom)';
	EXECUTE 'DELETE FROM ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' WHERE surface=0';

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.tache_sans_trous CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.anneaux_sup_50 CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp2 CASCADE';

	--Ajout de l'attribut densité urbaine aux espaces résiduels unis issus du reliquat lot1 et 2.
	--On classe d''abord les UF dense, ensuite groupee, puis diffuse et enfin isolee
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' ADD COLUMN densite VARCHAR(10)';

	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' a SET densite=
		(SELECT densite FROM (SELECT * FROM ' || schema_prod || '.gf_aires_densite_' || idcom || ' WHERE densite=''dense'')b WHERE ST_Intersects(a.geom,b.geom) AND ST_Area(ST_Intersection(a.geom,b.geom))/ST_Area(a.geom)>0.5) WHERE densite IS NULL';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' a SET densite=
		(SELECT densite FROM (SELECT * FROM ' || schema_prod || '.gf_aires_densite_' || idcom || ' WHERE densite=''groupee'')b WHERE ST_Intersects(a.geom,b.geom) AND ST_Area(ST_Intersection(a.geom,b.geom))/ST_Area(a.geom)>0.5) WHERE densite IS NULL';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' a SET densite=
		(SELECT densite FROM (SELECT * FROM ' || schema_prod || '.gf_aires_densite_' || idcom || ' WHERE densite=''diffuse'')b WHERE ST_Intersects(a.geom,b.geom) AND ST_Area(ST_Intersection(a.geom,b.geom))/ST_Area(a.geom)>0.5) WHERE densite IS NULL';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' a SET densite=''isolee'' WHERE densite IS NULL';

	--Ajout coefficient de Gravelius: 0,28*(P/sqrt(A)) (P= périmètre, A = aire)
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' ADD COLUMN gravelius NUMERIC';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' SET gravelius = 
		CASE WHEN ST_AREA(geom) >0 THEN 0.28*(ST_PERIMETER(geom)/SQRT(ST_AREA(geom))) END';

	--Classement des UF en fonction des critères de surfaces et du coeff de Gravelius cf tableau p 15
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' ADD COLUMN constructible VARCHAR(1)';

	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= (' || surf_dense || ' * 5) THEN ''O''
			WHEN surface >= (' || surf_dense || ' * 1.5) AND surface < (' || surf_dense || ' * 5) AND gravelius < 1.95 THEN ''O''
			WHEN surface >= (' || surf_dense || ') AND surface < (' || surf_dense || ' * 1.5) AND gravelius < 1.4 THEN ''O''
			ELSE ''N''
		END) WHERE densite = ''dense''';
		
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= ' || surf_groupee || ' * 4 THEN ''O''
			WHEN surface >= (' || surf_groupee || ' * 2) AND surface < (' || surf_groupee || ' * 4) AND gravelius < 2.05 THEN ''O''
			WHEN surface >= (' || surf_groupee || ') AND surface < (' || surf_groupee || ' * 2) AND gravelius < 1.5 THEN ''O''
			ELSE ''N''
		END) WHERE densite = ''groupee''';
		
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= ' || surf_diffuse || ' * 3 THEN ''O''
			WHEN surface >= (' || surf_diffuse || ' * 1.5) AND surface < (' || surf_diffuse || ' * 3) AND gravelius < 2.25 THEN ''O''
			WHEN surface >= (' || surf_diffuse || ') AND surface < (' || surf_diffuse || ' * 1.5) AND gravelius < 1.75 THEN ''O''
			ELSE ''N''
		END) WHERE densite IN (''diffuse'',''isolee'')';
		
	-- ensemble des reliquats lot1 et 2 répondant aux critères (lot3)	
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot3_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot3_' || idcom || ' AS
		SELECT row_number() over() AS gid,*
		FROM ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || '
		where constructible=''O''';
		
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot3_' || idcom || ' ADD CONSTRAINT gf_uf_lot3_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_lot3_' || idcom || ' using GIST (geom)';
	
	--suppression tables temporaires
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_ap_deg_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_ap_deg_max_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_aplat_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_reliquats_lots1_2_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_bat_lot3_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_bat_lot3_union_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_bati_trou_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_non_bat_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_non_bat_ti_' || idcom || ' CASCADE';			
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_aires_densite_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_bati_' || idcom || ' CASCADE';
	
END;
$BODY$;

--SELECT public.__4_uf_espace_residuel_lots2et3('public','33003',6,300);
