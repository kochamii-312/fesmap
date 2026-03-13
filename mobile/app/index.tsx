import { useEffect, useState } from 'react';
import { ActivityIndicator, View, StyleSheet } from 'react-native';
import { Redirect } from 'expo-router';
import { isAuthenticated } from '../src/services/auth';

export default function Index() {
  const [authState, setAuthState] = useState<boolean | null>(null);

  useEffect(() => {
    isAuthenticated()
      .then(setAuthState)
      .catch(() => setAuthState(false));
  }, []);

  if (authState === null) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color="#007AFF" />
      </View>
    );
  }

  // 認証状態に関わらず、タブ画面に遷移（現在地取得の動作確認用）
  return <Redirect href="/(tabs)" />;
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#f5f5f5',
  },
});
