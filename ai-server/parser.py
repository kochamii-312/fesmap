"""レスポンスパーサーモジュール。

AIモデルの出力テキストから構造化JSONを抽出し、
バリデーションとアクション判定を行う。
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any

logger = logging.getLogger(__name__)

# ニーズフィールドの許容値定義
VALID_MOBILITY_TYPES = {"wheelchair", "stroller", "cane", "walk", "other"}
VALID_COMPANIONS = {"child", "elderly", "disability"}
VALID_AVOID_CONDITIONS = {"stairs", "slope", "crowd", "dark"}
VALID_PREFER_CONDITIONS = {"restroom", "rest_area", "covered"}

# 日本語値→enum値の正規化マッピング（部分一致対応）
MOBILITY_TYPE_ALIASES: dict[str, str] = {
    # wheelchair
    "車椅子": "wheelchair",
    "車いす": "wheelchair",
    "くるまいす": "wheelchair",
    "車イス": "wheelchair",
    "wheelchair": "wheelchair",
    "ウィールチェア": "wheelchair",
    "電動車椅子": "wheelchair",
    "電動車いす": "wheelchair",
    "手動車椅子": "wheelchair",
    "車椅子利用": "wheelchair",
    # stroller
    "ベビーカー": "stroller",
    "べびーかー": "stroller",
    "乳母車": "stroller",
    "バギー": "stroller",
    "stroller": "stroller",
    "ベビーバギー": "stroller",
    "チャイルドカート": "stroller",
    # cane
    "杖": "cane",
    "つえ": "cane",
    "ステッキ": "cane",
    "cane": "cane",
    "松葉杖": "other",
    "松葉づえ": "other",
    "白杖": "cane",
    "はくじょう": "cane",
    # walk
    "徒歩": "walk",
    "歩行": "walk",
    "歩き": "walk",
    "walk": "walk",
    "walking": "walk",
    "健脚": "walk",
    # other
    "その他": "other",
    "other": "other",
    "シニアカー": "other",
    "電動カート": "other",
    "歩行器": "other",
}

COMPANION_ALIASES: dict[str, str] = {
    "子供": "child",
    "子ども": "child",
    "こども": "child",
    "幼児": "child",
    "child": "child",
    "children": "child",
    "赤ちゃん": "child",
    "乳幼児": "child",
    "乳児": "child",
    "小さい子": "child",
    "小さな子": "child",
    "高齢者": "elderly",
    "お年寄り": "elderly",
    "シニア": "elderly",
    "elderly": "elderly",
    "年配": "elderly",
    "年寄り": "elderly",
    "おじいちゃん": "elderly",
    "おばあちゃん": "elderly",
    "祖父": "elderly",
    "祖母": "elderly",
    "高齢": "elderly",
    "障害者": "disability",
    "障がい者": "disability",
    "しょうがいしゃ": "disability",
    "disability": "disability",
    "障碍者": "disability",
    "身体障害": "disability",
    "視覚障害": "disability",
    "聴覚障害": "disability",
}

AVOID_CONDITION_ALIASES: dict[str, str] = {
    "階段": "stairs",
    "かいだん": "stairs",
    "stairs": "stairs",
    "段差": "stairs",
    "だんさ": "stairs",
    "ステップ": "stairs",
    "step": "stairs",
    "steps": "stairs",
    "坂": "slope",
    "坂道": "slope",
    "傾斜": "slope",
    "slope": "slope",
    "急坂": "slope",
    "きつい坂": "slope",
    "上り坂": "slope",
    "下り坂": "slope",
    "勾配": "slope",
    "混雑": "crowd",
    "人混み": "crowd",
    "人ごみ": "crowd",
    "crowd": "crowd",
    "crowded": "crowd",
    "込み合": "crowd",
    "満員": "crowd",
    "暗い": "dark",
    "暗所": "dark",
    "暗がり": "dark",
    "dark": "dark",
    "夜道": "dark",
    "街灯がない": "dark",
    "照明がない": "dark",
}

PREFER_CONDITION_ALIASES: dict[str, str] = {
    "トイレ": "restroom",
    "お手洗い": "restroom",
    "化粧室": "restroom",
    "restroom": "restroom",
    "おむつ替え": "restroom",
    "多目的トイレ": "restroom",
    "バリアフリートイレ": "restroom",
    "toilet": "restroom",
    "休憩所": "rest_area",
    "休憩スポット": "rest_area",
    "ベンチ": "rest_area",
    "rest_area": "rest_area",
    "休憩": "rest_area",
    "座れる場所": "rest_area",
    "座れるところ": "rest_area",
    "腰掛け": "rest_area",
    "屋根": "covered",
    "屋根付き": "covered",
    "covered": "covered",
    "雨よけ": "covered",
    "アーケード": "covered",
    "屋内": "covered",
    "室内": "covered",
    "雨でも": "covered",
}

# 目的地を示すキーワードパターン（会話履歴から検出用）
_DESTINATION_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"(?:に|へ|まで)\s*(?:行き|いき|向か|むか)", re.UNICODE),
    re.compile(r"(?:目的地|行き先|行先|destination)", re.IGNORECASE | re.UNICODE),
    re.compile(
        r"(?:駅|公園|病院|空港|ホテル|レストラン|店|ショッピング|モール|美術館|博物館|神社|寺)",
        re.UNICODE,
    ),
    re.compile(r"(?:ルート|道順|経路|route)", re.IGNORECASE | re.UNICODE),
]

# ユーザーの意図検出パターン
_INTENT_ROUTE_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"(?:ルート|道順|経路|行き方|route)", re.IGNORECASE | re.UNICODE),
    re.compile(
        r"(?:に|へ|まで)\s*(?:行き|いき|向か|むか|着き|つき)", re.UNICODE
    ),
    re.compile(r"(?:案内|ナビ|navigate)", re.IGNORECASE | re.UNICODE),
]

_INTENT_SPOT_PATTERNS: list[re.Pattern[str]] = [
    re.compile(
        r"(?:スポット|場所|施設|おすすめ|探し|さがし|spot)", re.IGNORECASE | re.UNICODE
    ),
    re.compile(r"(?:近く|周辺|付近|nearby)", re.IGNORECASE | re.UNICODE),
    re.compile(r"(?:どこ|どんな|ありますか)", re.UNICODE),
]

# ニーズ抽出に必要な全フィールド
ALL_NEEDS_FIELDS = {
    "mobility_type",
    "companions",
    "max_distance_meters",
    "avoid_conditions",
    "prefer_conditions",
}


def _try_parse_dict(text: str) -> dict[str, Any] | None:
    """文字列をJSONパースし、dictなら返す。それ以外はNone。

    Args:
        text: パース対象の文字列。

    Returns:
        パース成功しdictの場合はその値、それ以外はNone。
    """
    try:
        result = json.loads(text)
        if isinstance(result, dict):
            return result
    except (json.JSONDecodeError, ValueError, TypeError):
        pass
    return None


def _close_open_strings(text: str) -> str:
    """未閉じの文字列リテラルを検出して閉じる。

    Args:
        text: 対象のJSON文字列。

    Returns:
        未閉じの文字列リテラルを閉じた文字列。
    """
    in_string = False
    escape_next = False
    for char in text:
        if escape_next:
            escape_next = False
            continue
        if char == "\\":
            escape_next = True
            continue
        if char == '"':
            in_string = not in_string
    if in_string:
        return text + '"'
    return text


def _close_brackets(text: str) -> str:
    """不足している閉じ括弧を補完する。

    文字列リテラル内の括弧は無視してカウントする。

    Args:
        text: 対象のJSON文字列。

    Returns:
        閉じ括弧を補完した文字列。
    """
    open_braces = 0
    open_brackets = 0
    in_string = False
    escape_next = False

    for char in text:
        if escape_next:
            escape_next = False
            continue
        if char == "\\":
            if in_string:
                escape_next = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if char == "{":
            open_braces += 1
        elif char == "}":
            open_braces -= 1
        elif char == "[":
            open_brackets += 1
        elif char == "]":
            open_brackets -= 1

    suffix = ""
    if open_brackets > 0:
        suffix += "]" * open_brackets
    if open_braces > 0:
        suffix += "}" * open_braces

    if suffix:
        # 閉じ括弧追加前に末尾のカンマを除去
        trimmed = text.rstrip()
        if trimmed.endswith(","):
            trimmed = trimmed[:-1]
        return trimmed + suffix
    return text


def _attempt_json_repair(text: str) -> dict[str, Any] | None:
    """不完全なJSONの自動修復を試みる。

    複数の修復戦略を段階的に適用する:
    1. 末尾カンマの除去
    2. シングルクォートのダブルクォート変換
    3. 未閉じ文字列リテラルの補完
    4. 閉じ括弧の補完（文字列リテラル内を正しく無視）
    5. キー名のクォート補完（JavaScriptスタイルのJSON対応）
    6. 上記の組み合わせによる多段修復

    Args:
        text: 修復対象のJSON文字列。

    Returns:
        修復・パースに成功した場合はdict、失敗した場合はNone。
    """
    if not isinstance(text, str) or not text.strip():
        return None

    candidates: list[str] = []

    # 基本クリーニング: 末尾カンマの除去
    cleaned = re.sub(r",\s*([}\]])", r"\1", text.strip())
    candidates.append(cleaned)

    # シングルクォートをダブルクォートに変換
    single_to_double = re.sub(
        r",\s*([}\]])", r"\1", text.strip().replace("'", '"')
    )
    candidates.append(single_to_double)

    # キー名にクォートがないJavaScriptスタイルの修復
    js_style = re.sub(
        r"(?<=[{,])\s*(\w+)\s*:",
        r' "\1":',
        text.strip(),
    )
    js_cleaned = re.sub(r",\s*([}\]])", r"\1", js_style)
    candidates.append(js_cleaned)

    # 各候補に対して段階的修復を試行
    for base in list(candidates):
        # まずそのままパースを試みる
        parsed = _try_parse_dict(base)
        if parsed is not None:
            return parsed

        # 未閉じ文字列リテラルの補完
        string_repaired = _close_open_strings(base)

        # 閉じ括弧の補完（文字列リテラル内の括弧を正しく無視）
        bracket_repaired = _close_brackets(string_repaired)

        # 修復後にパース試行
        if bracket_repaired != base:
            # 末尾カンマ再除去
            final = re.sub(r",\s*([}\]])", r"\1", bracket_repaired)
            parsed = _try_parse_dict(final)
            if parsed is not None:
                return parsed

    return None


def _extract_fragment_fields(text: str) -> dict[str, Any]:
    """部分的なJSONフラグメントからフィールドを正規表現で抽出する。

    完全なJSONパースに失敗した場合のフォールバックとして、
    キー・バリューペアを個別に正規表現で抽出する。
    シングルクォート・ダブルクォート両方、およびクォートなしキー名に対応。
    null値・空文字列は安全にスキップする。

    Args:
        text: 抽出対象のテキスト。

    Returns:
        抽出できたフィールドを含むレスポンスdict。抽出ゼロの場合は空dict。
    """
    if not isinstance(text, str) or not text.strip():
        return {}

    needs: dict[str, Any] = {}
    confidence: float = 0.0

    # クォート有無両対応の文字列値抽出パターン
    _q = r"""["\']?"""  # キー名のクォート（任意）
    _sv = r"""["\']([^"\']+)["\']"""  # 文字列値（空でないもの）

    # mobility_type の抽出
    mob_match = re.search(rf'{_q}mobility_type{_q}\s*:\s*{_sv}', text)
    if mob_match:
        val = mob_match.group(1).strip()
        if val and val != "null":
            needs["mobility_type"] = val

    # companions の抽出（未閉じリストにも部分対応）
    comp_match = re.search(
        rf'{_q}companions{_q}\s*:\s*\[([^\]]*)\]?', text
    )
    if comp_match:
        items = re.findall(r"""["\']([^"\']+)["\']""", comp_match.group(1))
        items = [i.strip() for i in items if i.strip() and i.strip() != "null"]
        if items:
            needs["companions"] = items

    # max_distance_meters の抽出（文字列値・数値値両対応）
    dist_match = re.search(
        rf'{_q}max_distance_meters{_q}\s*:\s*'
        r'(?:["\']?\s*(\d+(?:\.\d+)?)\s*(?:m|km|メートル|キロ)?["\']?'
        r'|(\d+(?:\.\d+)?))',
        text,
    )
    if dist_match:
        raw_dist = dist_match.group(1) or dist_match.group(2)
        if raw_dist:
            needs["max_distance_meters"] = float(raw_dist)

    # avoid_conditions の抽出（未閉じリストにも部分対応）
    avoid_match = re.search(
        rf'{_q}avoid_conditions{_q}\s*:\s*\[([^\]]*)\]?', text
    )
    if avoid_match:
        items = re.findall(r"""["\']([^"\']+)["\']""", avoid_match.group(1))
        items = [i.strip() for i in items if i.strip() and i.strip() != "null"]
        if items:
            needs["avoid_conditions"] = items

    # prefer_conditions の抽出（未閉じリストにも部分対応）
    prefer_match = re.search(
        rf'{_q}prefer_conditions{_q}\s*:\s*\[([^\]]*)\]?', text
    )
    if prefer_match:
        items = re.findall(r"""["\']([^"\']+)["\']""", prefer_match.group(1))
        items = [i.strip() for i in items if i.strip() and i.strip() != "null"]
        if items:
            needs["prefer_conditions"] = items

    # confidence の抽出
    conf_match = re.search(
        rf'{_q}confidence{_q}\s*:\s*(\d+(?:\.\d+)?)', text
    )
    if conf_match:
        confidence = float(conf_match.group(1))

    # destination の抽出
    dest_match = re.search(rf'{_q}destination{_q}\s*:\s*{_sv}', text)
    destination: str | None = None
    if dest_match:
        val = dest_match.group(1).strip()
        if val and val != "null":
            destination = val

    # action の抽出
    action_match = re.search(rf'{_q}action{_q}\s*:\s*{_sv}', text)
    action: str | None = None
    if action_match:
        val = action_match.group(1).strip()
        if val and val != "null":
            action = val

    # message の抽出
    msg_match = re.search(rf'{_q}message{_q}\s*:\s*{_sv}', text)
    message: str | None = None
    if msg_match:
        val = msg_match.group(1).strip()
        if val and val != "null":
            message = val

    if not needs and not destination and not action:
        return {}

    result: dict[str, Any] = {"needs": needs, "confidence": confidence}
    if destination:
        result["destination"] = destination
    if action:
        result["action"] = action
    if message:
        result["message"] = message
    result["missing_fields"] = []
    return result


def _sanitize_parsed_result(data: dict[str, Any]) -> dict[str, Any]:
    """パース済みdictの値をサニタイズする。

    null値、空文字列、unexpected型の値を安全に処理し、
    下流のバリデーションに渡せる状態にする。

    Args:
        data: パース済みのdict。

    Returns:
        サニタイズ済みのdict。
    """
    sanitized: dict[str, Any] = {}
    for key, value in data.items():
        # null値はスキップ
        if value is None:
            continue
        # 空文字列はスキップ（数値0やFalseは残す）
        if isinstance(value, str) and not value.strip():
            continue
        # ネストされたdictも再帰的にサニタイズ
        if isinstance(value, dict):
            sanitized_child = _sanitize_parsed_result(value)
            if sanitized_child:
                sanitized[key] = sanitized_child
        # リストの場合はnull・空文字列を除外
        elif isinstance(value, list):
            cleaned_list = [
                item
                for item in value
                if item is not None
                and not (isinstance(item, str) and not item.strip())
            ]
            # 空リストも保持（missing_fields等で意味を持つ場合がある）
            sanitized[key] = cleaned_list
        else:
            sanitized[key] = value
    return sanitized


def parse_json_response(text: str) -> dict[str, Any]:
    """テキストからJSON部分を抽出してパースする。

    以下の順序で試行:
    1. 入力のエッジケースチェック（None、空文字列、非文字列型）
    2. テキスト全体をJSONとしてパース
    3. ``json ... `` ブロックを探す（複数ブロック対応、修復込み）
    4. 最も外側の { ... } を探す（文字列リテラル内の括弧を正しく無視）
    5. 閉じ括弧不足の不完全JSONを自動修復
    6. 部分的なフラグメントから正規表現でフィールドを抽出
    7. すべて失敗した場合はデフォルト値を返す

    Args:
        text: パース対象のテキスト。None や非文字列型にも対応。

    Returns:
        抽出されたJSON辞書。パース失敗時はフォールバックレスポンス。
    """
    # エッジケース: None、空文字列、非文字列型の処理
    if not isinstance(text, str) or not text.strip():
        logger.warning("空または不正な入力。デフォルト値を返します。")
        return _fallback_response()

    stripped = text.strip()

    # 1. テキスト全体をパース
    parsed = _try_parse_dict(stripped)
    if parsed is not None:
        return _sanitize_parsed_result(parsed)

    # 2. ```json ... ``` ブロックを探す（複数ブロックにも対応）
    code_blocks = re.findall(
        r"```(?:json)?\s*(\{.*?\})\s*```", stripped, re.DOTALL
    )
    for block in code_blocks:
        parsed = _try_parse_dict(block)
        if parsed is not None:
            return _sanitize_parsed_result(parsed)
        # コードブロック内のJSON修復を試みる
        repaired = _attempt_json_repair(block)
        if repaired is not None:
            logger.info("コードブロック内の不完全なJSONを自動修復しました。")
            return _sanitize_parsed_result(repaired)

    # 3. 最も外側の { ... } を探す（文字列リテラル内の括弧を正しく無視）
    brace_start = stripped.find("{")
    if brace_start != -1:
        depth = 0
        in_string = False
        escape_next = False
        found_end = False

        for i in range(brace_start, len(stripped)):
            char = stripped[i]
            if escape_next:
                escape_next = False
                continue
            if char == "\\":
                if in_string:
                    escape_next = True
                continue
            if char == '"':
                in_string = not in_string
                continue
            if in_string:
                continue
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    candidate = stripped[brace_start : i + 1]
                    parsed = _try_parse_dict(candidate)
                    if parsed is not None:
                        return _sanitize_parsed_result(parsed)
                    # 抽出した部分の修復を試みる
                    repaired = _attempt_json_repair(candidate)
                    if repaired is not None:
                        logger.info("抽出JSONの自動修復に成功しました。")
                        return _sanitize_parsed_result(repaired)
                    found_end = True
                    break

        # 4. 閉じ括弧が見つからなかった場合（不完全なJSON）、修復を試みる
        if not found_end:
            incomplete = stripped[brace_start:]
            repaired = _attempt_json_repair(incomplete)
            if repaired is not None:
                logger.info("不完全なJSONを自動修復しました。")
                return _sanitize_parsed_result(repaired)

    # 5. 部分的なフラグメントからフィールドを抽出
    fragment = _extract_fragment_fields(stripped)
    if fragment:
        logger.info("JSONフラグメントからフィールドを部分抽出しました。")
        return _sanitize_parsed_result(fragment)

    # 6. パースできない場合はデフォルトを返す
    logger.warning(
        "JSON抽出失敗。デフォルト値を返します。入力テキスト: %s", stripped[:200]
    )
    return _fallback_response()


def _fallback_response() -> dict[str, Any]:
    """JSON抽出失敗時のフォールバックレスポンス。"""
    return {
        "needs": {},
        "confidence": 0.0,
        "missing_fields": list(ALL_NEEDS_FIELDS),
    }


def _normalize_value(raw: str, alias_map: dict[str, str]) -> str | None:
    """エイリアスマップを使って値を正規化する。

    完全一致を優先し、見つからなければ部分一致で推測する。
    部分一致では最も長いエイリアスを優先して精度を高める。

    Args:
        raw: 正規化対象の生の値文字列。
        alias_map: エイリアス→enum値のマッピング辞書。

    Returns:
        正規化されたenum値。一致しない場合はNone。
    """
    if not isinstance(raw, str) or not raw.strip():
        return None

    stripped = raw.strip().lower()

    # 完全一致チェック
    for alias, canonical in alias_map.items():
        if stripped == alias.lower():
            return canonical

    # 部分一致チェック（最も長いエイリアス一致を優先して精度向上）
    best_match: str | None = None
    best_match_len: int = 0
    for alias, canonical in alias_map.items():
        alias_lower = alias.lower()
        if alias_lower in stripped or stripped in alias_lower:
            if len(alias_lower) > best_match_len:
                best_match = canonical
                best_match_len = len(alias_lower)

    return best_match


def _normalize_list_values(
    raw_list: list[Any], alias_map: dict[str, str], valid_set: set[str]
) -> list[str]:
    """リスト値を正規化し、有効な値のみ返す。

    null値、空文字列、非文字列型を安全にスキップし、
    重複を除去した正規化済みリストを返す。

    Args:
        raw_list: 正規化対象の生のリスト。
        alias_map: エイリアス→enum値のマッピング辞書。
        valid_set: 有効なenum値のセット。

    Returns:
        正規化済みのユニークな値リスト。
    """
    result: list[str] = []
    seen: set[str] = set()
    for item in raw_list:
        # null値をスキップ
        if item is None:
            continue
        # 非文字列型は文字列化を試みる
        if not isinstance(item, str):
            try:
                item = str(item)
            except (TypeError, ValueError):
                continue
        # 空文字列をスキップ
        if not item.strip():
            continue
        # まずそのままvalid_setに含まれるかチェック
        if item in valid_set:
            normalized: str | None = item
        else:
            normalized = _normalize_value(item, alias_map)
        if normalized and normalized in valid_set and normalized not in seen:
            result.append(normalized)
            seen.add(normalized)
    return result


def _parse_distance(value: Any) -> float | None:
    """距離値をパースしてメートル単位のfloatに変換する。

    数値型はそのまま返し、文字列の場合は「500m」「1.5km」「2キロ」等の
    表記を解釈してメートル値に変換する。

    Args:
        value: パース対象の値（数値 or 文字列）。

    Returns:
        メートル単位の距離。パース不可の場合はNone。
    """
    if isinstance(value, (int, float)):
        return float(value)

    if not isinstance(value, str):
        return None

    stripped = value.strip()

    # 「km」「キロ」「キロメートル」表記
    km_match = re.match(
        r"^(\d+(?:\.\d+)?)\s*(?:km|キロメートル|キロ)", stripped, re.IGNORECASE
    )
    if km_match:
        return float(km_match.group(1)) * 1000

    # 「m」「メートル」表記
    m_match = re.match(
        r"^(\d+(?:\.\d+)?)\s*(?:m|メートル)", stripped, re.IGNORECASE
    )
    if m_match:
        return float(m_match.group(1))

    # 数値のみ（メートルとみなす）
    try:
        return float(stripped)
    except ValueError:
        return None


def validate_extracted_needs(needs: dict[str, Any]) -> dict[str, Any]:
    """抽出されたニーズをバリデーション・正規化し、不正な値を除去する。

    日本語表記やひらがな表記、英語表記のゆらぎを吸収して
    UserProfileの部分型として有効な値のみを残す。
    null値、空文字列、unexpected型は安全に除外する。

    Args:
        needs: AIモデルが抽出した生のニーズ辞書。

    Returns:
        バリデーション・正規化済みのニーズ辞書。
    """
    # エッジケース: needsがNoneまたはdict以外の場合
    if not isinstance(needs, dict):
        logger.warning("ニーズがdict型ではありません: %s", type(needs).__name__)
        return {}

    validated: dict[str, Any] = {}

    # mobility_type（正規化対応）
    if "mobility_type" in needs:
        raw_mobility = needs["mobility_type"]
        if isinstance(raw_mobility, str) and raw_mobility.strip():
            if raw_mobility in VALID_MOBILITY_TYPES:
                validated["mobility_type"] = raw_mobility
            else:
                normalized = _normalize_value(raw_mobility, MOBILITY_TYPE_ALIASES)
                if normalized and normalized in VALID_MOBILITY_TYPES:
                    validated["mobility_type"] = normalized
                else:
                    logger.debug(
                        "未知のmobility_typeを検出: %s", raw_mobility
                    )

    # companions（正規化対応、文字列→リスト変換にも対応）
    if "companions" in needs:
        raw_companions = needs["companions"]
        if isinstance(raw_companions, str) and raw_companions.strip():
            raw_companions = [raw_companions]
        if isinstance(raw_companions, list):
            valid_companions = _normalize_list_values(
                raw_companions, COMPANION_ALIASES, VALID_COMPANIONS
            )
            if valid_companions:
                validated["companions"] = valid_companions

    # max_distance_meters（文字列表記「500m」「1.5km」等のパースにも対応）
    if "max_distance_meters" in needs:
        dist = _parse_distance(needs["max_distance_meters"])
        if dist is not None and 0 < dist <= 100000:  # 0m超〜100kmまで
            validated["max_distance_meters"] = dist

    # avoid_conditions（正規化対応、文字列→リスト変換にも対応）
    if "avoid_conditions" in needs:
        raw_avoids = needs["avoid_conditions"]
        if isinstance(raw_avoids, str) and raw_avoids.strip():
            raw_avoids = [raw_avoids]
        if isinstance(raw_avoids, list):
            valid_avoids = _normalize_list_values(
                raw_avoids, AVOID_CONDITION_ALIASES, VALID_AVOID_CONDITIONS
            )
            if valid_avoids:
                validated["avoid_conditions"] = valid_avoids

    # prefer_conditions（正規化対応、文字列→リスト変換にも対応）
    if "prefer_conditions" in needs:
        raw_prefers = needs["prefer_conditions"]
        if isinstance(raw_prefers, str) and raw_prefers.strip():
            raw_prefers = [raw_prefers]
        if isinstance(raw_prefers, list):
            valid_prefers = _normalize_list_values(
                raw_prefers,
                PREFER_CONDITION_ALIASES,
                VALID_PREFER_CONDITIONS,
            )
            if valid_prefers:
                validated["prefer_conditions"] = valid_prefers

    return validated


def determine_missing_fields(needs: dict[str, Any]) -> list[str]:
    """ニーズデータから不足しているフィールドを特定する。

    Args:
        needs: バリデーション済みニーズ辞書。

    Returns:
        不足しているフィールド名のリスト。
    """
    if not isinstance(needs, dict):
        return list(ALL_NEEDS_FIELDS)

    missing: list[str] = []
    for field_name in ALL_NEEDS_FIELDS:
        value = needs.get(field_name)
        if value is None or (isinstance(value, list) and len(value) == 0):
            missing.append(field_name)
        elif isinstance(value, str) and not value.strip():
            missing.append(field_name)
    return missing


def _detect_destination_in_messages(messages: list[dict[str, str]]) -> bool:
    """会話履歴から目的地情報の有無を検出する。

    Args:
        messages: 会話履歴メッセージのリスト。

    Returns:
        目的地に関する言及が見つかった場合True。
    """
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content", "")
        if not isinstance(content, str):
            continue
        for pattern in _DESTINATION_PATTERNS:
            if pattern.search(content):
                return True
    return False


def _detect_destination_in_parsed(
    parsed_data: dict[str, Any] | None,
) -> bool:
    """パース済みレスポンスからdestination情報の有無を検出する。

    Args:
        parsed_data: パース済みのレスポンスデータ。

    Returns:
        有効なdestinationが含まれている場合True。
    """
    if not isinstance(parsed_data, dict):
        return False
    dest = parsed_data.get("destination")
    return isinstance(dest, str) and bool(dest.strip())


def _detect_user_intent(
    messages: list[dict[str, str]],
) -> str:
    """会話履歴からユーザーの意図を推測する。

    最新のメッセージほど重みを高くして意図を判定する。

    Args:
        messages: 会話履歴メッセージのリスト。

    Returns:
        推測された意図: "route", "spot", "consult" のいずれか。
    """
    route_score: float = 0.0
    spot_score: float = 0.0

    # ユーザーメッセージのみを抽出
    user_messages: list[str] = []
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get("role") != "user":
            continue
        content = msg.get("content", "")
        if isinstance(content, str):
            user_messages.append(content)

    total = len(user_messages)
    for idx, content in enumerate(user_messages):
        # 最新メッセージほど高い重み（最新=1.5, 最古=1.0）
        if total > 1:
            weight = 1.0 + 0.5 * (idx / (total - 1))
        else:
            weight = 1.0

        for pattern in _INTENT_ROUTE_PATTERNS:
            if pattern.search(content):
                route_score += weight
        for pattern in _INTENT_SPOT_PATTERNS:
            if pattern.search(content):
                spot_score += weight

    if route_score > spot_score:
        return "route"
    elif spot_score > route_score:
        return "spot"
    return "consult"


def _adjust_confidence_by_history(
    confidence: float, messages: list[dict[str, str]]
) -> float:
    """会話履歴の長さに応じてconfidenceを補正する。

    会話ターン数が多いほど情報収集が進んでいるため、
    confidenceを微増させる。ただし上限1.0。

    Args:
        confidence: 元のconfidence値。
        messages: 会話履歴メッセージのリスト。

    Returns:
        補正後のconfidence値（0.0〜1.0）。
    """
    # confidenceの型安全性
    try:
        confidence = float(confidence)
    except (TypeError, ValueError):
        confidence = 0.0
    confidence = max(0.0, min(confidence, 1.0))

    # ユーザーメッセージ数をターン数として算出
    user_turns = sum(
        1
        for m in messages
        if isinstance(m, dict) and m.get("role") == "user"
    )

    # 3ターン以上で補正開始、1ターンあたり+0.03、最大+0.15
    if user_turns >= 3:
        bonus = min((user_turns - 2) * 0.03, 0.15)
        return min(confidence + bonus, 1.0)
    return confidence


def determine_action(
    needs: dict[str, Any] | None,
    confidence: float,
    missing_fields: list[str],
    messages: list[dict[str, str]] | None = None,
    parsed_response: dict[str, Any] | None = None,
) -> tuple[str, str]:
    """抽出結果と会話コンテキストから次のアクションを判定する。

    判定ロジック:
    1. 会話履歴からの補正情報を収集（目的地有無、ユーザー意図、ターン数補正）
    2. パース済みレスポンスからもdestination情報を検出
    3. 抽出済みフィールド数によるconfidence補正（3フィールド以上で微増）
    4. 段階的なconfidence閾値で判定:
       - destination情報がある場合はルート検索の閾値を緩和
       - confidence >= 0.65 + mobility確定 + 目的地あり → search_route
       - confidence >= 0.75 + mobility確定 + 目的地あり + 不足1以下 → search_route
       - confidence >= 0.7 + mobility確定 + 不足1以下 → search_route
       - ルート意図 + confidence >= 0.5 + mobility確定 + 目的地あり → search_route
       - confidence >= 0.45 + mobility確定 → show_spots
       - スポット意図 + confidence >= 0.4 + mobility確定 → show_spots
       - スポット意図 + confidence >= 0.3 + 抽出済み2以上 → show_spots
       - それ以外 → ask_more

    Args:
        needs: バリデーション済みニーズ辞書。
        confidence: AIモデルが出力したconfidence値。
        missing_fields: 不足フィールドのリスト。
        messages: 会話履歴（オプション、判定精度向上に使用）。
        parsed_response: パース済みレスポンス（オプション、destination検出用）。

    Returns:
        (action, reason) のタプル。actionは "search_route", "show_spots",
        "ask_more" のいずれか。reasonはアクション選択理由の説明文。
    """
    # エッジケース: needsの型チェック
    if needs is None or not isinstance(needs, dict) or not needs:
        return ("ask_more", "ニーズ情報が未抽出のため、追加のヒアリングが必要です。")

    msgs: list[dict[str, str]] = messages if isinstance(messages, list) else []

    # 会話履歴ベースの補正
    adjusted_confidence = _adjust_confidence_by_history(confidence, msgs)
    has_destination_in_msgs = _detect_destination_in_messages(msgs)
    has_destination_in_response = _detect_destination_in_parsed(parsed_response)
    has_destination = has_destination_in_msgs or has_destination_in_response
    user_intent = _detect_user_intent(msgs)

    has_mobility = bool(
        needs.get("mobility_type")
        and isinstance(needs["mobility_type"], str)
        and needs["mobility_type"].strip()
    )
    n_missing = len(missing_fields) if isinstance(missing_fields, list) else 0

    # 抽出済みフィールド数による補正（情報が多いほど信頼度を上げる）
    n_filled = len(ALL_NEEDS_FIELDS) - n_missing
    if n_filled >= 3:
        field_bonus = min((n_filled - 2) * 0.02, 0.06)
        adjusted_confidence = min(adjusted_confidence + field_bonus, 1.0)

    # 判定理由を構築するための情報収集
    reason_parts: list[str] = []
    reason_parts.append(f"confidence={adjusted_confidence:.2f}")
    if adjusted_confidence != confidence:
        reason_parts.append(f"(元値{confidence:.2f}から会話長+フィールド数で補正)")
    reason_parts.append(f"mobility={'あり' if has_mobility else 'なし'}")
    reason_parts.append(f"不足フィールド={n_missing}")
    reason_parts.append(f"抽出済み={n_filled}/{len(ALL_NEEDS_FIELDS)}")
    if has_destination:
        reason_parts.append("目的地言及あり")
        if has_destination_in_response:
            reason_parts.append("(レスポンスに目的地含む)")
    reason_parts.append(f"意図={user_intent}")

    # 判定ロジック（段階的閾値）
    # 目的地がある場合は閾値を緩和してルート検索を積極提案
    if (
        adjusted_confidence >= 0.75
        and has_mobility
        and has_destination
        and n_missing <= 1
    ):
        action = "search_route"
        reason_parts.append("→ 高信頼度+目的地あり: ルート検索を提案")
    elif adjusted_confidence >= 0.65 and has_mobility and has_destination:
        action = "search_route"
        reason_parts.append("→ 目的地あり+十分な信頼度: ルート検索を提案")
    elif adjusted_confidence >= 0.7 and has_mobility and n_missing <= 1:
        action = "search_route"
        reason_parts.append("→ 十分な情報あり: ルート検索を提案")
    elif (
        user_intent == "route"
        and adjusted_confidence >= 0.5
        and has_mobility
        and has_destination
    ):
        # ユーザーが明示的にルートを求めている場合は閾値を大きく緩和
        action = "search_route"
        reason_parts.append("→ ルート検索意図+目的地あり: 閾値緩和でルート検索を提案")
    elif adjusted_confidence >= 0.45 and has_mobility:
        action = "show_spots"
        reason_parts.append("→ 中程度の信頼度: スポット提案を提案")
    elif user_intent == "spot" and adjusted_confidence >= 0.4 and has_mobility:
        action = "show_spots"
        reason_parts.append("→ スポット探し意図を検出: スポット提案を提案")
    elif (
        user_intent == "spot"
        and adjusted_confidence >= 0.3
        and n_filled >= 2
    ):
        # スポット探し意図で最低限の情報がある場合
        action = "show_spots"
        reason_parts.append("→ スポット探し意図+部分情報あり: スポット提案を提案")
    else:
        action = "ask_more"
        if not has_mobility:
            reason_parts.append("→ 移動手段が未確定: 追加ヒアリング")
        elif n_missing >= 3:
            reason_parts.append("→ 不足フィールドが多い: 追加ヒアリング")
        else:
            reason_parts.append("→ 信頼度不足: 追加ヒアリング")

    reason = ", ".join(reason_parts)
    return (action, reason)
