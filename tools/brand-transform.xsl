<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:s="http://www.w3.org/2000/svg" exclude-result-prefixes="s">
  <xsl:output method="xml" encoding="UTF-8" omit-xml-declaration="yes" indent="yes"/>
  <xsl:strip-space elements="s:svg"/>
  <xsl:param name="size" select="1024"/>
  <xsl:param name="waves" select="'currentColor'"/>
  <xsl:param name="orb" select="'currentColor'"/>
  <xsl:param name="layer" select="'all'"/>
  <xsl:key name="ids" match="*[@id]" use="@id"/>

  <!-- 母版契约只约束图层和颜色，不解释或生成几何。 -->
  <xsl:template match="/">
    <xsl:if test="not(s:svg/@viewBox) or count(s:svg/s:g[@id='waves']) != 1 or count(s:svg/s:g[@id='orb']) != 1">
      <xsl:message terminate="yes">SVG requires a viewBox and direct child groups id="waves" and id="orb".</xsl:message>
    </xsl:if>
    <xsl:if test="s:svg/*[not(self::s:g[@id='waves' or @id='orb'] or self::s:defs or self::s:title or self::s:desc or self::s:metadata)]">
      <xsl:message terminate="yes">All artwork must belong to the waves/orb groups; shared definitions belong in defs.</xsl:message>
    </xsl:if>
    <xsl:if test="//*[@id and count(key('ids', @id)) != 1]">
      <xsl:message terminate="yes">SVG IDs must be unique.</xsl:message>
    </xsl:if>
    <xsl:if test="not(s:svg/@fill = 'none' or s:svg/@fill = 'currentColor')">
      <xsl:message terminate="yes">SVG root fill must explicitly be none or currentColor; implicit black cannot inherit palette colors.</xsl:message>
    </xsl:if>
    <xsl:if test="//@color or //@style or //s:style or //@fill[. != 'none' and . != 'currentColor'] or //@stroke[. != 'none' and . != 'currentColor']">
      <xsl:message terminate="yes">Use presentation attributes and currentColor/none paints; colors belong in palettes.json, not CSS or SVG literals.</xsl:message>
    </xsl:if>
    <xsl:if test="//s:text or //s:image or //s:script or //s:foreignObject or //s:filter or s:svg/@opacity or //@*[local-name()='href' and not(starts-with(., '#'))]">
      <xsl:message terminate="yes">Masters must be self-contained vector artwork without fonts, raster images, filters, scripts, external references, or root opacity.</xsl:message>
    </xsl:if>
    <!-- 在每个完整图／分层图导出前检查引用，避免渲染器静默忽略缺失的裁剪。 -->
    <xsl:for-each select="//@*[contains(translate(., 'URL', 'url'), 'url(') or local-name()='href']">
      <xsl:variable name="reference" select="translate(., concat('&quot;', &quot;'&quot;, ' &#x9;&#xA;&#xD;'), '')"/>
      <xsl:variable name="target"><xsl:choose>
        <xsl:when test="local-name()='href' and starts-with($reference, '#')"><xsl:value-of select="substring($reference, 2)"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="substring-before(substring-after($reference, 'url(#'), ')')"/></xsl:otherwise>
      </xsl:choose></xsl:variable>
      <xsl:if test="not(string($target)) or not($reference = concat('#', $target) or $reference = concat('url(#', $target, ')')) or count(key('ids', string($target))) != 1">
        <xsl:message terminate="yes">SVG references must point to an existing local ID: <xsl:value-of select="."/></xsl:message>
      </xsl:if>
      <xsl:if test="$layer != 'all' and not(ancestor::s:g[parent::s:svg and (@id='waves' or @id='orb') and @id != $layer]) and key('ids', string($target))/ancestor-or-self::s:g[parent::s:svg and (@id='waves' or @id='orb') and @id != $layer]">
        <xsl:message terminate="yes">A retained reference points into the removed Composer layer; move shared definitions into defs.</xsl:message>
      </xsl:if>
    </xsl:for-each>
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy>
  </xsl:template>

  <xsl:template match="/s:svg">
    <xsl:copy>
      <xsl:apply-templates select="@*[name() != 'width' and name() != 'height']"/>
      <xsl:attribute name="width"><xsl:value-of select="$size"/></xsl:attribute>
      <xsl:attribute name="height"><xsl:value-of select="$size"/></xsl:attribute>
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/s:svg/s:g[@id='waves' or @id='orb']">
    <xsl:if test="$layer = 'all' or $layer = @id">
      <xsl:copy>
        <xsl:apply-templates select="@*"/>
        <xsl:variable name="ink"><xsl:choose><xsl:when test="@id='waves'"><xsl:value-of select="$waves"/></xsl:when><xsl:otherwise><xsl:value-of select="$orb"/></xsl:otherwise></xsl:choose></xsl:variable>
        <xsl:if test="$ink != 'currentColor'"><xsl:attribute name="color"><xsl:value-of select="$ink"/></xsl:attribute></xsl:if>
        <xsl:apply-templates select="node()"/>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
