CREATE OR REPLACE FUNCTION public.__3_uf_non_bati_lot1(
	schema_prod text,
	idcom text,
	taux_surface float,
	surfminuf float,
	largeur_min float,
	taux_convexhull float,
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

	--Sélection des unités foncière dans l'enveloppe urbaine
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_uf_envurb_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_envurb_' || idcom || ' AS 
		SELECT idcom, idtup, dcntpa,   nlocdep, nloccom, 
			a.geom, catpro2, catpro2txt, ST_AREA (ST_INTERSECTION(a.geom, b.geom)) as surf_int,
			100*(ST_AREA(ST_INTERSECTION(a.geom, b.geom)))/dcntpa as recouvr
		FROM ' || schema_prod || '.gf_tup_' || idcom || ' a,' || schema_prod || '.gf_envurb_' || idcom || ' b
		WHERE dcntpa>0 AND ST_INTERSECTS(a.geom, b.geom) AND
		(100*ST_AREA(ST_INTERSECTION(a.geom, b.geom))/dcntpa)>= ' || taux_surface || ' AND
		ST_AREA (ST_INTERSECTION(a.geom, b.geom))>= ' || surfminuf || '';
		
	--ALTER TABLE ' || schema_prod || '.gf_uf_envurb_' || idcom || ' ADD CONSTRAINT :pk1 primary key(idtup);
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_envurb_' || idcom || ' using GIST (geom)';

	--Sélection des unités foncières bâties
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_uf_bati_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_bati_' || idcom || ' AS 
		SELECT idcom, idtup, dcntpa,   nlocdep, nloccom, 
				catpro2, catpro2txt,geom
		FROM ' || schema_prod || '.gf_uf_envurb_' || idcom || '
		WHERE idtup IN (SELECT idtup FROM ' || schema_prod || '.gf_bat_union_' || idcom || ')';
		
	--EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bati_' || idcom || ' ADD CONSTRAINT gf_uf_bati_' || idcom || '_pkey PRIMARY KEY(idtup)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_bati_' || idcom || ' using GIST (geom)';

	--soustraction du bâti précédement défini aux unités foncières (utilisation du champ tampon_bat) -> couche unité foncière
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_uf_bati_trou_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_bati_trou_' || idcom || ' AS
		SELECT 
			a.idtup,b.code_densite, b.densite, st_multi(st_difference(a.geom, ST_Makevalid(st_buffer(b.geom,b.tampon_bat)))) AS geom
		FROM ' || schema_prod || '.gf_uf_bati_' || idcom || ' AS a 
		LEFT OUTER JOIN ' || schema_prod || '.gf_bat_union_' || idcom || ' AS b 
		ON (a.idtup = b.idtup and st_isvalid(a.geom))';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bati_trou_' || idcom || ' add column gid serial';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_bati_trou_' || idcom || ' add constraint gf_uf_bati_trou_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_bati_trou_' || idcom || ' using GIST (geom)';

	--Sélection des unités foncières non bâties (sélection inverse des unités foncières bâties) avec suppression des parties trop étroites (moins de 6 mètres de large)
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' AS 
		SELECT idcom, idtup, dcntpa,
				catpro2, catpro2txt,ST_BUFFER(ST_BUFFER(geom, -(' || largeur_min || '/2)), ' || largeur_min || '/2) as geom, ST_AREA(ST_BUFFER(ST_BUFFER(geom, -(' || largeur_min || '/2)), ' || largeur_min || '/2)) as surface
		FROM ' || schema_prod || '.gf_uf_envurb_' || idcom || '
		WHERE idtup NOT IN (SELECT idtup FROM ' || schema_prod || '.gf_bat_union_' || idcom || ')';
		
	--EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' ADD CONSTRAINT gf_uf_non_bati_' || idcom || '_pkey PRIMARY KEY(idtup)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' using GIST (geom)';

	EXECUTE 'DELETE FROM ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' WHERE surface = 0';


	--Ajout de l'attribut densité urbaine aux UF lot1. On classe d'abord les UF dense, ensuite groupee, puis diffuse et enfin isolee
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' ADD COLUMN densite VARCHAR(10)';

	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' a SET densite=
		(SELECT densite FROM (SELECT * FROM ' || schema_prod || '.gf_aires_densite_' || idcom || ' WHERE densite=''dense'')b WHERE ST_Intersects(a.geom,b.geom) AND ST_Area(ST_Intersection(a.geom,b.geom))/ST_Area(a.geom)>0.5) WHERE densite IS NULL';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' a SET densite=
		(SELECT densite FROM (SELECT * FROM ' || schema_prod || '.gf_aires_densite_' || idcom || ' WHERE densite=''groupee'')b WHERE ST_Intersects(a.geom,b.geom) AND ST_Area(ST_Intersection(a.geom,b.geom))/ST_Area(a.geom)>0.5) WHERE densite IS NULL';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' a SET densite=
		(SELECT densite FROM (SELECT * FROM ' || schema_prod || '.gf_aires_densite_' || idcom || ' WHERE densite=''diffuse'')b WHERE ST_Intersects(a.geom,b.geom) AND ST_Area(ST_Intersection(a.geom,b.geom))/ST_Area(a.geom)>0.5) WHERE densite IS NULL';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' a SET densite=''isolee'' WHERE densite IS NULL';

	--Ajout coefficient de Gravelius: 0,28*(P/sqrt(A)) (P= périmètre, A = aire)
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' ADD COLUMN gravelius NUMERIC';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' SET gravelius = 
		CASE WHEN ST_AREA(geom) >0 THEN 0.28*(ST_PERIMETER(geom)/SQRT(ST_AREA(geom))) END';

	--Ajout coefficient de formes particulières (pour détecter les routes de lotissement par exemple)
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' ADD COLUMN taux_convexhull NUMERIC';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' SET taux_convexhull = 
		CASE WHEN ST_AREA(geom) >0 THEN (ST_AREA(geom)/ST_AREA(ST_ConvexHull(geom))*100) END';

	--Classement des UF en fonction des critères de surfaces et du coeff de Gravelius cf tableau p 15
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' ADD COLUMN constructible VARCHAR(1)';

	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= (' || surf_dense || ' * 5) AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			WHEN surface >= (' || surf_dense || ' * 1.5) AND surface < (' || surf_dense || ' * 5) AND gravelius < 1.95 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			WHEN surface >= (' || surf_dense || ') AND surface < (' || surf_dense || ' * 1.5) AND gravelius < 1.4 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			ELSE ''N''
		END) WHERE densite = ''dense''';
		
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= ' || surf_groupee || ' * 4 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			WHEN surface >= (' || surf_groupee || ' * 2) AND surface < (' || surf_groupee || ' * 4) AND gravelius < 2.05 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			WHEN surface >= (' || surf_groupee || ') AND surface < (' || surf_groupee || ' * 2) AND gravelius < 1.5 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			ELSE ''N''
		END) WHERE densite = ''groupee''';
		
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' SET constructible = 
		(CASE 
			WHEN surface >= ' || surf_diffuse || ' * 3 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			WHEN surface >= (' || surf_diffuse || ' * 1.5) AND surface < (' || surf_diffuse || ' * 3) AND gravelius < 2.25 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			WHEN surface >= (' || surf_diffuse || ') AND surface < (' || surf_diffuse || ' * 1.5) AND gravelius < 1.75 AND taux_convexhull >= ' || taux_convexhull || ' THEN ''O''
			ELSE ''N''
		END) WHERE densite IN (''diffuse'',''isolee'')';

	--création de la table des UF non bâtie répondant aux critères (lot 1)
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_uf_lot1_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot1_' || idcom || ' AS 
		SELECT *
		FROM ' || schema_prod || '.gf_uf_non_bati_' || idcom || '
		WHERE constructible =''O''';
		
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot1_' || idcom || ' ADD COLUMN gid serial';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot1_' || idcom || ' ADD CONSTRAINT gf_uf_lot1_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_lot1_' || idcom || ' using GIST (geom)';

	--création de la table des UF non bâtie ne répondant pas aux critères
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_uf_non_bat_ti_' || idcom || ' CASCADE';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_non_bat_ti_' || idcom || ' AS 
		SELECT idcom, idtup, dcntpa,
				catpro2, catpro2txt,(ST_DUMP(geom)).geom as geom, ST_AREA((ST_DUMP(geom)).geom) as surface
		FROM ' || schema_prod || '.gf_uf_non_bati_' || idcom || '
		WHERE constructible =''N'' AND taux_convexhull >= ' || taux_convexhull || '';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_non_bat_ti_' || idcom || ' ADD COLUMN gid serial';	
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_non_bat_ti_' || idcom || ' ADD CONSTRAINT gf_uf_non_bat_ti_' || idcom || '_pkey PRIMARY KEY(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_non_bat_ti_' || idcom || ' using GIST (geom)';
	
	--suppression tables temporaires
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_envurb_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_non_bati_' || idcom || ' CASCADE';	
	
END;
$BODY$;

--SELECT public.__3_uf_non_bati_lot1('public','33003',30,100,6,50,300)
