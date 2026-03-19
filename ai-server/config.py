"""AI推論サーバーの設定モジュール（軽量版）。

環境変数からHF Inference APIの設定を読み込む。
開発環境ではHugging Face Inference API、本番環境では自前vLLMサーバーを使用。
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()

# ログレベルマッピング
LOG_LEVELS: dict[str, int] = {
    "DEBUG": logging.DEBUG,
    "INFO": logging.INFO,
    "WARNING": logging.WARNING,
    "ERROR": logging.ERROR,
    "CRITICAL": logging.CRITICAL,
}


@dataclass(frozen=True)
class ModelConfig:
    """モデルおよびAPI接続設定。"""

    # 環境設定
    env: str = field(
        default_factory=lambda: os.getenv("ENV", "development")
    )

    # モデル設定
    model_name: str = field(
        default_factory=lambda: os.getenv(
            "MODEL_NAME", "Qwen/Qwen2.5-72B-Instruct"
        )
    )
    # ニーズ抽出用の軽量モデル（JSON返却のみなので小さいモデルで十分）
    extraction_model_name: str = field(
        default_factory=lambda: os.getenv(
            "EXTRACTION_MODEL_NAME", "Qwen/Qwen2.5-7B-Instruct"
        )
    )

    # API設定（環境に応じて自動切り替え）
    api_key: str = field(default="")
    base_url: str = field(default="")

    # サーバー設定
    host: str = field(
        default_factory=lambda: os.getenv("HOST", "0.0.0.0")
    )
    port: int = field(
        default_factory=lambda: int(os.getenv("PORT", "8000"))
    )

    # ログ設定
    log_level: str = field(
        default_factory=lambda: os.getenv("LOG_LEVEL", "INFO")
    )

    def __post_init__(self) -> None:
        """環境に応じてbase_urlとapi_keyを設定する。"""
        if self.env == "production":
            url = os.getenv("VLLM_BASE_URL", "http://localhost:8000/v1")
            key = os.getenv("API_KEY", "dummy")
        else:
            url = os.getenv(
                "HF_BASE_URL", "https://router.huggingface.co/v1"
            )
            key = os.getenv("HF_TOKEN", "")

        # frozen=True なので object.__setattr__ を使用
        object.__setattr__(self, "base_url", url)
        object.__setattr__(self, "api_key", key)


def load_config() -> ModelConfig:
    """設定をロードして返す。"""
    config = ModelConfig()

    # ログ設定を適用
    level = LOG_LEVELS.get(config.log_level.upper(), logging.INFO)
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    return config
