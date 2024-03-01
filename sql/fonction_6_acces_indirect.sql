CREATE OR REPLACE FUNCTION public.__6_acces_indirect(
	schema_prod text,
	idcom text,
	larg_acces integer
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$

BEGIN

	--création de la table du lot1 sans accès
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_sans_acces_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot1_sans_acces_' || idcom || ' AS
		SELECT idtup,geom FROM ' || schema_prod || '.gf_uf_lot1_acces_' || idcom || ' WHERE nb_acces IS NULL';

	--création de la table du lot1 avec accès
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_avec_acces_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot1_avec_acces_' || idcom || ' AS
		SELECT ST_Buffer(ST_Union(geom),1) as geom FROM ' || schema_prod || '.gf_uf_lot1_acces_' || idcom || ' WHERE nb_acces IS NOT NULL';

	--Test de présence d'une parcelle ayant un accès à côté de la parcelle sans accès
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_jointure_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot1_jointure_' || idcom || ' AS
		SELECT 
			a.idtup,a.geom,''possible''::VARCHAR(20) AS acces_indirect
		FROM ' || schema_prod || '.gf_uf_lot1_sans_acces_' || idcom || ' a,' || schema_prod || '.gf_uf_lot1_avec_acces_' || idcom || ' b 
		WHERE ST_Intersects(a.geom,b.geom)';

	--Mise à jour de la table du lot1 avec colonne accès indirect possible
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot1_acces_' || idcom || ' ADD COLUMN acces_indirect VARCHAR(20)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_lot1_acces_' || idcom || ' a SET acces_indirect=(SELECT acces_indirect FROM ' || schema_prod || '.gf_uf_lot1_jointure_' || idcom || ' b WHERE a.idtup=b.idtup AND a.nb_acces IS NULL)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_lot1_acces_' || idcom || ' SET acces_indirect=''impossible'' WHERE nb_acces IS NULL AND acces_indirect IS NULL';

	--**************************************************
	--Traitement des accès indirects des parcelles lot2
	--**************************************************

	--selection des espaces résiduels sans accès
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_sans_acces_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot2_sans_acces_' || idcom || ' AS
		SELECT idtup,geom,ST_PointOnSurface(geom) as centroid FROM ' || schema_prod || '.gf_uf_lot2_acces_' || idcom || ' WHERE nb_acces IS NULL';

	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_uf_lot2_sans_acces_' || idcom || ' using GIST (geom)';

	--récupération des UF complètes, à l'origine des espaces résiduels précédents
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' AS
		SELECT DISTINCT a.idtup,a.geom FROM ' || schema_prod || '.gf_tup_' || idcom || ' a,' || schema_prod || '.gf_uf_lot2_sans_acces_' || idcom || ' b
		WHERE ST_Intersects(a.geom,b.centroid)';

	--découpage des UF originales avec les bâtiments + tampon (2m par défaut, pour un accès minimum de 4m)
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_sansbat_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_sansbat_' || idcom || ' AS
		SELECT a.idtup,(ST_Dump(ST_MakeValid(ST_Difference(a.geom,ST_Buffer(b.geom,' || larg_acces || '/2))))).geom as geom FROM ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' a,' || schema_prod || '.gf_bat_union_' || idcom || ' b
		WHERE a.idtup=b.idtup';

	--nettoyage couche précédente générant de très petits objets (moins de 10 m2)
	EXECUTE 'DELETE FROM ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_sansbat_' || idcom || ' WHERE ST_Area(geom)<10';

	--récupération de l'information nombre de parties de l'unité foncière après découpage du bâti
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' ADD COLUMN nb_part_isol integer';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' a SET nb_part_isol=(SELECT count(*) FROM ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_sansbat_' || idcom || ' b WHERE a.idtup=b.idtup GROUP BY idtup )';

	--Ajout de l'information d'accès indirect dans la table lot2_acces
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' ADD COLUMN acces_indirect VARCHAR(20)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' a SET acces_indirect=
		CASE 
			WHEN nb_part_isol=1 THEN ''possible''
			WHEN nb_part_isol>1 THEN ''impossible''
		END';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot2_acces_' || idcom || ' ADD COLUMN acces_indirect VARCHAR(20)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_lot2_acces_' || idcom || ' a SET acces_indirect=(SELECT acces_indirect FROM ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' b WHERE a.idtup=b.idtup AND nb_acces IS NULL)';

	--**************************************************
	--Traitement des accès indirects des parcelles lot3
	--**************************************************
	--création de la table du lot3 sans accès
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot3_sans_acces_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot3_sans_acces_' || idcom || ' AS
		SELECT idtup,geom FROM ' || schema_prod || '.gf_uf_lot3_acces_' || idcom || ' WHERE nb_acces IS NULL';

	--Test de présence d'une parcelle du lot1 ayant un accès à côté de la parcelle lot3 sans accès
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot3_jointure_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_uf_lot3_jointure_' || idcom || ' AS
		SELECT 
			a.idtup,a.geom,''possible''::VARCHAR(20) AS acces_indirect
		FROM ' || schema_prod || '.gf_uf_lot3_sans_acces_' || idcom || ' a,' || schema_prod || '.gf_uf_lot1_avec_acces_' || idcom || ' b 
		WHERE ST_Intersects(a.geom,b.geom)';

	--Mise à jour de la table du lot3 avec colonne accès indirect possible
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_uf_lot3_acces_' || idcom || ' ADD COLUMN acces_indirect VARCHAR(20)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_lot3_acces_' || idcom || ' a SET acces_indirect=(SELECT acces_indirect FROM ' || schema_prod || '.gf_uf_lot3_jointure_' || idcom || ' b WHERE a.idtup=b.idtup AND a.nb_acces IS NULL)';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_uf_lot3_acces_' || idcom || ' SET acces_indirect=''impossible'' WHERE nb_acces IS NULL AND acces_indirect IS NULL';
	
	--suppression tables temporaires 
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_bat_union_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_sans_acces_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_avec_acces_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot1_jointure_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_sans_acces_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot2_sans_acces_origine_sansbat_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot3_sans_acces_' || idcom || ' CASCADE';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_uf_lot3_jointure_' || idcom || ' CASCADE';
	

END;
$BODY$;

-- SELECT public.__6_acces_indirect('public','33003',4);
