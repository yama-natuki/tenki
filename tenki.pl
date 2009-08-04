#!/usr/bin/perl
# last updated : 2009/08/04 15:15:24 JST
# 	$Id: tenki.pl,v 1.13 2009/07/19 07:01:09 yama Exp yama $	

# weather.com が登録しないとAPI使えないみたいなので、自力で別のを作ることに。
# wunderground.com を利用。

#　地域名を入れる。近いエアポートリストがくるので、それ全部のxmlを取得、ここが時間的コストかかるなあ。
# 各xmlの日付を確認。一番新しいデータを選択して表示。

# 参考url
# http://api.wunderground.com/auto/wui/geo/GeoLookupXML/index.xml?query=sayama
# http://api.wunderground.com/auto/wui/geo/WXCurrentObXML/index.xml?query=RJTJ
# http://www.kawa.net/works/perl/treepp/treepp.html
# http://wiki.wunderground.com/index.php/API_-_XML
# www.wunderground.com
# http://www.wunderground.com/cgi-bin/findweather/hdfForecast?query=sayama&searchType=WEATHER&MR=1
# METAR〜定時航空気象実況
# http://japa.or.jp/test/meter.pl


use strict;
use XML::TreePP;
use Getopt::Long;
use Pod::Usage;

my $opt_lookup;
my $opt_pws;
my $opt_aircode;
my $opt_debug;
my $opt_dump;
my $url;
my $query;
my $man = 0;
my $opt_help = 0;

GetOptions(
	'lookup=s'	=> \$opt_lookup,
	'pws=s'		=> \$opt_pws,
	'aircode=s' => \$opt_aircode,
	'debug'		=> \$opt_debug,
	'dump'		=> \$opt_dump,
	'help|?'    => \$opt_help);

GetOptions('help|?' => \$opt_help, man => \$man) or pod2usage(2);
pod2usage(1) if $opt_help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($opt_lookup) {
	$url = 'http://api.wunderground.com/auto/wui/geo/GeoLookupXML/index.xml?query=';
	$query = $url . $opt_lookup;
    if ($opt_dump) {
	    url_dump($query);
	} else {
	    lookup($query);
	}
} elsif ($opt_aircode) {
    $url = 'http://api.wunderground.com/auto/wui/geo/WXCurrentObXML/index.xml?query=';
	$query = $url . $opt_aircode;
    if ($opt_dump) {
	    url_dump($query);
	} else {
	    airport($query);
	}
} elsif ($opt_pws) {
	$url = 'http://api.wunderground.com/weatherstation/WXCurrentObXML.asp?ID=';
	$query = $url . $opt_pws;
    if ($opt_dump) {
	    url_dump($query);
	} else {
	    pws($query);
	}
} else {
  pod2usage(2);
}


sub url_dump {
	my $pageurl = shift;
	my $tpp = XML::TreePP->new();
	my $tree = $tpp->parsehttp( GET => $pageurl);
	$tpp->set( indent => 2 );
	print $tpp->write($tree);
}

sub lookup {
	my $pageurl = shift;
	my $tpp = XML::TreePP->new();
    # ページのparse
	my $tree = $tpp->parsehttp( GET => $pageurl);
	if ($tree->{wui_error}->{title}) {
		print $tree->{wui_error}->{title} . "\n";
		exit;
	}
    # 空港の部分のツリーを格納。
	my $weather_point__hash = $tree->{location}->{nearby_weather_stations};
    # 各空港をハッシュに格納。
	my $airport_array = $weather_point__hash->{airport}->{station};
    # 空港の四桁コードを表示。
	print "飛行場            コード  緯度        経度" . "\n";
	foreach my $itemhash ( @$airport_array ) {
		printf("%-15s\t   %s   %s %s\n",
			   $itemhash->{city}, $itemhash->{icao}, $itemhash->{lat}, $itemhash->{lon});
	}
	if ($weather_point__hash->{pws}) {
		# 各観測所を配列に格納。
		my $pws_array = $weather_point__hash->{pws}->{station};
		print "--------------------------------------\n";
		print "観測所                     ID" . "\n";
		foreach my $itemhash ( @$pws_array ) {
			printf("%-17s\t   %s\n",
				   $itemhash->{city}, $itemhash->{id});
		}
	}
}

sub airport {
	my $pageurl = shift;
	my $tpp = XML::TreePP->new();
	my $tree = $tpp->parsehttp( GET => $pageurl) || die "can't get $pageurl";
	my $airport_hash = $tree->{current_observation};
	unless ($airport_hash->{display_location}->{city}) {
		print "NO DATA\n";
		exit;
	}
	printf("場所　　　　: %s, %s\n",
		   airport_translate($airport_hash->{display_location}->{city}),
		   country($airport_hash->{display_location}->{state_name}));
	print "更新時間　　: " . local_date($airport_hash->{observation_epoch}) . "\n";
	if ($opt_debug) {
		print "天候　　　　: " . $airport_hash->{weather} . "\n";
	}
	print "天候　　　　: " . weather($airport_hash->{weather}) . "\n";
	my $kaze = wind_speed($airport_hash->{wind_mph});
	my $kazemuki = wind_dir($airport_hash->{wind_dir});
	if ($opt_debug) {
		printf("風　　　　　: %s mph, %s\n",
			   $airport_hash->{wind_mph}, $airport_hash->{wind_dir});
	}
	if ($airport_hash->{wind_dir} eq "Variable") {
		printf ("風　　　　　: %.2f m/s, %s\n", $kaze, $kazemuki);
	} else {
		printf ("風　　　　　: %.2f m/s, %sの風\n", $kaze, $kazemuki);
	}
	printf ("気温　　　　: %s℃\n", $airport_hash->{temp_c});
	unless ( $airport_hash->{heat_index_c} eq "NA") {
		printf ("体感温度　　: %s℃\n", $airport_hash->{heat_index_c});
	} else {
		my $taikan = windchill($airport_hash->{temp_c},
				     $airport_hash->{relative_humidity},
					 wind_speed($airport_hash->{wind_mph}));
		printf ("体感温度* 　: %.1f℃\n", $taikan);
	}
	printf ("湿度　　　　: %s\n", $airport_hash->{relative_humidity});
	printf ("露点温度　　: %s℃\n", $airport_hash->{dewpoint_c});
	printf ("気圧　　　　: %s ヘクトパスカル\n", $airport_hash->{pressure_mb});
	printf ("視程　　　　: %s Km\n", $airport_hash->{visibility_km});
}

sub pws {
	my $pageurl = shift;
	my $tpp = XML::TreePP->new();
	my $tree = $tpp->parsehttp( GET => $pageurl) || die "can't get $pageurl";
	my $pws_hash = $tree->{current_observation};
	print "場所　　　　: " . $pws_hash->{location}->{full} . "\n";
	print "更新時間　　: " . $pws_hash->{observation_time} . "\n";
	if ($pws_hash->{weather}) {
		if ($opt_debug) {
			print "天候　　　　: " . $pws_hash->{weather} . "\n";
		}
		print "天候* 　　　: " . pws_weather($pws_hash->{weather}) . "\n";
	} else {
		print "天候　　　　: --\n";
	}	
	my $kaze = wind_speed($pws_hash->{wind_mph});
	my $kazemuki = wind_dir($pws_hash->{wind_dir});
	if ($opt_debug) {
		printf("風　　　　　: %s mph, %s\n",
			   $pws_hash->{wind_mph}, $pws_hash->{wind_dir});
	}
	printf ("風　　　　　: %.2f m/s, %sの風\n", $kaze, $kazemuki);
	printf ("気温　　　　: %s℃\n", $pws_hash->{temp_c});
	if ( $pws_hash->{heat_index_c}) {
		printf ("体感温度　　: %s℃\n", $pws_hash->{heat_index_c});
	} else {
		print "体感温度 　 : --\n";
	}
	printf ("湿度　　　　: %s%\n", $pws_hash->{relative_humidity});
	printf ("露点温度　　: %s℃\n", $pws_hash->{dewpoint_c});
	printf ("気圧　　　　: %s ヘクトパスカル\n", $pws_hash->{pressure_mb});
}

# 体感温度
sub windchill {
	# 引数は、温度、湿度、風速。
	return 37 - (37 - $_[0]) / (0.68 - 0.0014 * $_[1] + 1/(1.76 + 1.4*($_[2]^0.75))) - 0.29 * $_[0] * (1 - $_[1] / 100);
}

# 風向き
sub wind_dir {
	my $var =shift;
	my %muki = (
		"North"	   => "北",
        "East"	   => "東",
        "West"	   => "西",
        "South"	   => "南",
        "NE"	   => "北東",
        "NW"	   => "北西",
        "SE"	   => "南東",
        "SW"	   => "南西",
        "NNE"	   => "北北東",
        "ENE"	   => "東北東",
        "NNW"	   => "北北西",
        "WNW"	   => "西北西",
        "SSE"	   => "南南東",
        "ESE"	   => "東南東",
        "SSW"	   => "南南西",
        "WSW"	   => "西南西",
		"Variable" => "風向きが一定でない"
		);
	return $muki{$var};
}

# 風速 mph → m/s
sub  wind_speed {
	my $var = shift;
	return $var * 0.44704;
}

# 日付変換。
sub local_date {
	my $var = shift;
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($var);
	$year += 1900;
	$mon++;
	my @day_of_week = qw( 日 月 火 水 木 金 土 );
	return sprintf("%s年%s月%s日(%s) $hour時$min分",
				   $year, $mon, $mday, $day_of_week[$wday], $hour, $min );
}

# 近傍観測所の天気の翻訳。手抜き。
sub pws_weather {
	my $var =shift;
	my %tenki = (
		"FEW"			=> "少しの(雲量1/8～2/8)曇り時々晴れ",
		"OVC"			=> "曇り",
		"Flurries"		=> "flurries",
		"FOG"			=> "霧",
		"Hazy"			=> "hazy",
		"BKN"			=> "ほとんど曇り",
		"Mostly Sunny"	=> "mostlysunny",
		"SCT"			=> "ところにより曇り",
		"Partly Sunny"	=> "partlysunny",
		"Rain"			=> "雨",
		"Sleet"			=> "みぞれ（雪まじりの雨）",
		"Snow"			=> "雪",
		"SKC"			=> "快晴 （雲なし）",
		"Thunderstorms" => "雷雨",
		"Unknown"		=> "不明"
		);
	if ($tenki{$var}) {
		return $tenki{$var};
	} else {
		return $var;
	}
}

# 天気の翻訳。どんどん追記していってください。
sub weather  {
	my $var =shift;
	my %tenki = (
		"Clear"						   => "晴れ",
		"Cloudy"					   => "曇り",
		"Flurries"					   => "flurries",
		"Fog"						   => "霧",
		"haze"						   => "もや、かすみ",
		"Mostly Cloudy"				   => "ほとんど曇り",
		"Mostly Sunny"				   => "だいたい晴れ",
		"Partly Cloudy"				   => "ところにより曇り",
		"Partly Sunny"				   => "ところにより晴れ",
		"Overcast"					   => "曇り(どんよりした空模様)",
		"Scattered Clouds"			   => "ときおり曇り（雲がチラホラある時）",
		"light showers rain"		   => "弱いにわか雨",
		"light showers rain mist"	   => "弱いにわか雨と霞",
		"showers rain mist"			   => "にわか雨",
		"Heavy showers rain"		   => "強いにわか雨",
		"thunderstorm rain"			   => "雷雨",
		"light thunderstorm rain"	   => "弱い雷雨",
		"light thunderstorm rain mist" => "弱い雷雨と霞",
		"heavy thunderstorm rain"	   => "強い雷雨",
		"Rain"						   => "雨",
		"light rain"				   => "小雨",
		"light rain mist"			   => "小雨",
		"light rain drizzle mist"	   => "小雨／霧雨",
		"light drizzle mist"		   => "かるい霧雨",
		"Heavy Rain"				   => "大雨",
		"Sleet"						   => "みぞれ（雪まじりの雨）",
		"Snow"						   => "雪",
		"Sunny"						   => "快晴",
		"Thunderstorms"				   => "雷雨",
		"Unknown"					   => "不明",
		"Drizzle"					   => "霧雨",
		"Snow"						   => "雪",
		"Light Snow"				   => "小雪",
		"Heavy Snow"				   => "大雪"
		);
	if ($tenki{$var}) {
		return $tenki{$var};
	} else {
		return $var;
	}
}

sub country {
	my $var =shift;
	my %loc = (
		"Japan"    => "日本"
		);
	if ($loc{$var}) {
		return $loc{$var};
	} else {
		return $var;
	}
}

# 飛行場翻訳。適当に追加してね。 
sub airport_translate {
	my $var =shift;
	my %air = (
		"Tokyo (Haneda) International"	   => "東京国際空港 (羽田空港)",
		"Yokota Air Base"				   => "横田航空基地",
		"Tachikawa"						   => "立川飛行場",
		"Atsugi Aero"					   => "厚木飛行場",
		"Sendai"						   => "仙台空港",
		"New Tokyo International (Narita)" => "新東京国際空港 (成田空港)",
		"Sapporo"						   => "札幌空港 (丘珠空港)",
		"Iruma Aero"					   => "入間航空基地",
		"Kansai International"			   => "関西国際空港",
		"New Chitose"					   => "新千歳空港"
		);
	if ($air{$var}) {
		return $air{$var};
	} else {
		return $var;
	}
}
__END__

=head1 NAME

tenki - Using Getopt::Long and Pod::Usage

=head1 SYNOPSIS

tenki [options] 

 Options:
   --lookup=CITY      lookup station id or airport code
   --aircode=CODE     airport code
   --pws=ID           personal weather station id
   --help             show this help message and exit.


=cut
