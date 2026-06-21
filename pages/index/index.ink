<script def>
{
  "navigationBarTitleText": "SkyMate",
  "description": "SkyMate smart-glasses astronomy assistant. Supports page events, ASR, location, external sky chart fetch, and single-page state switching.",
  "schema": {
    "data": {
      "type": "object",
      "properties": {
        "mode": {
          "type": "string",
          "enum": ["home", "chat", "loading", "overview", "detail", "locate", "error"],
          "description": "Current page mode: home, chat, loading, overview, detail, locate, or error"
        },
        "userText": { "type": "string", "description": "Question from the agent chat" },
        "locationName": { "type": "string", "description": "Location label" },
        "latitude": { "type": "number", "description": "Observer latitude" },
        "longitude": { "type": "number", "description": "Observer longitude" },
        "targets": { "type": "string", "description": "Recommended targets JSON string" },
        "skyChart": { "type": "string", "description": "Raw sky chart JSON string" },
        "selectedObject": { "type": "string", "description": "Selected target key or object JSON" }
      }
    }
  }
}
</script>

<script setup>
const BUILD_VERSION = 'v9-aiui-card'
const SKY_CHART_ENDPOINT = 'https://sky.eunoia.top/sky/chart'
const HUD_TARGET_SLOT_COUNT = 5
const HUD_BG_SLOT_COUNT = 8
const SKY_OBJECT_LIMIT = 32
const SKY_MAP_SIZE = 184

const SKY_OPTIONS = {
  star_max_mag: 3.0,
  deep_sky_max_mag: 9.0,
  min_altitude_deg: 15.0,
  total_limit: 28,
  include_planets: true,
  include_deep_sky: true
}

const CITY_COORDS = [
  { name: '苏州', aliases: ['苏州', 'suzhou', 'su zhou'], lat: 31.2989, lon: 120.5853 },
  { name: '太仓', aliases: ['太仓', 'taicang', 'tai cang'], lat: 31.4839, lon: 121.15824 },
  { name: '厦门', aliases: ['厦门', '廈門', 'xiamen', 'xia men'], lat: 24.4798, lon: 118.0894 },
  { name: '上海', aliases: ['上海', 'shanghai', 'shang hai'], lat: 31.2304, lon: 121.4737 },
  { name: '杭州', aliases: ['杭州', 'hangzhou', 'hang zhou'], lat: 30.2741, lon: 120.1551 },
  { name: '南京', aliases: ['南京', 'nanjing', 'nan jing'], lat: 32.0603, lon: 118.7969 },
  { name: '北京', aliases: ['北京', 'beijing', 'bei jing'], lat: 39.9042, lon: 116.4074 },
  { name: '纽约', aliases: ['纽约', 'new york', 'nyc'], lat: 40.7128, lon: -74.0060 }
]

const FALLBACK_TARGETS = [
  {
    key: 'vega',
    name: '织女星',
    type: '亮星',
    typeClass: 'star',
    direction: '东北',
    altitude: '较高',
    magnitude: '很亮',
    bestTime: '入夜后',
    intro: '夏季夜空里非常显眼，城市里也比较容易看到。',
    locate: '朝东北较高的天空看，找一颗清亮稳定的白色亮星。'
  },
  {
    key: 'arcturus',
    name: '大角星',
    type: '亮星',
    typeClass: 'star',
    direction: '西方',
    altitude: '中高空',
    magnitude: '很亮',
    bestTime: '今晚',
    intro: '亮度高，颜色略暖，适合用来确认大致方位。',
    locate: '朝西方到西南方向看，找一颗略偏暖色的明亮星点。'
  },
  {
    key: 'jupiter',
    name: '木星',
    type: '行星',
    typeClass: 'planet',
    direction: '开阔天空',
    altitude: '中低空',
    magnitude: '很亮',
    bestTime: '今晚',
    intro: '如果它在地平线上方，通常比多数恒星更亮且不太闪。',
    locate: '先找无遮挡的地平线，再寻找稳定、不明显闪烁的亮点。'
  }
]

function hasValue(value) {
  return value !== undefined && value !== null && value !== ''
}

function text(value, fallback) {
  return hasValue(value) ? String(value) : (fallback || '')
}

function keyOf(value) {
  return text(value, '')
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^\w\u4e00-\u9fa5-]/g, '')
}

function readAny(source, keys) {
  const raw = source || {}
  for (let index = 0; index < keys.length; index += 1) {
    const value = raw[keys[index]]
    if (hasValue(value)) return value
  }
  return undefined
}

function parseJsonMaybe(value) {
  if (!hasValue(value)) return null
  if (typeof value === 'object') return value
  try {
    return JSON.parse(String(value))
  } catch (error) {
    return null
  }
}

function shortText(value, maxLength) {
  const valueText = text(value, '')
  const limit = maxLength || 42
  return valueText.length > limit ? `${valueText.slice(0, limit)}...` : valueText
}

function numeric(value, fallback) {
  const next = parseFloat(value)
  return Number.isFinite(next) ? next : fallback
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

function isReadableName(value) {
  const valueText = text(value, '')
  if (!valueText) return false
  return valueText.indexOf('å') < 0 && valueText.indexOf('�') < 0
}

function bestName(object, fallback) {
  const names = [
    readAny(object, ['display_name', 'name', 'name_zh', 'title', 'objectName']),
    readAny(object, ['name_en', 'designation', 'id'])
  ]
  for (let index = 0; index < names.length; index += 1) {
    if (isReadableName(names[index])) return text(names[index])
  }
  return fallback || '观测目标'
}

function angleText(value) {
  if (!hasValue(value)) return ''
  if (typeof value === 'number') return `${Math.round(value)}°`
  const valueText = String(value)
  return valueText.indexOf('°') >= 0 ? valueText : `${valueText}°`
}

function directionFromAzimuth(value) {
  const azimuth = parseFloat(text(value, '').replace('°', ''))
  if (isNaN(azimuth)) return ''
  const normalized = ((azimuth % 360) + 360) % 360
  if (normalized >= 337.5 || normalized < 22.5) return '北'
  if (normalized < 67.5) return '东北'
  if (normalized < 112.5) return '东'
  if (normalized < 157.5) return '东南'
  if (normalized < 202.5) return '南'
  if (normalized < 247.5) return '西南'
  if (normalized < 292.5) return '西'
  return '西北'
}

function targetType(raw) {
  const typeText = text(raw, '').toLowerCase()
  if (typeText.indexOf('moon') >= 0 || typeText.indexOf('月') >= 0) return { label: '月亮', className: 'moon', rank: 0 }
  if (typeText.indexOf('planet') >= 0 || typeText.indexOf('行星') >= 0) return { label: '行星', className: 'planet', rank: 1 }
  if (typeText.indexOf('star') >= 0 || typeText.indexOf('亮星') >= 0 || typeText.indexOf('恒星') >= 0) return { label: '亮星', className: 'star', rank: 2 }
  if (typeText.indexOf('constellation') >= 0 || typeText.indexOf('星座') >= 0) return { label: '星座', className: 'constellation', rank: 3 }
  if (typeText.indexOf('meteor') >= 0 || typeText.indexOf('流星') >= 0) return { label: '流星雨', className: 'meteor', rank: 4 }
  return { label: '深空', className: 'deep', rank: 5 }
}

function visibilityScore(target) {
  const typeScore = target.rank === 0 ? 0 : target.rank === 1 ? 1 : target.rank === 2 ? 2 : target.rank + 2
  const magnitude = parseFloat(target.magnitude)
  const magScore = isNaN(magnitude) ? 3 : Math.max(-1, magnitude)
  const altitude = parseFloat(target.altitude)
  const altBonus = !isNaN(altitude) && altitude >= 25 ? -1 : 0
  return typeScore * 10 + magScore + altBonus
}

function collectTargets(source, bucket) {
  if (!source) return
  if (Array.isArray(source)) {
    source.forEach(item => bucket.push(item))
    return
  }
  if (typeof source !== 'object') return

  const arrays = [
    'targets',
    'objects',
    'visibleObjects',
    'visible_objects',
    'recommendations',
    'recommended',
    'planets',
    'bright_stars',
    'stars',
    'deep_sky',
    'deepSky',
    'constellations',
    'meteorShowers'
  ]

  arrays.forEach(name => {
    if (Array.isArray(source[name])) source[name].forEach(item => bucket.push(item))
  })

  if (source.moon && typeof source.moon === 'object') bucket.push(Object.assign({ type: 'moon' }, source.moon))
  if (source.sky_chart && source.sky_chart !== source) collectTargets(source.sky_chart, bucket)
  if (source.skyChart && source.skyChart !== source) collectTargets(source.skyChart, bucket)
  if (source.chart && source.chart !== source) collectTargets(source.chart, bucket)
  if (source.data && source.data !== source) collectTargets(source.data, bucket)
  if (source.result && source.result !== source) collectTargets(source.result, bucket)
}

function normalizeTarget(raw, index) {
  const object = raw || {}
  const name = bestName(object, `目标 ${index + 1}`)
  const typeInfo = targetType(readAny(object, ['type', 'category', 'kind', 'objectType', 'object_type']))
  const azimuth = readAny(object, ['azimuth', 'azimuth_deg', 'azimuthDeg', 'az'])
  const altitude = readAny(object, ['altitude', 'altitude_deg', 'altitudeDeg', 'alt', 'elevation'])
  const chartX = numeric(readAny(object, ['chart_x', 'chartX', 'x']), NaN)
  const chartY = numeric(readAny(object, ['chart_y', 'chartY', 'y']), NaN)
  const direction = text(readAny(object, ['direction', 'azimuthText', 'cardinalDirection']) || directionFromAzimuth(azimuth), '开阔天空')
  const magnitude = text(readAny(object, ['magnitude', 'mag', 'brightness', 'apparentMagnitude']), '可见')
  const key = keyOf(readAny(object, ['key', 'id']) || name) || `target-${index + 1}`
  const altitudeText = angleText(altitude) || '中等高度'

  return {
    key,
    name,
    type: typeInfo.label,
    typeClass: typeInfo.className,
    rank: typeInfo.rank,
    azimuth: numeric(azimuth, NaN),
    altitudeDeg: numeric(altitude, NaN),
    chartX,
    chartY,
    direction,
    altitude: altitudeText,
    magnitude,
    bestTime: text(readAny(object, ['bestTime', 'visibleTime', 'timeWindow', 'time']), '今晚'),
    intro: text(readAny(object, ['intro', 'description', 'summary', 'reason']), `${name} 适合作为今晚的观测目标。`),
    locate: text(readAny(object, ['locate', 'tip', 'observationTip', 'howToFind']), `朝${direction}方向看，先找最亮、最稳定的光点。`)
  }
}

function pickTargets(rawChart) {
  const bucket = []
  collectTargets(rawChart, bucket)
  const seen = {}
  const targets = bucket
    .map((item, index) => normalizeTarget(item, index))
    .filter(item => {
      if (seen[item.key]) return false
      seen[item.key] = true
      return true
    })
    .sort((left, right) => visibilityScore(left) - visibilityScore(right))

  return (targets.length ? targets : FALLBACK_TARGETS).slice(0, HUD_TARGET_SLOT_COUNT)
}

function collectSkyObjects(rawChart, fallbackTargets) {
  const bucket = []
  collectTargets(rawChart, bucket)
  ;(fallbackTargets || []).forEach(item => bucket.push(item))
  const seen = {}
  const objects = bucket
    .map((item, index) => normalizeTarget(item, index))
    .filter(item => {
      if (seen[item.key]) return false
      seen[item.key] = true
      return Number.isFinite(item.azimuth) && Number.isFinite(item.altitudeDeg) && item.altitudeDeg >= 0
    })

  return (objects.length ? objects : (fallbackTargets || FALLBACK_TARGETS)).slice(0, SKY_OBJECT_LIMIT)
}

function skyChartPoint(target, index) {
  const item = target || {}
  if (Number.isFinite(item.azimuth) && Number.isFinite(item.altitudeDeg)) {
    const azimuth = ((item.azimuth % 360) + 360) % 360
    const altitude = clamp(item.altitudeDeg, 0, 90)
    const radius = clamp((90 - altitude) / 90, 0.04, 0.94)
    const radians = azimuth * Math.PI / 180
    return {
      left: clamp(Math.round((0.5 + Math.sin(radians) * radius * 0.46) * SKY_MAP_SIZE), 5, SKY_MAP_SIZE - 5),
      top: clamp(Math.round((0.5 - Math.cos(radians) * radius * 0.46) * SKY_MAP_SIZE), 5, SKY_MAP_SIZE - 5)
    }
  }

  if (Number.isFinite(item.chartX) && Number.isFinite(item.chartY)) {
    const normalizedX = item.chartX >= 0 && item.chartX <= 1 ? item.chartX : (item.chartX + 1) / 2
    const normalizedY = item.chartY >= 0 && item.chartY <= 1 ? item.chartY : (item.chartY + 1) / 2
    return {
      left: clamp(Math.round(normalizedX * SKY_MAP_SIZE), 5, SKY_MAP_SIZE - 5),
      top: clamp(Math.round(normalizedY * SKY_MAP_SIZE), 5, SKY_MAP_SIZE - 5)
    }
  }

  const azimuth = index * 137.5
  const radius = 0.54 + (index % 3) * 0.12
  const radians = azimuth * Math.PI / 180
  return {
    left: clamp(Math.round((0.5 + Math.sin(radians) * radius * 0.46) * SKY_MAP_SIZE), 5, SKY_MAP_SIZE - 5),
    top: clamp(Math.round((0.5 - Math.cos(radians) * radius * 0.46) * SKY_MAP_SIZE), 5, SKY_MAP_SIZE - 5)
  }
}

function skyObjectSize(target) {
  const magnitude = parseFloat(target && target.magnitude)
  if (target && target.typeClass === 'moon') return 10
  if (target && target.typeClass === 'planet') return 8
  if (isNaN(magnitude)) return 4
  return clamp(Math.round(7 - magnitude), 3, 8)
}

function dotStyle(point, size) {
  const dotSize = size || 8
  return `left:${point.left - Math.round(dotSize / 2)}px;top:${point.top - Math.round(dotSize / 2)}px;width:${dotSize}px;height:${dotSize}px;`
}

function labelStyle(point, size) {
  const labelLeft = point.left + 1
  const labelTop = point.top - 6
  return `left:${clamp(labelLeft, 4, SKY_MAP_SIZE - 54)}px;top:${clamp(labelTop, 4, SKY_MAP_SIZE - 12)}px;`
}

function hiddenStyle() {
  return 'display:none;'
}

function createSelectedSkyOverlay(target, index) {
  if (!target) {
    return {
      selectedSkyMarkerStyle: hiddenStyle(),
      selectedSkyLabelStyle: hiddenStyle()
    }
  }

  const point = skyChartPoint(target, index || 0)
  const size = Math.max(skyObjectSize(target) + 2, 8)
  return {
    selectedSkyMarkerStyle: dotStyle(point, size),
    selectedSkyLabelStyle: labelStyle(point, size)
  }
}

function bgPoint(index) {
  const left = [13, 26, 37, 54, 68, 81, 21, 74][index % HUD_BG_SLOT_COUNT]
  const top = [28, 18, 64, 36, 72, 24, 78, 54][index % HUD_BG_SLOT_COUNT]
  return { left, top }
}

function createHudSlots(targets, selectedKey) {
  const safeTargets = (targets && targets.length ? targets : FALLBACK_TARGETS).slice(0, HUD_TARGET_SLOT_COUNT)
  const selected = safeTargets.find(item => item.key === selectedKey) || safeTargets[0] || FALLBACK_TARGETS[0]
  const slots = {
    objectCount: String(safeTargets.length),
    focusStyle: hiddenStyle(),
    aimLine: selected ? `${selected.direction} / ${selected.altitude}` : 'AIM --'
  }

  for (let index = 0; index < HUD_BG_SLOT_COUNT; index += 1) {
    slots[`bg${index}Style`] = dotStyle(bgPoint(index), index % 3 === 0 ? 3 : 2)
  }

  for (let index = 0; index < HUD_TARGET_SLOT_COUNT; index += 1) {
    const target = safeTargets[index]
    if (!target) {
      slots[`target${index}Style`] = hiddenStyle()
      slots[`label${index}Style`] = hiddenStyle()
      slots[`target${index}Name`] = ''
      slots[`target${index}Meta`] = ''
      slots[`target${index}Key`] = ''
      slots[`target${index}Class`] = ''
      continue
    }

    const point = skyChartPoint(target, index)
    const selectedClass = selected && target.key === selected.key ? 'selected' : ''
    slots[`target${index}Style`] = dotStyle(point, selectedClass ? 12 : 9)
    slots[`label${index}Style`] = labelStyle(point)
    slots[`target${index}Name`] = target.name
    slots[`target${index}Meta`] = `${target.type} · ${target.direction}`
    slots[`target${index}Key`] = target.key
    slots[`target${index}Class`] = `${target.typeClass} ${selectedClass}`
  }

  if (selected) {
    const focusPoint = skyChartPoint(selected, 0)
    slots.focusStyle = dotStyle(focusPoint, 24)
  }

  return slots
}

function createSkyChartObjects(objects, selectedKey) {
  const source = objects && objects.length ? objects : FALLBACK_TARGETS
  return source.slice(0, SKY_OBJECT_LIMIT).map((target, index) => {
    const point = skyChartPoint(target, index)
    const size = skyObjectSize(target)
    return Object.assign({}, target, {
      style: dotStyle(point, size),
      selectedClass: '',
      labelStyle: hiddenStyle()
    })
  })
}

function cityFromText(input) {
  const raw = text(input, '').toLowerCase()
  for (let index = 0; index < CITY_COORDS.length; index += 1) {
    const city = CITY_COORDS[index]
    const matched = city.aliases.some(alias => raw.indexOf(alias.toLowerCase()) >= 0)
    if (matched) return city
  }
  return null
}

function coordinateFromText(input) {
  const raw = text(input, '')
  if (!raw) return null

  const latMatch = raw.match(/(?:\u7eac\u5ea6|\u5317\u7eac|lat(?:itude)?)[^\d\-+]*([+-]?\d+(?:\.\d+)?)/i)
  const lonMatch = raw.match(/(?:\u7ecf\u5ea6|\u4e1c\u7ecf|lon(?:gitude)?|lng)[^\d\-+]*([+-]?\d+(?:\.\d+)?)/i)
  if (latMatch && lonMatch) {
    const lat = parseFloat(latMatch[1])
    const lon = parseFloat(lonMatch[1])
    if (!isNaN(lat) && !isNaN(lon)) {
      return { name: cityFromText(raw)?.name || '文字位置', lat, lon }
    }
  }

  const numbers = raw.match(/[+-]?\d+(?:\.\d+)?/g) || []
  const latIndex = Math.max(raw.indexOf('北纬'), raw.indexOf('纬度'), raw.toLowerCase().indexOf('lat'))
  const lonIndex = Math.max(raw.indexOf('东经'), raw.indexOf('经度'), raw.toLowerCase().indexOf('lon'), raw.toLowerCase().indexOf('lng'))
  if (numbers.length >= 2 && latIndex >= 0 && lonIndex >= 0) {
    const first = parseFloat(numbers[0])
    const second = parseFloat(numbers[1])
    if (!isNaN(first) && !isNaN(second)) {
      const lat = latIndex < lonIndex ? first : second
      const lon = latIndex < lonIndex ? second : first
      if (Math.abs(lat) <= 90 && Math.abs(lon) <= 180) {
        return { name: cityFromText(raw)?.name || '文字位置', lat, lon }
      }
    }
  }

  const pairMatch = raw.match(/([+-]?\d+(?:\.\d+)?)\s*[,，]\s*([+-]?\d+(?:\.\d+)?)/)
  if (!pairMatch) return null

  const first = parseFloat(pairMatch[1])
  const second = parseFloat(pairMatch[2])
  if (isNaN(first) || isNaN(second)) return null

  const looksLatLon = Math.abs(first) <= 90 && Math.abs(second) <= 180
  const looksLonLat = Math.abs(first) <= 180 && Math.abs(second) <= 90
  if (looksLatLon) return { name: cityFromText(raw)?.name || '文字位置', lat: first, lon: second }
  if (looksLonLat) return { name: cityFromText(raw)?.name || '文字位置', lat: second, lon: first }
  return null
}

function placeFromQuery(query) {
  const raw = query || {}
  const lat = parseFloat(raw.lat || raw.latitude)
  const lon = parseFloat(raw.lon || raw.lng || raw.longitude)
  if (isNaN(lat) || isNaN(lon)) return null
  return {
    name: text(raw.locationName || raw.city || raw.location, '当前位置'),
    lat,
    lon
  }
}

function queryFromRaw(rawQuery) {
  if (!rawQuery) return {}
  if (typeof rawQuery === 'string') return parseJsonMaybe(rawQuery) || {}
  if (rawQuery.data && typeof rawQuery.data === 'string') {
    return Object.assign({}, rawQuery, parseJsonMaybe(rawQuery.data) || {})
  }
  if (rawQuery.data && typeof rawQuery.data === 'object') {
    return Object.assign({}, rawQuery, rawQuery.data)
  }
  return rawQuery
}

function errorText(error) {
  if (!error) return 'unknown error'
  return error.message || error.statusText || String(error)
}

function queryStringFromPayload(payload) {
  return Object.keys(payload || {})
    .filter(key => hasValue(payload[key]))
    .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(String(payload[key]))}`)
    .join('&')
}

async function responseErrorText(response, prefix) {
  const statusText = `${prefix || 'HTTP'} ${response ? response.status : 'unknown'}`
  if (!response) return statusText
  if (typeof response.json === 'function') {
    try {
      const json = await response.json()
      return `${statusText}: ${JSON.stringify(json).slice(0, 180)}`
    } catch (error) {}
  }
  if (typeof response.text !== 'function') return statusText
  try {
    const body = await response.text()
    return body ? `${statusText}: ${String(body).slice(0, 180)}` : statusText
  } catch (error) {
    return statusText
  }
}

function getRuntimeRoot() {
  if (typeof globalThis !== 'undefined') return globalThis
  if (typeof window !== 'undefined') return window
  if (typeof self !== 'undefined') return self
  return {}
}

function getSpeechRecognitionCandidate(root) {
  const runtime = root || getRuntimeRoot()
  const speechModule = runtime.speech || runtime.aiuiSpeech || runtime.rokidSpeech || {}
  return runtime.SpeechRecognition ||
    runtime.webkitSpeechRecognition ||
    speechModule.SpeechRecognition ||
    speechModule.recognition ||
    null
}

function safeAssignRecognitionOption(recognition, key, value) {
  if (!recognition) return
  try {
    recognition[key] = value
  } catch (error) {
    console.log('[SkyMate] ASR option ignored', key, error || {})
  }
}

function configureSpeechRecognition(recognition) {
  safeAssignRecognitionOption(recognition, 'lang', 'zh-CN')
  safeAssignRecognitionOption(recognition, 'continuous', false)
  safeAssignRecognitionOption(recognition, 'interimResults', false)
  safeAssignRecognitionOption(recognition, 'maxAlternatives', 1)
}

export default {
  data: Object.assign({
    mode: 'home',
    buildVersion: BUILD_VERSION,
    pageTag: '待唤醒',
    locationName: '等待位置',
    verdict: 'SkyMate 帮你看今晚星空。',
    condition: '使用当前位置后，我会给出今晚的观星建议。',
    assistantLine: '点击使用当前位置，开始判断今晚能看到什么。',
    diagnosticLine: 'ready',
    requestStatus: 'idle',
    asrStatus: 'idle',
    eventStatus: 'waiting',
    locationLine: '尚未定位',
    selectedIndex: 0,
    selectedKey: FALLBACK_TARGETS[0].key,
    selectedObject: FALLBACK_TARGETS[0],
    visibleObjects: FALLBACK_TARGETS,
    skyObjects: createSkyChartObjects(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key),
    homeDisplay: 'block',
    chatDisplay: 'none',
    loadingDisplay: 'none',
    overviewDisplay: 'none',
    detailDisplay: 'none',
    locateDisplay: 'none',
    errorDisplay: 'none'
  }, createHudSlots(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key), createSelectedSkyOverlay(FALLBACK_TARGETS[0], 0)),

  onLoad(rawQuery) {
    console.log('[SkyMate] page onLoad', rawQuery || {})
    const query = queryFromRaw(rawQuery)
    const chart = parseJsonMaybe(query.skyChart || query.chart || query.rawResult || query.result)
    const targets = parseJsonMaybe(query.targets)
    const userText = query.userText || query.prompt || query.question || query.message || query.input
    const placeText = userText || query.locationName || query.city || query.location || ''
    const queryPlace = placeFromQuery(query)

    if (Array.isArray(targets) || chart) {
      this.showChartResult({
        chart,
        targets: Array.isArray(targets) ? targets : null,
        locationName: text(query.locationName || query.city || query.location, '当前位置'),
        source: 'page-query'
      })
      return
    }

    if (queryPlace) {
      this.setData({ assistantLine: '收到经纬度，正在查当前位置星空。', diagnosticLine: 'query lat/lon' })
      this.loadSkyChart(queryPlace)
      return
    }

    if (placeText || query.mode === 'loading') {
      this.setData({ assistantLine: userText ? `收到问题：${userText}` : '收到页面查询，正在查星空。', diagnosticLine: 'query text' })
      this.handleUserText(placeText || '今晚苏州能看到什么')
      return
    }

    this.applyMode(text(query.mode, 'home'))
  },

  onShow() {
    console.log('[SkyMate] page onShow')
  },

  onReady() {
    console.log('[SkyMate] page onReady')
  },

  onVoiceWakeup(event) {
    console.log('[SkyMate] voice wakeup', event || {})
    this.reportEvent('voiceWakeup')
    this.startAsr()
  },

  onKeyUp(event) {
    const code = event && (event.code || event.key || event.keyCode)
    console.log('[SkyMate] key up', code)
    this.reportEvent(`key:${code || 'unknown'}`)

    const isBack = code === 'Backspace' || code === 'Escape' || code === 'Back' || code === 'GoBack' || code === 4 || code === 8 || code === 27
    const isUp = code === 'ArrowUp' || code === 'Up' || code === 19
    const isDown = code === 'ArrowDown' || code === 'Down' || code === 20
    const isConfirm = code === 'Enter' || code === 'NumpadEnter' || code === 'GlobalHook' || code === 'Select' || code === 'OK' || code === 13

    if (isBack) {
      if (event && event.preventDefault) event.preventDefault()
      if (event && event.stopPropagation) event.stopPropagation()
      this.goBack()
      return
    }

    if (isUp || isDown) {
      if (event && event.preventDefault) event.preventDefault()
      this.moveSelection(isUp ? -1 : 1)
      return
    }

    if (isConfirm) {
      if (event && event.preventDefault) event.preventDefault()
      this.confirmCurrent()
    }
  },

  reportEvent(name) {
    console.log('[SkyMate] page event', name)
    this.setData({
      eventStatus: name,
      diagnosticLine: name
    })
  },

  applyMode(mode) {
    const modeKey = ['home', 'chat', 'loading', 'overview', 'detail', 'locate', 'error'].indexOf(mode) >= 0 ? mode : 'home'
    const tagMap = {
      home: '待唤醒',
      chat: '听你说',
      loading: '查询中',
      overview: '今晚推荐',
      detail: '目标详情',
      locate: '寻找方向',
      error: '离线兜底'
    }

    this.setData({
      mode: modeKey,
      pageTag: tagMap[modeKey],
      homeDisplay: modeKey === 'home' ? 'block' : 'none',
      chatDisplay: modeKey === 'chat' ? 'block' : 'none',
      loadingDisplay: modeKey === 'loading' ? 'block' : 'none',
      overviewDisplay: modeKey === 'overview' ? 'block' : 'none',
      detailDisplay: modeKey === 'detail' ? 'block' : 'none',
      locateDisplay: modeKey === 'locate' ? 'block' : 'none',
      errorDisplay: modeKey === 'error' ? 'block' : 'none'
    })
  },

  startChat() {
    this.reportEvent('startChat')
    this.applyMode('chat')
  },

  startAsr() {
    this.reportEvent('startAsr')
    this.applyMode('chat')
    this.setData({
      asrStatus: 'listening',
      assistantLine: '我在听，说出城市和今晚想看的目标。'
    })

    const Recognition = getSpeechRecognitionCandidate()
    if (!Recognition) {
      if (this.startWxAsr()) return
      this.setData({
        asrStatus: 'unavailable',
        assistantLine: '当前环境没有 ASR，我先用苏州测试链路跑一遍。'
      })
      this.runSuzhouDemo()
      return
    }

    const recognition = new Recognition()
    configureSpeechRecognition(recognition)

    recognition.onresult = (event) => {
      const result = event && event.results && event.results[0] && event.results[0][0]
      const transcript = result ? result.transcript : ''
      console.log('[SkyMate] ASR result', transcript)
      this.setData({
        asrStatus: transcript ? 'success' : 'empty',
        assistantLine: transcript ? `我听到：${transcript}` : '我听到了，正在判断。'
      })
      this.handleUserText(transcript || '今晚苏州能看到什么')
    }

    recognition.onerror = (event) => {
      console.log('[SkyMate] ASR error', event || {})
      this.setData({
        asrStatus: 'error',
        assistantLine: '这次语音没有成功，我先用苏州测试链路验证。'
      })
      this.runSuzhouDemo()
    }

    recognition.onend = () => console.log('[SkyMate] ASR end')
    recognition.start()
  },

  startWxAsr() {
    const runtime = typeof wx !== 'undefined' ? wx : null
    if (!runtime || typeof runtime.getSpeechRecognizer !== 'function') return false

    try {
      const recognizer = runtime.getSpeechRecognizer()
      if (!recognizer) return false

      this.setData({
        asrStatus: 'wx-listening',
        assistantLine: '正在调用 Rokid 语音识别。'
      })

      const onResult = (event) => {
        const result = event || {}
        const transcript = result.transcript ||
          result.text ||
          result.result ||
          (result.results && result.results[0] && result.results[0][0] && result.results[0][0].transcript) ||
          ''
        console.log('[SkyMate] wx ASR result', transcript, result)
        this.setData({
          asrStatus: transcript ? 'wx-success' : 'wx-empty',
          assistantLine: transcript ? `我听到：${transcript}` : '我听到了，正在判断。'
        })
        this.handleUserText(transcript || '今晚苏州能看到什么')
      }

      const onError = (error) => {
        console.log('[SkyMate] wx ASR error', error || {})
        this.setData({
          asrStatus: 'wx-error',
          assistantLine: 'Rokid 语音识别没有成功，我先跑苏州测试链路。'
        })
        this.runSuzhouDemo()
      }

      if (typeof recognizer.onResult === 'function') recognizer.onResult(onResult)
      else recognizer.onresult = onResult

      if (typeof recognizer.onError === 'function') recognizer.onError(onError)
      else recognizer.onerror = onError

      if (typeof recognizer.onEnd === 'function') recognizer.onEnd(() => console.log('[SkyMate] wx ASR end'))
      else recognizer.onend = () => console.log('[SkyMate] wx ASR end')

      if (typeof recognizer.start === 'function') {
        recognizer.start({ lang: 'zh-CN' })
        return true
      }

      if (typeof recognizer.startRecognition === 'function') {
        recognizer.startRecognition({ lang: 'zh-CN' })
        return true
      }
    } catch (error) {
      console.log('[SkyMate] wx ASR setup failed', error || {})
    }
    return false
  },

  handleUserText(input) {
    this.reportEvent('handleUserText')
    const coordinate = coordinateFromText(input)
    if (coordinate) {
      this.loadSkyChart(coordinate)
      return
    }

    const city = cityFromText(input)
    if (city) {
      this.loadSkyChart(city)
      return
    }
    this.loadCurrentLocationOrFallback()
  },

  runCurrentLocation() {
    this.reportEvent('runCurrentLocation')
    this.loadCurrentLocationOrFallback()
  },

  async locateOnly() {
    this.reportEvent('locateOnly')
    this.setData({
      locationName: '正在定位',
      requestStatus: 'location',
      diagnosticLine: 'try location',
      assistantLine: '正在读取 GPS 位置。',
      locationLine: '正在获取当前位置...'
    })

    try {
      const place = await this.readRuntimeLocation()
      const latText = Number.isFinite(place.lat) ? place.lat.toFixed(4) : '--'
      const lonText = Number.isFinite(place.lon) ? place.lon.toFixed(4) : '--'
      this.setData({
        locationName: place.name || '当前位置',
        requestStatus: 'location ok',
        diagnosticLine: `lat=${latText} lon=${lonText}`,
        assistantLine: '已拿到当前位置，可以开始语音提问。',
        locationLine: `当前位置：${latText}, ${lonText}`
      })
    } catch (error) {
      console.log('[SkyMate] locateOnly unavailable', error || {})
      this.setData({
        requestStatus: 'location failed',
        diagnosticLine: errorText(error),
        assistantLine: '暂时没有拿到 GPS 位置。',
        locationLine: '当前位置：未获取到'
      })
    }
  },

  async loadCurrentLocationOrFallback() {
    this.applyMode('loading')
    this.setData({
      locationName: '正在定位',
      requestStatus: 'location',
      diagnosticLine: 'try location',
      assistantLine: '我先尝试读取设备当前位置。'
    })

    try {
      const place = await this.readRuntimeLocation()
      this.loadSkyChart(place)
    } catch (error) {
      console.log('[SkyMate] location unavailable', error || {})
      this.setData({
        requestStatus: 'location fallback',
        diagnosticLine: errorText(error)
      })
      this.loadSkyChart(CITY_COORDS[0])
    }
  },

  readRuntimeLocation() {
    const root = getRuntimeRoot()

    if (root.wx && typeof root.wx.getLocation === 'function') {
      return new Promise((resolve, reject) => {
        try {
          root.wx.getLocation({
            type: 'wgs84',
            success: (res) => {
              const lat = parseFloat(res && (res.latitude || res.lat))
              const lon = parseFloat(res && (res.longitude || res.lon || res.lng))
              if (isNaN(lat) || isNaN(lon)) {
                reject(new Error('wx.getLocation returned invalid coordinates'))
                return
              }
              resolve({ name: '当前位置', lat, lon })
            },
            fail: (error) => reject(error || new Error('wx.getLocation failed'))
          })
        } catch (error) {
          reject(error)
        }
      })
    }

    const navigator = root.navigator
    if (navigator && navigator.geolocation && typeof navigator.geolocation.getCurrentPosition === 'function') {
      return new Promise((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            const coords = position && position.coords
            const lat = parseFloat(coords && coords.latitude)
            const lon = parseFloat(coords && coords.longitude)
            if (isNaN(lat) || isNaN(lon)) {
              reject(new Error('navigator.geolocation returned invalid coordinates'))
              return
            }
            resolve({ name: '当前位置', lat, lon })
          },
          (error) => reject(error || new Error('navigator.geolocation failed')),
          { enableHighAccuracy: false, timeout: 5000, maximumAge: 300000 }
        )
      })
    }

    return Promise.reject(new Error('location API unavailable'))
  },

  runSuzhouDemo() {
    this.reportEvent('runSuzhouDemo')
    this.loadSkyChart(CITY_COORDS[0])
  },

  runShanghaiDemo() {
    this.reportEvent('runShanghaiDemo')
    this.loadSkyChart(CITY_COORDS[3])
  },

  async loadSkyChart(city) {
    const place = city || CITY_COORDS[0]
    this.applyMode('loading')
    this.setData({
      locationName: place.name,
      requestStatus: 'loading',
      diagnosticLine: `lat=${place.lat} lon=${place.lon}`,
      assistantLine: `正在查 ${place.name} 今晚的星空。`
    })

    const payload = Object.assign({}, SKY_OPTIONS, {
      lat: place.lat,
      lon: place.lon,
      latitude: place.lat,
      longitude: place.lon
    })

    try {
      const response = await this.fetchSkyChart(payload)
      const chart = await response.json()
      console.log('[SkyMate] sky chart result', chart)
      this.showChartResult({
        chart,
        locationName: place.name,
        source: 'sky-chart'
      })
    } catch (error) {
      console.log('[SkyMate] sky chart failed', error || {})
      this.showFallback(place.name, errorText(error))
    }
  },

  async fetchSkyChart(payload) {
    console.log('[SkyMate] sky fetch start', {
      url: SKY_CHART_ENDPOINT,
      lat: payload.lat,
      lon: payload.lon,
      total_limit: payload.total_limit
    })
    this.setData({
      requestStatus: 'fetch',
      diagnosticLine: `POST ${payload.lat},${payload.lon}`
    })

    try {
      const response = await fetch(SKY_CHART_ENDPOINT, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'User-Agent': 'Rizon/1.0'
        },
        body: JSON.stringify(payload)
      })

      if (!response.ok) throw new Error(await responseErrorText(response, 'HTTP'))
      this.setData({ requestStatus: `http ${response.status}`, diagnosticLine: 'POST ok' })
      return response
    } catch (firstError) {
      console.log('[SkyMate] sky fetch primary failed', errorText(firstError))
      this.setData({ requestStatus: 'retry POST', diagnosticLine: shortText(errorText(firstError), 62) })
    }

    const retryPayload = {
      lat: payload.lat,
      lon: payload.lon,
      latitude: payload.lat,
      longitude: payload.lon,
      total_limit: payload.total_limit || 28
    }

    const retryResponse = await fetch(SKY_CHART_ENDPOINT, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'X-User-Agent': 'Rizon/1.0'
      },
      body: JSON.stringify(retryPayload)
    })

    if (!retryResponse.ok) {
      const retryError = await responseErrorText(retryResponse, 'retry HTTP')
      console.log('[SkyMate] sky fetch retry POST failed', retryError)
      this.setData({ requestStatus: 'retry GET', diagnosticLine: shortText(retryError, 62) })

      const getUrl = `${SKY_CHART_ENDPOINT}?${queryStringFromPayload(retryPayload)}`
      const getResponse = await fetch(getUrl, {
        method: 'GET',
        headers: { 'X-User-Agent': 'Rizon/1.0' }
      })

      if (!getResponse.ok) throw new Error(await responseErrorText(getResponse, 'GET HTTP'))
      this.setData({ requestStatus: `GET ${getResponse.status}`, diagnosticLine: 'GET ok' })
      return getResponse
    }

    this.setData({ requestStatus: `retry ${retryResponse.status}`, diagnosticLine: 'minimal POST ok' })
    return retryResponse
  },

  showChartResult(options) {
    const chart = options && options.chart
    const providedTargets = options && options.targets
    const locationName = text(options && options.locationName, '当前位置')
    const targets = providedTargets ? providedTargets.map((item, index) => normalizeTarget(item, index)).slice(0, HUD_TARGET_SLOT_COUNT) : pickTargets(chart)
    const skyObjects = collectSkyObjects(chart || providedTargets, targets)
    const first = targets[0] || FALLBACK_TARGETS[0]
    const source = text(options && options.source, 'sky-chart')
    const targetNames = targets.slice(0, 2).map(item => item.name).join('、')
    const verdict = targets.length
      ? `${locationName}今晚优先看 ${targetNames}`
      : `${locationName}今晚先看亮星和亮行星`

    this.setData(Object.assign({
      visibleObjects: targets,
      selectedKey: first.key,
      selectedIndex: 0,
      selectedObject: first,
      locationName,
      skyObjects: createSkyChartObjects(skyObjects, first.key),
      verdict,
      condition: '城市里优先看亮星、行星和月亮；深空目标更适合望远镜或暗处。',
      assistantLine: '已筛出最适合普通用户看的目标。',
      requestStatus: `success ${source}`,
      diagnosticLine: `targets=${targets.length} sky=${skyObjects.length}`
    }, createHudSlots(targets, first.key), createSelectedSkyOverlay(first, 0)))
    this.applyMode('overview')
  },

  showFallback(locationName, reason) {
    console.log('[SkyMate] fallback reason', reason || '')
    this.setData(Object.assign({
      visibleObjects: FALLBACK_TARGETS,
      selectedKey: FALLBACK_TARGETS[0].key,
      selectedIndex: 0,
      selectedObject: FALLBACK_TARGETS[0],
      skyObjects: createSkyChartObjects(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key),
      locationName,
      verdict: `暂时查不到 ${locationName} 的实时星图`,
      condition: '可以先按一般情况看月亮、亮星和行星；深空目标不要在城市里强求。',
      assistantLine: '实时接口不可用时，已切到安全兜底建议。',
      requestStatus: 'fallback',
      diagnosticLine: shortText(reason || 'fetch failed', 62)
    }, createHudSlots(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key), createSelectedSkyOverlay(FALLBACK_TARGETS[0], 0)))
    this.applyMode('overview')
  },

  openHome() {
    this.reportEvent('openHome')
    this.applyMode('home')
  },

  openOverview() {
    this.reportEvent('openOverview')
    this.applyMode('overview')
  },

  openDetail() {
    this.reportEvent('openDetail')
    this.applyMode('detail')
  },

  openLocate() {
    this.reportEvent('openLocate')
    this.applyMode('locate')
  },

  goBack() {
    const mode = this.data.mode
    this.reportEvent(`back:${mode}`)
    if (mode === 'detail' || mode === 'locate') {
      this.applyMode('overview')
      return
    }
    if (mode === 'overview' || mode === 'chat' || mode === 'loading' || mode === 'error') {
      this.applyMode('home')
      return
    }
    this.applyMode('home')
  },

  confirmCurrent() {
    const mode = this.data.mode
    this.reportEvent(`confirm:${mode}`)
    if (mode === 'overview') {
      this.applyMode('detail')
      return
    }
    if (mode === 'detail') {
      this.setData({
        assistantLine: `${this.data.selectedObject.name}：${this.data.selectedObject.locate}`
      })
      return
    }
    if (mode === 'locate') {
      this.applyMode('detail')
      return
    }
    if (mode === 'chat') {
      this.startAsr()
      return
    }
    if (mode === 'home') {
      this.startAsr()
    }
  },

  moveSelection(offset) {
    const targets = this.data.visibleObjects && this.data.visibleObjects.length ? this.data.visibleObjects : FALLBACK_TARGETS
    const currentIndex = Math.max(0, targets.findIndex(item => item.key === this.data.selectedKey))
    const nextIndex = (currentIndex + offset + targets.length) % targets.length
    const target = targets[nextIndex] || targets[0] || FALLBACK_TARGETS[0]
    this.reportEvent(`focus:${target.key}`)
    this.setData(Object.assign({
      selectedIndex: nextIndex,
      selectedKey: target.key,
      selectedObject: target,
      skyObjects: createSkyChartObjects(this.data.skyObjects, target.key)
    }, createHudSlots(targets, target.key), createSelectedSkyOverlay(target, nextIndex)))
  },

  selectObject(event) {
    const dataset = (event && event.currentTarget && event.currentTarget.dataset) || {}
    const key = dataset.key || this.data.selectedKey
    const allObjects = (this.data.visibleObjects || []).concat(this.data.skyObjects || [])
    const target = allObjects.find(item => item.key === key) || this.data.visibleObjects[0] || FALLBACK_TARGETS[0]
    const index = Math.max(0, this.data.visibleObjects.findIndex(item => item.key === target.key))
    this.reportEvent(`selectObject:${key}`)
    this.setData(Object.assign({
      selectedIndex: index,
      selectedKey: target.key,
      selectedObject: target,
      skyObjects: createSkyChartObjects(this.data.skyObjects, target.key)
    }, createHudSlots(this.data.visibleObjects, target.key), createSelectedSkyOverlay(target, index)))
    this.applyMode('detail')
  }
}
</script>

<page>
  <view class="shell card {{ mode }}" tabindex="0" focusable="true" bindkeyup="onKeyUp">
    <view class="top-row">
      <view>
        <text class="brand">SkyMate</text>
        <text class="meta">{{ locationName }}</text>
      </view>
      <text class="status-pill">{{ pageTag }}</text>
    </view>

    <view class="sky-panel" bindtap="openDetail">
      <text class="sky-panel-title">实时星图</text>
      <text class="sky-panel-meta">地平坐标 · {{ objectCount }} 个推荐</text>
      <view class="sky-map">
        <view class="sky-circle horizon-ring"></view>
        <view class="sky-circle ring-30"></view>
        <view class="sky-circle ring-60"></view>
        <view class="sky-cross sky-cross-h"></view>
        <view class="sky-cross sky-cross-v"></view>
        <text class="cardinal cardinal-n">N</text>
        <text class="cardinal cardinal-e">E</text>
        <text class="cardinal cardinal-s">S</text>
        <text class="cardinal cardinal-w">W</text>
        <text
          class="sky-target {{ item.typeClass }} {{ item.selectedClass }}"
          style="{{ item.style }}"
          ink:for="{{ skyObjects }}"
          ink:for-item="item"
          ink:key="key"
          data-key="{{ item.key }}"
          bindtap="selectObject"
        ></text>
        <text
          class="sky-target-label"
          style="{{ item.labelStyle }}"
          ink:for="{{ skyObjects }}"
          ink:for-item="item"
          ink:key="key"
        >{{ item.name }}</text>
        <text
          class="selected-sky-marker {{ selectedObject.typeClass }}"
          style="{{ selectedSkyMarkerStyle }}"
        ></text>
        <text
          class="selected-sky-name"
          style="{{ selectedSkyLabelStyle }}"
        >{{ selectedObject.name }}</text>
      </view>
      <text class="sky-label">{{ selectedObject.name }}</text>
      <text class="sky-meta">{{ selectedObject.direction }} · {{ selectedObject.altitude }}</text>
    </view>

    <view class="content home-panel" style="display: {{ homeDisplay }};">
      <text class="kicker">观星助手</text>
      <text class="headline">SkyMate 帮你看今晚星空</text>
      <text class="body">我会读取 GPS 位置，判断今晚是否值得出门，并标出月亮、行星和亮星的大致方向。</text>
      <view class="button-grid home-actions">
        <button class="btn primary gps-btn" bindtap="runCurrentLocation">使用当前位置</button>
      </view>
    </view>

    <view class="content chat-panel" style="display: {{ chatDisplay }};">
      <text class="kicker">语音查询</text>
      <text class="headline">说出城市和问题</text>
      <text class="body">比如：今晚苏州能看到什么，或厦门能不能看金星。</text>
      <view class="asr-guide">
        <text class="guide-dot"></text>
        <text class="guide-text">{{ assistantLine }}</text>
      </view>
      <view class="button-grid">
        <button class="btn primary" bindtap="startAsr">开始听</button>
        <button class="btn secondary" bindtap="locateOnly">定位</button>
        <button class="btn ghost" bindtap="openHome">返回</button>
      </view>
      <text class="location-readout">{{ locationLine }}</text>
    </view>

    <view class="content loading-panel" style="display: {{ loadingDisplay }};">
      <text class="headline">正在查星空</text>
      <text class="body">{{ assistantLine }}</text>
      <text class="debug-line">{{ diagnosticLine }}</text>
    </view>

    <view class="content overview-panel" style="display: {{ overviewDisplay }};">
      <text class="headline">{{ verdict }}</text>
      <text class="body">{{ condition }}</text>
      <view class="target-row">
        <button class="target-btn {{ target0Class }}" data-key="{{ target0Key }}" bindtap="selectObject">
          <text class="target-name">{{ target0Name }}</text>
          <text class="target-meta">{{ target0Meta }}</text>
        </button>
        <button class="target-btn {{ target1Class }}" data-key="{{ target1Key }}" bindtap="selectObject">
          <text class="target-name">{{ target1Name }}</text>
          <text class="target-meta">{{ target1Meta }}</text>
        </button>
        <button class="target-btn {{ target2Class }}" data-key="{{ target2Key }}" bindtap="selectObject">
          <text class="target-name">{{ target2Name }}</text>
          <text class="target-meta">{{ target2Meta }}</text>
        </button>
        <button class="target-btn {{ target3Class }}" data-key="{{ target3Key }}" bindtap="selectObject">
          <text class="target-name">{{ target3Name }}</text>
          <text class="target-meta">{{ target3Meta }}</text>
        </button>
        <button class="target-btn {{ target4Class }}" data-key="{{ target4Key }}" bindtap="selectObject">
          <text class="target-name">{{ target4Name }}</text>
          <text class="target-meta">{{ target4Meta }}</text>
        </button>
      </view>
      <view class="button-grid compact overview-actions">
        <button class="btn ghost" bindtap="openHome">退出</button>
      </view>
    </view>

    <view class="content detail-panel" style="display: {{ detailDisplay }};">
      <text class="kicker">{{ selectedObject.type }}</text>
      <text class="headline">{{ selectedObject.name }}</text>
      <text class="body detail-meta">{{ selectedObject.direction }} · 高度 {{ selectedObject.altitude }} · 亮度 {{ selectedObject.magnitude }}</text>
      <view class="detail-block">
        <text class="detail-label">怎么找</text>
        <text class="detail-text">{{ selectedObject.locate }}</text>
      </view>
      <view class="detail-block intro-block">
        <text class="detail-label">介绍</text>
        <text class="detail-text">{{ selectedObject.intro }}</text>
      </view>
    </view>

    <view class="content locate-panel" style="display: {{ locateDisplay }};">
      <text class="headline">朝 {{ selectedObject.direction }} 看</text>
      <text class="body">{{ selectedObject.locate }}</text>
      <view class="button-grid compact">
        <button class="btn secondary" bindtap="openDetail">详情</button>
        <button class="btn ghost" bindtap="openOverview">总览</button>
      </view>
    </view>

    <view class="content error-panel" style="display: {{ errorDisplay }};">
      <text class="headline">暂时查不到实时数据</text>
      <text class="body">可以先按一般情况看月亮、亮星和行星。</text>
      <view class="button-grid compact">
        <button class="btn primary" bindtap="runCurrentLocation">重试定位</button>
        <button class="btn secondary" bindtap="runSuzhouDemo">苏州兜底</button>
      </view>
    </view>

    <view class="bottom-row">
      <text class="hint">{{ buildVersion }} · {{ requestStatus }}</text>
      <text class="hint right">{{ asrStatus }}</text>
    </view>
  </view>
</page>

<style>
.shell {
  width: 448px;
  min-height: 150px;
  box-sizing: border-box;
  padding: 7px 9px;
  overflow: hidden;
  color: #f6f7ec;
  background:
    radial-gradient(circle at 8% 12%, rgba(117, 255, 149, 0.22), transparent 25%),
    radial-gradient(circle at 84% 18%, rgba(255, 213, 104, 0.16), transparent 24%),
    linear-gradient(145deg, #020403 0%, #09100d 48%, #16180d 100%);
  border: 1px solid rgba(154, 255, 177, 0.30);
  border-radius: 14px;
}

.topbar {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 4px;
}

.brand {
  display: block;
  color: #ffffff;
  font-size: 20px;
  line-height: 21px;
  font-weight: 900;
  letter-spacing: -1px;
}

.subtitle {
  display: block;
  color: rgba(246, 247, 236, 0.58);
  font-size: 10px;
  line-height: 12px;
}

.right-stack {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.pill {
  min-width: 44px;
  height: 18px;
  line-height: 18px;
  text-align: center;
  color: #baffc6;
  background: rgba(93, 255, 126, 0.10);
  border: 1px solid rgba(93, 255, 126, 0.42);
  border-radius: 11px;
  font-size: 10px;
  font-weight: 800;
}

.diag {
  display: block;
  max-width: 172px;
  margin-top: 2px;
  overflow: hidden;
  color: rgba(158, 255, 177, 0.64);
  font-size: 8px;
  line-height: 10px;
  text-align: right;
}

.panel {
  display: block;
}

.hero,
.loading-row {
  display: flex;
  flex-direction: row;
  gap: 8px;
  align-items: center;
}

.mini-sky {
  position: relative;
  width: 76px;
  height: 46px;
  flex-shrink: 0;
  border-radius: 12px;
  background: radial-gradient(circle at 55% 68%, rgba(255, 211, 99, 0.30), transparent 12%), #030504;
  border: 1px solid rgba(246, 247, 236, 0.12);
}

.dot {
  position: absolute;
  width: 4px;
  height: 4px;
  border-radius: 2px;
  background: #f6f7ec;
}

.d1 {
  left: 22px;
  top: 17px;
}

.d2 {
  right: 20px;
  top: 14px;
}

.d3 {
  left: 45px;
  top: 38px;
}

.glow {
  position: absolute;
  left: 53px;
  top: 35px;
  width: 10px;
  height: 10px;
  border-radius: 5px;
  background: #ffd46b;
  box-shadow: 0 0 16px rgba(255, 212, 107, 0.8);
}

.hero-copy {
  flex: 1;
}

.kicker {
  display: block;
  color: #aef7ba;
  font-size: 10px;
  line-height: 12px;
  font-weight: 800;
}

.headline {
  display: block;
  color: #ffffff;
  font-size: 17px;
  line-height: 19px;
  font-weight: 900;
}

.headline.small {
  font-size: 13px;
  line-height: 15px;
}

.body {
  display: block;
  margin-top: 3px;
  color: rgba(246, 247, 236, 0.72);
  font-size: 9px;
  line-height: 11px;
}

.button-grid {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 5px;
}

.button-grid.slim {
  margin-top: 4px;
}

.btn {
  min-width: 57px;
  height: 21px;
  line-height: 21px;
  padding: 0 6px;
  color: #f6f7ec;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(246, 247, 236, 0.16);
  border-radius: 8px;
  font-size: 9px;
  font-weight: 900;
}

.primary {
  color: #031006;
  background: #75ff8c;
  border-color: rgba(117, 255, 140, 0.84);
}

.secondary {
  color: #dfffe5;
  background: rgba(117, 255, 140, 0.10);
  border-color: rgba(117, 255, 140, 0.40);
}

.ghost {
  color: rgba(246, 247, 236, 0.78);
}

.loader {
  width: 26px;
  height: 26px;
  border-radius: 13px;
  border: 2px solid rgba(117, 255, 140, 0.25);
  background: radial-gradient(circle, rgba(117, 255, 140, 0.8), transparent 35%);
}

.verdict {
  padding: 4px 7px;
  border-radius: 9px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(246, 247, 236, 0.10);
}

.target-list {
  display: flex;
  flex-direction: row;
  gap: 5px;
  margin-top: 5px;
}

.target-card {
  width: 82px;
  min-height: 39px;
  padding: 4px;
  text-align: left;
  border-radius: 9px;
  background: rgba(255, 255, 255, 0.07);
  border: 1px solid rgba(246, 247, 236, 0.13);
}

.target-card.planet {
  border-color: rgba(255, 214, 111, 0.55);
}

.target-card.star {
  border-color: rgba(160, 225, 255, 0.48);
}

.target-card.moon {
  border-color: rgba(246, 247, 236, 0.62);
}

.target-name {
  display: block;
  color: #ffffff;
  font-size: 12px;
  line-height: 14px;
  font-weight: 900;
}

.target-meta {
  display: block;
  margin-top: 3px;
  color: rgba(246, 247, 236, 0.64);
  font-size: 8px;
  line-height: 10px;
}

.metric-row {
  display: flex;
  flex-direction: row;
  gap: 5px;
  margin: 5px 0;
}

.metric {
  flex: 1;
  padding: 4px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.06);
}

.metric-label,
.metric-value {
  display: block;
  font-size: 9px;
  line-height: 12px;
}

.metric-label {
  color: rgba(246, 247, 236, 0.50);
}

.metric-value {
  color: #ffffff;
  font-weight: 900;
}

.status {
  margin-top: 4px;
  padding-top: 2px;
  border-top: 1px solid rgba(246, 247, 236, 0.10);
}

.debug-line {
  display: block;
  max-width: 410px;
  overflow: hidden;
  color: rgba(246, 247, 236, 0.66);
  font-size: 8px;
  line-height: 10px;
}

.status-line {
  display: none;
}

.debug-line {
  color: rgba(158, 255, 177, 0.62);
}

/* Deprecated experimental HUD skin. Kept inert because the template now uses .shell.card. */
.shell.hud {
  position: relative;
  width: 448px;
  height: 150px;
  min-height: 150px;
  padding: 0;
  overflow: hidden;
  color: #dfffe5;
  background:
    radial-gradient(circle at 78% 44%, rgba(83, 255, 125, 0.14), transparent 33%),
    linear-gradient(135deg, #020604 0%, #050d09 48%, #020403 100%);
  border: 1px solid rgba(76, 255, 116, 0.32);
  border-radius: 16px;
  font-family: Arial, sans-serif;
}

.scanline,
.vignette {
  position: absolute;
  left: 0;
  top: 0;
  width: 448px;
  height: 150px;
  pointer-events: none;
}

.scanline {
  opacity: 0.08;
  background: repeating-linear-gradient(to bottom, rgba(76, 255, 116, 0.08) 0, rgba(76, 255, 116, 0.08) 1px, transparent 1px, transparent 8px);
}

.vignette {
  box-shadow:
    inset 0 0 18px rgba(76, 255, 116, 0.08),
    inset 0 0 58px rgba(0, 0, 0, 0.90);
}

.corner {
  position: absolute;
  width: 16px;
  height: 16px;
  border-color: rgba(76, 255, 116, 0.64);
  z-index: 7;
}

.corner-tl {
  left: 10px;
  top: 10px;
  border-left: 2px solid;
  border-top: 2px solid;
}

.corner-tr {
  right: 10px;
  top: 10px;
  border-right: 2px solid;
  border-top: 2px solid;
}

.corner-bl {
  left: 10px;
  bottom: 10px;
  border-left: 2px solid;
  border-bottom: 2px solid;
}

.corner-br {
  right: 10px;
  bottom: 10px;
  border-right: 2px solid;
  border-bottom: 2px solid;
}

.hud-panel {
  position: absolute;
  top: 12px;
  z-index: 5;
}

.panel-left {
  left: 18px;
  width: 180px;
  text-align: left;
}

.panel-right {
  right: 18px;
  width: 128px;
  text-align: right;
}

.shell.hud .brand,
.shell.hud .meta,
.shell.hud .target-name,
.shell.hud .target-line {
  display: block;
  white-space: nowrap;
}

.shell.hud .brand {
  color: #5dff7c;
  font-size: 18px;
  line-height: 20px;
  font-weight: 900;
  letter-spacing: -0.5px;
}

.shell.hud .meta {
  max-width: 180px;
  overflow: hidden;
  color: rgba(198, 255, 210, 0.62);
  font-size: 9px;
  line-height: 11px;
}

.shell.hud .meta.strong {
  color: #5dff7c;
  font-size: 10px;
  font-weight: 900;
}

.shell.hud .state-pill {
  position: absolute;
  right: 18px;
  top: 34px;
  width: 86px;
  height: 18px;
  line-height: 18px;
  text-align: center;
  border: 1px solid rgba(93, 255, 124, 0.48);
  border-radius: 10px;
  background: rgba(0, 0, 0, 0.72);
  color: #5dff7c;
  font-size: 9px;
  font-weight: 900;
  box-shadow: 0 0 10px rgba(93, 255, 124, 0.14);
  z-index: 6;
}

.chart {
  position: absolute;
  left: 272px;
  top: 56px;
  width: 146px;
  height: 62px;
  overflow: hidden;
  border: 1px solid rgba(93, 255, 124, 0.38);
  border-radius: 10px;
  background:
    radial-gradient(circle at 50% 52%, rgba(93, 255, 124, 0.09), rgba(0, 0, 0, 0) 52%),
    rgba(0, 0, 0, 0.36);
  z-index: 2;
}

.grid {
  position: absolute;
  background: rgba(93, 255, 124, 0.12);
}

.grid-v {
  top: 0;
  width: 1px;
  height: 62px;
}

.grid-h {
  left: 0;
  width: 146px;
  height: 1px;
}

.g1 { left: 36px; }
.g2 { left: 73px; }
.g3 { left: 109px; }
.g4 { top: 21px; }
.g5 { top: 42px; }

.horizon {
  position: absolute;
  left: 20px;
  top: 10px;
  width: 106px;
  height: 42px;
  border: 1px solid rgba(93, 255, 124, 0.24);
  border-radius: 53px / 21px;
}

.axis {
  position: absolute;
  background: rgba(93, 255, 124, 0.16);
}

.axis-x {
  left: 22px;
  top: 31px;
  width: 102px;
  height: 1px;
}

.axis-y {
  left: 73px;
  top: 8px;
  width: 1px;
  height: 46px;
}

.bg-star {
  position: absolute;
  border-radius: 3px;
  background: rgba(165, 255, 184, 0.45);
  box-shadow: 0 0 4px rgba(93, 255, 124, 0.24);
  z-index: 1;
}

.star {
  position: absolute;
  display: block;
  min-width: 0;
  padding: 0;
  border-radius: 12px;
  border: 1px solid #8dffa1;
  background: rgba(93, 255, 124, 0.12);
  box-shadow:
    0 0 8px rgba(93, 255, 124, 0.62),
    0 0 14px rgba(93, 255, 124, 0.24);
  z-index: 4;
}

.star.planet {
  border-color: #ffd965;
  background: rgba(255, 217, 101, 0.18);
  box-shadow: 0 0 12px rgba(255, 217, 101, 0.55);
}

.star.moon {
  border-color: #f7ffe7;
  background: rgba(247, 255, 231, 0.18);
}

.star.selected {
  border-width: 2px;
}

.star-label {
  position: absolute;
  max-width: 42px;
  overflow: hidden;
  color: rgba(226, 255, 232, 0.78);
  font-size: 7px;
  line-height: 9px;
  z-index: 5;
}

.focus-ring {
  position: absolute;
  border: 1px solid rgba(93, 255, 124, 0.56);
  border-radius: 16px;
  box-shadow: 0 0 12px rgba(93, 255, 124, 0.16);
  z-index: 3;
}

.focus-dot {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 4px;
  height: 4px;
  margin-left: -2px;
  margin-top: -2px;
  border-radius: 2px;
  background: #5dff7c;
}

.reticle {
  position: absolute;
  z-index: 3;
}

.reticle-circle {
  left: 61px;
  top: 20px;
  width: 24px;
  height: 24px;
  border: 1px solid rgba(93, 255, 124, 0.30);
  border-radius: 13px;
}

.reticle-h {
  top: 32px;
  width: 36px;
  height: 1px;
  background: rgba(93, 255, 124, 0.24);
}

.reticle-h.left { left: 18px; }
.reticle-h.right { right: 18px; }

.reticle-v {
  left: 73px;
  width: 1px;
  height: 13px;
  background: rgba(93, 255, 124, 0.24);
}

.reticle-v.top { top: 5px; }
.reticle-v.bottom { bottom: 5px; }

.mode-panel {
  position: absolute;
  left: 18px;
  top: 48px;
  width: 238px;
  z-index: 6;
}

.overview-panel,
.detail-panel,
.locate-panel,
.error-panel {
  left: 18px;
  top: 44px;
  width: 238px;
}

.loading-panel {
  left: 18px;
  top: 52px;
  width: 238px;
}

.shell.hud .headline {
  display: block;
  max-width: 238px;
  max-height: 31px;
  overflow: hidden;
  color: #f7ffe7;
  font-size: 15px;
  line-height: 16px;
  font-weight: 900;
}

.shell.hud .body,
.shell.hud .debug-line {
  display: block;
  max-width: 228px;
  max-height: 24px;
  overflow: hidden;
  color: rgba(218, 255, 224, 0.70);
  font-size: 10px;
  line-height: 12px;
}

.shell.hud .kicker {
  display: block;
  color: rgba(93, 255, 124, 0.82);
  font-size: 9px;
  line-height: 11px;
  font-weight: 900;
}

.button-grid {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 5px;
  margin-top: 8px;
}

.button-grid.compact {
  margin-top: 7px;
}

.shell.hud .btn {
  min-width: 48px;
  height: 20px;
  line-height: 20px;
  padding: 0 7px;
  border-radius: 8px;
  border: 1px solid rgba(93, 255, 124, 0.36);
  background: rgba(0, 0, 0, 0.64);
  color: #8dffa1;
  font-size: 9px;
  font-weight: 900;
}

.shell.hud .btn.primary {
  background: rgba(93, 255, 124, 0.18);
  border-color: rgba(93, 255, 124, 0.72);
  color: #d8ffde;
}

.shell.hud .btn.ghost {
  color: rgba(218, 255, 224, 0.70);
  border-color: rgba(218, 255, 224, 0.20);
}

.shell.hud .target-card {
  position: absolute;
  right: 18px;
  bottom: 12px;
  width: 146px;
  min-height: 22px;
  padding: 3px 7px;
  text-align: left;
  border: 1px solid rgba(93, 255, 124, 0.28);
  border-radius: 8px;
  background: rgba(0, 0, 0, 0.64);
  z-index: 5;
}

.shell.hud .target-name {
  color: #f7ffe7;
  font-size: 10px;
  line-height: 12px;
  font-weight: 900;
}

.shell.hud .target-line {
  max-width: 132px;
  overflow: hidden;
  color: rgba(141, 255, 161, 0.70);
  font-size: 7px;
  line-height: 8px;
}

.shell.hud .target-line.dim {
  display: none;
}

/* Readable production card: overrides experimental HUD styles above. */
.shell.card {
  position: relative;
  width: 448px;
  height: 320px;
  min-height: 320px;
  box-sizing: border-box;
  padding: 18px 20px 16px;
  overflow: hidden;
  color: #eef7ee;
  background:
    radial-gradient(circle at 88% 20%, rgba(101, 255, 151, 0.18), transparent 30%),
    radial-gradient(circle at 12% 105%, rgba(255, 207, 91, 0.12), transparent 32%),
    linear-gradient(135deg, #040706 0%, #08110d 58%, #030503 100%);
  border: 1px solid rgba(98, 255, 139, 0.28);
  border-radius: 18px;
  font-family: Arial, sans-serif;
}

.top-row {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-start;
}

.shell.card .brand {
  display: block;
  color: #ffffff;
  font-size: 24px;
  line-height: 26px;
  font-weight: 900;
  letter-spacing: -0.6px;
}

.shell.card .meta {
  display: block;
  max-width: 280px;
  overflow: hidden;
  color: rgba(238, 247, 238, 0.58);
  font-size: 12px;
  line-height: 15px;
}

.status-pill {
  display: block;
  height: 26px;
  line-height: 26px;
  padding: 0 13px;
  border: 1px solid rgba(98, 255, 139, 0.46);
  border-radius: 14px;
  color: #8dffa3;
  background: rgba(98, 255, 139, 0.08);
  font-size: 11px;
  font-weight: 800;
}

.content {
  position: absolute;
  left: 20px;
  top: 86px;
  width: 262px;
}

.shell.card .headline {
  display: block;
  max-width: 262px;
  max-height: 72px;
  overflow: hidden;
  color: #ffffff;
  font-size: 26px;
  line-height: 30px;
  font-weight: 900;
}

.shell.card .body {
  display: block;
  max-width: 262px;
  max-height: 72px;
  margin-top: 8px;
  overflow: hidden;
  color: rgba(238, 247, 238, 0.70);
  font-size: 14px;
  line-height: 18px;
}

.shell.card .kicker {
  display: block;
  color: #8dffa3;
  font-size: 12px;
  line-height: 15px;
  font-weight: 800;
}

.button-grid,
.button-grid.compact {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 16px;
}

.shell.card .btn {
  min-width: 66px;
  height: 34px;
  line-height: 34px;
  padding: 0 13px;
  border: 1px solid rgba(238, 247, 238, 0.16);
  border-radius: 14px;
  color: #e8f7e9;
  background: rgba(255, 255, 255, 0.06);
  font-size: 13px;
  font-weight: 800;
}

.shell.card .btn.primary {
  color: #061208;
  background: #77ff91;
  border-color: #77ff91;
}

.shell.card .btn.secondary {
  color: #9dffaf;
  background: rgba(119, 255, 145, 0.09);
  border-color: rgba(119, 255, 145, 0.35);
}

.shell.card .btn.ghost {
  color: rgba(238, 247, 238, 0.72);
}

.target-row {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 16px;
}

.target-btn {
  width: 180px;
  height: 34px;
  line-height: 34px;
  padding: 0 12px;
  overflow: hidden;
  text-align: left;
  border: 1px solid rgba(119, 255, 145, 0.34);
  border-radius: 14px;
  color: #eaffed;
  background: rgba(119, 255, 145, 0.08);
  font-size: 13px;
  font-weight: 900;
}

.target-btn.planet {
  border-color: rgba(255, 214, 111, 0.58);
  color: #ffe18a;
  background: rgba(255, 214, 111, 0.10);
}

.target-btn.selected {
  background: rgba(119, 255, 145, 0.18);
}

.bottom-row {
  position: absolute;
  left: 20px;
  right: 20px;
  bottom: 16px;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-end;
}

.hint {
  display: block;
  max-width: 260px;
  overflow: hidden;
  color: rgba(238, 247, 238, 0.38);
  font-size: 11px;
  line-height: 14px;
}

.shell.card .mini-sky {
  position: absolute;
  right: 20px;
  top: 86px;
  width: 118px;
  height: 118px;
  flex-shrink: 0;
  border: 1px solid rgba(119, 255, 145, 0.18);
  border-radius: 24px;
  background:
    radial-gradient(circle at 50% 50%, rgba(119, 255, 145, 0.13), transparent 52%),
    rgba(0, 0, 0, 0.22);
}

.sky-dot {
  position: absolute;
  width: 6px;
  height: 6px;
  border-radius: 3px;
  background: #dffff0;
  box-shadow: 0 0 6px rgba(223, 255, 240, 0.55);
}

.sky-dot.d1 {
  left: 28px;
  top: 30px;
}

.sky-dot.d2 {
  left: 62px;
  top: 68px;
}

.sky-dot.d3 {
  right: 24px;
  top: 34px;
}

/* v4 production skin: compact smart-glasses card, 448 x 320. */
.shell.card {
  position: relative;
  width: 448px;
  height: 320px;
  min-height: 320px;
  box-sizing: border-box;
  padding: 18px 18px 14px;
  overflow: hidden;
  color: #edf7ee;
  background:
    radial-gradient(circle at 82% 28%, rgba(88, 196, 122, 0.22), transparent 30%),
    radial-gradient(circle at 14% 92%, rgba(223, 179, 86, 0.13), transparent 28%),
    linear-gradient(142deg, #050706 0%, #0b1210 52%, #050706 100%);
  border: 1px solid rgba(133, 220, 151, 0.24);
  border-radius: 22px;
  font-family: Arial, sans-serif;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.025);
}

.top-row {
  position: relative;
  z-index: 5;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-start;
}

.shell.card .brand {
  display: block;
  color: #ffffff;
  font-size: 24px;
  line-height: 26px;
  font-weight: 900;
  letter-spacing: -0.6px;
}

.shell.card .meta {
  display: block;
  max-width: 250px;
  height: 17px;
  overflow: hidden;
  color: rgba(237, 247, 238, 0.58);
  font-size: 12px;
  line-height: 17px;
}

.status-pill {
  display: block;
  max-width: 96px;
  height: 25px;
  line-height: 25px;
  padding: 0 11px;
  overflow: hidden;
  text-align: center;
  border: 1px solid rgba(133, 220, 151, 0.42);
  border-radius: 14px;
  color: #bdf7c8;
  background: rgba(133, 220, 151, 0.08);
  font-size: 10px;
  font-weight: 800;
}

.content {
  position: absolute;
  left: 18px;
  top: 84px;
  z-index: 4;
  width: 252px;
}

.shell.card .headline {
  display: block;
  max-width: 252px;
  max-height: 70px;
  overflow: hidden;
  color: #ffffff;
  font-size: 25px;
  line-height: 29px;
  font-weight: 900;
  letter-spacing: -0.3px;
}

.shell.card .body {
  display: block;
  max-width: 246px;
  max-height: 58px;
  margin-top: 8px;
  overflow: hidden;
  color: rgba(237, 247, 238, 0.72);
  font-size: 13px;
  line-height: 18px;
}

.shell.card .kicker {
  display: block;
  margin-bottom: 5px;
  color: #9feeb0;
  font-size: 12px;
  line-height: 15px;
  font-weight: 800;
}

.button-grid,
.button-grid.compact {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 15px;
}

.shell.card .btn {
  min-width: 66px;
  height: 34px;
  line-height: 34px;
  padding: 0 13px;
  border: 1px solid rgba(237, 247, 238, 0.16);
  border-radius: 13px;
  color: rgba(237, 247, 238, 0.88);
  background: rgba(255, 255, 255, 0.055);
  font-size: 13px;
  font-weight: 800;
}

.shell.card .btn.primary {
  color: #041007;
  background: #9ff0a7;
  border-color: #9ff0a7;
}

.shell.card .btn.secondary {
  color: #c5f7ce;
  background: rgba(159, 240, 167, 0.09);
  border-color: rgba(159, 240, 167, 0.33);
}

.shell.card .btn.ghost {
  color: rgba(237, 247, 238, 0.70);
}

.target-row {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 13px;
}

.target-btn {
  width: 196px;
  height: 34px;
  line-height: 34px;
  padding: 0 12px;
  overflow: hidden;
  text-align: left;
  border: 1px solid rgba(159, 240, 167, 0.30);
  border-radius: 13px;
  color: #edf7ee;
  background: rgba(159, 240, 167, 0.075);
  font-size: 13px;
  font-weight: 900;
}

.target-btn.planet {
  border-color: rgba(236, 197, 102, 0.55);
  color: #f1d28a;
  background: rgba(236, 197, 102, 0.11);
}

.target-btn.moon {
  border-color: rgba(232, 238, 222, 0.50);
  color: #f2f5e8;
}

.target-btn.selected {
  background: rgba(159, 240, 167, 0.17);
}

.sky-panel {
  position: absolute;
  right: 18px;
  top: 82px;
  z-index: 3;
  width: 130px;
  height: 168px;
  overflow: hidden;
  border: 1px solid rgba(159, 240, 167, 0.18);
  border-radius: 22px;
  background:
    radial-gradient(circle at 50% 42%, rgba(159, 240, 167, 0.10), transparent 42%),
    rgba(0, 0, 0, 0.18);
}

.orbit {
  position: absolute;
  left: 18px;
  top: 24px;
  border: 1px solid rgba(159, 240, 167, 0.18);
}

.orbit.outer {
  width: 94px;
  height: 64px;
  border-radius: 48px / 32px;
}

.orbit.inner {
  left: 38px;
  top: 37px;
  width: 52px;
  height: 36px;
  border-radius: 27px / 19px;
}

.sky-panel .sky-dot {
  position: absolute;
  display: block;
  width: 4px;
  height: 4px;
  border-radius: 2px;
  background: #edf7ee;
  box-shadow: 0 0 7px rgba(237, 247, 238, 0.58);
}

.sky-panel .d1 {
  left: 26px;
  right: auto;
  top: 32px;
}

.sky-panel .d2 {
  left: 88px;
  right: auto;
  top: 48px;
}

.sky-panel .d3 {
  left: 61px;
  right: auto;
  top: 72px;
}

.target-glow {
  position: absolute;
  left: 48px;
  top: 45px;
  width: 34px;
  height: 34px;
  border-radius: 18px;
  background: radial-gradient(circle, rgba(159, 240, 167, 0.78), rgba(159, 240, 167, 0.12) 42%, transparent 70%);
  box-shadow: 0 0 20px rgba(159, 240, 167, 0.34);
}

.target-glow.planet {
  background: radial-gradient(circle, rgba(236, 197, 102, 0.86), rgba(236, 197, 102, 0.16) 42%, transparent 70%);
  box-shadow: 0 0 22px rgba(236, 197, 102, 0.36);
}

.target-glow.moon {
  background: radial-gradient(circle, rgba(239, 243, 225, 0.9), rgba(239, 243, 225, 0.14) 42%, transparent 70%);
  box-shadow: 0 0 22px rgba(239, 243, 225, 0.32);
}

.sky-label {
  position: absolute;
  left: 14px;
  right: 14px;
  bottom: 35px;
  display: block;
  height: 18px;
  overflow: hidden;
  color: #ffffff;
  font-size: 14px;
  line-height: 18px;
  font-weight: 900;
}

.sky-meta {
  position: absolute;
  left: 14px;
  right: 14px;
  bottom: 18px;
  display: block;
  height: 15px;
  overflow: hidden;
  color: rgba(237, 247, 238, 0.62);
  font-size: 11px;
  line-height: 15px;
}

.bottom-row {
  position: absolute;
  left: 18px;
  right: 18px;
  bottom: 13px;
  z-index: 5;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
  padding-top: 10px;
  border-top: 1px solid rgba(237, 247, 238, 0.08);
}

.hint {
  display: block;
  max-width: 278px;
  height: 16px;
  overflow: hidden;
  color: rgba(237, 247, 238, 0.40);
  font-size: 11px;
  line-height: 16px;
}

.hint.right {
  max-width: 90px;
  text-align: right;
  color: rgba(159, 240, 167, 0.52);
}

/* v5 glance skin: compact, stable, and tuned for 448 x 320 smart-glasses UI. */
.shell.card {
  position: relative;
  width: 448px;
  height: 320px;
  min-height: 320px;
  box-sizing: border-box;
  padding: 16px 18px 12px;
  overflow: hidden;
  color: #f2f6ed;
  background:
    linear-gradient(150deg, #070908 0%, #10130f 58%, #0a0b09 100%),
    linear-gradient(90deg, rgba(118, 211, 137, 0.08), rgba(224, 188, 92, 0.06));
  border: 1px solid rgba(219, 232, 208, 0.16);
  border-radius: 8px;
  font-family: Arial, sans-serif;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.025);
}

.top-row {
  position: relative;
  z-index: 5;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-start;
}

.shell.card .brand {
  display: block;
  color: #ffffff;
  font-size: 24px;
  line-height: 26px;
  font-weight: 900;
  letter-spacing: 0;
}

.shell.card .meta {
  display: block;
  max-width: 258px;
  height: 17px;
  overflow: hidden;
  color: rgba(242, 246, 237, 0.58);
  font-size: 12px;
  line-height: 17px;
}

.status-pill {
  display: block;
  max-width: 86px;
  height: 24px;
  line-height: 24px;
  padding: 0 10px;
  overflow: hidden;
  text-align: center;
  border: 1px solid rgba(151, 218, 159, 0.44);
  border-radius: 8px;
  color: #c7f2c9;
  background: rgba(151, 218, 159, 0.09);
  font-size: 11px;
  font-weight: 800;
}

.content {
  position: absolute;
  left: 18px;
  top: 72px;
  z-index: 4;
  width: 252px;
}

.shell.card .headline {
  display: block;
  max-width: 252px;
  max-height: 58px;
  overflow: hidden;
  color: #ffffff;
  font-size: 24px;
  line-height: 28px;
  font-weight: 900;
  letter-spacing: 0;
}

.shell.card .body {
  display: block;
  max-width: 246px;
  max-height: 42px;
  margin-top: 7px;
  overflow: hidden;
  color: rgba(242, 246, 237, 0.70);
  font-size: 13px;
  line-height: 18px;
}

.overview-panel .headline,
.detail-panel .headline,
.locate-panel .headline,
.error-panel .headline {
  max-height: 52px;
  font-size: 22px;
  line-height: 26px;
}

.overview-panel .body,
.detail-panel .body,
.locate-panel .body,
.error-panel .body {
  max-height: 38px;
}

.shell.card .kicker {
  display: block;
  margin-bottom: 5px;
  color: #b8e9b8;
  font-size: 12px;
  line-height: 15px;
  font-weight: 800;
}

.button-grid,
.button-grid.compact {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 13px;
}

.shell.card .btn {
  min-width: 66px;
  height: 34px;
  line-height: 34px;
  padding: 0 12px;
  border: 1px solid rgba(242, 246, 237, 0.16);
  border-radius: 8px;
  color: rgba(242, 246, 237, 0.88);
  background: rgba(255, 255, 255, 0.055);
  font-size: 13px;
  font-weight: 800;
}

.shell.card .btn.primary {
  color: #071008;
  background: #b8e9b8;
  border-color: #b8e9b8;
}

.shell.card .btn.secondary {
  color: #cfefcf;
  background: rgba(184, 233, 184, 0.08);
  border-color: rgba(184, 233, 184, 0.28);
}

.shell.card .btn.ghost {
  color: rgba(242, 246, 237, 0.68);
}

.target-row {
  display: flex;
  flex-direction: column;
  gap: 5px;
  margin-top: 10px;
}

.target-btn,
.target-btn.star,
.target-btn.planet,
.target-btn.moon,
.target-btn.deep,
.target-btn.constellation,
.target-btn.meteor {
  position: relative;
  display: block;
  width: 218px;
  height: 32px;
  box-sizing: border-box;
  padding: 3px 10px;
  overflow: hidden;
  text-align: left;
  border: 1px solid rgba(184, 233, 184, 0.26);
  border-radius: 8px;
  color: #f2f6ed;
  background: rgba(184, 233, 184, 0.07);
  font-size: 12px;
  font-weight: 800;
}

.target-btn .target-name,
.target-btn .target-meta {
  display: block;
  max-width: 196px;
  overflow: hidden;
  white-space: nowrap;
}

.target-btn .target-name {
  color: #ffffff;
  font-size: 12px;
  line-height: 14px;
  font-weight: 900;
}

.target-btn .target-meta {
  margin-top: 1px;
  color: rgba(242, 246, 237, 0.56);
  font-size: 10px;
  line-height: 11px;
}

.target-btn.planet {
  border-color: rgba(225, 188, 92, 0.52);
  background: rgba(225, 188, 92, 0.10);
}

.target-btn.moon {
  border-color: rgba(232, 232, 218, 0.48);
  background: rgba(232, 232, 218, 0.08);
}

.target-btn.selected {
  border-color: rgba(184, 233, 184, 0.70);
  background: rgba(184, 233, 184, 0.15);
}

.sky-panel {
  position: absolute;
  right: 18px;
  top: 72px;
  z-index: 3;
  width: 134px;
  height: 188px;
  box-sizing: border-box;
  overflow: hidden;
  padding: 11px 10px 9px;
  border: 1px solid rgba(242, 246, 237, 0.14);
  border-radius: 8px;
  background: rgba(0, 0, 0, 0.20);
}

.sky-panel-title,
.sky-panel-meta,
.sky-label,
.sky-meta {
  display: block;
  overflow: hidden;
  white-space: nowrap;
}

.sky-panel-title {
  color: rgba(242, 246, 237, 0.92);
  font-size: 12px;
  line-height: 14px;
  font-weight: 900;
}

.sky-panel-meta {
  height: 13px;
  margin-top: 2px;
  color: rgba(242, 246, 237, 0.48);
  font-size: 9px;
  line-height: 13px;
}

.sky-map {
  position: absolute;
  left: 10px;
  top: 43px;
  width: 114px;
  height: 88px;
  overflow: hidden;
  border: 1px solid rgba(184, 233, 184, 0.16);
  border-radius: 8px;
  background: rgba(8, 12, 9, 0.72);
}

.sky-axis,
.sky-bg-dot,
.focus-ring,
.sky-target,
.sky-target-label {
  position: absolute;
}

.sky-axis {
  background: rgba(184, 233, 184, 0.10);
}

.sky-axis-h {
  left: 0;
  top: 50%;
  width: 114px;
  height: 1px;
}

.sky-axis-v {
  left: 50%;
  top: 0;
  width: 1px;
  height: 88px;
}

.sky-bg-dot {
  display: block;
  border-radius: 2px;
  background: rgba(242, 246, 237, 0.38);
}

.focus-ring {
  border: 1px solid rgba(184, 233, 184, 0.55);
  border-radius: 14px;
  box-shadow: 0 0 10px rgba(184, 233, 184, 0.10);
}

.sky-target,
.sky-target.star,
.sky-target.planet,
.sky-target.moon,
.sky-target.deep,
.sky-target.constellation,
.sky-target.meteor {
  display: block;
  min-width: 0;
  padding: 0;
  border: 1px solid #c9efcc;
  border-radius: 50%;
  background: #c9efcc;
  box-shadow: 0 0 8px rgba(201, 239, 204, 0.46);
}

.sky-target.planet {
  border-color: #e1bc5c;
  background: #e1bc5c;
  box-shadow: 0 0 9px rgba(225, 188, 92, 0.46);
}

.sky-target.moon {
  border-color: #f0f0df;
  background: #f0f0df;
}

.sky-target.selected {
  border-width: 2px;
}

.sky-target-label {
  max-width: 44px;
  height: 10px;
  overflow: hidden;
  color: rgba(242, 246, 237, 0.62);
  font-size: 8px;
  line-height: 10px;
}

.sky-label {
  position: absolute;
  left: 10px;
  right: 10px;
  bottom: 26px;
  height: 18px;
  color: #ffffff;
  font-size: 14px;
  line-height: 18px;
  font-weight: 900;
}

.sky-meta {
  position: absolute;
  left: 10px;
  right: 10px;
  bottom: 11px;
  height: 13px;
  color: rgba(242, 246, 237, 0.54);
  font-size: 10px;
  line-height: 13px;
}

.bottom-row {
  position: absolute;
  left: 18px;
  right: 18px;
  bottom: 12px;
  z-index: 5;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
  height: 20px;
  padding-top: 8px;
  border-top: 1px solid rgba(242, 246, 237, 0.08);
}

.hint {
  display: block;
  max-width: 280px;
  height: 14px;
  overflow: hidden;
  color: rgba(242, 246, 237, 0.36);
  font-size: 10px;
  line-height: 14px;
}

.hint.right {
  max-width: 86px;
  text-align: right;
  color: rgba(184, 233, 184, 0.52);
}

/* v6 interaction polish: keyboard focus, ASR guide, and denser overview fit. */
.shell.card.overview .content {
  top: 66px;
}

.shell.card.detail .content,
.shell.card.locate .content,
.shell.card.chat .content,
.shell.card.loading .content,
.shell.card.error .content {
  top: 76px;
}

.overview-panel .headline {
  max-height: 49px;
  font-size: 21px;
  line-height: 24px;
}

.overview-panel .body {
  max-height: 34px;
  margin-top: 6px;
  font-size: 12px;
  line-height: 17px;
}

.overview-panel .target-row {
  gap: 4px;
  margin-top: 8px;
}

.overview-panel .target-btn {
  height: 30px;
  padding-top: 2px;
}

.overview-panel .target-btn .target-name {
  line-height: 13px;
}

.overview-panel .target-btn .target-meta {
  line-height: 10px;
}

.overview-actions {
  margin-top: 4px;
}

.overview-actions .btn {
  min-width: 46px;
  height: 22px;
  line-height: 22px;
  padding: 0 8px;
  font-size: 10px;
}

.target-btn.selected,
.target-btn.star.selected,
.target-btn.planet.selected,
.target-btn.moon.selected,
.target-btn.deep.selected,
.target-btn.constellation.selected,
.target-btn.meteor.selected {
  border-color: rgba(151, 218, 159, 0.92);
  background: rgba(151, 218, 159, 0.16);
  box-shadow: 0 0 12px rgba(151, 218, 159, 0.22);
}

.target-btn.selected .target-name {
  color: #ffffff;
}

.target-btn.selected .target-meta {
  color: rgba(220, 246, 218, 0.72);
}

.asr-guide {
  display: flex;
  flex-direction: row;
  align-items: center;
  width: 232px;
  height: 30px;
  margin-top: 10px;
  padding: 0 9px;
  box-sizing: border-box;
  border: 1px solid rgba(151, 218, 159, 0.22);
  border-radius: 8px;
  background: rgba(151, 218, 159, 0.08);
}

.guide-dot {
  display: block;
  width: 8px;
  height: 8px;
  margin-right: 8px;
  border-radius: 4px;
  background: #b8e9b8;
  box-shadow: 0 0 10px rgba(184, 233, 184, 0.55);
}

.guide-text {
  display: block;
  max-width: 190px;
  height: 16px;
  overflow: hidden;
  color: rgba(242, 246, 237, 0.72);
  font-size: 11px;
  line-height: 16px;
}

.sky-panel {
  top: 66px;
  height: 200px;
  border-color: rgba(242, 246, 237, 0.16);
  background:
    radial-gradient(circle at 48% 45%, rgba(151, 218, 159, 0.12), transparent 42%),
    rgba(0, 0, 0, 0.28);
}

.sky-map {
  top: 43px;
  height: 100px;
  background:
    radial-gradient(circle at 50% 55%, rgba(184, 233, 184, 0.08), transparent 52%),
    linear-gradient(180deg, rgba(255, 255, 255, 0.035), rgba(255, 255, 255, 0.01)),
    rgba(8, 12, 9, 0.78);
}

.sky-axis-h {
  width: 114px;
}

.sky-axis-v {
  height: 100px;
}

.sky-target,
.sky-target.star,
.sky-target.planet,
.sky-target.moon,
.sky-target.deep,
.sky-target.constellation,
.sky-target.meteor {
  z-index: 6;
}

.sky-target.selected {
  transform: scale(1.08);
}

.focus-ring {
  z-index: 5;
  border-color: rgba(225, 188, 92, 0.78);
  box-shadow: 0 0 12px rgba(225, 188, 92, 0.18);
}

.sky-target-label {
  z-index: 7;
  max-width: 52px;
  color: rgba(242, 246, 237, 0.72);
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.7);
}

.sky-label {
  bottom: 31px;
}

.sky-meta {
  bottom: 15px;
}

/* v7 detail reading mode: no chart, no buttons, only object guidance. */
.shell.card.detail .sky-panel {
  display: none;
}

.shell.card.detail .content {
  left: 22px;
  top: 72px;
  width: 392px;
}

.detail-panel .headline {
  max-width: 392px;
  max-height: 32px;
  font-size: 25px;
  line-height: 30px;
}

.detail-panel .detail-meta {
  max-width: 392px;
  max-height: 22px;
  margin-top: 4px;
  color: rgba(242, 246, 237, 0.68);
  font-size: 13px;
  line-height: 18px;
}

.detail-block {
  width: 392px;
  margin-top: 12px;
}

.detail-block.intro-block {
  margin-top: 10px;
}

.detail-label {
  display: block;
  height: 16px;
  overflow: hidden;
  color: #b8e9b8;
  font-size: 12px;
  line-height: 16px;
  font-weight: 900;
}

.detail-text {
  display: block;
  max-width: 392px;
  max-height: 52px;
  margin-top: 3px;
  overflow: hidden;
  color: rgba(242, 246, 237, 0.76);
  font-size: 14px;
  line-height: 18px;
}

.shell.card.detail .bottom-row {
  border-top-color: rgba(242, 246, 237, 0.06);
}

/* v8 fetched sky chart: standard horizon projection with larger chart area. */
.shell.card.overview .content {
  left: 16px;
  top: 64px;
  width: 184px;
}

.overview-panel .headline {
  max-width: 184px;
  max-height: 42px;
  font-size: 18px;
  line-height: 21px;
}

.overview-panel .body {
  max-width: 182px;
  max-height: 30px;
  margin-top: 5px;
  font-size: 10px;
  line-height: 15px;
}

.overview-panel .target-row {
  gap: 3px;
  margin-top: 6px;
}

.overview-panel .target-btn,
.overview-panel .target-btn.star,
.overview-panel .target-btn.planet,
.overview-panel .target-btn.moon,
.overview-panel .target-btn.deep,
.overview-panel .target-btn.constellation,
.overview-panel .target-btn.meteor {
  width: 180px;
  height: 24px;
  padding: 1px 8px;
}

.overview-panel .target-btn .target-name,
.overview-panel .target-btn .target-meta {
  max-width: 162px;
}

.overview-panel .target-btn .target-name {
  font-size: 10px;
  line-height: 12px;
}

.overview-panel .target-btn .target-meta {
  font-size: 8px;
  line-height: 9px;
}

.shell.card.overview .sky-panel {
  right: 10px;
  top: 54px;
  width: 222px;
  height: 232px;
  padding: 9px 10px;
}

.shell.card.overview .sky-panel-title {
  font-size: 12px;
  line-height: 14px;
}

.shell.card.overview .sky-panel-meta {
  height: 12px;
  font-size: 9px;
  line-height: 12px;
}

.shell.card.overview .sky-map {
  left: 19px;
  top: 35px;
  width: 184px;
  height: 184px;
  border: 0;
  border-radius: 92px;
  background:
    radial-gradient(circle at 50% 50%, rgba(184, 233, 184, 0.10), transparent 9%),
    radial-gradient(circle at 50% 50%, rgba(184, 233, 184, 0.06), rgba(0, 0, 0, 0.02) 68%, rgba(0, 0, 0, 0.42) 100%);
}

.sky-circle,
.sky-cross,
.cardinal {
  position: absolute;
}

.sky-circle {
  border: 1px solid rgba(184, 233, 184, 0.20);
  border-radius: 50%;
}

.horizon-ring {
  left: 2px;
  top: 2px;
  width: 180px;
  height: 180px;
  border-color: rgba(242, 246, 237, 0.26);
}

.ring-30 {
  left: 32px;
  top: 32px;
  width: 120px;
  height: 120px;
}

.ring-60 {
  left: 61px;
  top: 61px;
  width: 62px;
  height: 62px;
}

.sky-cross {
  background: rgba(184, 233, 184, 0.12);
}

.sky-cross-h {
  left: 2px;
  top: 92px;
  width: 180px;
  height: 1px;
}

.sky-cross-v {
  left: 92px;
  top: 2px;
  width: 1px;
  height: 180px;
}

.cardinal {
  color: rgba(242, 246, 237, 0.56);
  font-size: 8px;
  line-height: 10px;
  font-weight: 900;
}

.cardinal-n {
  left: 88px;
  top: 3px;
}

.cardinal-e {
  right: 4px;
  top: 87px;
}

.cardinal-s {
  left: 88px;
  bottom: 3px;
}

.cardinal-w {
  left: 4px;
  top: 87px;
}

.shell.card.overview .sky-target,
.shell.card.overview .sky-target.star,
.shell.card.overview .sky-target.planet,
.shell.card.overview .sky-target.moon,
.shell.card.overview .sky-target.deep,
.shell.card.overview .sky-target.constellation,
.shell.card.overview .sky-target.meteor {
  z-index: 8;
  display: block;
  box-sizing: border-box;
  min-width: 0;
  min-height: 0;
  padding: 0;
  font-size: 0;
  line-height: 0;
  border-radius: 50%;
  border: 1px solid rgba(242, 246, 237, 0.72);
  background: rgba(242, 246, 237, 0.88);
  box-shadow: 0 0 6px rgba(242, 246, 237, 0.35);
}

.shell.card.overview .sky-target.planet {
  border-color: rgba(225, 188, 92, 0.95);
  background: rgba(225, 188, 92, 0.95);
  box-shadow: 0 0 9px rgba(225, 188, 92, 0.50);
}

.shell.card.overview .sky-target.moon {
  border-color: #f2f6ed;
  background: #f2f6ed;
  box-shadow: 0 0 10px rgba(242, 246, 237, 0.52);
}

.shell.card.overview .sky-target.deep,
.shell.card.overview .sky-target.constellation,
.shell.card.overview .sky-target.meteor {
  opacity: 0.78;
}

.shell.card.overview .sky-target.selected {
  z-index: 10;
  border: 2px solid #e1bc5c;
  background: rgba(225, 188, 92, 0.30);
  box-shadow: 0 0 12px rgba(225, 188, 92, 0.72);
}

.shell.card.overview .sky-target-label {
  z-index: 11;
  max-width: 62px;
  height: 11px;
  color: rgba(242, 246, 237, 0.86);
  font-size: 8px;
  line-height: 11px;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.82);
}

.shell.card.overview .sky-label,
.shell.card.overview .sky-meta {
  display: none;
}

/* v8.3: the large fetched sky chart is overview-only. */
.shell.card.home .sky-panel,
.shell.card.chat .sky-panel,
.shell.card.loading .sky-panel,
.shell.card.locate .sky-panel,
.shell.card.error .sky-panel {
  display: none;
}

.shell.card.home .content,
.shell.card.chat .content,
.shell.card.loading .content,
.shell.card.error .content {
  width: 392px;
}

.shell.card.home .headline,
.shell.card.chat .headline,
.shell.card.loading .headline,
.shell.card.error .headline {
  max-width: 392px;
}

.shell.card.home .body,
.shell.card.chat .body,
.shell.card.loading .body,
.shell.card.error .body {
  max-width: 356px;
}

/* v9 AIUI card skin: final overrides for a 480 x 320 smart-glasses surface. */
.shell.card {
  --sky-bg: #000000;
  --sky-surface: rgba(255, 255, 255, 0.045);
  --sky-surface-strong: rgba(255, 255, 255, 0.075);
  --sky-text: var(--color-text-primary);
  --sky-muted: var(--color-text-secondary);
  --sky-primary: var(--color-primary);
  --sky-primary-soft: var(--color-primary-40);
  --sky-border: var(--border-color-muted);
  --sky-gold: #e4bf63;
  position: relative;
  width: 480px;
  height: 320px;
  min-height: 320px;
  max-height: 320px;
  box-sizing: border-box;
  padding: 18px 20px 14px;
  overflow: hidden;
  color: var(--sky-text);
  background: var(--sky-bg);
  border: 2px solid var(--sky-border);
  border-radius: 12px;
  font-family: Arial, sans-serif;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.035);
}

.top-row {
  position: relative;
  z-index: 6;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-start;
  height: 38px;
}

.shell.card .brand {
  display: block;
  height: 24px;
  color: var(--sky-text);
  font-size: 22px;
  line-height: 24px;
  font-weight: 900;
  letter-spacing: 0;
}

.shell.card .meta {
  display: block;
  max-width: 300px;
  height: 15px;
  margin-top: 2px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 11px;
  line-height: 15px;
  white-space: nowrap;
}

.status-pill {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 78px;
  height: 26px;
  box-sizing: border-box;
  overflow: hidden;
  color: var(--sky-primary);
  background: rgba(255, 255, 255, 0.035);
  border: 2px solid var(--border-color-accent);
  border-radius: 12px;
  font-size: 11px;
  line-height: 11px;
  font-weight: 900;
  text-align: center;
  white-space: nowrap;
}

.content {
  position: absolute;
  left: 22px;
  top: 74px;
  z-index: 5;
  width: 436px;
}

.shell.card .kicker {
  display: block;
  height: 16px;
  margin-bottom: 5px;
  overflow: hidden;
  color: var(--sky-primary);
  font-size: 12px;
  line-height: 16px;
  font-weight: 900;
  white-space: nowrap;
}

.shell.card .headline {
  display: block;
  max-width: 436px;
  max-height: 58px;
  overflow: hidden;
  color: var(--sky-text);
  font-size: 24px;
  line-height: 29px;
  font-weight: 900;
  letter-spacing: 0;
}

.shell.card .body {
  display: block;
  max-width: 414px;
  max-height: 42px;
  margin-top: 8px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 13px;
  line-height: 19px;
}

.button-grid,
.button-grid.compact {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 16px;
}

.shell.card .btn {
  display: flex;
  justify-content: center;
  align-items: center;
  min-width: 70px;
  height: 34px;
  box-sizing: border-box;
  padding: 0 12px;
  overflow: hidden;
  color: var(--sky-text);
  background: var(--sky-surface);
  border: 2px solid var(--sky-border);
  border-radius: 12px;
  font-size: 13px;
  line-height: 13px;
  font-weight: 900;
  text-align: center;
  white-space: nowrap;
}

.shell.card .btn.primary {
  color: #061107;
  background: var(--sky-primary);
  border-color: var(--sky-primary);
}

.shell.card .btn.secondary {
  color: var(--sky-primary);
  background: rgba(255, 255, 255, 0.04);
  border-color: var(--border-color-accent);
}

.shell.card .btn.ghost {
  color: var(--sky-muted);
  background: transparent;
}

.shell.card.home .sky-panel,
.shell.card.chat .sky-panel,
.shell.card.loading .sky-panel,
.shell.card.detail .sky-panel,
.shell.card.locate .sky-panel,
.shell.card.error .sky-panel {
  display: none;
}

.shell.card.home .content,
.shell.card.chat .content,
.shell.card.loading .content,
.shell.card.locate .content,
.shell.card.error .content {
  left: 22px;
  top: 74px;
  width: 436px;
}

.shell.card.home .headline,
.shell.card.chat .headline,
.shell.card.loading .headline,
.shell.card.locate .headline,
.shell.card.error .headline {
  max-width: 436px;
}

.shell.card.home .body,
.shell.card.chat .body,
.shell.card.loading .body,
.shell.card.locate .body,
.shell.card.error .body {
  max-width: 414px;
}

.shell.card.home .content {
  top: 72px;
}

.shell.card.home .kicker {
  margin-bottom: 6px;
}

.shell.card.home .headline {
  max-width: 420px;
  max-height: 64px;
  font-size: 23px;
  line-height: 29px;
}

.shell.card.home .body {
  max-width: 390px;
  max-height: 56px;
  margin-top: 10px;
  font-size: 13px;
  line-height: 19px;
}

.home-actions {
  margin-top: 18px;
}

.shell.card .gps-btn {
  min-width: 128px;
  height: 36px;
}

.shell.card.overview .content {
  left: 18px;
  top: 56px;
  width: 210px;
}

.overview-panel .headline {
  max-width: 210px;
  max-height: 42px;
  font-size: 18px;
  line-height: 21px;
}

.overview-panel .body {
  max-width: 206px;
  max-height: 30px;
  margin-top: 5px;
  font-size: 10px;
  line-height: 15px;
}

.overview-panel .target-row {
  display: flex;
  flex-direction: column;
  gap: 3px;
  margin-top: 7px;
}

.overview-panel .target-btn,
.overview-panel .target-btn.star,
.overview-panel .target-btn.planet,
.overview-panel .target-btn.moon,
.overview-panel .target-btn.deep,
.overview-panel .target-btn.constellation,
.overview-panel .target-btn.meteor {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: flex-start;
  width: 204px;
  height: 22px;
  box-sizing: border-box;
  padding: 0 8px;
  overflow: hidden;
  color: var(--sky-text);
  background: var(--sky-surface);
  border: 1px solid var(--sky-border);
  border-radius: 8px;
  line-height: 1;
  text-align: left;
}

.target-btn .target-name,
.target-btn .target-meta {
  display: block;
  max-width: 184px;
  overflow: hidden;
  white-space: nowrap;
}

.target-btn .target-name {
  height: 11px;
  color: var(--sky-text);
  font-size: 10px;
  line-height: 11px;
  font-weight: 900;
}

.target-btn .target-meta {
  height: 8px;
  margin-top: 0;
  color: var(--sky-muted);
  font-size: 8px;
  line-height: 8px;
}

.target-btn.planet {
  border-color: rgba(228, 191, 99, 0.65);
  background: rgba(228, 191, 99, 0.10);
}

.target-btn.moon {
  border-color: rgba(242, 246, 237, 0.62);
  background: rgba(242, 246, 237, 0.08);
}

.target-btn.selected,
.target-btn.star.selected,
.target-btn.planet.selected,
.target-btn.moon.selected,
.target-btn.deep.selected,
.target-btn.constellation.selected,
.target-btn.meteor.selected {
  border-color: var(--sky-primary);
  background: var(--sky-primary-soft);
  box-shadow: none;
}

.overview-actions {
  margin-top: 5px;
}

.overview-actions .btn {
  min-width: 48px;
  height: 22px;
  padding: 0 8px;
  font-size: 10px;
  line-height: 20px;
}

.shell.card.overview .sky-panel {
  position: absolute;
  right: 14px;
  top: 54px;
  z-index: 4;
  display: block;
  width: 224px;
  height: 230px;
  box-sizing: border-box;
  padding: 9px 10px;
  overflow: hidden;
  background: var(--sky-surface);
  border: 2px solid var(--sky-border);
  border-radius: 12px;
}

.sky-panel-title,
.sky-panel-meta,
.sky-label,
.sky-meta {
  display: block;
  overflow: hidden;
  white-space: nowrap;
}

.shell.card.overview .sky-panel-title {
  height: 14px;
  color: var(--sky-text);
  font-size: 12px;
  line-height: 14px;
  font-weight: 900;
}

.shell.card.overview .sky-panel-meta {
  height: 12px;
  margin-top: 2px;
  color: var(--sky-muted);
  font-size: 9px;
  line-height: 12px;
}

.shell.card.overview .sky-map {
  position: absolute;
  left: 20px;
  top: 36px;
  width: 184px;
  height: 184px;
  overflow: hidden;
  background: rgba(64, 255, 94, 0.035);
  border: 0;
  border-radius: 92px;
}

.sky-circle,
.sky-cross,
.cardinal,
.sky-target,
.sky-target-label {
  position: absolute;
}

.sky-circle {
  border: 1px solid rgba(64, 255, 94, 0.24);
  border-radius: 50%;
}

.horizon-ring {
  left: 2px;
  top: 2px;
  width: 180px;
  height: 180px;
}

.ring-30 {
  left: 32px;
  top: 32px;
  width: 120px;
  height: 120px;
}

.ring-60 {
  left: 61px;
  top: 61px;
  width: 62px;
  height: 62px;
}

.sky-cross {
  background: rgba(64, 255, 94, 0.18);
}

.sky-cross-h {
  left: 2px;
  top: 92px;
  width: 180px;
  height: 1px;
}

.sky-cross-v {
  left: 92px;
  top: 2px;
  width: 1px;
  height: 180px;
}

.cardinal {
  color: var(--sky-primary);
  font-size: 8px;
  line-height: 10px;
  font-weight: 900;
}

.cardinal-n {
  left: 88px;
  top: 3px;
}

.cardinal-e {
  right: 4px;
  top: 87px;
}

.cardinal-s {
  left: 88px;
  bottom: 3px;
}

.cardinal-w {
  left: 4px;
  top: 87px;
}

.shell.card.overview .sky-target,
.shell.card.overview .sky-target.star,
.shell.card.overview .sky-target.planet,
.shell.card.overview .sky-target.moon,
.shell.card.overview .sky-target.deep,
.shell.card.overview .sky-target.constellation,
.shell.card.overview .sky-target.meteor {
  z-index: 8;
  display: block;
  min-width: 0;
  min-height: 0;
  box-sizing: border-box;
  padding: 0;
  background: rgba(64, 255, 94, 0.55);
  border: 1px solid rgba(64, 255, 94, 0.62);
  border-radius: 50%;
  box-shadow: 0 0 5px rgba(64, 255, 94, 0.28);
}

.shell.card.overview .sky-target.planet {
  background: rgba(64, 255, 94, 0.74);
  border-color: rgba(64, 255, 94, 0.82);
  box-shadow: 0 0 7px rgba(64, 255, 94, 0.38);
}

.shell.card.overview .sky-target.moon {
  background: rgba(64, 255, 94, 0.78);
  border-color: var(--sky-primary);
}

.shell.card.overview .sky-target.selected {
  z-index: 10;
  background: rgba(64, 255, 94, 0.26);
  border: 2px solid var(--sky-primary);
  box-shadow: 0 0 8px rgba(64, 255, 94, 0.55);
}

.shell.card.overview .selected-sky-marker {
  position: absolute;
  z-index: 12;
  display: block;
  min-width: 0;
  min-height: 0;
  box-sizing: border-box;
  padding: 0;
  background: rgba(64, 255, 94, 0.26);
  border: 2px solid var(--sky-primary);
  border-radius: 50%;
  box-shadow: 0 0 8px rgba(64, 255, 94, 0.55);
}

.shell.card.overview .selected-sky-name {
  position: absolute;
  z-index: 13;
  display: block;
  max-width: 54px;
  height: 12px;
  overflow: hidden;
  color: var(--sky-primary);
  font-size: 9px;
  line-height: 12px;
  font-weight: 900;
  white-space: nowrap;
}

.shell.card.overview .sky-target-label {
  z-index: 11;
  max-width: 54px;
  height: 12px;
  overflow: hidden;
  color: var(--sky-primary);
  font-size: 9px;
  line-height: 12px;
  font-weight: 900;
}

.shell.card.overview .sky-label,
.shell.card.overview .sky-meta {
  display: none;
}

.shell.card.detail .content {
  left: 24px;
  top: 66px;
  width: 432px;
}

.detail-panel .headline {
  max-width: 432px;
  max-height: 34px;
  font-size: 26px;
  line-height: 32px;
}

.detail-panel .detail-meta {
  max-width: 432px;
  max-height: 22px;
  margin-top: 4px;
  color: var(--sky-muted);
  font-size: 13px;
  line-height: 18px;
}

.detail-block {
  width: 432px;
  margin-top: 12px;
}

.detail-label {
  display: block;
  height: 16px;
  overflow: hidden;
  color: var(--sky-primary);
  font-size: 12px;
  line-height: 16px;
  font-weight: 900;
}

.detail-text {
  display: block;
  max-width: 432px;
  max-height: 52px;
  margin-top: 3px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 14px;
  line-height: 18px;
}

.asr-guide {
  display: flex;
  flex-direction: row;
  align-items: center;
  width: 300px;
  height: 32px;
  box-sizing: border-box;
  margin-top: 12px;
  padding: 0 10px;
  background: var(--sky-surface);
  border: 2px solid var(--border-color-accent);
  border-radius: 12px;
}

.guide-dot {
  display: block;
  width: 8px;
  height: 8px;
  margin-right: 8px;
  background: var(--sky-primary);
  border-radius: 4px;
}

.guide-text {
  display: block;
  max-width: 254px;
  height: 16px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 11px;
  line-height: 16px;
  white-space: nowrap;
}

.location-readout {
  display: block;
  max-width: 300px;
  height: 16px;
  margin-top: 10px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 11px;
  line-height: 16px;
  white-space: nowrap;
}

.debug-line {
  display: block;
  max-width: 414px;
  height: 16px;
  margin-top: 9px;
  overflow: hidden;
  color: rgba(255, 255, 255, 0.36);
  font-size: 10px;
  line-height: 16px;
  white-space: nowrap;
}

.bottom-row {
  position: absolute;
  left: 20px;
  right: 20px;
  bottom: 12px;
  z-index: 6;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
  height: 20px;
  box-sizing: border-box;
  padding-top: 7px;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
}

.hint {
  display: block;
  max-width: 302px;
  height: 13px;
  overflow: hidden;
  color: rgba(255, 255, 255, 0.38);
  font-size: 10px;
  line-height: 13px;
  white-space: nowrap;
}

.hint.right {
  max-width: 100px;
  color: var(--sky-primary);
  text-align: right;
}
</style>
