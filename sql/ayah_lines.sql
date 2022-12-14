Use nextgen;
-- SET @row_number = 0;   

SELECT 
    min(ayah) start_ayah,
    min(start_line) start_page_line,
    CONVERT(min(start_line)/1000,SIGNED) start_page,
    mod(min(start_line),1000) start_line,
    max(ayah) end_ayah,
    max(end_line) end_page_line,
    CONVERT(max(end_line)/1000,SIGNED) end_page,
    mod(max(end_line),1000) end_line,
    count(ayah) ayahs,
    sum(`lines`) `lines`
FROM (
    SELECT
        -- (@row_number:=@row_number + 1) AS `#`, 
        ayah,
        min(pl) start_line,
        max(pl) end_line,
        sum(line_fraction) `lines`
    FROM (
        SELECT
            pl, ayah, g_count, g_count2,
            g_count / g_count2  line_fraction
        FROM (
            SELECT
                gpl.page_number * 1000 + gpl.line_number    pl,
                ga.sura_number * 1000 + ga.ayah_number      ayah, 
                count(g.glyph_id)                           g_count              
            FROM glyph_page_line gpl 
            INNER JOIN glyph g ON g.glyph_id = gpl.glyph_id 
            INNER JOIN glyph_ayah ga ON ga.glyph_id = g.glyph_id 
            WHERE 
                (ga.sura_number * 1000 + ga.ayah_number) BETWEEN 27091 AND 28004 AND
                -- (gpl.page_number=3 OR gpl.page_number=2) AND 
                g.glyph_type_id = 1
            GROUP BY ayah, pl
            ORDER BY pl ASC
        ) line_ayah_glyphs

        -- Get glyphs per line
        JOIN (
            SELECT
                gpl2.page_number * 1000 + gpl2.line_number  pl2,
                count(g2.glyph_id)                          g_count2
            FROM glyph_page_line                        gpl2
            LEFT JOIN glyph g2 ON g2.glyph_id = gpl2.glyph_id
            WHERE 
                -- (gpl2.page_number=3 OR gpl2.page_number=2) AND
                g2.glyph_type_id = 1
            GROUP BY pl2
        ) line_glyphs
            ON line_glyphs.pl2 = line_ayah_glyphs.pl    
    ) ayah_line_fractions
    GROUP BY ayah
    ORDER BY ayah ASC
) ayahs_details

