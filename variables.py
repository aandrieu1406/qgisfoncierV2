# initialisation des variables

import os.path
import csv

global noticePath,surf_min_zone,surf_comblement,surfminbat,taux_surface,surfminuf,largeur_min,larg_acces,reserve_dense,reserve_groupe,reserve_diffus,reserve_isole,surf_dense,surf_groupee,surf_diffus,taux_convexhull,dossier_log

#paramètres application
surf_min_zone='500'
surf_comblement='50'
surfminbat='25'
taux_surface='30'
surfminuf='100'
largeur_min='6'
larg_acces='4'
reserve_dense='10'
reserve_groupe=str(float(reserve_dense)*1.5)
reserve_diffus=str(float(reserve_dense)*2.5)
reserve_isole=str(float(reserve_dense)*3.5)
surf_dense='300'
surf_groupee=str(float(surf_dense)*1.66)
surf_diffus=str(float(surf_dense)*3.33)
taux_convexhull='50'

noticePath=os.path.dirname(__file__)+"/doc/notice.pdf"
dossier_log=os.path.dirname(__file__)+'/log'
# si le dossie de sortie est un sous dossier (+ de 2 niveaux), il faut l'avoir créer au préalable



