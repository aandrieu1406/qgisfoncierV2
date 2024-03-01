CREATE OR REPLACE FUNCTION public.__12_tab_synthese(
	schema_prod text,	
	idcom text
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$
	
BEGIN

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_synth_plu_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_synth_plu_' || idcom || ' AS
		WITH 
			p1 AS (SELECT DISTINCT libelle,typezone FROM ' || schema_prod || '.gf_plu_' || idcom || '),
			p2 AS (SELECT sum(surface)::bigint as surf_tot FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' WHERE type IN(''type 1'',''type 2'')),
			p3 AS (SELECT 
					typezone,
					sum(case 
						when type=''type 1'' then st_area(st_intersection(a.geom,b.geom))
					end)::bigint as surf_m2_lot1,
					count(case 
						when type=''type 1'' then st_area(st_intersection(a.geom,b.geom))
					end) as nb_lot1,
					sum(case 
						when type=''type 2'' then st_area(st_intersection(a.geom,b.geom))
					end)::bigint as surf_m2_lot2,
					count(case 
						when type=''type 2'' then st_area(st_intersection(a.geom,b.geom))
					end) as nb_lot2

				FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a,' || schema_prod || '.gf_plu_' || idcom || ' b
				WHERE ST_Intersects(a.geom,b.geom) 
				GROUP BY typezone)
		SELECT        
				com.insee_com as idcom,
				com.nom as nom_com,
				p1.libelle,
				p1.typezone,
				p3.nb_lot1 as nb_uf_foncier_non_bati,
				p3.surf_m2_lot1 as surf_m2_uf_foncier_non_bati,
				((p3.surf_m2_lot1*1.0/p2.surf_tot)*100)::integer as tx_surf_uf_foncier_non_bati,
				p3.nb_lot2 as nb_uf_fond_parcelle,
				p3.surf_m2_lot2 as surf_m2_uf_fond_parcelle,
				((p3.surf_m2_lot2*1.0/p2.surf_tot)*100)::integer as tx_surf_uf_fond_parcelle
		FROM p1,p2,p3,' || schema_prod || '.gf_com_' || idcom || ' as com
		WHERE p1.typezone=p3.typezone'
	;

	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_synth_typo_prop_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_synth_typo_prop_' || idcom || ' AS
		WITH
			p1 AS (SELECT
					typologie_prop,
					count(case 
						when type=''type 1'' then 1
					end) as nb_lot1,
					sum(case 
						when type=''type 1'' then ST_Area(geom)
					end)::bigint as surf_m2_lot1,
					count(case 
						when type=''type 2'' then 1
					end) as nb_lot2,
					sum(case 
						when type=''type 2'' then ST_Area(geom)
					end)::bigint as surf_m2_lot2
				FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || '
				GROUP BY typologie_prop),
			p2 AS (SELECT sum(ST_Area(geom))::bigint as surf_tot FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' WHERE type IN(''type 1'',''type 2''))
		SELECT
			com.insee_com as idcom,
			com.nom as nom_com,
			typologie_prop as typologie_proprietaire,
			nb_lot1 as nb_uf_foncier_non_bati,
			surf_m2_lot1 as surf_m2_uf_foncier_non_bati,
			((p1.surf_m2_lot1*1.0/p2.surf_tot)*100)::integer as tx_surf_uf_foncier_non_bati,
			nb_lot2 as nb_uf_fond_parcelle,
			surf_m2_lot2 as surf_m2_uf_fond_parcelle,
			((p1.surf_m2_lot2*1.0/p2.surf_tot)*100)::integer as tx_surf_uf_fond_parcelle
		FROM p1,p2,' || schema_prod || '.gf_com_' || idcom || ' as com'
	;

END;
$BODY$;

-- SELECT public.__12_tab_synthese('public','33003');
