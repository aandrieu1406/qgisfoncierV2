CREATE OR REPLACE FUNCTION public.__11_calcul_potentiel(
	schema_prod text,	
	idcom text,
	surf_dense integer
	)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    --VOLATILE PARALLEL UNSAFE
AS $BODY$
	
BEGIN

	--Mise à jour de la table foncier_mutable avec l'information de nombre de logement du carreau
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN pot_bas integer';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET pot_bas=
		CASE 
			WHEN densite=''dense'' THEN floor(surface/' || surf_dense || ')
			WHEN densite=''groupee'' THEN floor(surface/(' || surf_dense || '*1.66))
			WHEN densite IN (''diffuse'',''isolee'') THEN floor(surface/(' || surf_dense || '*3.33))
		END';
			
	EXECUTE 'ALTER TABLE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' ADD COLUMN pot_haut integer';
	EXECUTE 'UPDATE ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' a SET pot_haut=
		CASE 
			WHEN densite=''dense'' THEN pot_bas*4
			WHEN densite=''groupee'' THEN pot_bas*2
			WHEN densite IN (''diffuse'',''isolee'') THEN pot_bas
		END';
		
	EXECUTE 'DROP TABLE IF EXISTS ' || schema_prod || '.gf_synth_potentiel_logt_' || idcom || '';
	EXECUTE 'CREATE TABLE ' || schema_prod || '.gf_synth_potentiel_logt_' || idcom || ' AS
		SELECT 
			a.idcom,
			com.nom as nom_com,
			a.type,
			count(*) as nb,
			sum(pot_bas) as potentiel_bas,
			sum(pot_haut) as potentiel_haut
		FROM ' || schema_prod || '.gf_foncier_mutable_' || idcom || ' as a,' || schema_prod || '.gf_com_' || idcom || ' as com
		GROUP BY a.idcom,com.nom,a.type
		ORDER BY a.type';

END;
$BODY$;

-- SELECT public.__11_calcul_potentiel('public','33003',300);
