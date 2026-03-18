import CoreLocation

// 駅情報
struct TransitStation {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let lineIds: [String]
}

// 路線情報
struct TransitLine {
    let id: String
    let name: String
    let company: String
    let color: String // hex color
    let stationIds: [String] // ordered station IDs
    let avgIntervalMinutes: Double // average time between stations
    let isLoop: Bool

    init(
        id: String,
        name: String,
        company: String,
        color: String,
        stationIds: [String],
        avgIntervalMinutes: Double,
        isLoop: Bool = false
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.color = color
        self.stationIds = stationIds
        self.avgIntervalMinutes = avgIntervalMinutes
        self.isLoop = isLoop
    }
}

// 直通運転接続情報
struct ThroughServiceConnection {
    let lineId1: String
    let lineId2: String
    let stationId: String
    let penaltyMinutes: Double
}

// 東京エリアの路線・駅データベース
enum TokyoTransitData {

    // MARK: - 直通運転データ

    static let throughServiceConnections: [ThroughServiceConnection] = [
        ThroughServiceConnection(lineId1: "tokyu_dento", lineId2: "metro_hanzomon", stationId: "shibuya", penaltyMinutes: 0),
    ]

    /// 直通運転かどうかを判定
    static func isThroughService(lineId1: String, lineId2: String, atStation stationId: String) -> Bool {
        throughServiceConnections.contains { conn in
            conn.stationId == stationId &&
            ((conn.lineId1 == lineId1 && conn.lineId2 == lineId2) ||
             (conn.lineId1 == lineId2 && conn.lineId2 == lineId1))
        }
    }

    // MARK: - 駅データ

    static let stations: [TransitStation] = [
        // 東急田園都市線（Nominatim verified coordinates）
        TransitStation(
            id: "shibuya",
            name: "渋谷",
            coordinate: CLLocationCoordinate2D(latitude: 35.6591, longitude: 139.7002),
            lineIds: ["tokyu_dento", "jr_yamanote", "metro_hanzomon", "metro_ginza", "metro_fukutoshin"]
        ),
        TransitStation(
            id: "ikejiriohashi",
            name: "池尻大橋",
            coordinate: CLLocationCoordinate2D(latitude: 35.6510, longitude: 139.6848),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "sangenjaya",
            name: "三軒茶屋",
            coordinate: CLLocationCoordinate2D(latitude: 35.6437, longitude: 139.6720),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "komazawadaigaku",
            name: "駒沢大学",
            coordinate: CLLocationCoordinate2D(latitude: 35.6332, longitude: 139.6612),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "sakurashinmachi",
            name: "桜新町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6317, longitude: 139.6454),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "yoga",
            name: "用賀",
            coordinate: CLLocationCoordinate2D(latitude: 35.6265, longitude: 139.6333),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "futakotamagawa",
            name: "二子玉川",
            coordinate: CLLocationCoordinate2D(latitude: 35.6114, longitude: 139.6291),
            lineIds: ["tokyu_dento", "tokyu_oimachi"]
        ),
        TransitStation(
            id: "futakoshinchi",
            name: "二子新地",
            coordinate: CLLocationCoordinate2D(latitude: 35.6072, longitude: 139.6224),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "takatsu",
            name: "高津",
            coordinate: CLLocationCoordinate2D(latitude: 35.6030, longitude: 139.6164),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "mizonokuchi",
            name: "溝の口",
            coordinate: CLLocationCoordinate2D(latitude: 35.5994, longitude: 139.6116),
            lineIds: ["tokyu_dento", "tokyu_oimachi"]
        ),
        TransitStation(
            id: "kajigaya",
            name: "梶が谷",
            coordinate: CLLocationCoordinate2D(latitude: 35.5937, longitude: 139.6055),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "miyazakidai",
            name: "宮崎台",
            coordinate: CLLocationCoordinate2D(latitude: 35.5870, longitude: 139.5913),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "miyamaedaira",
            name: "宮前平",
            coordinate: CLLocationCoordinate2D(latitude: 35.5848, longitude: 139.5815),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "saginuma",
            name: "鷺沼",
            coordinate: CLLocationCoordinate2D(latitude: 35.5793, longitude: 139.5733),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "tamaplaza",
            name: "たまプラーザ",
            coordinate: CLLocationCoordinate2D(latitude: 35.5767, longitude: 139.5585),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "azamino",
            name: "あざみ野",
            coordinate: CLLocationCoordinate2D(latitude: 35.5687, longitude: 139.5534),
            lineIds: ["tokyu_dento"]
        ),
        TransitStation(
            id: "chuorinkan",
            name: "中央林間",
            coordinate: CLLocationCoordinate2D(latitude: 35.5073, longitude: 139.4453),
            lineIds: ["tokyu_dento"]
        ),

        // 東急大井町線（二子玉川・溝の口は上で定義済み）
        TransitStation(
            id: "oimachi",
            name: "大井町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6074, longitude: 139.7344),
            lineIds: ["tokyu_oimachi"]
        ),
        TransitStation(
            id: "hatanodai",
            name: "旗の台",
            coordinate: CLLocationCoordinate2D(latitude: 35.6053, longitude: 139.7021),
            lineIds: ["tokyu_oimachi"]
        ),
        TransitStation(
            id: "okusawa",
            name: "大岡山",
            coordinate: CLLocationCoordinate2D(latitude: 35.6078, longitude: 139.6859),
            lineIds: ["tokyu_oimachi"]
        ),
        TransitStation(
            id: "jiyugaoka",
            name: "自由が丘",
            coordinate: CLLocationCoordinate2D(latitude: 35.6074, longitude: 139.6693),
            lineIds: ["tokyu_oimachi"]
        ),

        // JR南武線
        TransitStation(
            id: "kawasaki",
            name: "川崎",
            coordinate: CLLocationCoordinate2D(latitude: 35.5313, longitude: 139.7020),
            lineIds: ["jr_nambu"]
        ),
        TransitStation(
            id: "musashikosugi",
            name: "武蔵小杉",
            coordinate: CLLocationCoordinate2D(latitude: 35.5762, longitude: 139.6596),
            lineIds: ["jr_nambu"]
        ),
        TransitStation(
            id: "musashimizonokuchi",
            name: "武蔵溝ノ口",
            coordinate: CLLocationCoordinate2D(latitude: 35.5991, longitude: 139.6134),
            lineIds: ["jr_nambu"]
        ),
        TransitStation(
            id: "noborito",
            name: "登戸",
            coordinate: CLLocationCoordinate2D(latitude: 35.6165, longitude: 139.5690),
            lineIds: ["jr_nambu"]
        ),
        TransitStation(
            id: "inadazutsumi",
            name: "稲田堤",
            coordinate: CLLocationCoordinate2D(latitude: 35.6327, longitude: 139.5241),
            lineIds: ["jr_nambu"]
        ),
        TransitStation(
            id: "fuchuhommachi",
            name: "府中本町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6636, longitude: 139.4782),
            lineIds: ["jr_nambu"]
        ),
        TransitStation(
            id: "tachikawa",
            name: "立川",
            coordinate: CLLocationCoordinate2D(latitude: 35.6983, longitude: 139.4138),
            lineIds: ["jr_nambu", "jr_chuo_rapid"]
        ),

        // JR山手線（渋谷・代々木は他セクションで定義済み、巣鴨は都営三田線セクションで定義済み）
        TransitStation(
            id: "tokyo",
            name: "東京",
            coordinate: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
            lineIds: ["jr_yamanote", "jr_chuo_rapid"]
        ),
        TransitStation(
            id: "kanda",
            name: "神田",
            coordinate: CLLocationCoordinate2D(latitude: 35.6918, longitude: 139.7709),
            lineIds: ["jr_yamanote", "metro_ginza", "jr_chuo_rapid"]
        ),
        TransitStation(
            id: "akihabara",
            name: "秋葉原",
            coordinate: CLLocationCoordinate2D(latitude: 35.6984, longitude: 139.7731),
            lineIds: ["jr_yamanote", "metro_hibiya"]
        ),
        TransitStation(
            id: "okachimachi",
            name: "御徒町",
            coordinate: CLLocationCoordinate2D(latitude: 35.7074, longitude: 139.7745),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "ueno",
            name: "上野",
            coordinate: CLLocationCoordinate2D(latitude: 35.7141, longitude: 139.7774),
            lineIds: ["jr_yamanote", "metro_ginza", "metro_hibiya"]
        ),
        TransitStation(
            id: "uguisudani",
            name: "鶯谷",
            coordinate: CLLocationCoordinate2D(latitude: 35.7206, longitude: 139.7787),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "nippori",
            name: "日暮里",
            coordinate: CLLocationCoordinate2D(latitude: 35.7281, longitude: 139.7710),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "nishinippori",
            name: "西日暮里",
            coordinate: CLLocationCoordinate2D(latitude: 35.7320, longitude: 139.7669),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "tabata",
            name: "田端",
            coordinate: CLLocationCoordinate2D(latitude: 35.7381, longitude: 139.7608),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "komagome",
            name: "駒込",
            coordinate: CLLocationCoordinate2D(latitude: 35.7363, longitude: 139.7468),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "otsuka",
            name: "大塚",
            coordinate: CLLocationCoordinate2D(latitude: 35.7316, longitude: 139.7287),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "ikebukuro",
            name: "池袋",
            coordinate: CLLocationCoordinate2D(latitude: 35.7295, longitude: 139.7109),
            lineIds: ["jr_yamanote", "metro_fukutoshin"]
        ),
        TransitStation(
            id: "mejiro",
            name: "目白",
            coordinate: CLLocationCoordinate2D(latitude: 35.7210, longitude: 139.7065),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "takadanobaba",
            name: "高田馬場",
            coordinate: CLLocationCoordinate2D(latitude: 35.7126, longitude: 139.7035),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "shinookubo",
            name: "新大久保",
            coordinate: CLLocationCoordinate2D(latitude: 35.7012, longitude: 139.7001),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "shinjuku",
            name: "新宿",
            coordinate: CLLocationCoordinate2D(latitude: 35.6896, longitude: 139.7006),
            lineIds: ["jr_yamanote", "toei_shinjuku", "jr_chuo_rapid", "toei_oedo", "metro_marunouchi"]
        ),
        TransitStation(
            id: "harajuku",
            name: "原宿",
            coordinate: CLLocationCoordinate2D(latitude: 35.6702, longitude: 139.7027),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "ebisu",
            name: "恵比寿",
            coordinate: CLLocationCoordinate2D(latitude: 35.6467, longitude: 139.7100),
            lineIds: ["jr_yamanote", "metro_hibiya"]
        ),
        TransitStation(
            id: "meguro",
            name: "目黒",
            coordinate: CLLocationCoordinate2D(latitude: 35.6337, longitude: 139.7158),
            lineIds: ["jr_yamanote", "toei_mita"]
        ),
        TransitStation(
            id: "gotanda",
            name: "五反田",
            coordinate: CLLocationCoordinate2D(latitude: 35.6264, longitude: 139.7234),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "osaki",
            name: "大崎",
            coordinate: CLLocationCoordinate2D(latitude: 35.6197, longitude: 139.7284),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "shinagawa",
            name: "品川",
            coordinate: CLLocationCoordinate2D(latitude: 35.6284, longitude: 139.7387),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "takanawagateway",
            name: "高輪ゲートウェイ",
            coordinate: CLLocationCoordinate2D(latitude: 35.6355, longitude: 139.7406),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "tamachi",
            name: "田町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6457, longitude: 139.7475),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "hamamatsucho",
            name: "浜松町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6555, longitude: 139.7571),
            lineIds: ["jr_yamanote"]
        ),
        TransitStation(
            id: "shimbashi",
            name: "新橋",
            coordinate: CLLocationCoordinate2D(latitude: 35.6660, longitude: 139.7583),
            lineIds: ["jr_yamanote", "metro_ginza"]
        ),
        TransitStation(
            id: "yurakucho",
            name: "有楽町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6751, longitude: 139.7628),
            lineIds: ["jr_yamanote"]
        ),

        // 東京メトロ半蔵門線（渋谷は上で定義済み）
        TransitStation(
            id: "omotesando",
            name: "表参道",
            coordinate: CLLocationCoordinate2D(latitude: 35.6652, longitude: 139.7123),
            lineIds: ["metro_hanzomon", "metro_ginza"]
        ),
        TransitStation(
            id: "aoyamaicchome",
            name: "青山一丁目",
            coordinate: CLLocationCoordinate2D(latitude: 35.6725, longitude: 139.7240),
            lineIds: ["metro_hanzomon", "metro_ginza", "toei_oedo"]
        ),
        TransitStation(
            id: "nagatacho",
            name: "永田町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6787, longitude: 139.7375),
            lineIds: ["metro_hanzomon"]
        ),
        TransitStation(
            id: "hanzomon",
            name: "半蔵門",
            coordinate: CLLocationCoordinate2D(latitude: 35.6850, longitude: 139.7445),
            lineIds: ["metro_hanzomon"]
        ),
        TransitStation(
            id: "kudanshita",
            name: "九段下",
            coordinate: CLLocationCoordinate2D(latitude: 35.6953, longitude: 139.7511),
            lineIds: ["metro_hanzomon", "toei_shinjuku"]
        ),
        TransitStation(
            id: "otemachi",
            name: "大手町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6862, longitude: 139.7637),
            lineIds: ["metro_hanzomon", "toei_mita"]
        ),
        TransitStation(
            id: "mitsukoshimae",
            name: "三越前",
            coordinate: CLLocationCoordinate2D(latitude: 35.6857, longitude: 139.7730),
            lineIds: ["metro_hanzomon", "metro_ginza"]
        ),
        TransitStation(
            id: "suitengumae",
            name: "水天宮前",
            coordinate: CLLocationCoordinate2D(latitude: 35.6840, longitude: 139.7864),
            lineIds: ["metro_hanzomon"]
        ),
        TransitStation(
            id: "sumiyoshi",
            name: "住吉",
            coordinate: CLLocationCoordinate2D(latitude: 35.6898, longitude: 139.8160),
            lineIds: ["metro_hanzomon"]
        ),
        TransitStation(
            id: "kinshicho",
            name: "錦糸町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6959, longitude: 139.8143),
            lineIds: ["metro_hanzomon"]
        ),
        TransitStation(
            id: "oshiage",
            name: "押上",
            coordinate: CLLocationCoordinate2D(latitude: 35.7108, longitude: 139.8132),
            lineIds: ["metro_hanzomon"]
        ),

        // 都営三田線（目黒・大手町・神保町は上で定義済み、または下で共有）
        TransitStation(
            id: "shirokanedai",
            name: "白金台",
            coordinate: CLLocationCoordinate2D(latitude: 35.6385, longitude: 139.7253),
            lineIds: ["toei_mita"]
        ),
        TransitStation(
            id: "shirokanetakanawa",
            name: "白金高輪",
            coordinate: CLLocationCoordinate2D(latitude: 35.6432, longitude: 139.7334),
            lineIds: ["toei_mita"]
        ),
        TransitStation(
            id: "mita",
            name: "三田",
            coordinate: CLLocationCoordinate2D(latitude: 35.6486, longitude: 139.7466),
            lineIds: ["toei_mita"]
        ),
        TransitStation(
            id: "shibakoen",
            name: "芝公園",
            coordinate: CLLocationCoordinate2D(latitude: 35.6529, longitude: 139.7514),
            lineIds: ["toei_mita"]
        ),
        TransitStation(
            id: "daimon",
            name: "大門",
            coordinate: CLLocationCoordinate2D(latitude: 35.6557, longitude: 139.7568),
            lineIds: ["toei_mita", "toei_oedo"]
        ),
        TransitStation(
            id: "hibiya",
            name: "日比谷",
            coordinate: CLLocationCoordinate2D(latitude: 35.6750, longitude: 139.7600),
            lineIds: ["toei_mita"]
        ),
        TransitStation(
            id: "jimbocho",
            name: "神保町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6959, longitude: 139.7577),
            lineIds: ["toei_mita", "toei_shinjuku"]
        ),
        TransitStation(
            id: "suidobashi",
            name: "水道橋",
            coordinate: CLLocationCoordinate2D(latitude: 35.7020, longitude: 139.7535),
            lineIds: ["toei_mita"]
        ),
        TransitStation(
            id: "kasuga",
            name: "春日",
            coordinate: CLLocationCoordinate2D(latitude: 35.7079, longitude: 139.7520),
            lineIds: ["toei_mita", "toei_oedo"]
        ),
        TransitStation(
            id: "sugamo",
            name: "巣鴨",
            coordinate: CLLocationCoordinate2D(latitude: 35.7334, longitude: 139.7394),
            lineIds: ["toei_mita", "jr_yamanote"]
        ),
        TransitStation(
            id: "nishitakashimadaira",
            name: "西高島平",
            coordinate: CLLocationCoordinate2D(latitude: 35.7928, longitude: 139.6361),
            lineIds: ["toei_mita"]
        ),

        // 都営新宿線（新宿・九段下・神保町は上で定義済み）
        TransitStation(
            id: "shinjukusanchome",
            name: "新宿三丁目",
            coordinate: CLLocationCoordinate2D(latitude: 35.6925, longitude: 139.7058),
            lineIds: ["toei_shinjuku", "metro_marunouchi", "metro_fukutoshin"]
        ),
        TransitStation(
            id: "akebonobashi",
            name: "曙橋",
            coordinate: CLLocationCoordinate2D(latitude: 35.6934, longitude: 139.7219),
            lineIds: ["toei_shinjuku"]
        ),
        TransitStation(
            id: "ichigaya",
            name: "市ヶ谷",
            coordinate: CLLocationCoordinate2D(latitude: 35.6916, longitude: 139.7356),
            lineIds: ["toei_shinjuku"]
        ),
        TransitStation(
            id: "iwamotocho",
            name: "岩本町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6944, longitude: 139.7754),
            lineIds: ["toei_shinjuku"]
        ),
        TransitStation(
            id: "bakuroyokoyama",
            name: "馬喰横山",
            coordinate: CLLocationCoordinate2D(latitude: 35.6917, longitude: 139.7834),
            lineIds: ["toei_shinjuku"]
        ),
        TransitStation(
            id: "motoyawata",
            name: "本八幡",
            coordinate: CLLocationCoordinate2D(latitude: 35.7268, longitude: 139.9313),
            lineIds: ["toei_shinjuku"]
        ),

        // JR中央線快速（東京・神田・新宿・立川は上で定義済み）
        TransitStation(
            id: "ochanomizu",
            name: "御茶ノ水",
            coordinate: CLLocationCoordinate2D(latitude: 35.6997, longitude: 139.7633),
            lineIds: ["jr_chuo_rapid"]
        ),
        TransitStation(
            id: "yotsuya",
            name: "四ツ谷",
            coordinate: CLLocationCoordinate2D(latitude: 35.6860, longitude: 139.7300),
            lineIds: ["jr_chuo_rapid"]
        ),
        TransitStation(
            id: "nakano",
            name: "中野",
            coordinate: CLLocationCoordinate2D(latitude: 35.7074, longitude: 139.6655),
            lineIds: ["jr_chuo_rapid"]
        ),
        TransitStation(
            id: "ogikubo",
            name: "荻窪",
            coordinate: CLLocationCoordinate2D(latitude: 35.7043, longitude: 139.6200),
            lineIds: ["jr_chuo_rapid"]
        ),
        TransitStation(
            id: "kichijoji",
            name: "吉祥寺",
            coordinate: CLLocationCoordinate2D(latitude: 35.7030, longitude: 139.5796),
            lineIds: ["jr_chuo_rapid"]
        ),
        TransitStation(
            id: "mitaka",
            name: "三鷹",
            coordinate: CLLocationCoordinate2D(latitude: 35.7026, longitude: 139.5607),
            lineIds: ["jr_chuo_rapid"]
        ),
        // 飯田橋（都営大江戸線 + 他路線）
        TransitStation(
            id: "iidabashi",
            name: "飯田橋",
            coordinate: CLLocationCoordinate2D(latitude: 35.7010, longitude: 139.7475),
            lineIds: ["toei_oedo"]
        ),

        // 都営大江戸線
        TransitStation(
            id: "tochomae",
            name: "都庁前",
            coordinate: CLLocationCoordinate2D(latitude: 35.6906, longitude: 139.6928),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "shinjukunishiguchi",
            name: "新宿西口",
            coordinate: CLLocationCoordinate2D(latitude: 35.6929, longitude: 139.6991),
            lineIds: ["toei_oedo"]
        ),
        // 東新宿 - metro_fukutoshin セクションで定義済み（lineIds に toei_oedo 追加済み）
        TransitStation(
            id: "wakamatsu_kawada",
            name: "若松河田",
            coordinate: CLLocationCoordinate2D(latitude: 35.6986, longitude: 139.7189),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "ushigome_yanagicho",
            name: "牛込柳町",
            coordinate: CLLocationCoordinate2D(latitude: 35.7003, longitude: 139.7270),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "ushigome_kagurazaka",
            name: "牛込神楽坂",
            coordinate: CLLocationCoordinate2D(latitude: 35.7019, longitude: 139.7367),
            lineIds: ["toei_oedo"]
        ),
        // 飯田橋 - 上で定義済み
        // 春日 - toei_mita セクションで定義済み（lineIds に toei_oedo 追加済み）
        TransitStation(
            id: "hongosanchome",
            name: "本郷三丁目",
            coordinate: CLLocationCoordinate2D(latitude: 35.7072, longitude: 139.7603),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "uenoOkachimachi",
            name: "上野御徒町",
            coordinate: CLLocationCoordinate2D(latitude: 35.7080, longitude: 139.7733),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "shinokachimachi",
            name: "新御徒町",
            coordinate: CLLocationCoordinate2D(latitude: 35.7073, longitude: 139.7818),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "kuramae",
            name: "蔵前",
            coordinate: CLLocationCoordinate2D(latitude: 35.7016, longitude: 139.7910),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "ryogoku",
            name: "両国",
            coordinate: CLLocationCoordinate2D(latitude: 35.6958, longitude: 139.7934),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "kiyosumishirakawa",
            name: "清澄白河",
            coordinate: CLLocationCoordinate2D(latitude: 35.6821, longitude: 139.7988),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "monzennakacho",
            name: "門前仲町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6726, longitude: 139.7950),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "tsukishima",
            name: "月島",
            coordinate: CLLocationCoordinate2D(latitude: 35.6648, longitude: 139.7843),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "kachidoki",
            name: "勝どき",
            coordinate: CLLocationCoordinate2D(latitude: 35.6597, longitude: 139.7767),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "tsukijishijo",
            name: "築地市場",
            coordinate: CLLocationCoordinate2D(latitude: 35.6616, longitude: 139.7674),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "shiodome",
            name: "汐留",
            coordinate: CLLocationCoordinate2D(latitude: 35.6604, longitude: 139.7620),
            lineIds: ["toei_oedo"]
        ),
        // 大門 - toei_mita セクションで定義済み（lineIds に toei_oedo 追加済み）
        TransitStation(
            id: "akabanebashi",
            name: "赤羽橋",
            coordinate: CLLocationCoordinate2D(latitude: 35.6535, longitude: 139.7450),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "azabujuban",
            name: "麻布十番",
            coordinate: CLLocationCoordinate2D(latitude: 35.6553, longitude: 139.7370),
            lineIds: ["toei_oedo"]
        ),
        // 六本木 - metro_hibiya セクションで定義済み（lineIds に toei_oedo 追加済み）
        // 青山一丁目 - metro_hanzomon セクションで定義済み（lineIds に toei_oedo 追加済み）
        TransitStation(
            id: "kokuritsukyogijo",
            name: "国立競技場",
            coordinate: CLLocationCoordinate2D(latitude: 35.6801, longitude: 139.7137),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "yoyogi",
            name: "代々木",
            coordinate: CLLocationCoordinate2D(latitude: 35.6832, longitude: 139.7020),
            lineIds: ["toei_oedo", "jr_yamanote"]
        ),
        // 新宿 - jr_yamanote セクションで定義済み（lineIds に toei_oedo 追加済み）
        // 都庁前 - 上で定義済み（ループ接続点）
        TransitStation(
            id: "nishishinjuku5",
            name: "西新宿五丁目",
            coordinate: CLLocationCoordinate2D(latitude: 35.6900, longitude: 139.6846),
            lineIds: ["toei_oedo"]
        ),
        TransitStation(
            id: "nakanosakaue",
            name: "中野坂上",
            coordinate: CLLocationCoordinate2D(latitude: 35.6970, longitude: 139.6765),
            lineIds: ["toei_oedo"]
        ),

        // 東京メトロ丸ノ内線
        TransitStation(
            id: "akasakamitsuke",
            name: "赤坂見附",
            coordinate: CLLocationCoordinate2D(latitude: 35.6782, longitude: 139.7357),
            lineIds: ["metro_marunouchi", "metro_ginza"]
        ),
        TransitStation(
            id: "kokkaigijido",
            name: "国会議事堂前",
            coordinate: CLLocationCoordinate2D(latitude: 35.6740, longitude: 139.7450),
            lineIds: ["metro_marunouchi"]
        ),
        TransitStation(
            id: "kasumigaseki",
            name: "霞ケ関",
            coordinate: CLLocationCoordinate2D(latitude: 35.6725, longitude: 139.7516),
            lineIds: ["metro_marunouchi", "metro_hibiya"]
        ),
        TransitStation(
            id: "ginza",
            name: "銀座",
            coordinate: CLLocationCoordinate2D(latitude: 35.6730, longitude: 139.7620),
            lineIds: ["metro_marunouchi", "metro_ginza", "metro_hibiya"]
        ),
        TransitStation(
            id: "korakuen",
            name: "後楽園",
            coordinate: CLLocationCoordinate2D(latitude: 35.7068, longitude: 139.7521),
            lineIds: ["metro_marunouchi"]
        ),

        // 東京メトロ銀座線（共有駅以外）
        TransitStation(
            id: "gaienmae",
            name: "外苑前",
            coordinate: CLLocationCoordinate2D(latitude: 35.6704, longitude: 139.7175),
            lineIds: ["metro_ginza"]
        ),
        TransitStation(
            id: "tameikesanno",
            name: "溜池山王",
            coordinate: CLLocationCoordinate2D(latitude: 35.6708, longitude: 139.7413),
            lineIds: ["metro_ginza"]
        ),
        TransitStation(
            id: "toranomon",
            name: "虎ノ門",
            coordinate: CLLocationCoordinate2D(latitude: 35.6700, longitude: 139.7490),
            lineIds: ["metro_ginza"]
        ),
        TransitStation(
            id: "nihombashi",
            name: "日本橋",
            coordinate: CLLocationCoordinate2D(latitude: 35.6820, longitude: 139.7740),
            lineIds: ["metro_ginza"]
        ),
        TransitStation(
            id: "asakusa",
            name: "浅草",
            coordinate: CLLocationCoordinate2D(latitude: 35.7115, longitude: 139.7967),
            lineIds: ["metro_ginza"]
        ),

        // 東京メトロ日比谷線（共有駅以外）
        TransitStation(
            id: "nakameguro",
            name: "中目黒",
            coordinate: CLLocationCoordinate2D(latitude: 35.6441, longitude: 139.6991),
            lineIds: ["metro_hibiya"]
        ),
        TransitStation(
            id: "hiroo",
            name: "広尾",
            coordinate: CLLocationCoordinate2D(latitude: 35.6512, longitude: 139.7225),
            lineIds: ["metro_hibiya"]
        ),
        TransitStation(
            id: "roppongi_hibiya",
            name: "六本木",
            coordinate: CLLocationCoordinate2D(latitude: 35.6633, longitude: 139.7328),
            lineIds: ["metro_hibiya", "toei_oedo"]
        ),
        TransitStation(
            id: "kamiyacho",
            name: "神谷町",
            coordinate: CLLocationCoordinate2D(latitude: 35.6630, longitude: 139.7460),
            lineIds: ["metro_hibiya"]
        ),
        TransitStation(
            id: "tsukiji",
            name: "築地",
            coordinate: CLLocationCoordinate2D(latitude: 35.6673, longitude: 139.7716),
            lineIds: ["metro_hibiya"]
        ),
        TransitStation(
            id: "kitasenju",
            name: "北千住",
            coordinate: CLLocationCoordinate2D(latitude: 35.7497, longitude: 139.8049),
            lineIds: ["metro_hibiya"]
        ),

        // 東京メトロ副都心線（共有駅以外）
        TransitStation(
            id: "meijijingumae",
            name: "明治神宮前",
            coordinate: CLLocationCoordinate2D(latitude: 35.6700, longitude: 139.7027),
            lineIds: ["metro_fukutoshin"]
        ),
        TransitStation(
            id: "kitasando",
            name: "北参道",
            coordinate: CLLocationCoordinate2D(latitude: 35.6790, longitude: 139.7050),
            lineIds: ["metro_fukutoshin"]
        ),
        TransitStation(
            id: "higashishinjuku",
            name: "東新宿",
            coordinate: CLLocationCoordinate2D(latitude: 35.6960, longitude: 139.7100),
            lineIds: ["metro_fukutoshin", "toei_oedo"]
        ),
    ]

    // MARK: - 路線データ

    static let lines: [TransitLine] = [
        TransitLine(
            id: "tokyu_dento",
            name: "東急田園都市線",
            company: "東急電鉄",
            color: "#00A54F",
            stationIds: [
                "shibuya", "ikejiriohashi", "sangenjaya", "komazawadaigaku",
                "sakurashinmachi", "yoga", "futakotamagawa", "futakoshinchi",
                "takatsu", "mizonokuchi", "kajigaya", "miyazakidai", "miyamaedaira", "saginuma", "tamaplaza", "azamino", "chuorinkan",
            ],
            avgIntervalMinutes: 2.0
        ),
        TransitLine(
            id: "tokyu_oimachi",
            name: "東急大井町線",
            company: "東急電鉄",
            color: "#F18C43",
            stationIds: [
                "oimachi", "hatanodai", "okusawa", "jiyugaoka",
                "futakotamagawa", "mizonokuchi",
            ],
            avgIntervalMinutes: 3.0
        ),
        TransitLine(
            id: "jr_nambu",
            name: "JR南武線",
            company: "JR東日本",
            color: "#FFD700",
            stationIds: [
                "kawasaki", "musashikosugi", "musashimizonokuchi",
                "noborito", "inadazutsumi", "fuchuhommachi", "tachikawa",
            ],
            avgIntervalMinutes: 3.0
        ),
        TransitLine(
            id: "jr_yamanote",
            name: "JR山手線",
            company: "JR東日本",
            color: "#9ACD32",
            stationIds: [
                "tokyo", "kanda", "akihabara", "okachimachi",
                "ueno", "uguisudani", "nippori", "nishinippori",
                "tabata", "komagome", "sugamo", "otsuka",
                "ikebukuro", "mejiro", "takadanobaba", "shinookubo",
                "shinjuku", "yoyogi", "harajuku", "shibuya",
                "ebisu", "meguro", "gotanda", "osaki",
                "shinagawa", "takanawagateway", "tamachi", "hamamatsucho",
                "shimbashi", "yurakucho",
            ],
            avgIntervalMinutes: 2.0,
            isLoop: true
        ),
        TransitLine(
            id: "metro_hanzomon",
            name: "東京メトロ半蔵門線",
            company: "東京メトロ",
            color: "#8F76D6",
            stationIds: [
                "shibuya", "omotesando", "aoyamaicchome", "nagatacho",
                "hanzomon", "kudanshita", "otemachi", "mitsukoshimae",
                "suitengumae", "sumiyoshi", "kinshicho", "oshiage",
            ],
            avgIntervalMinutes: 2.0
        ),
        TransitLine(
            id: "toei_mita",
            name: "都営三田線",
            company: "都営地下鉄",
            color: "#0079C2",
            stationIds: [
                "meguro", "shirokanedai", "shirokanetakanawa", "mita",
                "shibakoen", "daimon", "hibiya", "otemachi", "jimbocho",
                "suidobashi", "kasuga", "sugamo", "nishitakashimadaira",
            ],
            avgIntervalMinutes: 2.0
        ),
        TransitLine(
            id: "toei_shinjuku",
            name: "都営新宿線",
            company: "都営地下鉄",
            color: "#6CBB5A",
            stationIds: [
                "shinjuku", "shinjukusanchome", "akebonobashi", "ichigaya",
                "kudanshita", "jimbocho", "iwamotocho", "bakuroyokoyama",
                "motoyawata",
            ],
            avgIntervalMinutes: 2.0
        ),
        TransitLine(
            id: "jr_chuo_rapid",
            name: "JR中央線快速",
            company: "JR東日本",
            color: "#F15A22",
            stationIds: [
                "tokyo", "kanda", "ochanomizu", "yotsuya", "shinjuku",
                "nakano", "ogikubo", "kichijoji", "mitaka", "tachikawa",
            ],
            avgIntervalMinutes: 3.0
        ),
        TransitLine(
            id: "toei_oedo",
            name: "都営大江戸線",
            company: "都営地下鉄",
            color: "#B6007A",
            stationIds: [
                "tochomae", "shinjukunishiguchi", "higashishinjuku",
                "wakamatsu_kawada", "ushigome_yanagicho", "ushigome_kagurazaka",
                "iidabashi", "kasuga", "hongosanchome",
                "uenoOkachimachi", "shinokachimachi", "kuramae",
                "ryogoku", "kiyosumishirakawa", "monzennakacho",
                "tsukishima", "kachidoki", "tsukijishijo",
                "shiodome", "daimon", "akabanebashi",
                "azabujuban", "roppongi_hibiya", "aoyamaicchome",
                "kokuritsukyogijo", "yoyogi", "shinjuku",
                "tochomae", "nishishinjuku5", "nakanosakaue",
            ],
            avgIntervalMinutes: 2.0,
            isLoop: true
        ),
        TransitLine(
            id: "metro_marunouchi",
            name: "東京メトロ丸ノ内線",
            company: "東京メトロ",
            color: "#F62E36",
            stationIds: [
                "ogikubo", "shinjuku", "shinjukusanchome", "yotsuya",
                "akasakamitsuke", "kokkaigijido", "kasumigaseki",
                "ginza", "tokyo", "otemachi", "korakuen", "ikebukuro",
            ],
            avgIntervalMinutes: 2.0
        ),
        TransitLine(
            id: "metro_ginza",
            name: "東京メトロ銀座線",
            company: "東京メトロ",
            color: "#FF9500",
            stationIds: [
                "shibuya", "omotesando", "gaienmae", "aoyamaicchome",
                "akasakamitsuke", "tameikesanno", "toranomon", "shimbashi",
                "ginza", "nihombashi", "mitsukoshimae", "kanda", "ueno", "asakusa",
            ],
            avgIntervalMinutes: 2.0
        ),
        TransitLine(
            id: "metro_hibiya",
            name: "東京メトロ日比谷線",
            company: "東京メトロ",
            color: "#B5B5AC",
            stationIds: [
                "nakameguro", "ebisu", "hiroo", "roppongi_hibiya",
                "kamiyacho", "kasumigaseki", "hibiya", "ginza",
                "tsukiji", "akihabara", "ueno", "kitasenju",
            ],
            avgIntervalMinutes: 2.0
        ),
        TransitLine(
            id: "metro_fukutoshin",
            name: "東京メトロ副都心線",
            company: "東京メトロ",
            color: "#9C5E31",
            stationIds: [
                "shibuya", "meijijingumae", "kitasando",
                "shinjukusanchome", "higashishinjuku", "ikebukuro",
            ],
            avgIntervalMinutes: 2.0
        ),
    ]

    // MARK: - ルックアップヘルパー

    /// 駅IDで駅を検索
    static func station(byId id: String) -> TransitStation? {
        stations.first { $0.id == id }
    }

    /// 駅名で駅を検索
    static func station(byName name: String) -> TransitStation? {
        stations.first { $0.name == name }
    }

    /// 指定座標から最寄りの駅を検索
    /// - Parameters:
    ///   - coord: 検索の中心座標
    ///   - maxDistance: 最大検索距離（メートル）。デフォルト1000m
    /// - Returns: 最寄りの駅。見つからなければnil
    static func nearestStation(
        to coord: CLLocationCoordinate2D,
        maxDistance: Double = 1000
    ) -> TransitStation? {
        var bestStation: TransitStation?
        var bestDist = Double.infinity

        for s in stations {
            let dist = TransitRouteService.haversineDistance(
                from: coord, to: s.coordinate
            )
            if dist < bestDist && dist <= maxDistance {
                bestDist = dist
                bestStation = s
            }
        }
        return bestStation
    }

    /// 指定座標から近い順にN件の駅を返す
    /// - Parameters:
    ///   - coord: 検索の中心座標
    ///   - maxDistance: 最大検索距離（メートル）
    ///   - limit: 返す件数の上限
    /// - Returns: 近い順の駅リスト
    static func nearestStations(
        to coord: CLLocationCoordinate2D,
        maxDistance: Double = 2000,
        limit: Int = 5
    ) -> [TransitStation] {
        stations
            .map { ($0, TransitRouteService.haversineDistance(from: coord, to: $0.coordinate)) }
            .filter { $0.1 <= maxDistance }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    /// 指定駅が属する路線一覧
    static func lines(forStation stationId: String) -> [TransitLine] {
        lines.filter { $0.stationIds.contains(stationId) }
    }
}
