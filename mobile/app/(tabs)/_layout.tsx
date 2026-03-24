import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: '#007AFF',
        headerStyle: { backgroundColor: '#007AFF' },
        headerTintColor: '#fff',
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'ホーム',
          tabBarIcon: ({ color, size }) => <Ionicons name="map" size={size} color={color} />,
          headerTitle: 'フェスマップ',
        }}
      />
      <Tabs.Screen
        name="route"
        options={{
          title: 'ルート',
          tabBarIcon: ({ color, size }) => <Ionicons name="navigate" size={size} color={color} />,
          headerTitle: 'ルート検索',
        }}
      />
      <Tabs.Screen
        name="chat"
        options={{
          title: 'チャット',
          tabBarIcon: ({ color, size }) => <Ionicons name="chatbubbles" size={size} color={color} />,
          headerTitle: 'AIチャット',
        }}
      />
      <Tabs.Screen
        name="spots"
        options={{
          title: 'スポット',
          tabBarIcon: ({ color, size }) => <Ionicons name="location" size={size} color={color} />,
          headerTitle: 'スポット検索',
        }}
      />
      <Tabs.Screen
        name="ProfileScreen"
        options={{
          title: '設定',
          tabBarIcon: ({ color, size }) => <Ionicons name="settings" size={size} color={color} />,
          headerTitle: 'プロファイル設定',
        }}
      />
    </Tabs>
  );
}
