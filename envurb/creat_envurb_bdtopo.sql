/* Méthode :
1. sélection des bâtiments de +25m2
2. sélection des zones anthropisées de la BDTOPO
3. union de tous les éléments produits précédemment
4. dilatation érosion +40/-25 pour créer l'enveloppe urbaine en liant les éléments
5. suppression des trous de moins d'1 ha
6. suppression des ilots de moins de 2ha et contenant moins de 8 bâtiments
*/

-- récupération variables
\set dep :dep
\set tab_batiment batiment_ :dep
\set tab_construction_surfacique construction_surfacique_ :dep
\set tab_terrain_de_sport terrain_de_sport_ :dep
\set tab_cimetiere cimetiere_ :dep
\set tab_aerodrome aerodrome_ :dep
\set tab_piste_d_aerodrome piste_d_aerodrome_ :dep
\set tab_poste_de_transformation poste_de_transformation_ :dep
\set tab_reservoir reservoir_ :dep
\set tab_equipement_de_transport equipement_de_transport_ :dep
\set tab_zone_d_activite_ou_d_interet zone_d_activite_ou_d_interet_ :dep
\set tab_envurb envurb_ :dep

--initialisation des variables
\set schema0 :schema_data

\set pkey1 envurb_ :dep _pkey

---------------------------------------------------------------------------
SELECT CURRENT_TIME;
---------------------------------------------------------------------------

--sélection des bâtiments de plus de 25m2
DROP TABLE IF EXISTS :schema0.batiment_sup_25;
CREATE TABLE :schema0.batiment_sup_25 AS
SELECT geom::geometry(MultiPolygon,2154) 
FROM :schema0.:tab_batiment a
WHERE st_area(geom)>25
;

create index ON :schema0.batiment_sup_25 using GIST(geom);

SELECT 'création de la couche surf_anthropise';

--sélection des zones anthropisées non bâties de la BDTOPO (cimetière, terrain de sport, réservoir, constructions surfaciques, piste aérodrome, aérodrome, equipement transport, poste_transfo et zones d'activité (nature NOT IN ('Sports nautiques','Sports en eaux vives','Site de vol libre','Site d''escalade','Baignade surveillée','Aquaculture','Sentier de découverte','Parc de loisirs','Enceinte militaire','Champ de tir','Espace public') AND nat_detail NOT IN ('Parc éolien')
DROP TABLE IF EXISTS :schema0.surf_anthropise;
CREATE TABLE :schema0.surf_anthropise AS
SELECT geom FROM :schema0.:tab_construction_surfacique 
UNION ALL 
SELECT geom FROM :schema0.:tab_terrain_de_sport 
UNION ALL 
SELECT geom FROM :schema0.:tab_cimetiere 
UNION ALL 
SELECT geom FROM :schema0.:tab_aerodrome 
UNION ALL 
SELECT geom FROM :schema0.:tab_poste_de_transformation 
UNION ALL 
SELECT geom FROM :schema0.:tab_zone_d_activite_ou_d_interet 
where NOT (nature IN ('Sports nautiques','Sports en eaux vives','Site de vol libre','Site d''escalade','Baignade surveillée','Aquaculture','Sentier de découverte','Parc de loisirs','Enceinte militaire','Champ de tir','Golf','Camp militaire non clos','Mégalithe','Ouvrage militaire','Champ de tir','Espace public') OR (nature='Centrale électrique' AND nat_detail='Parc éolien'))
UNION ALL 
SELECT geom FROM :schema0.:tab_reservoir 
WHERE nature NOT IN ('Réservoir d''eau ou château d''eau au sol') 
UNION ALL 
SELECT geom FROM :schema0.:tab_piste_d_aerodrome 
UNION ALL 
SELECT geom FROM :schema0.:tab_equipement_de_transport
UNION ALL
SELECT geom FROM :schema0.batiment_sup_25;

create index ON :schema0.surf_anthropise using GIST(geom);

---------------------------------------------------------------------------
SELECT CURRENT_TIME;
---------------------------------------------------------------------------

--Union des éléments de la BD TOPO avec dilatation (40m) et érosion (-25m)
SELECT 'Dilatation +40 / érosion -25';
DROP TABLE IF EXISTS :schema0.temp;
CREATE TABLE :schema0.temp AS
SELECT 
	st_buffer(geom,40,'side=left join=mitre') as geom
FROM :schema0.surf_anthropise;
CREATE INDEX ON :schema0.temp USING GIST(geom);

DROP TABLE IF EXISTS :schema0.temp2;
CREATE TABLE :schema0.temp2 AS
SELECT 
	st_buffer((st_dump(st_union(st_clusterintersecting(geom)))).geom,-25) as geom
FROM :schema0.temp;
CREATE INDEX ON :schema0.temp2 USING GIST(geom);

DROP TABLE IF EXISTS :schema0.surf_anthropise_union;
CREATE TABLE :schema0.surf_anthropise_union AS
SELECT 
	(st_dump(st_union(st_clusterintersecting(geom)))).geom::geometry(Polygon,2154) as geom
FROM :schema0.temp2;
CREATE INDEX ON :schema0.surf_anthropise_union USING GIST(geom);

---------------------------------------------------------------------------
SELECT CURRENT_TIME;
---------------------------------------------------------------------------
--suppression des "trous" de moins d'1 ha
SELECT 'Suppresion des trous de moins d''un ha';
DROP TABLE IF EXISTS :schema0.tache_sans_trous;
CREATE TABLE :schema0.tache_sans_trous AS
SELECT st_makepolygon(st_exteriorring(geom))::geometry (Polygon,2154) as geom
FROM :schema0.surf_anthropise_union;

CREATE INDEX ON :schema0.tache_sans_trous USING GIST(geom);

DROP TABLE IF EXISTS :schema0.anneaux_sup_10000;
WITH
	tache_anneaux_poly AS(
		SELECT row_number() over () as id, st_geometryN(geom,1) AS geom
		FROM :schema0.surf_anthropise_union),
	decompte_trou AS (
		SELECT id, geom, ST_NumInteriorRings(geom) as nb_trou
		FROM tache_anneaux_poly),
	creation_des_anneaux AS (
		SELECT id, n as num_trou, st_makepolygon(st_interiorringn(geom,n))::geometry (Polygon,2154) as geom
		FROM decompte_trou
		CROSS JOIN generate_series(1,nb_trou) as n
		WHERE nb_trou>0)
SELECT * into :schema0.anneaux_sup_10000
FROM creation_des_anneaux
WHERE st_area(geom)>10000;

CREATE INDEX ON :schema0.anneaux_sup_10000 USING GIST(geom);

DROP TABLE IF EXISTS :schema0.trous_bouches;
CREATE TABLE :schema0.trous_bouches AS
	SELECT st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_difference((st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t1.geom))),3))),(st_multi(st_collectionextract(st_forcecollection(st_makevalid(st_union(t2.geom))),3)))))),3))::geometry (MultiPolygon,2154) as geom
	FROM :schema0.tache_sans_trous as t1, :schema0.anneaux_sup_10000 as t2
	WHERE st_intersects(t1.geom,t2.geom);

CREATE INDEX ON :schema0.trous_bouches USING GIST(geom);

DROP TABLE IF EXISTS :schema0.trous_bouches2;
CREATE TABLE :schema0.trous_bouches2 AS
SELECT (ST_DUMP(geom)).geom::geometry(Polygon,2154) as geom
FROM :schema0.trous_bouches;

CREATE INDEX ON :schema0.trous_bouches USING GIST(geom);

SELECT 'création de la couche finale envurb';
---------------------------------------------------------------------------
SELECT CURRENT_TIME;
---------------------------------------------------------------------------

DROP TABLE IF EXISTS :schema0.:tab_envurb;
CREATE TABLE :schema0.:tab_envurb AS
WITH
	morceaux_seuls AS (
	SELECT a.geom FROM :schema0.tache_sans_trous a,:schema0.trous_bouches b
	WHERE not ST_Intersects(a.geom,b.geom))
SELECT * FROM morceaux_seuls UNION SELECT * FROM :schema0.trous_bouches2;

CREATE INDEX ON :schema0.:tab_envurb using GIST(geom);

--Ajout d'un champ unique id
ALTER TABLE :schema0.:tab_envurb ADD COLUMN id serial;
CREATE INDEX ON :schema0.:tab_envurb using btree(id);

--ajout champ nombre de bâtiments par ilot
ALTER TABLE :schema0.batiment_sup_25 ADD COLUMN centroid geometry(Point,2154);
UPDATE :schema0.batiment_sup_25 SET centroid=ST_Centroid(geom);
CREATE INDEX ON :schema0.batiment_sup_25 using GIST(centroid);

ALTER TABLE :schema0.:tab_envurb ADD COLUMN nb_bat integer;
UPDATE :schema0.:tab_envurb a SET nb_bat = b.nb_bat FROM
(SELECT a.id,count(b.geom) as nb_bat FROM :schema0.:tab_envurb a,:schema0.batiment_sup_25 b
WHERE ST_Intersects(a.geom,b.centroid)
GROUP BY a.id) b WHERE a.id=b.id;

--Ajout champ surface
ALTER TABLE :schema0.:tab_envurb ADD COLUMN surface integer;
UPDATE :schema0.:tab_envurb SET surface=ST_Area(geom);

--Suppression des ilots de moins de 2ha et contenant moins de 8 bâtiments
DELETE FROM :schema0.:tab_envurb WHERE
surface<20000 OR nb_bat<10;

--suppression des ilots sans bâtiments et moins de 2ha
DELETE FROM :schema0.:tab_envurb WHERE
surface<20000 AND nb_bat is NULL;

ALTER TABLE :schema0.:tab_envurb ADD CONSTRAINT :pkey1 primary key (id);
CREATE INDEX ON :schema0.:tab_envurb USING GIST(geom);

--suppression des tables temporaires
DROP TABLE IF EXISTS :schema0.temp;
DROP TABLE IF EXISTS :schema0.temp2;
DROP TABLE IF EXISTS :schema0.surf_anthropise;
DROP TABLE IF EXISTS :schema0.surf_anthropise_union;
DROP TABLE IF EXISTS :schema0.tache_sans_trous;
DROP TABLE IF EXISTS :schema0.anneaux_sup_10000;
DROP TABLE IF EXISTS :schema0.trous_bouches;
DROP TABLE IF EXISTS :schema0.trous_bouches2;
DROP TABLE IF EXISTS :schema0.batiment_sup_25;

---------------------------------------------------------------------------
SELECT CURRENT_TIME;
---------------------------------------------------------------------------