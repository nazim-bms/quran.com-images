package Quran::DB;

use strict;
use warnings;

use base qw/Quran/;
use Data::Dumper;
use Mojo::Log;

use DBI;

my $log = new Mojo::Log;

sub new {
	my $class = shift;
	my $config = shift;

	my $database = $config->{database} or die "database name needed";
	my $username = $config->{username} or die "database username needed";
	my $password = $config->{password} or die "database password needed";
	my $host = $config->{host} // 'localhost';
	my $port = $config->{port} // '3306';

	my $dbh = DBI->connect("dbi:mysql:database=".$database.";host=".$host.";port=".$port, $username, $password) or die;

	bless {
		_class => $class,
		_dbh   => $dbh
	}, $class;
}

sub reset_bounding_box_table {
	my ($self, $page) = @_;
	my $prep = $self->{_dbh}->prepare_cached("TRUNCATE glyph_page_line_bbox");
	$prep->execute();
}

sub get_ayah_range_details {
	my ($self, $start_ayah, $end_ayah) = @_;

	if (!defined $self->{_selected_ayah_range_details}) {
	 	$self->{_selected_ayah_range_details}= $self->{_dbh}->prepare_cached(" \
			SELECT \
				min(ayah) start_ayah, \
				min(start_page_line) start_page_line, \
				CONVERT(min(start_page_line)/1000,SIGNED) start_page, \
				mod(min(start_page_line),1000) start_line, \
				max(ayah) end_ayah, \
				max(end_page_line) end_page_line, \
				CONVERT(max(end_page_line)/1000,SIGNED) end_page, \
				mod(max(end_page_line),1000) end_line, \
				count(ayah) ayahs, \
				sum(`lines`) `lines` \
			FROM ( \
				SELECT \
					ayah, \
					min(pl) start_page_line, \
					max(pl) end_page_line, \
					sum(line_fraction) `lines` \
				FROM ( \
					SELECT \
						pl, ayah, g_count, \
						g_count2, \
						g_count / g_count2  line_fraction \
					FROM ( \
						SELECT \
							gpl.page_number * 1000 + gpl.line_number    pl, \
							ga.sura_number * 1000 + ga.ayah_number      ayah, \ 
							count(g.glyph_id)                           g_count \              
						FROM glyph_page_line gpl  \
						INNER JOIN glyph g ON g.glyph_id = gpl.glyph_id  \
						INNER JOIN glyph_ayah ga ON ga.glyph_id = g.glyph_id  \
						WHERE  \
							(ga.sura_number * 1000 + ga.ayah_number) BETWEEN ? AND ? AND \
							g.glyph_type_id = 1 \
						GROUP BY ayah, pl \
						ORDER BY pl ASC \
						) line_ayah_glyphs \
					JOIN ( \
						SELECT \
							gpl2.page_number * 1000 + gpl2.line_number  pl2, \
							count(g2.glyph_id)                          g_count2 \
						FROM glyph_page_line                        gpl2 \
						LEFT JOIN glyph g2 ON g2.glyph_id = gpl2.glyph_id \
						WHERE  \
							g2.glyph_type_id = 1 \
						GROUP BY pl2 \
					) line_glyphs \
						ON line_glyphs.pl2 = line_ayah_glyphs.pl     \
				) ayah_line_fractions \
				GROUP BY ayah \
				ORDER BY ayah ASC \
			) ayahs_details");
	}

	$self->{_selected_ayah_range_details}->execute($start_ayah, $end_ayah);

	my $ayah_range_details = {};

	# $log->info(Dumper {$start_ayah, $end_ayah});

	while (my ($start_ayah, $start_page_line, $start_page, $start_line,
			$end_ayah, $end_page_line, $end_page, $end_line, $ayahs, $lines_length) 
			= $self->{_selected_ayah_range_details}->fetchrow_array) {

			if ((int($start_ayah) % 1000) eq '1') {
				if (((int($start_page_line) % 1000) eq '2')) {
					$start_page_line = (int($start_page_line / 1000) - 1) * 1000 + 15;
				} else {
					$start_page_line = $start_page_line - 2;
				}
				$start_page = int($start_page_line / 1000);
				$start_line = $start_page_line % 1000;
			}

			$ayah_range_details = {
				start_ayah 		=> $start_ayah,
				start_page_line => $start_page_line,
				start_page  	=> $start_page,
				start_line  	=> $start_line,
				end_ayah		=> $end_ayah,
				end_page_line	=> $end_page_line,
				end_page		=> $end_page,
				end_line		=> $end_line,
				ayahs			=> $ayahs,
				lines_length	=> $lines_length,
				display_lines	=> 15*(int($end_page_line/1000)-int($start_page_line/1000)) 
									+ ($end_page_line % 1000) - ($start_page_line % 1000) + 1
			},
	};

	$self->{_selected_ayah_range_details}->finish;

	return $ayah_range_details;
}

sub get_ayah_lines {
	my ($self, $start_ayah_page_line, $end_ayah_page_line, $start_ayah) = @_;

	#if starting from the beginning of a page with sura heading on previous page
	#then adjust beginning line to previous page last line, so that line is included
	#in the results of query below.
	if (((int($start_ayah_page_line) % 1000) eq '2') and ((int($start_ayah) % 1000) eq '1')) {
		$start_ayah_page_line = (int($start_ayah_page_line / 1000) - 1) * 1000 + 15;
	}


	if (!defined $self->{_select_ayah_glyphs}) {
		$self->{_select_ayah_glyphs} = $self->{_dbh}->prepare_cached(
			"SELECT \
				gpl.glyph_page_line_id, gpl.page_number, gpl.line_number, gpl.line_type, gpl.position, \
				ga.sura_number, ga.ayah_number, \
				g.font_file, g.glyph_code, gt.glyph_type_id, \
				gt.name \
			FROM glyph_page_line gpl \
			LEFT JOIN glyph g ON g.glyph_id = gpl.glyph_id \
			LEFT JOIN glyph_ayah ga ON ga.glyph_id = g.glyph_id \
			LEFT JOIN glyph_type gt ON g.glyph_type_id = gt.glyph_type_id \
			WHERE ((gpl.page_number * 1000 + gpl.line_number) >= ?) \
				AND ((gpl.page_number * 1000 + gpl.line_number) <= ?) \
			ORDER BY gpl.page_number ASC, gpl.line_number ASC, gpl.position DESC"
			);
	}

	$self->{_select_ayah_glyphs}->execute($start_ayah_page_line, $end_ayah_page_line);

	my $lines = [];
	my $i = 0;
	my $last_line_number = '';
	while (my ($glyph_page_line_id, $page_number, $line_number, $line_type, $glyph_position,
			$sura_number, $ayah_number, 
			$font, $glyph_code, $glyph_type_id, $glyph_type) = $self->{_select_ayah_glyphs}->fetchrow_array) {
		my $glyph_text = '&#'. $glyph_code .';';
		
		$last_line_number = $line_number if $last_line_number eq '';
		$i++ if $last_line_number ne $line_number;

		if (!defined $lines->[$i]) {
			$lines->[$i] = {
				number => $i + 1,
				page_number => $page_number,
				line_number => $line_number,
				type   => $line_type,
				text   => $glyph_text,
				font   => Quran::FONT_DIR .'/'. $font,
				glyphs => [{
					page_line_id => $glyph_page_line_id,
					sura_number  => $sura_number,
					ayah_number  => $ayah_number,
					code         => $glyph_code,
					text         => $glyph_text,
					type_id		 => $glyph_type_id,
					type         => $glyph_type,
					position     => $glyph_position
				}],
			};
		}
		else {
			push @{ $lines->[$i]->{glyphs} }, {
				page_line_id => $glyph_page_line_id,
				sura_number  => $sura_number,
				ayah_number  => $ayah_number,
				code         => $glyph_code,
				text         => $glyph_text,
				type_id		 => $glyph_type_id,
				type         => $glyph_type,
				position     => $glyph_position
			};
			$lines->[$i]->{text} .= $glyph_text;
		}
		$last_line_number = $line_number;
	}

	$self->{_select_ayah_glyphs}->finish;

	return $lines;
}

sub get_page_lines {
	my ($self, $page) = @_;

	# if (!defined $self->{_select_page_glyphs}) {
	# 	$self->{_select_page_glyphs} = $self->{_dbh}->prepare_cached(
	# 		"SELECT gpl.glyph_page_line_id, gpl.line_number, gpl.line_type, gpl.position, g.font_file, ".
	# 		"g.glyph_code, gt.name FROM glyph_page_line gpl LEFT JOIN glyph g ON ".
	# 		"g.glyph_id = gpl.glyph_id LEFT JOIN glyph_type gt ON g.glyph_type_id = ".
	# 		"gt.glyph_type_id WHERE gpl.page_number = ? ORDER BY gpl.page_number ASC, ".
	# 		"gpl.line_number ASC, gpl.position DESC");
	# }

	if (!defined $self->{_select_page_glyphs}) {
		$self->{_select_page_glyphs} = $self->{_dbh}->prepare_cached(
			"SELECT \
				gpl.glyph_page_line_id, gpl.line_number, gpl.line_type, gpl.position, \
				ga.sura_number, ga.ayah_number, \
				g.font_file, g.glyph_code, gt.glyph_type_id, \
				gt.name \
			FROM glyph_page_line gpl \
			LEFT JOIN glyph g ON g.glyph_id = gpl.glyph_id \
			LEFT JOIN glyph_ayah ga ON ga.glyph_id = g.glyph_id \
			LEFT JOIN glyph_type gt ON g.glyph_type_id = gt.glyph_type_id \
			WHERE gpl.page_number = ? \
			ORDER BY gpl.page_number ASC, gpl.line_number ASC, gpl.position DESC"
			);
	}

	$self->{_select_page_glyphs}->execute($page);

	my $lines = [];

	while (my ($glyph_page_line_id, $line_number, $line_type, $glyph_position,
			$sura_number, $ayah_number, 
			$line_font, $glyph_code, $glyph_type_id, $glyph_type) = $self->{_select_page_glyphs}->fetchrow_array) {
		my $glyph_text = '&#'. $glyph_code .';';
		if (!defined $lines->[$line_number - 1]) {
			$lines->[$line_number - 1] = {
				number => $line_number,
				type   => $line_type,
				text   => $glyph_text,
				font   => Quran::FONT_DIR .'/'. $line_font,
				glyphs => [{
					page_line_id => $glyph_page_line_id,
					sura_number  => $sura_number,
					ayah_number  => $ayah_number,
					code         => $glyph_code,
					text         => $glyph_text,
					type_id		 => $glyph_type_id,
					type         => $glyph_type,
					position     => $glyph_position
				}],
			};
		}
		else {
			push @{ $lines->[$line_number - 1]->{glyphs} }, {
				page_line_id => $glyph_page_line_id,
				sura_number  => $sura_number,
				ayah_number  => $ayah_number,
				code         => $glyph_code,
				text         => $glyph_text,
				type_id		 => $glyph_type_id,
				type         => $glyph_type,
				position     => $glyph_position
			};
			$lines->[$line_number - 1]->{text} .= $glyph_text;
		}
	}

	$self->{_select_page_glyphs}->finish;

	return $lines;
}

sub set_page_line_bbox {
	my $self = shift;

	my ($glyph_page_line_id, $img_width, $min_x, $max_x, $min_y, $max_y) = @_;

	if (!defined $self->{_set_page_line_bbox}) {
		$self->{_set_page_line_bbox} = 1;
		$self->{_set_page_line_bbox_select} = $self->{_dbh}->prepare_cached(
			"SELECT glyph_page_bbox_id FROM glyph_page_line_bbox WHERE glyph_page_line_id = ? AND img_width = ?"
		);
		$self->{_set_page_line_bbox_insert} = $self->{_dbh}->prepare_cached(
			"INSERT INTO glyph_page_line_bbox (glyph_page_line_id, img_width, min_x, max_x, min_y, max_y) ".
			"VALUES (?, ?, ?, ?, ?, ?)"
		);
		$self->{_set_page_line_bbox_update} = $self->{_dbh}->prepare_cached(
			"UPDATE glyph_page_line_bbox SET min_x = ?, max_x = ?, min_y = ?, max_y = ? ".
			"WHERE glyph_page_line_id = ? AND img_width = ?"
		);
	}
	else {
		$self->{_set_page_line_bbox_select}->execute($glyph_page_line_id, $img_width);
		my @glyph_page_bbox_id = $self->{_set_page_line_bbox_select}->fetchrow_array;
		$self->{_set_page_line_bbox_select}->finish;

		if (scalar @glyph_page_bbox_id) {
			$self->{_set_page_line_bbox_update}->execute($min_x, $max_x, $min_y, $max_y, $glyph_page_line_id, $img_width);
			$self->{_set_page_line_bbox_update}->finish;
		}
		else {
			$self->{_set_page_line_bbox_insert}->execute($glyph_page_line_id, $img_width, $min_x, $max_x, $min_y, $max_y);
			$self->{_set_page_line_bbox_insert}->finish;
		}
	}
=cut

		$self->{_select_page_glyphs} = $self->{_dbh}->prepare_cached(
			"SELECT gpl.glyph_page_line_id, gpl.line_number, gpl.line_type, gpl.position, g.font_file, ".
			"g.glyph_code, gt.name FROM glyph_page_line gpl LEFT JOIN glyph g ON ".
			"g.glyph_id = gpl.glyph_id LEFT JOIN glyph_type gt ON g.glyph_type_id = ".
			"gt.glyph_type_id WHERE gpl.page_number = ? ORDER BY gpl.page_number ASC, ".
			"gpl.line_number ASC, gpl.position DESC");
	}

	$self->{_select_page_glyphs}->execute($page);
=cut
	return;
}

sub get_ornament_glyph {
	my ($self, $name) = @_;

	my $sth;
	if (!defined $self->{_sth_ornament}) {
		$sth = ($self->{_sth_ornament} = $self->{_dbh}->prepare_cached(
		"SELECT g.glyph_code, gt.name FROM glyph g, glyph_type gt, ".
		"glyph_type gtp WHERE g.glyph_type_id = gt.glyph_type_id AND ".
		"gt.parent_id = gtp.glyph_type_id AND gtp.name = 'ornament' AND ".
		"gt.name = ?"));
	}
	else {
		$sth = $self->{_sth_ornament};
	}

	$sth->execute($name);

	my ($glyph_code, $glyph_type) = $sth->fetchrow_array;

	$sth->finish;

	return {
		code => $glyph_code,
		text => '&#'. $glyph_code .';',
		type => $glyph_type,
		position => 0
	};
}

sub _get_glyph_type {
	my ($self, $glyph_code, $page_number) = @_;

	$glyph_code =~ s/[^\d]*//g;

	my $sth;
	if (!defined $self->{_sth_glyph_type}) {
		$sth = ($self->{_sth_glyph_type} = $self->{_dbh}->prepare_cached(
		"SELECT gt.name FROM glyph_type gt, glyph g WHERE g.glyph_type_id = ".
		"gt.glyph_type_id AND g.glyph_code = ? AND g.page_number = ?"));
	}
	else {
		$sth = $self->{_sth_glyph_type};
	}

	$sth->execute($glyph_code, $page_number);

	my ($glyph_type) = $sth->fetchrow_array;

	$sth->finish;

	return $glyph_type? $glyph_type : '';
}

sub _get_word_val {
	my ($self, $key, $glyph_code, $page_number) = @_;

	my @keys = qw/arabic lemma root stem/;
	return if not grep $key eq $_, @keys;

	$glyph_code =~ s/[^\d]//g;

	my $sth;

	if (!defined $self->{"_sth_word_$key"}) {
		$sth = ($self->{"_sth_word_$key"} = $self->{_dbh}->prepare_cached(
		"SELECT wk.value FROM word_$key wk, word w, glyph g WHERE ".
		"w.word_$key"."_id = wk.word_$key"."_id AND w.glyph_id = g.glyph_id AND ".
		"g.glyph_code = ? AND w.page_number = ?"));
	}
	else {
		$sth = $self->{"_sth_word_$key"};
	}

	$sth->execute($glyph_code, $page_number);

	my ($word_val) = $sth->fetchrow_array;

	$sth->finish;

	return $word_val? $word_val : '';
}

1;
