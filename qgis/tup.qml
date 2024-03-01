<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<qgis minScale="1e+08" labelsEnabled="0" simplifyDrawingTol="1" styleCategories="AllStyleCategories" simplifyLocal="1" version="3.10.0-A Coruña" simplifyAlgorithm="0" simplifyMaxScale="1" readOnly="0" simplifyDrawingHints="1" hasScaleBasedVisibilityFlag="0" maxScale="100000">
  <flags>
    <Identifiable>1</Identifiable>
    <Removable>1</Removable>
    <Searchable>1</Searchable>
  </flags>
  <renderer-v2 type="singleSymbol" enableorderby="0" symbollevels="0" forceraster="0">
    <symbols>
      <symbol type="fill" alpha="1" force_rhr="0" name="0" clip_to_extent="1">
        <layer class="SimpleFill" locked="0" pass="0" enabled="1">
          <prop v="3x:0,0,0,0,0,0" k="border_width_map_unit_scale"/>
          <prop v="245,245,245,255" k="color"/>
          <prop v="bevel" k="joinstyle"/>
          <prop v="0,0" k="offset"/>
          <prop v="3x:0,0,0,0,0,0" k="offset_map_unit_scale"/>
          <prop v="MM" k="offset_unit"/>
          <prop v="108,110,90,255" k="outline_color"/>
          <prop v="solid" k="outline_style"/>
          <prop v="0" k="outline_width"/>
          <prop v="MM" k="outline_width_unit"/>
          <prop v="solid" k="style"/>
          <data_defined_properties>
            <Option type="Map">
              <Option type="QString" value="" name="name"/>
              <Option name="properties"/>
              <Option type="QString" value="collection" name="type"/>
            </Option>
          </data_defined_properties>
        </layer>
      </symbol>
    </symbols>
    <rotation/>
    <sizescale/>
  </renderer-v2>
  <customproperties>
    <property key="embeddedWidgets/count" value="0"/>
    <property key="variableNames"/>
    <property key="variableValues"/>
  </customproperties>
  <blendMode>0</blendMode>
  <featureBlendMode>0</featureBlendMode>
  <layerOpacity>1</layerOpacity>
  <SingleCategoryDiagramRenderer attributeLegend="1" diagramType="Histogram">
    <DiagramCategory penWidth="0" barWidth="5" penColor="#000000" enabled="0" lineSizeScale="3x:0,0,0,0,0,0" scaleBasedVisibility="0" minScaleDenominator="100000" backgroundColor="#ffffff" maxScaleDenominator="1e+08" lineSizeType="MM" backgroundAlpha="255" scaleDependency="Area" opacity="1" labelPlacementMethod="XHeight" diagramOrientation="Up" rotationOffset="270" sizeType="MM" sizeScale="3x:0,0,0,0,0,0" minimumSize="0" penAlpha="255" width="15" height="15">
      <fontProperties description="MS Shell Dlg 2,8.25,-1,5,50,0,0,0,0,0" style=""/>
      <attribute label="" field="" color="#000000"/>
    </DiagramCategory>
  </SingleCategoryDiagramRenderer>
  <DiagramLayerSettings linePlacementFlags="18" placement="1" dist="0" zIndex="0" showAll="1" priority="0" obstacle="0">
    <properties>
      <Option type="Map">
        <Option type="QString" value="" name="name"/>
        <Option name="properties"/>
        <Option type="QString" value="collection" name="type"/>
      </Option>
    </properties>
  </DiagramLayerSettings>
  <geometryOptions geometryPrecision="0" removeDuplicateNodes="0">
    <activeChecks/>
    <checkConfiguration type="Map">
      <Option type="Map" name="QgsGeometryGapCheck">
        <Option type="double" value="0" name="allowedGapsBuffer"/>
        <Option type="bool" value="false" name="allowedGapsEnabled"/>
        <Option type="QString" value="" name="allowedGapsLayer"/>
      </Option>
    </checkConfiguration>
  </geometryOptions>
  <fieldConfiguration>
    <field name="IDCOM">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="IDTUP">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="NLOCMAISON">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="NLOCLOG">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="NLOCDEP">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="NLOCCOM">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="NLOCAPPT">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="DCNTPA">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="CATPRO2">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="CATPRO2TXT">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
    <field name="DCNTARTI">
      <editWidget type="TextEdit">
        <config>
          <Option/>
        </config>
      </editWidget>
    </field>
  </fieldConfiguration>
  <aliases>
    <alias index="0" field="IDCOM" name=""/>
    <alias index="1" field="IDTUP" name=""/>
    <alias index="2" field="NLOCMAISON" name=""/>
    <alias index="3" field="NLOCLOG" name=""/>
    <alias index="4" field="NLOCDEP" name=""/>
    <alias index="5" field="NLOCCOM" name=""/>
    <alias index="6" field="NLOCAPPT" name=""/>
    <alias index="7" field="DCNTPA" name=""/>
    <alias index="8" field="CATPRO2" name=""/>
    <alias index="9" field="CATPRO2TXT" name=""/>
    <alias index="10" field="DCNTARTI" name=""/>
  </aliases>
  <excludeAttributesWMS/>
  <excludeAttributesWFS/>
  <defaults>
    <default expression="" field="IDCOM" applyOnUpdate="0"/>
    <default expression="" field="IDTUP" applyOnUpdate="0"/>
    <default expression="" field="NLOCMAISON" applyOnUpdate="0"/>
    <default expression="" field="NLOCLOG" applyOnUpdate="0"/>
    <default expression="" field="NLOCDEP" applyOnUpdate="0"/>
    <default expression="" field="NLOCCOM" applyOnUpdate="0"/>
    <default expression="" field="NLOCAPPT" applyOnUpdate="0"/>
    <default expression="" field="DCNTPA" applyOnUpdate="0"/>
    <default expression="" field="CATPRO2" applyOnUpdate="0"/>
    <default expression="" field="CATPRO2TXT" applyOnUpdate="0"/>
    <default expression="" field="DCNTARTI" applyOnUpdate="0"/>
  </defaults>
  <constraints>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="IDCOM" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="IDTUP" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="NLOCMAISON" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="NLOCLOG" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="NLOCDEP" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="NLOCCOM" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="NLOCAPPT" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="DCNTPA" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="CATPRO2" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="CATPRO2TXT" unique_strength="0"/>
    <constraint constraints="0" notnull_strength="0" exp_strength="0" field="DCNTARTI" unique_strength="0"/>
  </constraints>
  <constraintExpressions>
    <constraint desc="" field="IDCOM" exp=""/>
    <constraint desc="" field="IDTUP" exp=""/>
    <constraint desc="" field="NLOCMAISON" exp=""/>
    <constraint desc="" field="NLOCLOG" exp=""/>
    <constraint desc="" field="NLOCDEP" exp=""/>
    <constraint desc="" field="NLOCCOM" exp=""/>
    <constraint desc="" field="NLOCAPPT" exp=""/>
    <constraint desc="" field="DCNTPA" exp=""/>
    <constraint desc="" field="CATPRO2" exp=""/>
    <constraint desc="" field="CATPRO2TXT" exp=""/>
    <constraint desc="" field="DCNTARTI" exp=""/>
  </constraintExpressions>
  <expressionfields/>
  <attributeactions>
    <defaultAction key="Canvas" value="{00000000-0000-0000-0000-000000000000}"/>
  </attributeactions>
  <attributetableconfig sortExpression="" actionWidgetStyle="dropDown" sortOrder="0">
    <columns>
      <column type="actions" hidden="1" width="-1"/>
      <column type="field" name="IDCOM" hidden="0" width="-1"/>
      <column type="field" name="IDTUP" hidden="0" width="-1"/>
      <column type="field" name="NLOCMAISON" hidden="0" width="-1"/>
      <column type="field" name="NLOCLOG" hidden="0" width="-1"/>
      <column type="field" name="NLOCDEP" hidden="0" width="-1"/>
      <column type="field" name="NLOCCOM" hidden="0" width="-1"/>
      <column type="field" name="NLOCAPPT" hidden="0" width="-1"/>
      <column type="field" name="DCNTPA" hidden="0" width="-1"/>
      <column type="field" name="CATPRO2" hidden="0" width="-1"/>
      <column type="field" name="CATPRO2TXT" hidden="0" width="-1"/>
      <column type="field" name="DCNTARTI" hidden="0" width="-1"/>
    </columns>
  </attributetableconfig>
  <conditionalstyles>
    <rowstyles/>
    <fieldstyles/>
  </conditionalstyles>
  <storedexpressions/>
  <editform tolerant="1"></editform>
  <editforminit/>
  <editforminitcodesource>0</editforminitcodesource>
  <editforminitfilepath></editforminitfilepath>
  <editforminitcode><![CDATA[# -*- coding: utf-8 -*-
"""
Les formulaires QGIS peuvent avoir une fonction Python qui sera appelée à l'ouverture du formulaire.

Utilisez cette fonction pour ajouter plus de fonctionnalités à vos formulaires.

Entrez le nom de la fonction dans le champ "Fonction d'initialisation Python".
Voici un exemple à suivre:
"""
from qgis.PyQt.QtWidgets import QWidget

def my_form_open(dialog, layer, feature):
    geom = feature.geometry()
    control = dialog.findChild(QWidget, "MyLineEdit")

]]></editforminitcode>
  <featformsuppress>0</featformsuppress>
  <editorlayout>generatedlayout</editorlayout>
  <editable>
    <field editable="1" name="CATPRO2"/>
    <field editable="1" name="CATPRO2TXT"/>
    <field editable="1" name="DCNTARTI"/>
    <field editable="1" name="DCNTPA"/>
    <field editable="1" name="IDCOM"/>
    <field editable="1" name="IDTUP"/>
    <field editable="1" name="NLOCAPPT"/>
    <field editable="1" name="NLOCCOM"/>
    <field editable="1" name="NLOCDEP"/>
    <field editable="1" name="NLOCLOG"/>
    <field editable="1" name="NLOCMAISON"/>
    <field editable="1" name="dcntarti"/>
    <field editable="1" name="dcntpa"/>
    <field editable="1" name="idcom"/>
    <field editable="1" name="idtup"/>
    <field editable="1" name="nlocappt"/>
    <field editable="1" name="nloccom"/>
    <field editable="1" name="nlocdep"/>
    <field editable="1" name="nloclog"/>
    <field editable="1" name="nlocmaison"/>
    <field editable="1" name="typprop"/>
    <field editable="1" name="typproptxt"/>
  </editable>
  <labelOnTop>
    <field name="CATPRO2" labelOnTop="0"/>
    <field name="CATPRO2TXT" labelOnTop="0"/>
    <field name="DCNTARTI" labelOnTop="0"/>
    <field name="DCNTPA" labelOnTop="0"/>
    <field name="IDCOM" labelOnTop="0"/>
    <field name="IDTUP" labelOnTop="0"/>
    <field name="NLOCAPPT" labelOnTop="0"/>
    <field name="NLOCCOM" labelOnTop="0"/>
    <field name="NLOCDEP" labelOnTop="0"/>
    <field name="NLOCLOG" labelOnTop="0"/>
    <field name="NLOCMAISON" labelOnTop="0"/>
    <field name="dcntarti" labelOnTop="0"/>
    <field name="dcntpa" labelOnTop="0"/>
    <field name="idcom" labelOnTop="0"/>
    <field name="idtup" labelOnTop="0"/>
    <field name="nlocappt" labelOnTop="0"/>
    <field name="nloccom" labelOnTop="0"/>
    <field name="nlocdep" labelOnTop="0"/>
    <field name="nloclog" labelOnTop="0"/>
    <field name="nlocmaison" labelOnTop="0"/>
    <field name="typprop" labelOnTop="0"/>
    <field name="typproptxt" labelOnTop="0"/>
  </labelOnTop>
  <widgets/>
  <previewExpression>IDCOM</previewExpression>
  <mapTip></mapTip>
  <layerGeometryType>2</layerGeometryType>
</qgis>
