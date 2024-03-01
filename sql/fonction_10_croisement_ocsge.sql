CREATE OR REPLACE FUNCTION public.__10_croisement_ocsge(
	schema_prod text,	
	idcom text,
	nom_ocsge text,
	schema_ocs text
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$


BEGIN

	--1. création table OCS sur la commune pour accélérer les temps de traitement
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_ocsge_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_ocsge_' || idcom || ' AS
		WITH 
			com AS (SELECT ST_Buffer(geom,200,''side=left join=mitre'') as geom FROM ' || schema_prod || '.gf_com_' || idcom || '),-- ajout d''un buffer de 200m pour éviter les effets de bord
			ocs AS (SELECT ST_Buffer(t2.geom,0) as geom,code15niv1,lib15niv1,code15niv2,lib15niv2,code15niv3,lib15niv3,code15niv4,lib15niv4 FROM ' || schema_ocs || '.' || nom_ocsge || ' as t2,com WHERE st_intersects(com.geom,t2.geom))
		SELECT
			code15niv1,lib15niv1,
			code15niv2,lib15niv2,
			code15niv3,lib15niv3,
			code15niv4,lib15niv4,
			ST_Intersection(com.geom,ocs.geom) as geom
		FROM com,ocs
		WHERE ST_Intersects(com.geom,ocs.geom)';

	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_ocsge_' || idcom || ' ALTER COLUMN geom type geometry(MultiPolygon, 2154) using ST_Multi(geom)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_ocsge_' || idcom || ' USING gist(geom)';

	--1a. découpage des gisements fonciers avec la couche OCS GE, niveau 4
	-- 7 postes niv 4 des zones urbanisées (1111 à 1125)
	-- 9 postes niv 3 des autres territoires artificialisés (121 à 142)
	-- 4 postes niv 1 (2 à 5)

	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || ''; 
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || ' as
		SELECT 
			gid,t1.idtup,t1.idcom,t1.type,t1.surface as surf_gisement,
			t2.code15niv1,t2.lib15niv1,
			t2.code15niv2,t2.lib15niv2,
			t2.code15niv3,t2.lib15niv3,
			t2.code15niv4,t2.lib15niv4,
			CASE
				WHEN code15niv4<1200 THEN code15niv4
				WHEN code15niv4>1200 AND code15niv4<2000 THEN code15niv3
				ELSE code15niv1
			END::integer AS code15agg,
			CASE
				WHEN code15niv4<1200 THEN lib15niv4
				WHEN code15niv4>1200 AND code15niv4<2000 THEN lib15niv3
				ELSE lib15niv1
			END::varchar(100) AS lib15agg,
			ST_Area(ST_Intersection(t1.geom,t2.geom)) as surf_inter,
			ST_Intersection(t1.geom,t2.geom) as geom
		FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' as t1, ' || schema_prod || '.gf_ocsge_' || idcom || ' as t2
		WHERE ST_Intersects(t1.geom,t2.geom)';

	--création index et clé primaire
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || ' USING gist(geom)';

	--agrégation des information OCS sur les parcelles (lots)
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.temp_ocs';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.temp_ocs AS
		WITH 
			surf_max as(
				SELECT gid,max(surf_inter) as surface_ocs_maj
				FROM ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || '
				group by gid),
			ocs_maj as(
				SELECT a.gid,code15agg as code15agg_maj,lib15agg as lib15agg_maj,surface_ocs_maj
				FROM ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || ' a,surf_max
				WHERE surf_inter=surface_ocs_maj and a.gid=surf_max.gid),
			agg as(
				SELECT gid,array_agg(code15agg) as code15agg,array_agg(lib15agg) as lib15agg,
				count(*) as nb_ocs,array_agg(surf_inter::integer) as surfaces_ocs
				FROM ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || '
				group by gid)
		SELECT agg.gid,code15agg,lib15agg,nb_ocs,surfaces_ocs,code15agg_maj,lib15agg_maj,surface_ocs_maj::integer
		FROM agg,ocs_maj
		WHERE agg.gid=ocs_maj.gid';

	--ajout des colonnes ocs dans la table du foncier mutable
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN code15agg text';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET code15agg=(SELECT code15agg::varchar FROM ' || schema_prod || '.temp_ocs b WHERE a.gid=b.gid)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN lib15agg text';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET lib15agg=(SELECT lib15agg::varchar FROM ' || schema_prod || '.temp_ocs b WHERE a.gid=b.gid)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN nb_ocs integer';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET nb_ocs=(SELECT nb_ocs FROM ' || schema_prod || '.temp_ocs b WHERE a.gid=b.gid)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN surfaces_ocs text';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET surfaces_ocs=(SELECT surfaces_ocs::varchar FROM ' || schema_prod || '.temp_ocs b WHERE a.gid=b.gid)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN code15agg_maj integer';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET code15agg_maj=(SELECT code15agg_maj FROM ' || schema_prod || '.temp_ocs b WHERE a.gid=b.gid)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN lib15agg_maj text';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET lib15agg_maj=(SELECT lib15agg_maj FROM ' || schema_prod || '.temp_ocs b WHERE a.gid=b.gid)';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN surface_ocs_maj integer';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET surface_ocs_maj=(SELECT surface_ocs_maj FROM ' || schema_prod || '.temp_ocs b WHERE a.gid=b.gid)';

	--2. regroupement par occupation sur champs code15agg et lib15agg
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_synth_ocsge_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_synth_ocsge_' || idcom || ' AS
		WITH 
			p1 as (SELECT insee_com as idcom,nom FROM ' || schema_prod || '.gf_com_' || idcom || '),
			p2 as (SELECT sum(surface) as surface_tot FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' WHERE type IN (''type 1'',''type 2'')),
			p3 as (SELECT sum(surf_inter)::bigint as surf_m2, code15agg, lib15agg, type FROM ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || ' WHERE type IN (''type 1'',''type 2'') GROUP BY code15agg, lib15agg, type ORDER BY type,code15agg)
		SELECT 
			p1.idcom,p1.nom as nom_com,
			p3.type,
			p3.code15agg as code_2015,
			p3.lib15agg as libelle_2015,
			p3.surf_m2 as surface_m2,
			((p3.surf_m2/p2.surface_tot)*100)::integer as tx_surface 
		FROM p1,p2,p3';

	--3. Formatage de la couche foncier_mutable pour la sortie finale
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.fonc_mut_temp';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.fonc_mut_temp AS
		SELECT
			a.gid,
			type,
			idtup,
			idcom,
			com.nom as nom_com,
			surface,
			densite,
			nb_acces as acces_nb,
			types_acces as acces_type,
			acces_indirect as acces_mode,
			cl_admin as acces_voie,
			typologie_prop,
			catpro2 as prop_type,
			catpro2txt as prop_lib,
			nb_prop as propr_nb,
			plu_lib as plu_zone,
			nb_plu_lib as plu_zon_nb,
			plu_typezone as plu_typezo,
			plu_lib_maj as plu_libmaj,
			surf_plu_lib as plu_surf,
			tx_surf_plu_lib as plu_tx_zon,
			nb_ocs as ocs_nb,
			code15agg as ocs_cods,
			lib15agg as ocs_libs,
			surfaces_ocs as ocs_surfs,
			code15agg_maj as ocs_codmaj,
			lib15agg_maj as ocs_libmaj,
			surface_ocs_maj as ocssurfmaj,
			a.geom
		FROM
			' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a,' || schema_prod || '.gf_com_' || idcom || ' as com
		ORDER BY a.gid';

	--suppression table foncier mutable pour la remplacer
	EXECUTE 'DROP TABLE if exists ' || schema_prod || '.gf_foncier_mutable_' || idcom || '';
	EXECUTE 'ALTER TABLE ' || schema_prod || '.fonc_mut_temp RENAME TO gf_foncier_mutable_' || idcom || '';

	--creation clé primaire et index sur la table foncier mutable
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD CONSTRAINT gf_foncier_mutable_' || idcom || '_pkey primary key(gid)';
	EXECUTE 'CREATE INDEX ON ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' USING gist(geom)';

	--suppression tables temporaires	
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.temp_ocs';
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_foncier_mutable_ocsge_' || idcom || ' CASCADE ';
	
END;
$BODY$;

-- SELECT public.__10_croisement_ocsge('public','33003');
