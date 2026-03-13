import React, { useState, useRef, useCallback } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  FlatList,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import { ChatMessage, ChatResponse } from '../../src/types';
import { sendChat } from '../../src/services/api';
import { getCurrentUserId } from '../../src/services/auth';
import { saveChatNeeds, clearChatNeeds } from '../../src/services/userNeeds';

interface DisplayMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
}

// 初回表示用のサジェスションチップ
const SUGGESTIONS = [
  '車椅子で東京駅に行きたい',
  '近くのバリアフリートイレを探して',
  'ベビーカーで移動しやすいルートは?',
  '高齢の母と一緒に観光したい',
  '段差のない道で新宿駅まで行きたい',
  'エレベーターがある駅を教えて',
  '休憩できる場所はある？',
  '雨の日でも安心なルートは？',
];

// 会話ターン数に応じた追加サジェスション（会話中に表示可能）
const FOLLOWUP_SUGGESTIONS: Record<string, string[]> = {
  mobility: [
    '段差のないルートを検索して',
    'エレベーターのある出口を教えて',
    '車椅子対応レストランはある？',
  ],
  restroom: [
    '他のトイレも表示して',
    'オストメイト対応のトイレは？',
    'おむつ替えシートがある場所は？',
  ],
  route: [
    '所要時間はどれくらい？',
    '途中に休憩できる場所はある？',
    '別のルートも見たい',
  ],
  spot: [
    'もっと近い場所はある？',
    '営業時間を教えて',
    'その場所にトイレはある？',
  ],
  general: [
    '他にバリアフリーの情報はある？',
    'この近くのおすすめスポットは？',
    '天気に合わせたルートを教えて',
  ],
};

const HIT_SLOP = { top: 10, bottom: 10, left: 10, right: 10 };

// ---------------------------------------------------------------------------
// モックレスポンス生成（API未接続時のフォールバック）
// ---------------------------------------------------------------------------

/** キーワードグループ定義: パターン配列 → カテゴリ */
interface KeywordGroup {
  category: string;
  keywords: string[];
}

const KEYWORD_GROUPS: KeywordGroup[] = [
  { category: 'restroom', keywords: ['トイレ', 'お手洗い', '化粧室', 'おむつ替え', 'オストメイト', '授乳室', '授乳'] },
  { category: 'wheelchair', keywords: ['車椅子', '車いす', 'くるまいす', 'ウィールチェア'] },
  { category: 'stroller', keywords: ['ベビーカー', '赤ちゃん', '乳児', '幼児', '子連れ', '子ども連れ'] },
  { category: 'elderly', keywords: ['高齢', 'お年寄り', 'シニア', '杖', '歩行器', '足が悪い', '足が不自由'] },
  { category: 'visual', keywords: ['視覚', '目が見えない', '目が不自由', '点字', '白杖', '盲導犬'] },
  { category: 'route', keywords: ['ルート', '行きたい', '行き方', '道順', '経路', '道のり', 'アクセス', '乗り換え', '乗換'] },
  { category: 'elevator', keywords: ['エレベーター', 'エレベータ', 'EV', 'リフト'] },
  { category: 'stairs', keywords: ['階段', '段差', 'スロープ', 'バリアフリー', '段差なし', 'フラット'] },
  { category: 'spot', keywords: ['スポット', 'おすすめ', '観光', '名所', '見どころ', '遊び場', '公園'] },
  { category: 'food', keywords: ['レストラン', '食事', 'ランチ', 'カフェ', '飲食', 'ご飯', '食べ'] },
  { category: 'hotel', keywords: ['ホテル', '宿泊', '宿', '泊まる', '旅館'] },
  { category: 'station', keywords: ['駅', '空港', 'バス停', 'バスターミナル', 'ターミナル'] },
  { category: 'weather', keywords: ['雨', '天気', '雪', '暑い', '寒い', '屋根'] },
  { category: 'rest', keywords: ['休憩', '休む', 'ベンチ', '座る', '疲れ'] },
  { category: 'time', keywords: ['時間', '所要時間', '何分', 'どのくらい', 'どれくらい'] },
  { category: 'help', keywords: ['助けて', 'ヘルプ', '使い方', '何ができる', 'できること'] },
  { category: 'greeting', keywords: ['こんにちは', 'こんばんは', 'おはよう', 'はじめまして', 'ありがとう', 'よろしく'] },
];

/** メッセージから該当するカテゴリをすべて抽出する */
function matchCategories(message: string): string[] {
  const matched: string[] = [];
  for (const group of KEYWORD_GROUPS) {
    if (group.keywords.some((kw) => message.includes(kw))) {
      matched.push(group.category);
    }
  }
  return matched;
}

/** 会話履歴からニーズを抽出するモックロジック */
function extractNeeds(
  message: string,
  categories: string[],
): Record<string, unknown> {
  const needs: Record<string, unknown> = {};

  // 移動手段の推定
  if (categories.includes('wheelchair')) {
    needs.mobilityType = 'wheelchair';
  } else if (categories.includes('stroller')) {
    needs.mobilityType = 'stroller';
  } else if (categories.includes('elderly')) {
    needs.mobilityType = 'cane';
  }

  // 同行者の推定
  const companions: string[] = [];
  if (categories.includes('stroller') || message.includes('子ども') || message.includes('子供')) {
    companions.push('child');
  }
  if (categories.includes('elderly')) {
    companions.push('elderly');
  }
  if (categories.includes('wheelchair') || categories.includes('visual')) {
    companions.push('disability');
  }
  if (companions.length > 0) {
    needs.companions = companions;
  }

  // 回避条件の推定
  const avoid: string[] = [];
  if (categories.includes('stairs') || categories.includes('wheelchair') || categories.includes('stroller')) {
    avoid.push('stairs');
  }
  if (message.includes('坂') || message.includes('急な')) {
    avoid.push('slope');
  }
  if (message.includes('混雑') || message.includes('人混み') || message.includes('混んで')) {
    avoid.push('crowd');
  }
  if (message.includes('暗い') || message.includes('夜道')) {
    avoid.push('dark');
  }
  if (avoid.length > 0) {
    needs.avoidConditions = avoid;
  }

  // 希望条件の推定
  const prefer: string[] = [];
  if (categories.includes('restroom')) {
    prefer.push('restroom');
  }
  if (categories.includes('rest')) {
    prefer.push('rest_area');
  }
  if (categories.includes('weather') || message.includes('屋根')) {
    prefer.push('covered');
  }
  if (prefer.length > 0) {
    needs.preferConditions = prefer;
  }

  // 目的地の簡易抽出（「〜に行きたい」「〜まで」パターン）
  const destPatterns = [
    /(.+?)(に行きたい|へ行きたい|まで行きたい|に向かいたい)/,
    /(.+?)(まで|への).*ルート/,
    /(.+?)(に|へ).*アクセス/,
  ];
  for (const pattern of destPatterns) {
    const match = message.match(pattern);
    if (match) {
      // キーワード部分のみ取り出し（移動手段を除去）
      const dest = match[1]
        .replace(/車椅子で|ベビーカーで|杖で|徒歩で/g, '')
        .trim();
      if (dest.length > 0 && dest.length < 30) {
        needs.destination = dest;
        break;
      }
    }
  }

  return needs;
}

/** suggestedAction を判定するロジック */
function decideSuggestedAction(
  categories: string[],
  needs: Record<string, unknown>,
): string | undefined {
  // トイレ系 → 地図表示
  if (categories.includes('restroom')) {
    return 'バリアフリートイレを地図で表示';
  }
  // ルート検索系（目的地あり）
  if (categories.includes('route') && needs.destination) {
    return 'ルート検索画面を開く';
  }
  // エレベーター・駅情報
  if (categories.includes('elevator') || (categories.includes('station') && categories.includes('stairs'))) {
    return 'バリアフリー設備を地図で表示';
  }
  // スポット・食事・ホテル → スポット検索
  if (categories.includes('spot') || categories.includes('food') || categories.includes('hotel')) {
    return '周辺スポットを検索';
  }
  // 移動手段が特定されてルートの話 → ルート検索
  if (needs.mobilityType && (categories.includes('route') || categories.includes('stairs'))) {
    return 'ルート検索画面を開く';
  }
  return undefined;
}

/**
 * モックレスポンス生成（API未接続時のフォールバック）
 *
 * @param message - ユーザーの入力メッセージ
 * @param conversationLength - 現在の会話ターン数（ユーザー+アシスタントの合計）
 */
function generateMockResponse(message: string, conversationLength: number = 0): ChatResponse {
  const categories = matchCategories(message);
  const needs = extractNeeds(message, categories);
  const suggestedAction = decideSuggestedAction(categories, needs);

  // --- 挨拶系 ---
  if (categories.includes('greeting') && categories.length === 1) {
    if (message.includes('ありがとう')) {
      return {
        reply: 'どういたしまして！他にもお手伝いできることがあれば、お気軽にお声がけください。バリアフリーのルートやスポット情報など、何でもお尋ねいただけます。',
        extractedNeeds: needs,
      };
    }
    return {
      reply: 'こんにちは！AccessRouteのAIコンシェルジュです。バリアフリーのルート検索やスポット案内など、お気軽にご相談ください。車椅子、ベビーカー、杖をお使いの方など、どなたでもお手伝いいたします。',
      extractedNeeds: needs,
    };
  }

  // --- ヘルプ系 ---
  if (categories.includes('help')) {
    return {
      reply: 'AccessRouteでは以下のことができます：\n\n• バリアフリールートの検索（段差・階段を避けるルート）\n• 車椅子対応トイレ・多機能トイレの検索\n• バリアフリー対応スポット・レストランの検索\n• エレベーター・スロープのある駅出口のご案内\n• お身体の状況に合わせた最適ルートのご提案\n\n何かお探しのことはありますか？',
      extractedNeeds: needs,
    };
  }

  // --- トイレ系（複合キーワード対応） ---
  if (categories.includes('restroom')) {
    if (message.includes('オストメイト')) {
      return {
        reply: 'オストメイト対応トイレをお探しですね。東京駅では丸の内地下1階の多機能トイレにオストメイト設備があります。また、八重洲地下街の北口付近にもございます。地図で場所をご確認いただけます。',
        suggestedAction,
        extractedNeeds: needs,
      };
    }
    if (message.includes('おむつ替え') || message.includes('授乳')) {
      return {
        reply: 'おむつ替え・授乳スペースをお探しですね。東京駅周辺では、KITTE 4階のベビー休憩室、大丸東京店のベビールーム（11階）がおすすめです。どちらもエレベーターでアクセスできます。',
        suggestedAction: '周辺スポットを検索',
        extractedNeeds: needs,
      };
    }
    // 車椅子 + トイレの複合
    if (categories.includes('wheelchair')) {
      return {
        reply: '車椅子対応のバリアフリートイレをお探しですね。東京駅構内には丸の内地下1階（改札外）と京葉ストリート（改札内）に広めの車椅子対応トイレがあります。丸の内側が最もアクセスしやすいです。',
        suggestedAction,
        extractedNeeds: needs,
      };
    }
    return {
      reply: '最寄りのバリアフリートイレをお探しですね。東京駅周辺には丸の内地下通路と八重洲地下街に車椅子対応トイレがあります。丸の内側の地下1階が最もアクセスしやすいです。詳しい場所を地図でお見せしましょうか？',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- 車椅子系 ---
  if (categories.includes('wheelchair')) {
    // 車椅子 + 食事
    if (categories.includes('food')) {
      return {
        reply: '車椅子でも入りやすいレストランをお探しですね。東京駅周辺では、丸ビル（段差なし・広い通路）、KITTE（全フロアバリアフリー）のレストランが車椅子対応です。テーブル席の高さや通路幅も配慮されています。',
        suggestedAction: '周辺スポットを検索',
        extractedNeeds: needs,
      };
    }
    // 車椅子 + ホテル
    if (categories.includes('hotel')) {
      return {
        reply: '車椅子対応のホテルをお探しですね。東京駅周辺では、東京ステーションホテル、フォーシーズンズホテル丸の内、相鉄フレッサイン東京駅八重洲口などがバリアフリールームを備えています。ご予算や日程を教えていただければ、さらに絞り込めます。',
        suggestedAction: '周辺スポットを検索',
        extractedNeeds: needs,
      };
    }
    // 車椅子 + ルート
    if (categories.includes('route') || needs.destination) {
      const destText = needs.destination ? `「${needs.destination}」への` : '';
      return {
        reply: `車椅子での${destText}お出かけですね。段差のないルートを優先的にご案内します。エレベーターやスロープのあるルートをお探しします。${needs.destination ? '' : '目的地を教えていただければ、具体的なルートをご提案できます。'}`,
        suggestedAction: needs.destination ? 'ルート検索画面を開く' : undefined,
        extractedNeeds: needs,
      };
    }
    return {
      reply: '車椅子でのお出かけですね。段差のないルートを優先的にご案内します。目的地を教えていただければ、エレベーターやスロープのあるルートをお探しします。周辺施設のバリアフリー情報もお伝えできますよ。',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- ベビーカー・子連れ系 ---
  if (categories.includes('stroller')) {
    if (categories.includes('food')) {
      return {
        reply: 'お子さま連れで入りやすいレストランをお探しですね。ベビーカーのまま入店できるお店や、キッズメニューのあるレストランを優先してご案内します。東京駅周辺では、KITTEや丸ビルのレストランフロアが広くておすすめです。',
        suggestedAction: '周辺スポットを検索',
        extractedNeeds: needs,
      };
    }
    if (categories.includes('route') || needs.destination) {
      const destText = needs.destination ? `「${needs.destination}」への` : '';
      return {
        reply: `ベビーカーでの${destText}移動ですね。エレベーターがある駅出口や、段差の少ない歩道を優先してご案内できます。${needs.destination ? 'ルートを検索しますね。' : '目的地はどちらですか？'}`,
        suggestedAction: needs.destination ? 'ルート検索画面を開く' : undefined,
        extractedNeeds: needs,
      };
    }
    return {
      reply: 'ベビーカーでの移動ですね。エレベーターがある駅出口や、段差の少ない歩道を優先してご案内できます。おむつ替えスペースや授乳室の情報もお伝えできますよ。目的地はどちらですか？',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- 高齢者・杖系 ---
  if (categories.includes('elderly')) {
    if (categories.includes('rest')) {
      return {
        reply: '休憩しながら移動できるルートをお探しですね。ベンチや休憩スペースのある場所を経由するルートをご案内できます。東京駅周辺では、丸の内仲通りにベンチが多く設置されています。',
        suggestedAction: 'ルート検索画面を開く',
        extractedNeeds: needs,
      };
    }
    if (categories.includes('route') || needs.destination) {
      const destText = needs.destination ? `「${needs.destination}」への` : '';
      return {
        reply: `ご高齢の方との${destText}お出かけですね。歩きやすく、休憩場所のあるルートを優先してご案内します。急な坂道や長い階段を避けたルートをお探しします。${needs.destination ? '' : '目的地を教えてください。'}`,
        suggestedAction: needs.destination ? 'ルート検索画面を開く' : undefined,
        extractedNeeds: needs,
      };
    }
    return {
      reply: 'ご高齢の方やお体の不自由な方のお出かけをサポートいたします。段差や急坂を避けたルート、休憩場所の案内、車椅子対応施設の情報など、お気軽にご相談ください。',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- 視覚障害系 ---
  if (categories.includes('visual')) {
    return {
      reply: '視覚に障がいのある方のための情報をご案内します。点字ブロックのあるルートや、音声案内のある施設の情報をお伝えできます。目的地を教えていただければ、具体的なルートをご提案いたします。',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- エレベーター系 ---
  if (categories.includes('elevator')) {
    if (categories.includes('station')) {
      return {
        reply: 'エレベーターのある駅出口をお探しですね。東京駅では丸の内北口・南口、八重洲中央口にエレベーターがあります。地図でエレベーターの位置を表示しましょうか？',
        suggestedAction: 'バリアフリー設備を地図で表示',
        extractedNeeds: needs,
      };
    }
    return {
      reply: 'エレベーター情報をお探しですね。駅名や施設名を教えていただければ、エレベーターの場所や利用可能時間をご案内いたします。',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- 段差・バリアフリー系 ---
  if (categories.includes('stairs')) {
    return {
      reply: '段差やスロープの情報をお探しですね。段差のない経路を優先してルートをご案内できます。目的地を教えていただければ、バリアフリールートを検索します。',
      suggestedAction: suggestedAction ?? 'ルート検索画面を開く',
      extractedNeeds: needs,
    };
  }

  // --- 天気系 ---
  if (categories.includes('weather')) {
    return {
      reply: '天候を考慮したルートをお探しですね。屋根のある通路や地下道を優先したルートをご案内できます。東京駅周辺では、丸の内地下通路や八重洲地下街を使えば、雨でも濡れずに移動できます。',
      suggestedAction: 'ルート検索画面を開く',
      extractedNeeds: needs,
    };
  }

  // --- 休憩系 ---
  if (categories.includes('rest')) {
    return {
      reply: '休憩できる場所をお探しですね。東京駅周辺では、丸の内仲通りのベンチ、KITTE屋上庭園、東京駅構内の待合室などがあります。お体の状況に合わせて、近くの休憩スポットをご案内できますよ。',
      suggestedAction: '周辺スポットを検索',
      extractedNeeds: needs,
    };
  }

  // --- 食事系 ---
  if (categories.includes('food')) {
    return {
      reply: 'バリアフリー対応のレストラン・カフェをお探しですね。東京駅周辺では、KITTE、丸ビル、大丸東京店のレストランフロアが段差なしでアクセスしやすいです。お食事のジャンルやご予算はありますか？',
      suggestedAction: '周辺スポットを検索',
      extractedNeeds: needs,
    };
  }

  // --- ホテル系 ---
  if (categories.includes('hotel')) {
    return {
      reply: 'バリアフリー対応のホテルをお探しですね。お身体の状況に合ったホテルをご案内いたします。エリアやご予算のご希望はありますか？',
      suggestedAction: '周辺スポットを検索',
      extractedNeeds: needs,
    };
  }

  // --- ルート・行き先系 ---
  if (categories.includes('route')) {
    if (needs.destination) {
      return {
        reply: `「${needs.destination}」へのバリアフリールートをお探しですね。お身体の状況（車椅子、ベビーカー、杖など）を教えていただければ、最適なルートをご提案します。`,
        suggestedAction: 'ルート検索画面を開く',
        extractedNeeds: needs,
      };
    }
    return {
      reply: '目的地へのバリアフリールートをお探しですね。出発地と目的地を教えてください。段差やスロープの情報を含めたルートをご提案します。',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- スポット系 ---
  if (categories.includes('spot')) {
    return {
      reply: 'バリアフリー対応のおすすめスポットをご紹介します。東京駅周辺では、丸ビル（車椅子対応）、KITTE（エレベーター完備）、東京ステーションホテルなどがアクセスしやすいです。他のエリアもお調べできますよ。',
      suggestedAction: '周辺スポットを検索',
      extractedNeeds: needs,
    };
  }

  // --- 時間・所要時間系 ---
  if (categories.includes('time')) {
    return {
      reply: '所要時間を知りたいですね。出発地と目的地、移動手段を教えていただければ、バリアフリールートでのおおよその所要時間をお伝えできます。',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- 駅系（単独） ---
  if (categories.includes('station')) {
    return {
      reply: '駅のバリアフリー情報をお探しですね。エレベーター、多機能トイレ、車椅子対応改札口などの情報をご案内できます。駅名を教えていただけますか？',
      suggestedAction,
      extractedNeeds: needs,
    };
  }

  // --- 会話ターン数に応じたデフォルト返答の変化 ---
  if (conversationLength === 0) {
    // 初回メッセージへのデフォルト
    return {
      reply: 'ご相談ありがとうございます！目的地や移動手段を教えてください。車椅子、ベビーカー、杖など、お客様の状況に合わせたバリアフリールートやスポットをご提案いたします。',
      extractedNeeds: needs,
    };
  }

  if (conversationLength < 4) {
    // 序盤の会話
    return {
      reply: 'もう少し詳しく教えていただけますか？例えば、目的地、移動手段（車椅子・ベビーカーなど）、避けたい条件（階段・坂道など）をお伝えいただくと、より最適なご案内ができます。',
      extractedNeeds: needs,
    };
  }

  // 会話が進んだ段階でのデフォルト
  return {
    reply: '他にお手伝いできることはありますか？ルートの変更、別のスポットの検索、トイレや休憩場所のご案内など、何でもお気軽にどうぞ。',
    extractedNeeds: needs,
  };
}

export default function ChatScreen() {
  const router = useRouter();
  const [messages, setMessages] = useState<DisplayMessage[]>([]);
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [suggestedAction, setSuggestedAction] = useState<string | undefined>();
  const flatListRef = useRef<FlatList<DisplayMessage>>(null);

  const canSend = inputText.trim().length > 0 && !isLoading;

  const sendMessage = useCallback(
    async (text?: string) => {
      const messageText = (text ?? inputText).trim();
      if (!messageText || isLoading) return;

      const userMsg: DisplayMessage = {
        id: `user-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
        role: 'user',
        content: messageText,
      };

      setMessages((prev) => [...prev, userMsg]);
      setInputText('');
      setIsLoading(true);
      setSuggestedAction(undefined);

      // Build conversation history for the API
      const history: ChatMessage[] = [
        ...messages.map((m) => ({ role: m.role, content: m.content })),
        { role: 'user' as const, content: messageText },
      ];

      let response: ChatResponse;
      try {
        const userId = (await getCurrentUserId()) ?? 'anonymous';
        response = await sendChat(userId, messageText, history);
      } catch {
        // API未接続時はモックレスポンスを使用（会話ターン数を渡す）
        response = generateMockResponse(messageText, messages.length);
      }

      const replyText = response?.reply ?? '申し訳ございません。応答を取得できませんでした。';
      const assistantMsg: DisplayMessage = {
        id: `assistant-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
        role: 'assistant',
        content: replyText,
      };

      setMessages((prev) => [...prev, assistantMsg]);

      if (response.suggestedAction) {
        setSuggestedAction(response.suggestedAction);
      }

      // チャットから抽出されたニーズをAsyncStorageに保存（おすすめスポット等で活用）
      if (response.extractedNeeds && Object.keys(response.extractedNeeds).length > 0) {
        saveChatNeeds(response.extractedNeeds).catch((err) =>
          console.warn('[Chat] ニーズ保存失敗:', err)
        );
      }

      setIsLoading(false);
    },
    [inputText, isLoading, messages],
  );

  const resetConversation = useCallback(() => {
    setMessages([]);
    setSuggestedAction(undefined);
    setInputText('');
    clearChatNeeds().catch(() => {});
  }, []);

  const renderMessage = useCallback(({ item }: { item: DisplayMessage }) => {
    const isUser = item.role === 'user';
    return (
      <View
        style={[
          styles.messageBubbleRow,
          isUser ? styles.userRow : styles.assistantRow,
        ]}
      >
        <View
          style={[
            styles.bubble,
            isUser ? styles.userBubble : styles.assistantBubble,
          ]}
          accessibilityLabel={`${isUser ? 'ユーザー' : 'AIアシスタント'}: ${item.content}`}
        >
          <Text
            style={[
              styles.bubbleText,
              isUser ? styles.userBubbleText : styles.assistantBubbleText,
            ]}
          >
            {item.content}
          </Text>
        </View>
      </View>
    );
  }, []);

  const renderEmptyWelcome = useCallback(
    () => (
      <View style={styles.welcomeContainer}>
        <Text style={styles.welcomeIcon}>{'💬'}</Text>
        <Text style={styles.welcomeTitle}>
          {'AIコンシェルジュに\n旅行の相談をしてみましょう'}
        </Text>
        <View style={styles.suggestionsContainer}>
          {SUGGESTIONS.map((suggestion) => (
            <TouchableOpacity
              key={suggestion}
              style={styles.suggestionChip}
              onPress={() => sendMessage(suggestion)}
              hitSlop={HIT_SLOP}
              activeOpacity={0.6}
              accessibilityLabel={suggestion}
              accessibilityRole="button"
            >
              <Text style={styles.suggestionText}>{suggestion}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>
    ),
    [sendMessage],
  );

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
    >
      {/* Header reset button */}
      <View style={styles.headerBar}>
        <TouchableOpacity
          onPress={resetConversation}
          style={styles.resetButton}
          hitSlop={HIT_SLOP}
          activeOpacity={0.6}
          accessibilityLabel="会話をリセット"
          accessibilityHint="チャット履歴をすべて削除します"
        >
          <Text style={styles.resetButtonText}>リセット</Text>
        </TouchableOpacity>
      </View>

      {/* Messages list */}
      <FlatList
        ref={flatListRef}
        data={messages}
        keyExtractor={(item) => item.id}
        renderItem={renderMessage}
        ListEmptyComponent={renderEmptyWelcome}
        contentContainerStyle={
          messages.length === 0
            ? styles.emptyListContent
            : styles.listContent
        }
        onContentSizeChange={() =>
          flatListRef.current?.scrollToEnd({ animated: true })
        }
        keyboardShouldPersistTaps="handled"
      />

      {/* Typing indicator */}
      {isLoading && (
        <View style={styles.typingContainer}>
          <View style={styles.typingBubble}>
            <ActivityIndicator size="small" color="#666" />
            <Text style={styles.typingText}>応答中...</Text>
          </View>
        </View>
      )}

      {/* Suggested action */}
      {suggestedAction && (
        <View style={styles.actionContainer}>
          <TouchableOpacity
            style={styles.actionCard}
            activeOpacity={0.6}
            accessibilityRole="button"
            accessibilityLabel={suggestedAction}
            onPress={() => {
              if (suggestedAction.includes('ルート')) {
                router.navigate('/(tabs)/route');
              } else if (
                suggestedAction.includes('スポット') ||
                suggestedAction.includes('トイレ') ||
                suggestedAction.includes('地図') ||
                suggestedAction.includes('設備')
              ) {
                router.navigate('/(tabs)/spots');
              } else {
                sendMessage(suggestedAction);
              }
            }}
          >
            <Text style={styles.actionLabel}>提案されたアクション</Text>
            <Text style={styles.actionText}>{suggestedAction}</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Input bar */}
      <View style={styles.inputBar}>
        <TextInput
          style={styles.textInput}
          value={inputText}
          onChangeText={setInputText}
          placeholder="メッセージを入力..."
          placeholderTextColor="#999"
          multiline
          maxLength={1000}
          returnKeyType="send"
          onSubmitEditing={() => canSend && sendMessage()}
          blurOnSubmit={false}
          accessibilityLabel="メッセージ入力フィールド"
        />
        <TouchableOpacity
          style={[styles.sendButton, !canSend && styles.sendButtonDisabled]}
          onPress={() => sendMessage()}
          disabled={!canSend}
          hitSlop={HIT_SLOP}
          activeOpacity={0.6}
          accessibilityLabel="メッセージを送信"
          accessibilityHint="入力したメッセージをAIに送信します"
        >
          <Text
            style={[
              styles.sendButtonText,
              !canSend && styles.sendButtonTextDisabled,
            ]}
          >
            送信
          </Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  headerBar: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#ddd',
  },
  resetButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    backgroundColor: '#f0f0f0',
    minHeight: 44,
    minWidth: 44,
    justifyContent: 'center',
    alignItems: 'center',
  },
  resetButtonText: {
    fontSize: 14,
    color: '#007AFF',
  },
  listContent: {
    paddingHorizontal: 12,
    paddingVertical: 12,
  },
  emptyListContent: {
    flexGrow: 1,
    justifyContent: 'center',
  },
  messageBubbleRow: {
    marginVertical: 4,
    flexDirection: 'row',
  },
  userRow: {
    justifyContent: 'flex-end',
  },
  assistantRow: {
    justifyContent: 'flex-start',
  },
  bubble: {
    maxWidth: '75%',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 16,
  },
  userBubble: {
    backgroundColor: '#007AFF',
    borderBottomRightRadius: 4,
  },
  assistantBubble: {
    backgroundColor: '#E9E9EB',
    borderBottomLeftRadius: 4,
  },
  bubbleText: {
    fontSize: 16,
    lineHeight: 22,
  },
  userBubbleText: {
    color: '#fff',
  },
  assistantBubbleText: {
    color: '#1c1c1e',
  },
  typingContainer: {
    paddingHorizontal: 12,
    paddingBottom: 4,
  },
  typingBubble: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    backgroundColor: '#E9E9EB',
    borderRadius: 16,
    paddingHorizontal: 14,
    paddingVertical: 10,
    gap: 8,
  },
  typingText: {
    fontSize: 14,
    color: '#666',
  },
  actionContainer: {
    paddingHorizontal: 12,
    paddingBottom: 8,
  },
  actionCard: {
    backgroundColor: '#E8F5E9',
    borderRadius: 12,
    padding: 12,
    borderLeftWidth: 4,
    borderLeftColor: '#4CAF50',
  },
  actionLabel: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
  actionText: {
    fontSize: 15,
    color: '#1B5E20',
    fontWeight: '500',
  },
  inputBar: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#ddd',
    backgroundColor: '#fafafa',
  },
  textInput: {
    flex: 1,
    minHeight: 40,
    maxHeight: 120,
    backgroundColor: '#f0f0f0',
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingTop: 10,
    paddingBottom: 10,
    fontSize: 16,
    color: '#1c1c1e',
  },
  sendButton: {
    marginLeft: 8,
    backgroundColor: '#007AFF',
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 10,
    justifyContent: 'center',
    alignItems: 'center',
    minHeight: 44,
    minWidth: 44,
  },
  sendButtonDisabled: {
    backgroundColor: '#ccc',
  },
  sendButtonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
  sendButtonTextDisabled: {
    color: '#999',
  },
  welcomeContainer: {
    alignItems: 'center',
    paddingHorizontal: 24,
  },
  welcomeIcon: {
    fontSize: 48,
    marginBottom: 16,
  },
  welcomeTitle: {
    fontSize: 18,
    fontWeight: '500',
    textAlign: 'center',
    color: '#666',
    lineHeight: 26,
    marginBottom: 20,
  },
  suggestionsContainer: {
    alignItems: 'flex-start',
    gap: 8,
  },
  suggestionChip: {
    backgroundColor: '#f0f0f0',
    borderRadius: 20,
    paddingHorizontal: 14,
    paddingVertical: 10,
    minHeight: 44,
    justifyContent: 'center',
  },
  suggestionText: {
    fontSize: 14,
    color: '#1c1c1e',
  },
});
