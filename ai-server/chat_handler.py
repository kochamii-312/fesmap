
import os
import random
from typing import List, Optional, Dict, Any

import requests
from pydantic import BaseModel, Field

# --- Pydantic Models for Request and Response ---

class ChatRequest(BaseModel):
    """Request model for the /chat endpoint."""
    message: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None

class Spot(BaseModel):
    """Response model for a single recommended spot."""
    id: str
    name: str
    reason: str
    latitude: float
    longitude: float

class ShowOnMapAction(BaseModel):
    """Action model for showing spots on the map."""
    type: str = "SHOW_ON_MAP"
    spot_ids: List[str]

class ChatResponse(BaseModel):
    """Response model for the /chat endpoint."""
    assistant_message: str
    recommended_conditions: List[str] = []
    spots: List[Spot] = []
    followup_question: Optional[str] = None
    action: Optional[ShowOnMapAction] = None


# --- Condition and Keyword Mapping ---

CONDITION_KEYWORDS: Dict[str, List[str]] = {
    "車いす": ["車いす", "車椅子"],
    "ベビーカー": ["ベビーカー"],
    "杖": ["杖", "つえ"],
    "徒歩": ["徒歩", "歩き"],
    "階段": ["階段"],
    "急な坂道": ["坂道", "坂"],
    "混雑": ["混雑", "混んでる", "人混み"],
    "暗い道": ["暗い道", "夜道"],
}

KEYWORD_TO_YOLP_CATEGORY: Dict[str, List[str]] = {
    "さくら": ["0105007", "0112003", "0112001", "0201001"], # 公園, 庭園, 川辺, 観光名所
    "桜": ["0105007", "0112003", "0112001", "0201001"],
    "静か": ["0105007", "0108001", "0804001"], # 公園, 図書館, カフェ
    "落ち着いた": ["0105007", "0108001", "0804001"],
    "ランチ": ["0101001", "0102001", "0103001"], # 和食, 洋食, 中華
    "カフェ": ["0804001"],
    "景色": ["0201001", "0201002", "0105007"], # 観光名所, 展望台, 公園
}

# --- YOLP API Integration ---

YOLP_API_BASE_URL = "https://map.yahooapis.jp/search/local/V1/localSearch"

def _search_yolp(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calls the Yahoo Open Local Platform (YOLP) API.
    """
    api_key = os.getenv("YOLP_API_KEY")
    if not api_key:
        print("Error: YOLP_API_KEY environment variable not set.")
        # In a real scenario, you'd want to handle this more gracefully.
        # For this implementation, we return an empty feature set.
        return {"Feature": []}

    headers = {"Authorization": f"YJDN anRzYWl0b3VAY3J5cHRpay5jb20-"}
    default_params = {
        "appid": api_key,
        "output": "json",
        "results": 20, # Request more results to have enough for scoring
        "sort": "hybrid", # Sort by a mix of distance and relevance
    }
    all_params = {**default_params, **params}

    try:
        response = requests.get(YOLP_API_BASE_URL, headers=headers, params=all_params)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error calling YOLP API: {e}")
        return {"Feature": []}

def _normalize_yolp_response(yolp_features: List[Dict[str, Any]], reason_keyword: str) -> List[Spot]:
    """
    Converts YOLP API response to a list of Spot objects.
    """
    spots = []
    for feature in yolp_features:
        try:
            gid = feature.get("Gid")
            name = feature.get("Name")
            coords_str = feature.get("Geometry", {}).get("Coordinates", "0,0")
            lon_str, lat_str = coords_str.split(',')
            
            if not gid or not name:
                continue

            spots.append(Spot(
                id=gid,
                name=name,
                reason=f"{reason_keyword}に関連するスポットです。", # Simple reason
                latitude=float(lat_str),
                longitude=float(lon_str),
            ))
        except (ValueError, TypeError, KeyError) as e:
            print(f"Skipping feature due to parsing error: {e} - {feature}")
            continue
    return spots


# --- Core Logic ---

def _parse_message(message: str) -> (List[str], List[str]):
    """
    Extracts keywords and conditions from the user's message.
    """
    detected_conditions = []
    for condition, keywords in CONDITION_KEYWORDS.items():
        if any(kw in message for kw in keywords):
            detected_conditions.append(condition)

    detected_keywords = []
    for keyword in KEYWORD_TO_YOLP_CATEGORY.keys():
        if keyword in message:
            detected_keywords.append(keyword)
            
    return detected_keywords, detected_conditions

def _score_and_rank_spots(spots: List[Spot]) -> List[Spot]:
    """
    Scores and ranks spots. For now, it's a simple selection of the top 5.
    In a real app, this could involve more complex scoring based on relevance, distance, etc.
    """
    # Simple random shuffle and take top 5 to simulate scoring
    random.shuffle(spots)
    return spots[:5]

async def process_chat_message(request: ChatRequest) -> ChatResponse:
    """
    Main function to process the chat message, call YOLP, and return a response.
    """
    keywords, conditions = _parse_message(request.message)

    search_params: Dict[str, Any] = {}
    if request.latitude and request.longitude:
        search_params["lat"] = request.latitude
        search_params["lon"] = request.longitude
        search_params["dist"] = 5 # Search within 5km
    
    primary_keyword = "目的地"
    if not keywords:
        # No specific keywords, perform a generic search for "tourist spots"
        search_params["gc"] = "0201001" # Category for tourist spots
    else:
        primary_keyword = keywords[0]
        # Use categories from the first detected keyword
        category_codes = KEYWORD_TO_YOLP_CATEGORY.get(primary_keyword, [])
        if category_codes:
            search_params["gc"] = ",".join(category_codes)
        # Also use the keyword for a query search
        search_params["query"] = primary_keyword

    # Call YOLP API
    yolp_data = _search_yolp(search_params)
    all_spots = _normalize_yolp_response(yolp_data.get("Feature", []), primary_keyword)

    # Score, rank, and get top 5
    recommended_spots = _score_and_rank_spots(all_spots)

    # Build response
    if not recommended_spots:
        assistant_msg = "すみません、ご希望に合う場所が見つかりませんでした。別のキーワードで試していただけますか？"
        return ChatResponse(assistant_message=assistant_msg, recommended_conditions=conditions)

    assistant_msg = f"「{primary_keyword}」に関連する場所を5件提案します。"
    spot_ids = [spot.id for spot in recommended_spots]
    
    response = ChatResponse(
        assistant_message=assistant_msg,
        recommended_conditions=conditions,
        spots=recommended_spots,
        action=ShowOnMapAction(spot_ids=spot_ids)
    )

    # Add a followup question if location was not provided
    if not request.latitude or not request.longitude:
        response.followup_question = "現在地の近くで探しますか？"

    return response
