/**
 * アクセシビリティスコア計算のテスト
 *
 * ユーザープロファイルとルート・スポットの条件の組み合わせによる
 * スコア計算ロジックを網羅的に検証する。
 */

import { Timestamp } from "firebase-admin/firestore";

// firebase-admin モック
jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
}));

jest.mock("firebase-admin/firestore", () => ({
  Timestamp: {
    now: jest.fn(() => ({ seconds: 1700000000, nanoseconds: 0 })),
  },
}));

jest.mock("firebase-functions/params", () => ({
  defineString: jest.fn(() => ({ value: jest.fn(() => "mock-value") })),
}));

import { calculateRouteScore, calculateWeightedRouteScore, calculateSpotScore, generateWarnings } from "../utils/scoring";
import { RouteStep, UserProfile, SpotSummary } from "../types";

// テスト用ヘルパー: UserProfile を生成
const createProfile = (
  overrides: Partial<UserProfile> = {}
): UserProfile => ({
  userId: "test-user",
  mobilityType: "walk",
  companions: [],
  maxDistanceMeters: 1000,
  avoidConditions: [],
  preferConditions: [],
  createdAt: Timestamp.now(),
  updatedAt: Timestamp.now(),
  ...overrides,
});

// テスト用ヘルパー: RouteStep を生成
const createStep = (
  overrides: Partial<RouteStep> = {}
): RouteStep => ({
  stepId: "step-1",
  instruction: "直進する",
  distanceMeters: 100,
  durationSeconds: 120,
  startLocation: { lat: 35.6812, lng: 139.7671 },
  endLocation: { lat: 35.6815, lng: 139.7680 },
  polyline: "encoded_string",
  hasStairs: false,
  hasSlope: false,
  ...overrides,
});

describe("アクセシビリティスコア計算", () => {
  // ============================
  // ルートスコア計算
  // ============================

  describe("calculateRouteScore", () => {
    it("ステップが空の場合、スコア 100 を返すこと", () => {
      const profile = createProfile();
      const score = calculateRouteScore([], profile);
      expect(score).toBe(100);
    });

    it("障害物のないルートでスコア 100 を返すこと", () => {
      const profile = createProfile({ avoidConditions: ["stairs", "slope"] });
      const steps = [
        createStep({ hasStairs: false, hasSlope: false, surfaceType: "paved" }),
        createStep({ hasStairs: false, hasSlope: false, surfaceType: "paved" }),
      ];

      const score = calculateRouteScore(steps, profile);
      expect(score).toBe(100);
    });

    // --- 車椅子ユーザー × 階段あり → 低スコア ---
    it("車椅子ユーザー × 階段ありルートで低スコアになること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs"],
      });
      const steps = [
        createStep({ hasStairs: true }),
        createStep({ hasStairs: true }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 階段2つ × 30ペナルティ = 60ペナルティ → スコア40
      expect(score).toBe(40);
    });

    it("車椅子ユーザー × 階段1つで中程度スコアになること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs"],
      });
      const steps = [
        createStep({ hasStairs: true }),
        createStep({ hasStairs: false }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 階段1つ × 30ペナルティ = 30ペナルティ → スコア70
      expect(score).toBe(70);
    });

    // --- ベビーカーユーザー × エレベーターありルート → 高スコア ---
    it("ベビーカーユーザー × 階段なし・舗装路で高スコアになること", () => {
      const profile = createProfile({
        mobilityType: "stroller",
        avoidConditions: ["stairs"],
      });
      const steps = [
        createStep({ hasStairs: false, hasSlope: false, surfaceType: "paved" }),
      ];

      const score = calculateRouteScore(steps, profile);
      expect(score).toBe(100);
    });

    // --- 急勾配ペナルティ ---
    it("勾配回避設定 × 急勾配(>8%)で大きなペナルティが適用されること", () => {
      const profile = createProfile({
        avoidConditions: ["slope"],
      });
      const steps = [
        createStep({ hasSlope: true, slopeGrade: 10 }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 急勾配(>8%) → 25ペナルティ → スコア75
      expect(score).toBe(75);
    });

    it("勾配回避設定 × 中程度勾配(5-8%)で中程度ペナルティが適用されること", () => {
      const profile = createProfile({
        avoidConditions: ["slope"],
      });
      const steps = [
        createStep({ hasSlope: true, slopeGrade: 7 }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 中程度勾配(5-8%) → 15ペナルティ → スコア85
      expect(score).toBe(85);
    });

    it("勾配回避設定 × 緩勾配(<5%)でペナルティなしであること", () => {
      const profile = createProfile({
        avoidConditions: ["slope"],
      });
      const steps = [
        createStep({ hasSlope: true, slopeGrade: 3 }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 緩勾配(<5%) → ペナルティなし → スコア100
      expect(score).toBe(100);
    });

    it("勾配回避設定 × ちょうど5%で中程度ペナルティが適用されること", () => {
      const profile = createProfile({
        avoidConditions: ["slope"],
      });
      const steps = [
        createStep({ hasSlope: true, slopeGrade: 5 }),
      ];

      const score = calculateRouteScore(steps, profile);
      // ちょうど5% → 中程度ペナルティ15 → スコア85
      expect(score).toBe(85);
    });

    // --- 未舗装路ペナルティ ---
    it("車椅子ユーザー × 未舗装路でペナルティが適用されること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
      });
      const steps = [
        createStep({ surfaceType: "gravel" }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 未舗装路ペナルティ 20 → スコア80
      expect(score).toBe(80);
    });

    it("ベビーカーユーザー × 未舗装路でペナルティが適用されること", () => {
      const profile = createProfile({
        mobilityType: "stroller",
      });
      const steps = [
        createStep({ surfaceType: "dirt" }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 未舗装路ペナルティ 20 → スコア80
      expect(score).toBe(80);
    });

    it("杖ユーザー × 未舗装路でペナルティが適用されないこと", () => {
      const profile = createProfile({
        mobilityType: "cane",
      });
      const steps = [
        createStep({ surfaceType: "gravel" }),
      ];

      const score = calculateRouteScore(steps, profile);
      // 杖ユーザーには未舗装路ペナルティなし
      expect(score).toBe(100);
    });

    it("通常歩行ユーザー × 未舗装路でペナルティが適用されないこと", () => {
      const profile = createProfile({
        mobilityType: "walk",
      });
      const steps = [
        createStep({ surfaceType: "dirt" }),
      ];

      const score = calculateRouteScore(steps, profile);
      expect(score).toBe(100);
    });

    // --- 複合ペナルティ ---
    it("車椅子ユーザー × 階段 + 急勾配 + 未舗装路の複合ペナルティ", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs", "slope"],
      });
      const steps = [
        createStep({ hasStairs: true }),                    // +30
        createStep({ hasSlope: true, slopeGrade: 10 }),     // +25
        createStep({ surfaceType: "gravel" }),               // +20
      ];

      const score = calculateRouteScore(steps, profile);
      // 合計ペナルティ: 30 + 25 + 20 = 75 → スコア25
      expect(score).toBe(25);
    });

    // --- スコアのクランプ ---
    it("ペナルティが 100 を超える場合スコア 0 にクランプされること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs", "slope"],
      });
      const steps = [
        createStep({ hasStairs: true }),  // +30
        createStep({ hasStairs: true }),  // +30
        createStep({ hasStairs: true }),  // +30
        createStep({ hasSlope: true, slopeGrade: 10 }),  // +25
      ];

      const score = calculateRouteScore(steps, profile);
      // 合計ペナルティ: 30+30+30+25 = 115 → クランプ → 0
      expect(score).toBe(0);
    });

    // --- avoidConditions 未設定時のテスト ---
    it("avoidConditions が空の場合、階段があってもペナルティなしであること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: [],
      });
      const steps = [
        createStep({ hasStairs: true }),
      ];

      const score = calculateRouteScore(steps, profile);
      // avoidConditions に stairs がないのでペナルティなし
      // ただし wheelchair × 未舗装チェックはステップに surfaceType 指定なし
      expect(score).toBe(100);
    });

    // --- 乗り換えペナルティ ---
    it("乗り換え2回以上でペナルティが適用されること", () => {
      const profile = createProfile({ mobilityType: "walk" });
      const transitDetail = {
        lineName: "JR中央線",
        vehicleType: "train" as const,
        departureStop: "東京",
        arrivalStop: "新宿",
        numStops: 5,
      };
      const steps = [
        createStep({ transitDetail }),
        createStep({ transitDetail }),
        createStep({ transitDetail }),
      ];

      const score = calculateRouteScore(steps, profile);
      // transitSteps=3, transferCount=2, 通常ユーザー: 2*10=20ペナルティ → スコア80
      expect(score).toBe(80);
    });

    it("車椅子ユーザーは乗り換えペナルティが大きくなること", () => {
      const profile = createProfile({ mobilityType: "wheelchair" });
      const transitDetail = {
        lineName: "JR中央線",
        vehicleType: "train" as const,
        departureStop: "東京",
        arrivalStop: "新宿",
        numStops: 5,
      };
      const steps = [
        createStep({ transitDetail }),
        createStep({ transitDetail }),
        createStep({ transitDetail }),
      ];

      const score = calculateRouteScore(steps, profile);
      // transferCount=2, wheelchair: 2*15=30ペナルティ → スコア70
      expect(score).toBe(70);
    });

    // --- nearbySpots ボーナス ---
    it("希望条件に合うスポットがある場合ボーナスが加算されること", () => {
      const profile = createProfile({
        preferConditions: ["restroom"],
      });
      const steps = [createStep()];
      const nearbySpots: SpotSummary[] = [
        {
          spotId: "spot-1",
          name: "トイレ",
          category: "restroom",
          location: { lat: 35.68, lng: 139.76 },
          accessibilityScore: 80,
          distanceMeters: 50,
          distanceFromRoute: 50,
          wheelchairAccessible: false,
        },
      ];

      const score = calculateRouteScore(steps, profile, nearbySpots);
      // ボーナス +5 → スコア100(ペナルティなし) → 100 (上限100なので変わらず)
      // ペナルティ付きで確認する
      expect(score).toBe(100);
    });

    it("ボーナスが15点を超えないこと（上限テスト）", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs"],
        preferConditions: ["restroom", "rest_area"],
      });
      const steps = [
        createStep({ hasStairs: true }), // -30ペナルティ
      ];
      const nearbySpots: SpotSummary[] = [
        { spotId: "s1", name: "トイレ1", category: "restroom", location: { lat: 35.68, lng: 139.76 }, accessibilityScore: 80, distanceMeters: 50, distanceFromRoute: 50, wheelchairAccessible: false },
        { spotId: "s2", name: "トイレ2", category: "restroom", location: { lat: 35.68, lng: 139.76 }, accessibilityScore: 80, distanceMeters: 50, distanceFromRoute: 50, wheelchairAccessible: false },
        { spotId: "s3", name: "休憩所1", category: "rest_area", location: { lat: 35.68, lng: 139.76 }, accessibilityScore: 80, distanceMeters: 50, distanceFromRoute: 50, wheelchairAccessible: false },
        { spotId: "s4", name: "公園1", category: "park", location: { lat: 35.68, lng: 139.76 }, accessibilityScore: 80, distanceMeters: 50, distanceFromRoute: 50, wheelchairAccessible: false },
      ];

      const score = calculateRouteScore(steps, profile, nearbySpots);
      // ペナルティ30, ボーナス: restroom*2(10) + rest_area(5) + park(5) = 20 → 上限15
      // 100 - 30 + 15 = 85
      expect(score).toBe(85);
    });

    it("ボーナスによりスコアが100を超えないこと", () => {
      const profile = createProfile({
        preferConditions: ["restroom"],
      });
      const steps = [createStep()]; // ペナルティなし
      const nearbySpots: SpotSummary[] = [
        { spotId: "s1", name: "トイレ", category: "restroom", location: { lat: 35.68, lng: 139.76 }, accessibilityScore: 80, distanceMeters: 50, distanceFromRoute: 50, wheelchairAccessible: false },
      ];

      const score = calculateRouteScore(steps, profile, nearbySpots);
      // 100 - 0 + 5 = 105 → クランプ → 100
      expect(score).toBe(100);
    });
  });

  // ============================
  // 重み付きルートスコア計算
  // ============================

  describe("calculateWeightedRouteScore", () => {
    it("同行者なしの場合、基本スコアと同じ値を返すこと", () => {
      const profile = createProfile({
        avoidConditions: ["stairs", "slope"],
        companions: [],
      });
      const steps = [
        createStep({ hasStairs: true }),  // stairsPenalty: 30
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      const basic = calculateRouteScore(steps, profile);
      // 同行者なし → 全重み1.0 → 基本スコアと同じ
      expect(weighted).toBe(basic);
    });

    it("車椅子同行者（disability）で階段ペナルティが増幅されること", () => {
      const profile = createProfile({
        avoidConditions: ["stairs"],
        companions: ["disability"],
      });
      const steps = [
        createStep({ hasStairs: true }),  // stairsPenalty: 30
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      // disability: stairsPenalty重み2.0 → 30*2.0=60 → 100-60=40
      expect(weighted).toBe(40);
    });

    it("高齢者同行で坂道ペナルティが増幅されること", () => {
      const profile = createProfile({
        avoidConditions: ["slope"],
        companions: ["elderly"],
      });
      const steps = [
        createStep({ hasSlope: true, slopeGrade: 10 }),  // slopePenalty: 25
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      // elderly: slopePenalty重み1.5 → 25*1.5=37.5 → 100-37.5=62.5 → round → 63
      expect(weighted).toBe(63);
    });

    it("高齢者同行で階段ペナルティも増幅されること", () => {
      const profile = createProfile({
        avoidConditions: ["stairs"],
        companions: ["elderly"],
      });
      const steps = [
        createStep({ hasStairs: true }),  // stairsPenalty: 30
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      // elderly: stairsPenalty重み1.5 → 30*1.5=45 → 100-45=55
      expect(weighted).toBe(55);
    });

    it("子供同行で各ペナルティが軽度に増幅されること", () => {
      const profile = createProfile({
        avoidConditions: ["stairs"],
        companions: ["child"],
      });
      const steps = [
        createStep({ hasStairs: true }),  // stairsPenalty: 30
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      // child: stairsPenalty重み1.3 → 30*1.3=39 → 100-39=61
      expect(weighted).toBe(61);
    });

    it("otherPenalty（未舗装路）に重み係数が適用されること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        companions: ["disability"],
      });
      const steps = [
        createStep({ surfaceType: "gravel" }),  // otherPenalty: 20
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      // disability: otherPenalty重み1.5 → 20*1.5=30 → 100-30=70
      expect(weighted).toBe(70);
    });

    it("複数の同行者がいる場合、最大の重みが適用されること", () => {
      const profile = createProfile({
        avoidConditions: ["stairs"],
        companions: ["child", "elderly", "disability"],
      });
      const steps = [
        createStep({ hasStairs: true }),  // stairsPenalty: 30
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      // disability の stairsPenalty重み2.0 が最大 → 30*2.0=60 → 100-60=40
      expect(weighted).toBe(40);
    });

    it("重み付きスコアも0-100にクランプされること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs", "slope"],
        companions: ["disability"],
      });
      const steps = [
        createStep({ hasStairs: true }),  // stairsPenalty: 30 * 2.0 = 60
        createStep({ hasStairs: true }),  // stairsPenalty: 30 * 2.0 = 60
      ];

      const weighted = calculateWeightedRouteScore(steps, profile);
      // 60+60=120 → 100-120=-20 → クランプ → 0
      expect(weighted).toBe(0);
    });

    it("ボーナスが重み付きスコアにも適用されること", () => {
      const profile = createProfile({
        avoidConditions: ["stairs"],
        companions: ["elderly"],
        preferConditions: ["restroom"],
      });
      const steps = [
        createStep({ hasStairs: true }),  // stairsPenalty: 30 * 1.5 = 45
      ];
      const nearbySpots: SpotSummary[] = [
        { spotId: "s1", name: "トイレ", category: "restroom", location: { lat: 35.68, lng: 139.76 }, accessibilityScore: 80, distanceMeters: 50, distanceFromRoute: 50, wheelchairAccessible: false },
      ];

      const weighted = calculateWeightedRouteScore(steps, profile, nearbySpots);
      // 100 - 45 + 5 = 60
      expect(weighted).toBe(60);
    });
  });

  // ============================
  // 警告メッセージ生成
  // ============================

  describe("generateWarnings", () => {
    it("障害物のないルートで警告が空であること", () => {
      const profile = createProfile();
      const steps = [createStep()];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toEqual([]);
    });

    // --- 車椅子ユーザーへの階段警告 ---
    it("車椅子ユーザーに階段警告が出ること（avoidConditions なし）", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: [],
      });
      const steps = [createStep({ hasStairs: true })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("階段");
      expect(warnings[0]).toContain("車椅子");
    });

    it("車椅子ユーザー × avoidConditions に stairs ありで汎用階段警告が出ること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs"],
      });
      const steps = [
        createStep({ hasStairs: true }),
        createStep({ hasStairs: true }),
      ];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("2箇所の階段");
    });

    // --- ベビーカーユーザーへの階段警告 ---
    it("ベビーカーユーザーに階段警告が出ること", () => {
      const profile = createProfile({
        mobilityType: "stroller",
        avoidConditions: [],
      });
      const steps = [createStep({ hasStairs: true })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("階段");
      expect(warnings[0]).toContain("ベビーカー");
    });

    // --- 杖使用者への階段・坂道警告 ---
    it("杖使用者に階段警告が出ること", () => {
      const profile = createProfile({
        mobilityType: "cane",
        avoidConditions: [],
      });
      const steps = [createStep({ hasStairs: true })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("階段");
      expect(warnings[0]).toContain("杖");
    });

    it("杖使用者に急坂警告が出ること", () => {
      const profile = createProfile({
        mobilityType: "cane",
        avoidConditions: [],
      });
      const steps = [createStep({ hasSlope: true, slopeGrade: 10 })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("急な坂道");
      expect(warnings[0]).toContain("杖");
    });

    // --- 高齢者同行時の警告 ---
    it("高齢者同行で階段警告が出ること（avoidConditions なし）", () => {
      const profile = createProfile({
        companions: ["elderly"],
        avoidConditions: [],
      });
      const steps = [createStep({ hasStairs: true })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("階段");
      expect(warnings[0]).toContain("同行者");
    });

    it("高齢者同行で急坂警告が出ること（avoidConditions なし）", () => {
      const profile = createProfile({
        companions: ["elderly"],
        avoidConditions: [],
      });
      const steps = [createStep({ hasSlope: true, slopeGrade: 10 })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("急な坂道");
      expect(warnings[0]).toContain("同行者");
    });

    // --- 障がい者同行時の警告 ---
    it("障がい者同行で階段警告が出ること", () => {
      const profile = createProfile({
        companions: ["disability"],
        avoidConditions: [],
      });
      const steps = [createStep({ hasStairs: true })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("階段");
      expect(warnings[0]).toContain("同行者");
    });

    it("障がい者同行で急坂警告が出ること", () => {
      const profile = createProfile({
        companions: ["disability"],
        avoidConditions: [],
      });
      const steps = [createStep({ hasSlope: true, slopeGrade: 10 })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("急な坂道");
      expect(warnings[0]).toContain("同行者");
    });

    // --- 乗り換え警告 ---
    it("乗り換え2回以上で警告が出ること", () => {
      const profile = createProfile();
      const transitDetail = {
        lineName: "JR中央線",
        vehicleType: "train" as const,
        departureStop: "東京",
        arrivalStop: "新宿",
        numStops: 5,
      };
      const steps = [
        createStep({ transitDetail }),
        createStep({ transitDetail }),
        createStep({ transitDetail }),
      ];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("2回の乗り換え");
    });

    it("乗り換え1回では警告が出ないこと", () => {
      const profile = createProfile();
      const transitDetail = {
        lineName: "JR中央線",
        vehicleType: "train" as const,
        departureStop: "東京",
        arrivalStop: "新宿",
        numStops: 5,
      };
      const steps = [
        createStep({ transitDetail }),
        createStep({ transitDetail }),
      ];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toEqual([]);
    });

    // --- 未舗装路警告 ---
    it("車椅子ユーザーに未舗装路警告が出ること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
      });
      const steps = [createStep({ surfaceType: "gravel" })];

      const warnings = generateWarnings(steps, profile);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("未舗装");
    });

    // --- 複合警告 ---
    it("階段 + 急坂 + 未舗装 + 乗り換えで複数の警告が出ること", () => {
      const profile = createProfile({
        mobilityType: "wheelchair",
        avoidConditions: ["stairs", "slope"],
      });
      const transitDetail = {
        lineName: "JR中央線",
        vehicleType: "train" as const,
        departureStop: "東京",
        arrivalStop: "新宿",
        numStops: 5,
      };
      const steps = [
        createStep({ hasStairs: true }),
        createStep({ hasSlope: true, slopeGrade: 10 }),
        createStep({ surfaceType: "gravel" }),
        createStep({ transitDetail }),
        createStep({ transitDetail }),
        createStep({ transitDetail }),
      ];

      const warnings = generateWarnings(steps, profile);
      // 階段、急坂、未舗装、乗り換え の4つの警告
      expect(warnings.length).toBeGreaterThanOrEqual(4);
      expect(warnings.some((w) => w.includes("階段"))).toBe(true);
      expect(warnings.some((w) => w.includes("急な坂道"))).toBe(true);
      expect(warnings.some((w) => w.includes("未舗装"))).toBe(true);
      expect(warnings.some((w) => w.includes("乗り換え"))).toBe(true);
    });

    // --- 勾配8%以下では急坂警告が出ないこと ---
    it("勾配8%以下では急坂警告が出ないこと", () => {
      const profile = createProfile({
        avoidConditions: ["slope"],
      });
      const steps = [createStep({ hasSlope: true, slopeGrade: 7 })];

      const warnings = generateWarnings(steps, profile);
      // generateWarnings は >8% のみを急坂としてカウントする
      expect(warnings).toEqual([]);
    });
  });

  // ============================
  // スポットスコア計算
  // ============================

  describe("calculateSpotScore", () => {
    // 基本スコア検証
    it("基準スコアが 50 であること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "mixed",
      };
      const profile = createProfile();

      const score = calculateSpotScore(accessibility, profile);
      expect(score).toBe(50);
    });

    // 車椅子ユーザー × 車椅子対応スポット
    it("車椅子ユーザー × 車椅子対応で +20 加算されること", () => {
      const accessibility = {
        wheelchairAccessible: true,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "mixed",
      };
      const profile = createProfile({ mobilityType: "wheelchair" });

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 20 = 70
      expect(score).toBe(70);
    });

    // 非車椅子ユーザー × 車椅子対応スポット
    it("非車椅子ユーザー × 車椅子対応で +10 加算されること", () => {
      const accessibility = {
        wheelchairAccessible: true,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "mixed",
      };
      const profile = createProfile({ mobilityType: "walk" });

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 10 = 60
      expect(score).toBe(60);
    });

    // エレベーターあり
    it("エレベーターありで +10 加算されること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: true,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "mixed",
      };
      const profile = createProfile();

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 10 = 60
      expect(score).toBe(60);
    });

    // バリアフリートイレ
    it("バリアフリートイレありで +10 加算されること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: true,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "mixed",
      };
      const profile = createProfile();

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 10 = 60
      expect(score).toBe(60);
    });

    // 子連れ × おむつ交換台
    it("子連れ × おむつ交換台ありで +10 加算されること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: true,
        hasNursingRoom: false,
        floorType: "mixed",
      };
      const profile = createProfile({ companions: ["child"] });

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 10 = 60
      expect(score).toBe(60);
    });

    // 子連れでない × おむつ交換台
    it("子連れでない × おむつ交換台ありで加算なしであること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: true,
        hasNursingRoom: false,
        floorType: "mixed",
      };
      const profile = createProfile({ companions: [] });

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 0 = 50（子連れでないので加算なし）
      expect(score).toBe(50);
    });

    // 子連れ × 授乳室
    it("子連れ × 授乳室ありで +10 加算されること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: true,
        floorType: "mixed",
      };
      const profile = createProfile({ companions: ["child"] });

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 10 = 60
      expect(score).toBe(60);
    });

    // フラットな床
    it("フラットな床で +10 加算されること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "flat",
      };
      const profile = createProfile();

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 10 = 60
      expect(score).toBe(60);
    });

    // 階段のある床
    it("階段のある床で -20 減算されること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "steps",
      };
      const profile = createProfile();

      const score = calculateSpotScore(accessibility, profile);
      // 50 - 20 = 30
      expect(score).toBe(30);
    });

    // --- ベビーカーユーザー × フル装備スポット → 高スコア ---
    it("ベビーカーユーザー × エレベーター・おむつ台・授乳室・フラットで高スコアになること", () => {
      const accessibility = {
        wheelchairAccessible: true,
        hasElevator: true,
        hasAccessibleRestroom: true,
        hasBabyChangingStation: true,
        hasNursingRoom: true,
        floorType: "flat",
      };
      const profile = createProfile({
        mobilityType: "stroller",
        companions: ["child"],
      });

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 10(wheelchair非wheelchair) + 10(elevator) + 10(restroom) + 10(baby) + 10(nursing) + 10(flat) = 100
      expect(score).toBe(100);
    });

    // --- 車椅子ユーザー × フル装備スポット → 最高スコア ---
    it("車椅子ユーザー × フル装備スポットで最高スコア（クランプ100）になること", () => {
      const accessibility = {
        wheelchairAccessible: true,
        hasElevator: true,
        hasAccessibleRestroom: true,
        hasBabyChangingStation: true,
        hasNursingRoom: true,
        floorType: "flat",
      };
      const profile = createProfile({
        mobilityType: "wheelchair",
        companions: ["child"],
      });

      const score = calculateSpotScore(accessibility, profile);
      // 50 + 20(wheelchair) + 10(elevator) + 10(restroom) + 10(baby) + 10(nursing) + 10(flat) = 120 → クランプ → 100
      expect(score).toBe(100);
    });

    // --- 最低スコアのケース ---
    it("設備なし × 階段ありで最低スコアになること", () => {
      const accessibility = {
        wheelchairAccessible: false,
        hasElevator: false,
        hasAccessibleRestroom: false,
        hasBabyChangingStation: false,
        hasNursingRoom: false,
        floorType: "steps",
      };
      const profile = createProfile();

      const score = calculateSpotScore(accessibility, profile);
      // 50 - 20 = 30
      expect(score).toBe(30);
    });
  });
});
