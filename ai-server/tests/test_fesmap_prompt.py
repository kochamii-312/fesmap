
import sys
from pathlib import Path
import json

# ai-server ディレクトリをパスに追加
sys.path.append(str(Path(__file__).parent.parent))

from server import _build_chat_messages, AIChatRequest, ChatMessage

def test_festival_prompt_construction():
    """
    学園祭（フェス君）プロンプトが正しく構築されるかテストする。
    """
    print("--- Testing Festival Prompt Construction ---")
    
    # 1. シンプルな質問
    request = AIChatRequest(
        messages=[
            ChatMessage(role="user", content="おすすめの模擬店を教えて！")
        ]
    )
    
    messages = _build_chat_messages(request)
    
    system_content = messages[0]["content"]
    print("\n[System Prompt Preview]")
    print(system_content[:200] + "...")
    
    # プロンプト内に学園祭のキーワードが含まれているか確認
    assert "フェス君" in system_content
    assert "模擬店" in system_content
    assert "11棟" in system_content
    
    print("\n[User Message]")
    print(messages[1]["content"])
    
    # 2. ユーザープロファイル（車椅子）がある場合
    request_with_profile = AIChatRequest(
        messages=[
            ChatMessage(role="user", content="車椅子で行ける展示はあるかな？")
        ],
        user_profile={
            "mobility_type": "wheelchair",
            "avoid_conditions": ["stairs"]
        }
    )
    
    messages_with_profile = _build_chat_messages(request_with_profile)
    print("\n[System Prompt with Profile]")
    # プロファイルの JSON が含まれているか確認
    last_part = messages_with_profile[0]["content"][-100:]
    print(f"...{last_part}")
    assert "wheelchair" in messages_with_profile[0]["content"]

    print("\n--- Prompt Construction Test Passed! ---")

if __name__ == "__main__":
    test_festival_prompt_construction()
