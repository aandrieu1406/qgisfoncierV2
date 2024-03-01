CREATE OR REPLACE FUNCTION public.__5_accessibilite(
	schema_prod text,
	schema_bdtopo text,
	idcom text,
	bdt_route text
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$

DECLARE
	lots varchar[] := array['lot1','lot2','lot3'];
	lot varchar;
BEGIN
	FOREACH lot IN ARRAY lots 
		LOOP
			RAISE NOTICE '%',lot;
			
			--simplification de la table des routes (transformation en 2D) et sélection des routes à l'intérieur de l'enveloppe urbaine (+tampon 200m)
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_route_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_route_' || idcom || ' AS
				SELECT route.id, route.nature, route.cl_admin, route.largeur, ST_Force2D(route.geom) AS geom
				FROM ' || schema_bdtopo || '.' || bdt_route || ' AS route,' || schema_prod || '.gf_com_' || idcom || ' AS com WHERE st_dwithin(route.geom, com.geom, 200)';

			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_route_' || idcom || ' ALTER COLUMN geom type geometry(MultiLineString, 2154) USING ST_Multi(geom)';
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_route_' || idcom || ' ADD COLUMN gid serial';
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_route_' || idcom || ' ADD CONSTRAINT gf_route_' || idcom || '_pkey PRIMARY KEY(gid)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_route_' || idcom || ' USING GIST (geom)';

			-- route à proximité des parcelles
			-- critères de sélection des routes : Chemin, Route à 1 chaussée, Route empierrée, Piste cyclable
			-- critère de proximité = 30m : pour alléger le traitement on ne garde que les routes qui sont à moins de 30m des parcelles

			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_route_zone_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_route_zone_' || lot || '_' || idcom || ' AS
				SELECT DISTINCT a.gid, a.largeur, a.nature, a.cl_admin, a.geom
				FROM ' || schema_prod || '.gf_route_' || idcom || ' AS a, ' || schema_prod || '.gf_uf_' || lot || '_' || idcom || ' AS b
				WHERE a.nature IN (''Chemin'',''Route à 1 chaussée'',''Route empierrée'',''Piste cyclable'') and st_dwithin(a.geom, b.geom, 30)';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_route_zone_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_route_zone_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_route_zone_' || lot || '_' || idcom || ' USING GIST (geom)';

			-- correction des tronçons ne disposant pas de largeur -- Route à 1 chaussée = 7m ??? Pourquoi ??? La plupart des tronçons de type "route à 1 voie" ayant une largeur définie est 3.5, 4 ou 5 ??
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_route_zone_corr_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_route_zone_corr_' || lot || '_' || idcom || ' AS
				SELECT 	gid,
					CASE
						WHEN largeur = 0 and (nature = ''Chemin'' or nature = ''Route empierrée'') THEN 3
						WHEN largeur = 0 and nature = ''Route à 1 chaussée'' THEN 7
						WHEN largeur = 0 and nature = ''Piste cyclable'' THEN 2
						ELSE largeur
					END AS largeur,
					nature,
					cl_admin,
					geom
				FROM ' || schema_prod || '.gf_route_zone_' || lot || '_' || idcom || '';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_route_zone_corr_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_route_zone_corr_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_route_zone_corr_' || lot || '_' || idcom || ' USING GIST (geom)';

			--acces: intersection route (buffer 10m + largeur route / 2), par parcelle 
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_brut_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_acces_brut_' || lot || '_' || idcom || ' AS
				SELECT 
					b.gid,a.gid AS gid_uf,b.largeur,b.cl_admin, 
					st_intersection(ST_MakeValid(st_buffer(a.geom,10 + b.largeur/2)),ST_MakeValid(b.geom)) AS geom
				FROM ' || schema_prod || '.gf_uf_' || lot || '_' || idcom || ' AS a, ' || schema_prod || '.gf_route_zone_corr_' || lot || '_' || idcom || ' AS b
				WHERE st_dwithin(a.geom,b.geom,10 + b.largeur/2)
				order by gid_uf';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_brut_' || lot || '_' || idcom || ' ADD COLUMN gid_route serial';
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_brut_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_acces_brut_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid_route)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_acces_brut_' || lot || '_' || idcom || ' USING GIST (geom)';

			-- accès atomiques avec routes départementales et nationales -> buffer d'un mètre pour la route
			-- Ici on crée une couche de routes transformée en polygones de largeur 2m, rattachées aux parcelles. Le lien se fait par l'identifiant UF de la parcelle
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_acces_' || lot || '_' || idcom || ' AS
				WITH acces_fus AS (SELECT gid_uf, count(gid) AS n_troncon,cl_admin, st_union(geom) AS geom_grep
							FROM ' || schema_prod || '.gf_acces_brut_' || lot || '_' || idcom || '
							group by gid_uf,cl_admin),
					acces_fus_buf AS (SELECT gid_uf,n_troncon,cl_admin, st_buffer(geom_grep,1) AS geom
								FROM acces_fus),
					acces_fus_buf_deg AS (SELECT gid_uf,cl_admin, n_troncon,(st_dump(geom)).geom AS geom_dump
								FROM acces_fus_buf)
				SELECT *
				FROM acces_fus_buf_deg';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_' || lot || '_' || idcom || ' ADD COLUMN gid_acces serial';	
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_acces_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid_acces)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_acces_' || lot || '_' || idcom || ' USING GIST (geom_dump)';

			--typage des accès atomiques (avec nationales et départementales)
			--Ici on qualifie les accès (angle ou simple) en fonction du ratio entre la surface de l'enveloppe convexe de la route et la surface de la route (largeur 2m). Le seuil est fixé à 3
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_type_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_acces_type_' || lot || '_' || idcom || ' AS
				WITH 
					acces_convex AS (SELECT *,st_convexhull(geom_dump) AS geom_convex
							FROM ' || schema_prod || '.gf_acces_' || lot || '_' || idcom || '),
					acces_aire AS (SELECT *, st_area(acces_convex.geom_convex) / st_area(geom_dump) AS ratio_acces
								FROM acces_convex)			
					SELECT *,
						CASE
							WHEN ratio_acces > 3 THEN ''acces_angle''
							ELSE ''acces_simple''
						END::varchar(50) AS type_acces
					FROM acces_aire';
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_type_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_acces_type_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid_acces)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_acces_type_' || lot || '_' || idcom || ' USING gist (geom_convex)';

			--sous-typage des accés atomiques (hors nationales et départementales) difference entre angle et raquettes
			--On crée une ligne directe (la plus courte) entre le centroide de l'enveloppe convexe du tronçon route et le tronçon. Si cette ligne intersecte le segment de route, le sous-typage est de type "autre", sinon, c'est de type "acces_angle"

			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_sous_type_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_acces_sous_type_' || lot || '_' || idcom || ' AS
				WITH cent AS (SELECT gid_acces, gid_uf, st_centroid(geom_dump) AS geom_cent, geom_dump
							FROM ' || schema_prod || '.gf_acces_type_' || lot || '_' || idcom || '
							WHERE type_acces = ''acces_angle''),
					orient AS (SELECT cent.*, b.geom, st_shortestline(geom_cent, st_convexhull(b.geom)) AS line
							FROM cent, ' || schema_prod || '.gf_uf_' || lot || '_' || idcom || ' AS b
							WHERE cent.gid_uf = b.gid),
					sous_typ AS (SELECT orient.*,
							CASE
								WHEN st_intersects(geom_dump, st_shortestline(geom_cent, st_convexhull(geom))) is FALSE THEN ''acces_angle''
								ELSE ''autre''
							END AS sous_type_acces
					FROM orient)
				SELECT row_number() over() AS gid,a.*, sous_typ.geom_cent, sous_typ.line,sous_typ.sous_type_acces
				FROM ' || schema_prod || '.gf_acces_type_' || lot || '_' || idcom || ' AS a left outer join sous_typ on a.gid_acces = sous_typ.gid_acces';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_sous_type_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_acces_sous_type_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_acces_sous_type_' || lot || '_' || idcom || ' USING gist (geom_dump)';

			--connexion au réseau
			--On connecte les tronçons routes avec les parcelles (chemin le plus court) -> couche de lignes
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_connexion_reseau_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_connexion_reseau_' || lot || '_' || idcom || ' AS
				SELECT row_number() over() AS gid,a.gid_acces,a.type_acces, b.gid AS gid_uf, st_shortestline(b.geom, a.geom_dump) AS geom_l
				FROM ' || schema_prod || '.gf_acces_sous_type_' || lot || '_' || idcom || ' AS a, ' || schema_prod || '.gf_uf_' || lot || '_' || idcom || ' AS b
				WHERE  a.gid_uf = b.gid';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_connexion_reseau_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_connexion_reseau_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_connexion_reseau_' || lot || '_' || idcom || ' USING GIST (geom_l)';

			--test de validité
			--C'est pour éviter des cas du type parcelle trés fine entre la parcelle testée et l'accés proprement dit, qui empèche l'accés réel. 
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_type_valide_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_acces_type_valide_' || lot || '_' || idcom || ' AS
				WITH inter_acces AS (SELECT a.*, st_intersection(a.geom_l, st_buffer(b.geom,-2)) AS geom_inter_acces
								FROM ' || schema_prod || '.gf_connexion_reseau_' || lot || '_' || idcom || ' AS a, ' || schema_prod || '.gf_uf_' || lot || '_' || idcom || ' AS b
								WHERE a.gid_uf = b.gid)
				SELECT row_number() over() AS gid,a.gid_acces, geometrytype(a.geom_inter_acces),
					CASE
						WHEN st_isempty(a.geom_inter_acces) or geometrytype(a.geom_inter_acces)=''POINT'' THEN ''acces_valide''
						WHEN geometrytype(a.geom_inter_acces)=''LINESTRING'' and st_length(geom_inter_acces) /  st_length(geom_l) < 0.3 THEN ''acces_valide_b''
						ELSE ''acces_non_valide''
					END AS validite	
				FROM inter_acces AS a';
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_type_valide_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_acces_type_valide_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid)';

			--jointure accès
			--ajout d'une colonne validité à la table acces_sous_type
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_valide_def_' || lot || '_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_acces_valide_def_' || lot || '_' || idcom || ' AS
				SELECT row_number() over() AS gid2,a.*, COALESCE(b.validite, ''acces_valide_type2'')  AS validite
				FROM ' || schema_prod || '.gf_acces_sous_type_' || lot || '_' || idcom || ' AS a left outer join ' || schema_prod || '.gf_acces_type_valide_' || lot || '_' || idcom || ' AS b on a.gid_acces = b.gid_acces';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_acces_valide_def_' || lot || '_' || idcom || ' ADD CONSTRAINT gf_acces_valide_def_' || lot || '_' || idcom || '_pkey PRIMARY KEY(gid2)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_acces_valide_def_' || lot || '_' || idcom || ' USING GIST (geom_dump)';

			-- typage des parcelles, typage des doubles accès
			-- 
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_' || lot || '_acces_' || idcom || '';
			EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_' || lot || '_acces_' || idcom || ' AS
				WITH acces_uf AS (SELECT count(gid_acces)AS nb_acces, cast(array_agg(gid_acces) AS varchar(200)) AS acces_uf, gid_uf,cast(array_agg(cl_admin) AS varchar(200)) AS cl_admin, cast(array_agg(type_acces) AS varchar(200)) AS types_acces,cast(array_agg(sous_type_acces) AS varchar(200)) AS sous_type_acces, st_union(geom_dump) AS geom_acces
							FROM ' || schema_prod || '.gf_acces_valide_def_' || lot || '_' || idcom || '
							WHERE  validite != ''acces_non_valide''
							group by gid_uf)
				SELECT row_number() over() AS gid,a.idtup,a.geom,a.surface,a.densite,acces_uf.*
				FROM ' || schema_prod || '.gf_uf_' || lot || '_' || idcom || ' AS a left outer join acces_uf on (a.gid = acces_uf.gid_uf)';
				
			EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_' || lot || '_acces_' || idcom || ' ADD CONSTRAINT gf_uf_' || lot || '_acces_' || idcom || '_pkey PRIMARY KEY(gid)';
			EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_' || lot || '_acces_' || idcom || ' USING GIST (geom_acces)';
			
			--suppression tables temporaires
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_brut_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_sous_type_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_type_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_type_valide_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_valide_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_acces_valide_def_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_connexion_reseau_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_route_zone_corr_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_route_zone_' || lot || '_' || idcom || ' CASCADE';
			EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_' || idcom || ' CASCADE';			
			
		
		END LOOP;
END;
$BODY$;

-- SELECT public.__5_accessibilite('public','r_ign_bdtopo','33003','troncon_de_route_d33');
