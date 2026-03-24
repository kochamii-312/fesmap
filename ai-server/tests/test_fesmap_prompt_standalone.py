
import sys
from pathlib import Path
import json

def load_prompt(filename: str) -> str:
    """プロンプトファイルを読み込む（server.pyの簡易版）。"""
    prompt_path = Path(__file__).parent.parent / "prompts" / filename
    with open(prompt_path, "r", encoding="utf-8") as f:
        return f.read()

def _build_chat_messages(request_messages, user_profile=None) -> list[dict[str, str]]:
    """プロンプト構築ロジックの再現。"""
    system_prompt = load_prompt("chat_system.txt")
    messages = [{"role": "system", "content": system_prompt}]

    if user_profile:
        profile_text = (
            f"\n\nユーザーの既知のプロファイル情報: "
            f"{json.dumps(user_profile, ensure_ascii=False)}"
        )
        messages[0]["content"] += profile_text

    for msg in request_messages:
        messages.append({"role": msg["role"], "content": msg["content"]})

    return messages

def test_festival_prompt_logic():
    print("--- Testing Festival Prompt Logic (Standalone) ---")
    
    # 1. シンプルな質問
    user_msg = [{"role": "user", "content": "おすすめの模擬店を教えて！"}]
    messages = _build_chat_messages(user_msg)
    
    system_content = messages[0]["content"]
    print("\n[System Prompt Preview]")
    print(system_content[:200] + "...")
    
    # チェック項目
    assert "フェス君" in system_content, "フェス君のキャラクター設定が反映されていません"
    assert "模擬店" in system_content, "模擬店のカテゴリが含まれていません"
    assert "11棟" in system_content, "場所のカテゴリが含まれていません"
    
    print("\n[Check Results]")
    print("- キャラクター: フェス君 OK")
    print("- カテゴリ (模擬店): OK")
    print("- 場所 (11棟): OK")
    
    # 2. ユーザープロファイル
    profile = {"mobility_type": "wheelchair", "avoid_conditions": ["stairs"]}
    messages_with_profile = _build_chat_messages(user_msg, user_profile=profile)
    
    print("\n[Profile Inclusion Check]")
    assert "wheelchair" in messages_with_profile[0]["content"]
    print("- プロファイル (wheelchair) 埋め込み: OK")

    print("\n--- All Prompt Logic Tests Passed! ---")

if __name__ == "__main__":
    test_festival_prompt_logic()
