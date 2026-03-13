// AsyncStorage キー定数（プロファイル、チャット、ニーズで共有）
export const STORAGE_KEYS = {
  mobilityType: 'profile_mobilityType',
  companions: 'profile_companions',
  maxDistance: 'profile_maxDistance',
  avoidConditions: 'profile_avoidConditions',
  preferConditions: 'profile_preferConditions',
  chatExtractedNeeds: 'chat_extractedNeeds',
} as const;
