import React, { useState, useCallback, useRef, useMemo, forwardRef, useImperativeHandle, useEffect } from 'react';
import { View, Text, StyleSheet, ViewStyle } from 'react-native';
import { WebView } from 'react-native-webview';

const GOOGLE_MAPS_API_KEY = process.env.EXPO_PUBLIC_GOOGLE_MAPS_API_KEY || '';

// WebView DirectionsService から返される結果の型定義
export interface DirectionsResult {
  routes: Array<{
    legs: Array<{
      distance: { value: number; text: string };
      duration: { value: number; text: string };
      departure_time?: { text: string; value: number };
      arrival_time?: { text: string; value: number };
      start_address: string;
      end_address: string;
      start_location?: { lat: number; lng: number };
      end_location?: { lat: number; lng: number };
      steps: Array<{
        instruction: string;
        distance: { value: number };
        duration: { value: number };
        start_location: { lat: number; lng: number };
        end_location: { lat: number; lng: number };
        travel_mode: string;
        transit_details?: {
          line: { name: string; short_name?: string; color?: string; vehicle: { type: string } };
          departure_stop: { name: string };
          arrival_stop: { name: string };
          departure_time?: { text: string };
          arrival_time?: { text: string };
          num_stops: number;
          headsign?: string;
        };
        polyline?: { points: string };
      }>;
    }>;
    overview_polyline?: { points: string };
    fare?: { text: string };
  }>;
  status: string;
  type?: string;
}

export type Region = {
  latitude: number;
  longitude: number;
  latitudeDelta: number;
  longitudeDelta: number;
};

type MarkerProps = {
  coordinate: { latitude: number; longitude: number };
  title?: string;
  description?: string;
  pinColor?: string;
  children?: React.ReactNode;
};

// ルートの座標配列
export type RouteCoordinate = {
  latitude: number;
  longitude: number;
};

// ルート表示用のデータ（マルチモーダル対応）
export type RouteData = {
  id: string;
  coordinates: RouteCoordinate[];
  color?: string;
  width?: number;
  selected?: boolean;
  mode?: 'walking' | 'transit' | 'driving' | 'bicycling';
  dashed?: boolean; // 徒歩区間の点線表示
};

// 乗り換え地点マーカー
type WaypointMarker = {
  latitude: number;
  longitude: number;
  title?: string;
  label?: string; // 路線名ラベル（例: "山手線 → 中央線"）
  mode?: 'walking' | 'transit' | 'driving' | 'bicycling';
};

// 地図初期化時に自動実行するDirections検索リクエスト
export type DirectionsRequest = {
  originLat: number;
  originLng: number;
  destLat: number;
  destLng: number;
  mode: string; // 'walking' | 'transit' | 'driving' | 'bicycling'
};

type MapViewProps = {
  style?: ViewStyle;
  initialRegion?: Region;
  region?: Region; // 動的に地図の中心を移動する
  onRegionChangeComplete?: (region: Region) => void;
  onRouteSelect?: (routeId: string) => void;
  onDirectionsResult?: (result: DirectionsResult) => void;
  showsUserLocation?: boolean;
  showsMyLocationButton?: boolean;
  userLocationCoords?: { latitude: number; longitude: number }; // 既知の現在地座標（GPS取得済み）
  accessibilityLabel?: string;
  routes?: RouteData[];
  originMarker?: { latitude: number; longitude: number; title?: string };
  destinationMarker?: { latitude: number; longitude: number; title?: string };
  waypointMarkers?: WaypointMarker[];
  fitToRoute?: boolean;
  directionsRequest?: DirectionsRequest; // 地図ロード時に自動でDirections検索を実行
  children?: React.ReactNode;
};

function collectMarkers(children: React.ReactNode): MarkerProps[] {
  const markers: MarkerProps[] = [];
  React.Children.forEach(children, (child) => {
    if (React.isValidElement<MarkerProps>(child) && child.props?.coordinate) {
      markers.push(child.props);
    }
  });
  return markers;
}

// HTML特殊文字をエスケープ（XSS防止）
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// JavaScript文字列リテラル内で安全に使えるようエスケープ
function escapeJsString(str: string): string {
  return str
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/<\//g, '<\\/');
}

function pinColorToHex(pinColor?: string): string {
  const colorMap: Record<string, string> = {
    red: '#FF0000',
    green: '#00AA00',
    orange: '#FF8800',
    blue: '#0066FF',
    purple: '#9900CC',
    yellow: '#FFCC00',
  };
  if (!pinColor) return '#FF0000';
  if (pinColor.startsWith('#')) return pinColor;
  return colorMap[pinColor.toLowerCase()] || '#FF0000';
}

function getZoomLevel(latDelta: number): number {
  if (latDelta <= 0.002) return 17;
  if (latDelta <= 0.005) return 16;
  if (latDelta <= 0.01) return 15;
  if (latDelta <= 0.02) return 14;
  if (latDelta <= 0.05) return 13;
  if (latDelta <= 0.1) return 12;
  if (latDelta <= 0.3) return 11;
  return 10;
}

// モード別のデフォルト色を返す
function getModeColor(mode?: string, fallbackColor?: string): string {
  switch (mode) {
    case 'walking':
      return '#888888';
    case 'transit':
      return fallbackColor || '#9900CC';
    case 'driving':
      return '#0066FF';
    case 'bicycling':
      return '#FF8800';
    default:
      return fallbackColor || '#4285F4';
  }
}

// モード別のデフォルト線幅を返す
function getModeWidth(mode?: string, fallbackWidth?: number, selected?: boolean): number {
  const base = (() => {
    switch (mode) {
      case 'walking':
        return fallbackWidth || 4;
      case 'transit':
        return fallbackWidth || 7;
      case 'driving':
        return fallbackWidth || 5;
      case 'bicycling':
        return fallbackWidth || 5;
      default:
        return fallbackWidth || 5;
    }
  })();
  return selected ? base + 1 : base;
}

// ウェイポイントマーカー色をモードから取得
function getWaypointColor(mode?: string): string {
  switch (mode) {
    case 'walking':
      return '#888888';
    case 'transit':
      return '#9900CC';
    case 'driving':
      return '#0066FF';
    case 'bicycling':
      return '#FF8800';
    default:
      return '#666666';
  }
}

function buildMapHtml(
  region: Region,
  markers: MarkerProps[],
  showsUserLocation: boolean,
  showsMyLocationButton: boolean,
  routes?: RouteData[],
  originMarker?: { latitude: number; longitude: number; title?: string },
  destinationMarker?: { latitude: number; longitude: number; title?: string },
  fitToRoute?: boolean,
  waypointMarkers?: WaypointMarker[],
  directionsRequest?: DirectionsRequest,
  userLocationCoords?: { latitude: number; longitude: number },
): string {
  const markersJs = markers
    .map(
      (m) => `
      (function() {
        var marker = new google.maps.Marker({
          position: { lat: ${m.coordinate.latitude}, lng: ${m.coordinate.longitude} },
          map: map,
          title: ${JSON.stringify(m.title || '')},
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: 10,
            fillColor: '${pinColorToHex(m.pinColor)}',
            fillOpacity: 1,
            strokeColor: '#FFFFFF',
            strokeWeight: 2,
          }
        });
        ${
          m.title || m.description
            ? `
        var infowindow = new google.maps.InfoWindow({
          content: '<div style="font-size:14px;"><strong>${escapeHtml(m.title || '')}</strong>${m.description ? '<br/>' + escapeHtml(m.description) : ''}</div>'
        });
        marker.addListener('click', function() {
          infowindow.open(map, marker);
        });
        `
            : ''
        }
      })();`
    )
    .join('\n');

  // Origin marker (green pin) - skip if coordinates are (0,0)
  const originMarkerJs = originMarker && !(originMarker.latitude === 0 && originMarker.longitude === 0)
    ? `
    (function() {
      var originIcon = {
        path: 'M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z',
        fillColor: '#00AA00',
        fillOpacity: 1,
        strokeColor: '#FFFFFF',
        strokeWeight: 2,
        scale: 2,
        anchor: new google.maps.Point(12, 22),
      };
      new google.maps.Marker({
        position: { lat: ${originMarker.latitude}, lng: ${originMarker.longitude} },
        map: map,
        icon: originIcon,
        title: ${JSON.stringify(originMarker.title || '出発地')},
        zIndex: 1000,
      });
    })();
    `
    : '';

  // Destination marker (red pin) - skip if coordinates are (0,0)
  const destinationMarkerJs = destinationMarker && !(destinationMarker.latitude === 0 && destinationMarker.longitude === 0)
    ? `
    (function() {
      var destIcon = {
        path: 'M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z',
        fillColor: '#FF3B30',
        fillOpacity: 1,
        strokeColor: '#FFFFFF',
        strokeWeight: 2,
        scale: 2,
        anchor: new google.maps.Point(12, 22),
      };
      new google.maps.Marker({
        position: { lat: ${destinationMarker.latitude}, lng: ${destinationMarker.longitude} },
        map: map,
        icon: destIcon,
        title: ${JSON.stringify(destinationMarker.title || '目的地')},
        zIndex: 1000,
      });
    })();
    `
    : '';

  // マルチモーダル対応ルートポリライン描画
  const routesJs = (routes && routes.length > 0)
    ? routes
        .map((route) => {
          const isWalking = route.mode === 'walking' || route.dashed;
          const color = route.color || getModeColor(route.mode);
          const selectedColor = route.selected ? color : '#AAAAAA';
          const opacity = route.selected ? 1.0 : 0.5;
          const width = getModeWidth(route.mode, route.width, route.selected);
          const zIndex = route.selected ? 100 : 10;
          const filteredCoords = route.coordinates.filter((c) => !(c.latitude === 0 && c.longitude === 0));
          const pathJs = filteredCoords.map((c) => `{lat:${c.latitude},lng:${c.longitude}}`).join(',');

          const safeRouteId = escapeJsString(route.id);

          if (isWalking) {
            // 徒歩区間: 点線パターン（SymbolPath.CIRCLE を繰り返す）
            return `
      (function() {
        var path = [${pathJs}];
        var polyline = new google.maps.Polyline({
          path: path,
          strokeOpacity: 0,
          icons: [{
            icon: {
              path: google.maps.SymbolPath.CIRCLE,
              scale: 3,
              fillColor: '${selectedColor}',
              fillOpacity: ${opacity},
              strokeWeight: 0,
            },
            offset: '0',
            repeat: '12px'
          }],
          map: map,
          zIndex: ${zIndex},
        });
        polyline.addListener('click', function() {
          window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'routeSelect', routeId: '${safeRouteId}' }));
        });
      })();`;
          }

          // 通常のポリライン（transit, driving, bicycling, デフォルト）
          return `
      (function() {
        var path = [${pathJs}];
        var polyline = new google.maps.Polyline({
          path: path,
          strokeColor: '${selectedColor}',
          strokeOpacity: ${opacity},
          strokeWeight: ${width},
          map: map,
          zIndex: ${zIndex},
        });
        polyline.addListener('click', function() {
          window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'routeSelect', routeId: '${safeRouteId}' }));
        });
      })();`;
        })
        .join('\n')
    : '';

  // ウェイポイントマーカー（乗り換え地点）
  const waypointMarkersJs = (waypointMarkers && waypointMarkers.length > 0)
    ? waypointMarkers
        .map((wp) => {
          const wpColor = getWaypointColor(wp.mode);
          const safeTitle = escapeHtml(wp.title || '');
          const safeLabel = escapeHtml(wp.label || '');
          // ラベルがある場合は駅名の下に路線名を小さく表示
          const infoContent = wp.label
            ? `<div style="font-size:12px;padding:2px 6px;white-space:nowrap;"><strong>${safeTitle}</strong><br/><span style="font-size:10px;color:#666;">${safeLabel}</span></div>`
            : `<div style="font-size:12px;padding:2px 4px;white-space:nowrap;"><strong>${safeTitle}</strong></div>`;
          return `
      (function() {
        var wpMarker = new google.maps.Marker({
          position: { lat: ${wp.latitude}, lng: ${wp.longitude} },
          map: map,
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: 7,
            fillColor: '${wpColor}',
            fillOpacity: 1,
            strokeColor: '#FFFFFF',
            strokeWeight: 2,
          },
          title: ${JSON.stringify(wp.title || '乗り換え')},
          zIndex: 500,
        });
        ${wp.title ? `
        var wpInfo = new google.maps.InfoWindow({
          content: ${JSON.stringify(infoContent)}
        });
        wpMarker.addListener('click', function() {
          wpInfo.open(map, wpMarker);
        });
        ` : ''}
      })();`;
        })
        .join('\n')
    : '';

  // Fit bounds to routes + waypoints
  const fitBoundsJs = (fitToRoute && routes && routes.length > 0)
    ? `
    (function() {
      var bounds = new google.maps.LatLngBounds();
      ${(() => {
        // selected なルートがあればそのすべてを対象にする（マルチモーダルの全区間を包含）
        const selectedRoutes = routes.filter((r) => r.selected);
        return selectedRoutes.length > 0 ? selectedRoutes : (routes.length > 0 ? [routes[0]] : []);
      })()
        .map(
          (route) =>
            route.coordinates
              .filter((c) => !(c.latitude === 0 && c.longitude === 0))
              .map((c) => `bounds.extend({lat:${c.latitude},lng:${c.longitude}});`)
              .join('\n')
        )
        .join('\n')}
      ${originMarker && !(originMarker.latitude === 0 && originMarker.longitude === 0) ? `bounds.extend({lat:${originMarker.latitude},lng:${originMarker.longitude}});` : ''}
      ${destinationMarker && !(destinationMarker.latitude === 0 && destinationMarker.longitude === 0) ? `bounds.extend({lat:${destinationMarker.latitude},lng:${destinationMarker.longitude}});` : ''}
      ${(waypointMarkers || []).filter((wp) => !(wp.latitude === 0 && wp.longitude === 0)).map((wp) => `bounds.extend({lat:${wp.latitude},lng:${wp.longitude}});`).join('\n')}
      if (!bounds.isEmpty()) {
        map.fitBounds(bounds, { top: 60, bottom: 60, left: 40, right: 40 });
      }
    })();
    `
    : '';

  // If no routes but origin + destination, fit bounds to markers
  const fitMarkersJs = (fitToRoute && (!routes || routes.length === 0) && originMarker && destinationMarker)
    ? `
    (function() {
      var bounds = new google.maps.LatLngBounds();
      ${!(originMarker.latitude === 0 && originMarker.longitude === 0) ? `bounds.extend({lat:${originMarker.latitude},lng:${originMarker.longitude}});` : ''}
      ${!(destinationMarker.latitude === 0 && destinationMarker.longitude === 0) ? `bounds.extend({lat:${destinationMarker.latitude},lng:${destinationMarker.longitude}});` : ''}
      ${(waypointMarkers || []).filter((wp) => !(wp.latitude === 0 && wp.longitude === 0)).map((wp) => `bounds.extend({lat:${wp.latitude},lng:${wp.longitude}});`).join('\n')}
      if (!bounds.isEmpty()) {
        map.fitBounds(bounds, { top: 60, bottom: 60, left: 40, right: 40 });
      }
    })();
    `
    : '';

  return `<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; }
    html, body, #map { width: 100%; height: 100%; }
    .gm-style-iw-d { overflow: hidden !important; }
    .gm-style-iw { padding: 0 !important; }
    .gm-ui-hover-effect { display: none !important; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map;
    var pendingDirectionsRequest = false;
    window._spotMarkers = [];
    function initMap() {
      map = new google.maps.Map(document.getElementById('map'), {
        center: { lat: ${region.latitude}, lng: ${region.longitude} },
        zoom: ${getZoomLevel(region.latitudeDelta)},
        disableDefaultUI: true,
        zoomControl: true,
        gestureHandling: 'greedy',
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false,
        styles: [
          { featureType: 'transit', stylers: [{ visibility: 'on' }] },
          { featureType: 'poi', elementType: 'labels', stylers: [{ visibility: 'off' }] },
        ],
      });

      ${markersJs}
      ${routesJs}
      ${waypointMarkersJs}
      ${originMarkerJs}
      ${destinationMarkerJs}
      ${fitBoundsJs}
      ${fitMarkersJs}

      ${
        showsUserLocation
          ? `
      // 現在地の青い丸を表示する関数
      function showUserLocationMarker(userPos) {
        // 外側のパルスリング（アニメーション）
        var pulseCircle = new google.maps.Circle({
          center: userPos,
          radius: 30,
          map: map,
          fillColor: '#4285F4',
          fillOpacity: 0.15,
          strokeColor: '#4285F4',
          strokeOpacity: 0.3,
          strokeWeight: 1,
          zIndex: 998,
        });

        // 内側の青い丸（現在地マーカー）
        new google.maps.Marker({
          position: userPos,
          map: map,
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: 8,
            fillColor: '#4285F4',
            fillOpacity: 1,
            strokeColor: '#FFFFFF',
            strokeWeight: 3,
          },
          title: '現在地',
          zIndex: 999,
        });

        // パルスアニメーション
        var growing = true;
        setInterval(function() {
          var r = pulseCircle.getRadius();
          if (growing) {
            r += 2;
            if (r >= 60) growing = false;
          } else {
            r -= 2;
            if (r <= 30) growing = true;
          }
          pulseCircle.setRadius(r);
        }, 50);
      }

      ${userLocationCoords
        ? `
      // 既知の座標を使って即座に現在地を表示・ズーム
      (function() {
        var userPos = { lat: ${userLocationCoords.latitude}, lng: ${userLocationCoords.longitude} };
        showUserLocationMarker(userPos);
        map.panTo(userPos);
        map.setZoom(16);
      })();
      `
        : `
      // GPS座標未取得の場合はWebView内で取得を試みる
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(function(pos) {
          var userPos = { lat: pos.coords.latitude, lng: pos.coords.longitude };
          showUserLocationMarker(userPos);
          map.panTo(userPos);
          map.setZoom(16);
        });
      }
      `}
      `
          : ''
      }

      ${
        showsMyLocationButton && showsUserLocation
          ? `
      (function() {
        var locationBtn = document.createElement('button');
        locationBtn.textContent = '📍';
        locationBtn.style.cssText = 'position:absolute;bottom:20px;right:20px;width:44px;height:44px;border-radius:22px;background:#fff;border:1px solid #ccc;font-size:20px;cursor:pointer;box-shadow:0 2px 6px rgba(0,0,0,0.3);z-index:1000;';
        locationBtn.setAttribute('aria-label', '現在地に移動');
        document.body.appendChild(locationBtn);
        locationBtn.addEventListener('click', function() {
          if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(function(pos) {
              map.panTo({ lat: pos.coords.latitude, lng: pos.coords.longitude });
              map.setZoom(16);
            });
          }
        });
      })();
      `
          : ''
      }

      // WebView内のJSエラーをReact Nativeに通知
      window.onerror = function(msg, url, line, col, error) {
        window.ReactNativeWebView.postMessage(JSON.stringify({
          type: 'jsError',
          message: msg,
          line: line,
          col: col,
          stack: error ? error.stack : ''
        }));
        return false;
      };

      map.addListener('idle', function() {
        var center = map.getCenter();
        var bounds = map.getBounds();
        if (center && bounds) {
          var ne = bounds.getNorthEast();
          var sw = bounds.getSouthWest();
          var region = {
            latitude: center.lat(),
            longitude: center.lng(),
            latitudeDelta: ne.lat() - sw.lat(),
            longitudeDelta: ne.lng() - sw.lng(),
          };
          window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'regionChange', region: region }));
        }
      });

      // React Native からの経路検索メッセージを受信するリスナー
      document.addEventListener('message', function(e) {
        try {
          var msg = JSON.parse(e.data);
          if (msg.type === 'searchDirections') {
            searchDirections(msg.originLat, msg.originLng, msg.destLat, msg.destLng, msg.mode, msg.departureTime);
          }
        } catch(err) { console.warn('[MapView] Message parse error:', err); }
      });

      // 自動Directions検索（directionsRequestが指定されている場合）
      ${directionsRequest ? `
      setTimeout(function() {
        searchDirections(${directionsRequest.originLat}, ${directionsRequest.originLng}, ${directionsRequest.destLat}, ${directionsRequest.destLng}, '${escapeJsString(directionsRequest.mode)}', null);
      }, 500);
      ` : ''}
    }

    // Google Maps DirectionsService を使った経路検索
    // WebView 内で実行し、結果を ReactNativeWebView.postMessage で返す
    function searchDirections(originLat, originLng, destLat, destLng, mode, departureTime) {
      if (pendingDirectionsRequest) return;
      pendingDirectionsRequest = true;
      var directionsService = new google.maps.DirectionsService();
      var validModes = {'WALKING':1,'TRANSIT':1,'DRIVING':1,'BICYCLING':1};
      var upperMode = mode.toUpperCase();
      if (!validModes[upperMode]) upperMode = 'TRANSIT';
      var request = {
        origin: new google.maps.LatLng(originLat, originLng),
        destination: new google.maps.LatLng(destLat, destLng),
        travelMode: google.maps.TravelMode[upperMode],
        provideRouteAlternatives: true,
        unitSystem: google.maps.UnitSystem.METRIC,
        language: 'ja',
      };
      if (mode === 'transit' && departureTime) {
        request.transitOptions = { departureTime: new Date(departureTime * 1000) };
      } else if (mode === 'transit') {
        request.transitOptions = { departureTime: new Date() };
      }

      directionsService.route(request, function(result, status) {
        pendingDirectionsRequest = false;
        var response = { type: 'directionsResult', status: status, requestedMode: mode };
        if (status === 'ZERO_RESULTS' && upperMode !== 'WALKING' && upperMode !== 'TRANSIT') {
          // driving/bicycling で結果なし → walking で自動リトライ
          // transit は自前ルーターを使用するためリトライしない
          window.ReactNativeWebView.postMessage(JSON.stringify({
            type: 'jsError',
            message: mode + ' returned ZERO_RESULTS, retrying with WALKING'
          }));
          searchDirections(originLat, originLng, destLat, destLng, 'walking', null);
          return;
        }
        if (status !== 'OK') {
          window.ReactNativeWebView.postMessage(JSON.stringify({
            type: 'jsError',
            message: 'DirectionsService error: ' + status + ' (mode: ' + mode + ')'
          }));
          window.ReactNativeWebView.postMessage(JSON.stringify(response));
          return;
        }
        try {
          response.routes = result.routes.map(function(route) {
            return {
              legs: route.legs.map(function(leg) {
                var legDist = leg.distance || {};
                var legDur = leg.duration || {};
                return {
                  distance: { value: legDist.value || 0, text: legDist.text || '' },
                  duration: { value: legDur.value || 0, text: legDur.text || '' },
                  departure_time: leg.departure_time ? { text: leg.departure_time.text || '', value: leg.departure_time.value || 0 } : undefined,
                  arrival_time: leg.arrival_time ? { text: leg.arrival_time.text || '', value: leg.arrival_time.value || 0 } : undefined,
                  start_address: leg.start_address || '',
                  end_address: leg.end_address || '',
                  start_location: leg.start_location ? { lat: leg.start_location.lat(), lng: leg.start_location.lng() } : { lat: 0, lng: 0 },
                  end_location: leg.end_location ? { lat: leg.end_location.lat(), lng: leg.end_location.lng() } : { lat: 0, lng: 0 },
                  steps: (leg.steps || []).map(function(step) {
                    var stepData = {
                      instruction: step.instructions || '',
                      distance: { value: step.distance ? step.distance.value : 0 },
                      duration: { value: step.duration ? step.duration.value : 0 },
                      start_location: step.start_location ? { lat: step.start_location.lat(), lng: step.start_location.lng() } : { lat: 0, lng: 0 },
                      end_location: step.end_location ? { lat: step.end_location.lat(), lng: step.end_location.lng() } : { lat: 0, lng: 0 },
                      travel_mode: step.travel_mode || '',
                    };
                    try {
                      if (step.transit) {
                        var line = (step.transit.line || {});
                        var vehicle = (line.vehicle || {});
                        stepData.transit_details = {
                          line: {
                            name: line.name || '',
                            short_name: line.short_name || '',
                            color: line.color || '',
                            vehicle: { type: vehicle.type || 'OTHER' }
                          },
                          departure_stop: { name: (step.transit.departure_stop || {}).name || '' },
                          arrival_stop: { name: (step.transit.arrival_stop || {}).name || '' },
                          departure_time: step.transit.departure_time ? { text: step.transit.departure_time.text || '' } : undefined,
                          arrival_time: step.transit.arrival_time ? { text: step.transit.arrival_time.text || '' } : undefined,
                          num_stops: step.transit.num_stops || 0,
                          headsign: step.transit.headsign || '',
                        };
                      }
                    } catch(transitErr) {
                      window.ReactNativeWebView.postMessage(JSON.stringify({
                        type: 'jsError', message: 'transit parse error: ' + transitErr.message
                      }));
                    }
                    if (step.polyline) {
                      stepData.polyline = { points: step.polyline.points || '' };
                    }
                    return stepData;
                  }),
                };
              }),
              overview_polyline: route.overview_polyline ? { points: route.overview_polyline.points || '' } : undefined,
              fare: route.fare ? { text: route.fare.text || '' } : undefined,
            };
          });
        } catch(parseErr) {
          window.ReactNativeWebView.postMessage(JSON.stringify({
            type: 'jsError',
            message: 'Route parse error: ' + parseErr.message,
            stack: parseErr.stack || ''
          }));
          response.status = 'PARSE_ERROR';
        }
        window.ReactNativeWebView.postMessage(JSON.stringify(response));
      });
    }
  </script>
  <script src="https://maps.googleapis.com/maps/api/js?key=${GOOGLE_MAPS_API_KEY}&callback=initMap" async defer></script>
</body>
</html>`;
}

export { GOOGLE_MAPS_API_KEY };

export function Marker(_props: MarkerProps) {
  return null;
}

const MapViewWrapper = forwardRef<WebView, MapViewProps>(function MapViewWrapper({
  style,
  initialRegion,
  region: controlledRegion,
  onRegionChangeComplete,
  onRouteSelect,
  onDirectionsResult,
  showsUserLocation = false,
  showsMyLocationButton = false,
  userLocationCoords,
  accessibilityLabel,
  routes,
  originMarker,
  destinationMarker,
  waypointMarkers,
  fitToRoute = false,
  directionsRequest,
  children,
}, ref) {
  const [error, setError] = useState(false);
  const webViewRef = useRef<WebView>(null);

  // 親コンポーネントから WebView ref にアクセスできるようにする
  useImperativeHandle(ref, () => webViewRef.current as WebView);

  // controlledRegion が変わったら地図を移動
  useEffect(() => {
    if (controlledRegion && webViewRef.current) {
      const zoom = getZoomLevel(controlledRegion.latitudeDelta);
      webViewRef.current.injectJavaScript(`
        if (typeof map !== 'undefined') {
          map.panTo({lat: ${controlledRegion.latitude}, lng: ${controlledRegion.longitude}});
          map.setZoom(${zoom});
        }
        true;
      `);
    }
  }, [controlledRegion?.latitude, controlledRegion?.longitude]);

  const region = initialRegion || {
    latitude: 35.6812,
    longitude: 139.7671,
    latitudeDelta: 0.01,
    longitudeDelta: 0.01,
  };

  const markers = collectMarkers(children);

  // マーカーの安定キー（座標ベースで変化を検出）
  const markersKey = markers
    .map((m) => `${m.coordinate.latitude},${m.coordinate.longitude}:${m.title || ''}`)
    .join(';');

  // Build a stable key for routes to detect changes
  const routesKey = routes
    ? routes.map((r) => `${r.id}:${r.selected ? '1' : '0'}:${r.mode || ''}`).join(',')
    : '';

  // Build a stable key for waypoint markers
  const waypointsKey = waypointMarkers
    ? waypointMarkers.map((wp) => `${wp.latitude},${wp.longitude}:${wp.mode || ''}:${wp.label || ''}`).join(';')
    : '';

  // HTML生成は初期表示とルート変更時のみ（マーカー更新ではWebView再生成しない）
  // initialRegion はマウント時に一度だけ使い、以降はinjectJavaScriptでマーカーを更新
  const initialHtmlRef = useRef<string | null>(null);
  const html = useMemo(
    () => {
      const generated = buildMapHtml(
        region,
        markers,
        showsUserLocation,
        showsMyLocationButton,
        routes,
        originMarker,
        destinationMarker,
        fitToRoute,
        waypointMarkers,
        directionsRequest,
        userLocationCoords,
      );
      initialHtmlRef.current = generated;
      return generated;
    },
    [
      // 注: region と markersKey は意図的に依存から除外
      // マーカー更新でWebView再読み込みすると現在地に戻されるため
      showsUserLocation,
      showsMyLocationButton,
      routesKey,
      waypointsKey,
      originMarker?.latitude,
      originMarker?.longitude,
      destinationMarker?.latitude,
      destinationMarker?.longitude,
      fitToRoute,
      JSON.stringify(directionsRequest),
      userLocationCoords?.latitude,
      userLocationCoords?.longitude,
    ],
  );

  // マーカーが変化したらWebView再生成ではなくinjectJavaScriptで更新
  useEffect(() => {
    if (!webViewRef.current || markers.length === 0) return;
    const markersJs = markers.map((m) => `
      (function() {
        var marker = new google.maps.Marker({
          position: { lat: ${m.coordinate.latitude}, lng: ${m.coordinate.longitude} },
          map: map,
          title: ${JSON.stringify(m.title || '')},
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: 10,
            fillColor: '${pinColorToHex(m.pinColor)}',
            fillOpacity: 1,
            strokeColor: '#FFFFFF',
            strokeWeight: 2,
          }
        });
        ${m.title || m.description ? `
        var infowindow = new google.maps.InfoWindow({
          content: '<div style="font-size:14px;"><strong>${escapeHtml(m.title || '')}</strong>${m.description ? '<br/>' + escapeHtml(m.description) : ''}</div>'
        });
        marker.addListener('click', function() {
          infowindow.open(map, marker);
        });
        ` : ''}
      })();
    `).join('\n');

    webViewRef.current.injectJavaScript(`
      if (typeof map !== 'undefined' && typeof window._spotMarkers !== 'undefined') {
        window._spotMarkers.forEach(function(m) { m.setMap(null); });
      }
      window._spotMarkers = [];
      (function() {
        ${markers.map((m) => `
          var marker = new google.maps.Marker({
            position: { lat: ${m.coordinate.latitude}, lng: ${m.coordinate.longitude} },
            map: map,
            title: ${JSON.stringify(m.title || '')},
            icon: {
              path: google.maps.SymbolPath.CIRCLE,
              scale: 10,
              fillColor: '${pinColorToHex(m.pinColor)}',
              fillOpacity: 1,
              strokeColor: '#FFFFFF',
              strokeWeight: 2,
            }
          });
          ${m.title || m.description ? `
          var infowindow = new google.maps.InfoWindow({
            content: '<div style="font-size:14px;"><strong>${escapeHtml(m.title || '')}</strong>${m.description ? '<br/>' + escapeHtml(m.description) : ''}</div>'
          });
          marker.addListener('click', function() {
            infowindow.open(map, marker);
          });
          ` : ''}
          window._spotMarkers.push(marker);
        `).join('\n')}
      })();
      true;
    `);
  }, [markersKey]);

  const handleMessage = useCallback(
    (event: { nativeEvent: { data: string } }) => {
      try {
        const data = JSON.parse(event.nativeEvent.data);
        if (data.type === 'regionChange' && onRegionChangeComplete) {
          onRegionChangeComplete(data.region);
        }
        if (data.type === 'routeSelect' && onRouteSelect) {
          onRouteSelect(data.routeId);
        }
        if (data.type === 'directionsResult' && onDirectionsResult) {
          onDirectionsResult(data as DirectionsResult);
        }
        if (data.type === 'jsError') {
          console.error('[MapView JS Error]', data.message, 'line:', data.line, data.stack);
        }
      } catch (err) {
        console.warn('[MapView] Message parse error:', err);
      }
    },
    [onRegionChangeComplete, onRouteSelect, onDirectionsResult],
  );

  if (error) {
    return (
      <View style={[styles.container, style]} accessibilityLabel={accessibilityLabel}>
        <View style={styles.fallback}>
          <Text style={styles.fallbackIcon}>{'\u{1F5FA}'}</Text>
          <Text style={styles.fallbackText}>地図を読み込めませんでした</Text>
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.container, style]} accessibilityLabel={accessibilityLabel}>
      <WebView
        ref={webViewRef}
        source={{ html }}
        style={styles.webview}
        onMessage={handleMessage}
        onError={() => setError(true)}
        javaScriptEnabled
        domStorageEnabled
        geolocationEnabled={showsUserLocation}
        scrollEnabled={false}
        bounces={false}
        overScrollMode="never"
      />
    </View>
  );
});

export default MapViewWrapper;

/**
 * WebView 内の DirectionsService に経路検索リクエストを送信する
 * MapViewWrapper の WebView ref を使って JS を注入する
 */
export function requestDirections(
  webViewRef: React.RefObject<WebView>,
  origin: { lat: number; lng: number },
  destination: { lat: number; lng: number },
  mode: string,
  departureTime?: number,
) {
  // Validate coordinates
  if (isNaN(origin.lat) || isNaN(origin.lng) || isNaN(destination.lat) || isNaN(destination.lng)) {
    console.warn('[MapView] requestDirections: invalid coordinates (NaN)');
    return;
  }
  // Validate mode
  const validModes = ['walking', 'transit', 'driving', 'bicycling'];
  const safeMode = validModes.includes(mode) ? mode : 'transit';
  webViewRef.current?.injectJavaScript(`
    searchDirections(${origin.lat}, ${origin.lng}, ${destination.lat}, ${destination.lng}, '${safeMode}', ${departureTime || 'null'});
    true;
  `);
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#E8F0FE',
    overflow: 'hidden',
  },
  webview: {
    flex: 1,
    backgroundColor: 'transparent',
  },
  fallback: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  fallbackIcon: {
    fontSize: 48,
    marginBottom: 8,
  },
  fallbackText: {
    fontSize: 14,
    color: '#666',
  },
});
