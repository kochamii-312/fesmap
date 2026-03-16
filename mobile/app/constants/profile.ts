export const MOBILITY_OPTIONS = {
  wheelchair: { label: '車椅子', icon: '♿️', color: '#007AFF', desc: '段差を回避' },
  stroller: { label: 'ベビーカー', icon: '👶', color: '#5856D6', desc: 'エレベーター優先' },
  cane: { label: '杖・歩行', icon: '🦯', color: '#FF9500', desc: '平坦な道を選択' },
  walk: { label: '徒歩', icon: '🚶', color: '#34C759', desc: '標準的なルート' },
};

export const AVOID_OPTIONS = {
  stairs: { label: '階段', icon: '🪜' },
  slope: { label: '急な坂道', icon: '⛰️' },
  crowd: { label: '混雑', icon: '👥' },
  dark: { label: '暗い道', icon: '🌙' },
};

export const PREFER_OPTIONS = {
  restroom: { label: 'トイレ', icon: '🚻' },
  rest_area: { label: '休憩所', icon: '🪑' },
  covered: { label: '屋根あり', icon: '⛱️' },
};