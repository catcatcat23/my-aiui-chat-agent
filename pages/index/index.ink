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
        "selectedObject": { "type": "string", "description": "Selected target key or object JSON" },
        "detailIntro": { "type": "string", "description": "Generated object intro shown on the detail page" },
        "detailQuestion": { "type": "string", "description": "Latest user question asked on the object detail page" },
        "detailAnswer": { "type": "string", "description": "Latest SkyMate answer on the object detail page" },
        "detailObjectContext": { "type": "string", "description": "Object-scoped context passed to the detail page agent" }
      }
    }
  }
}
</script>

<script setup>
const BUILD_VERSION = 'v9-aiui-card'
const SKY_CHART_ENDPOINT = 'https://sky.eunoia.top/sky/chart'
const GEOCODING_ENDPOINT = 'https://geocoding-api.open-meteo.com/v1/search'
const HUD_TARGET_SLOT_COUNT = 5
const SKY_REQUEST_TARGET_LIMIT = 30
const HUD_BG_SLOT_COUNT = 8
const SKY_OBJECT_LIMIT = 32
const SKY_MAP_SIZE = 184

const SKY_OPTIONS = {
  star_max_mag: 3.0,
  deep_sky_max_mag: 9.0,
  min_altitude_deg: 15.0,
  total_limit: SKY_REQUEST_TARGET_LIMIT,
  include_planets: true,
  include_deep_sky: true
}

const CITY_COORDS = [
  { name: '苏州', aliases: ['苏州', 'suzhou', 'su zhou'], lat: 31.2989, lon: 120.5853 },
  { name: '太仓', aliases: ['太仓', 'taicang', 'tai cang'], lat: 31.4839, lon: 121.15824 },
  { name: '厦门', aliases: ['厦门', '廈門', 'xiamen', 'xia men'], lat: 24.4798, lon: 118.0894 },
  { name: '福州', aliases: ['福州', '福州市', 'fuzhou', 'fu zhou'], lat: 26.0745, lon: 119.2965 },
  { name: '海南', aliases: ['海南', '海南省', 'hainan'], lat: 19.1959, lon: 109.7453 },
  { name: '上海', aliases: ['上海', 'shanghai', 'shang hai'], lat: 31.2304, lon: 121.4737 },
  { name: '杭州', aliases: ['杭州', 'hangzhou', 'hang zhou'], lat: 30.2741, lon: 120.1551 },
  { name: '南京', aliases: ['南京', 'nanjing', 'nan jing'], lat: 32.0603, lon: 118.7969 },
  { name: '北京', aliases: ['北京', 'beijing', 'bei jing'], lat: 39.9042, lon: 116.4074 },
  { name: '伦敦', aliases: ['伦敦', 'london'], lat: 51.5074, lon: -0.1278 },
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

  return targets.length ? targets : FALLBACK_TARGETS
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
  const allTargets = targets && targets.length ? targets : FALLBACK_TARGETS
  const selectedIndex = Math.max(0, allTargets.findIndex(item => item.key === selectedKey))
  const maxStart = Math.max(0, allTargets.length - HUD_TARGET_SLOT_COUNT)
  const windowStart = clamp(selectedIndex - HUD_TARGET_SLOT_COUNT + 1, 0, maxStart)
  const safeTargets = allTargets.slice(windowStart, windowStart + HUD_TARGET_SLOT_COUNT)
  const selected = allTargets[selectedIndex] || safeTargets[0] || FALLBACK_TARGETS[0]
  const slots = {
    objectCount: String(allTargets.length),
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
    slots[`target${index}Meta`] = `${windowStart + index + 1}/${allTargets.length} · ${target.type} · ${target.direction}`
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

function createDetailFacts(target) {
  const object = target || FALLBACK_TARGETS[0]
  const key = text(object.key, '').toLowerCase()
  const name = text(object.name, '').toLowerCase()
  const typeClass = text(object.typeClass, '')
  const type = text(object.type, '')
  const sourceColor = text(readAny(object, ['color', 'colorText', 'visualColor', 'spectralColor']), '')
  const sourceSize = text(readAny(object, ['size', 'diameter', 'radius', 'scale']), '')
  const sourceKnowledge = text(readAny(object, ['knowledge', 'astronomy', 'fact', 'science']), '')
  const id = `${key} ${name}`

  let color = sourceColor
  let size = sourceSize
  let knowledge = sourceKnowledge

  if (id.indexOf('vega') >= 0 || name.indexOf('织女') >= 0) {
    color = color || '蓝白色'
    size = size || '半径约为太阳的 2 倍'
    knowledge = knowledge || '它是夏季大三角的重要亮星，也是天文学常用的亮度校准星。'
  } else if (id.indexOf('arcturus') >= 0 || name.indexOf('大角') >= 0) {
    color = color || '橙黄色'
    size = size || '红巨星，半径约为太阳的 25 倍'
    knowledge = knowledge || '它是牧夫座最亮的星，颜色偏暖，肉眼比较容易和白色亮星区分。'
  } else if (id.indexOf('altair') >= 0 || name.indexOf('牛郎') >= 0) {
    color = color || '白色'
    size = size || '半径约为太阳的 1.8 倍'
    knowledge = knowledge || '它是夏季大三角的一角，自转很快，形状略微扁。'
  } else if (id.indexOf('alphacca') >= 0 || id.indexOf('alphecca') >= 0 || name.indexOf('贯索') >= 0) {
    color = color || '白色'
    size = size || '主星约为太阳的数倍尺度'
    knowledge = knowledge || '它是北冕座最亮的星，属于双星系统，亮度会有轻微变化。'
  } else if (id.indexOf('sadr') >= 0 || name.indexOf('天津') >= 0) {
    color = color || '黄白色'
    size = size || '超巨星，真实尺度远大于太阳'
    knowledge = knowledge || '它位于天鹅座十字形中心附近，周围有丰富的银河背景。'
  } else if (id.indexOf('eltanin') >= 0 || name.indexOf('天棓') >= 0) {
    color = color || '橙色'
    size = size || '巨星，半径明显大于太阳'
    knowledge = knowledge || '它是天龙座的亮星，适合用来确认北方天空的弯曲星列。'
  } else if (id.indexOf('rasalhague') >= 0 || name.indexOf('候') >= 0) {
    color = color || '白色'
    size = size || '比太阳更大、更热'
    knowledge = knowledge || '它是蛇夫座最亮的星，常作为夏夜寻找蛇夫座的入口。'
  } else if (typeClass === 'planet' || type.indexOf('行星') >= 0) {
    color = color || (id.indexOf('mars') >= 0 || name.indexOf('火星') >= 0 ? '偏红色' : '白色到淡黄色')
    size = size || '行星有真实圆面，但肉眼看起来通常仍像稳定亮点'
    knowledge = knowledge || '行星自身不发光，主要反射太阳光，所以通常比恒星更稳定、不太闪烁。'
  } else if (typeClass === 'moon' || type.indexOf('月') >= 0) {
    color = color || '灰白色'
    size = size || '视直径约 0.5 度，是夜空中最大的明显目标'
    knowledge = knowledge || '月面明暗来自高地和月海，盈亏会明显影响深空目标可见度。'
  } else if (typeClass === 'deep-sky' || type.indexOf('深空') >= 0) {
    color = color || '肉眼多呈灰白色雾斑'
    size = size || '真实尺度通常很大，但距离极远，视面积较小'
    knowledge = knowledge || '深空目标需要暗天空和耐心观察，城市里通常不如亮星和行星明显。'
  } else {
    color = color || '肉眼多呈白色或略带冷暖色'
    size = size || '如果是恒星，真实体积通常远大于行星，但因距离很远只显示为点光源'
    knowledge = knowledge || '恒星颜色和表面温度有关，越蓝通常越热，偏橙红通常温度较低。'
  }

  return { color, size, knowledge }
}

function detailGuideAnswer(target, question) {
  const object = target || FALLBACK_TARGETS[0]
  const name = text(object.name, '这个目标')
  const direction = text(object.direction, '天空开阔处')
  const altitude = text(object.altitude, '中等高度')
  const locate = text(object.locate, `朝${direction}看，先找最亮、最稳定的光点。`)
  const facts = createDetailFacts(object)
  const questionText = text(question, '')

  if (questionText.indexOf('高度') >= 0 || questionText.indexOf('多高') >= 0) {
    return `${name}现在在${direction}方向，高度大约是${altitude}。先把视野抬到这个高度附近，再找稳定、较亮的光点。它的颜色多呈${facts.color}，${facts.size}。`
  }

  if (questionText.indexOf('方向') >= 0 || questionText.indexOf('哪里') >= 0 || questionText.indexOf('哪边') >= 0) {
    return `${name}在${direction}方向。找一片开阔视野，先按这个方向扫一遍，再用亮度和稳定性确认。补充一点：${facts.knowledge}`
  }

  if (questionText.indexOf('介绍') >= 0 || questionText.indexOf('什么') >= 0) {
    return `${name}是今晚可以优先关注的${text(object.type, '天体')}，现在大致在${direction}，高度${altitude}。城市里先用肉眼找较亮、较稳定的光点。它的颜色多为${facts.color}，${facts.knowledge}`
  }

  return `${name}在${direction}方向，高度${altitude}。${locate} 颜色多为${facts.color}，${facts.size}。`
}

function createDetailIntro(target) {
  const object = target || FALLBACK_TARGETS[0]
  const name = text(object.name, '这个目标')
  const type = text(object.type, '天体')
  const direction = text(object.direction, '天空开阔处')
  const altitude = text(object.altitude, '中等高度')
  const magnitude = text(object.magnitude, '未知')
  const facts = createDetailFacts(object)
  const base = `${name}是今晚推荐观察的${type}，位于${direction}方向，高度约${altitude}。视觉颜色多为${facts.color}，${facts.size}，亮度${magnitude}。`
  return shortText(base, 118)
}

function extractTranscriptFromEvent(event) {
  const result = event || {}
  return result.transcript ||
    result.text ||
    result.result ||
    (result.results && result.results[0] && result.results[0][0] && result.results[0][0].transcript) ||
    ''
}

function getLanguageModelCandidate(root) {
  const runtime = root || getRuntimeRoot()
  return runtime.LanguageModel || null
}

function parseModelJson(value) {
  const raw = text(value, '').trim()
  if (!raw) return null
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i)
  const candidate = fenced ? fenced[1] : raw
  const jsonObject = candidate.match(/\{[\s\S]*\}/)
  return parseJsonMaybe(jsonObject ? jsonObject[0] : candidate)
}

function normalizeResolvedPlace(value, fallbackName) {
  const object = value || {}
  const lat = parseFloat(object.lat || object.latitude)
  const lon = parseFloat(object.lon || object.lng || object.longitude)
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null
  if (Math.abs(lat) > 90 || Math.abs(lon) > 180) return null
  return {
    name: text(object.name || object.locationName || object.city, fallbackName || '文字位置'),
    lat,
    lon
  }
}

function extractLocationQuery(input) {
  let value = text(input, '').trim()
  if (!value) return ''
  value = value
    .replace(/(今晚|今天|明天|现在|当地|这里|那边)/g, '')
    .replace(/(能不能|能否|可以|可不可以|适合|看看|看到|看见|看)/g, '')
    .replace(/(什么|星星|星空|观星|月亮|行星|星座|流星雨|吗|呢|啊|呀)/g, '')
    .replace(/[，。！？,.!?]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  return value || text(input, '').trim()
}

function geocodingUrl(input) {
  const query = extractLocationQuery(input)
  if (!query) return ''
  return `${GEOCODING_ENDPOINT}?name=${encodeURIComponent(query)}&count=1&language=zh&format=json`
}

function placeFromGeocodingResult(result, fallbackName) {
  const list = result && Array.isArray(result.results) ? result.results : []
  if (!list.length) return null
  const first = list[0]
  return normalizeResolvedPlace({
    name: first.name || fallbackName,
    lat: first.latitude,
    lon: first.longitude
  }, fallbackName)
}

function createLocationResolvePrompt(input) {
  return [
    '请把用户输入里的地点解析成经纬度。',
    '只返回 JSON，不要解释，不要 Markdown。',
    '格式：{"name":"地点名","lat":数字,"lon":数字,"confidence":0到1}',
    '如果没有明确地点，返回 {"name":"","lat":null,"lon":null,"confidence":0}',
    `用户输入：${text(input, '')}`
  ].join('\n')
}

function createObjectIndex(objects) {
  const index = {}
  ;(Array.isArray(objects) ? objects : []).forEach(item => {
    if (!item) return
    const key = keyOf(item.key || item.name)
    if (key) index[key] = item
    const nameKey = keyOf(item.name)
    if (nameKey) index[nameKey] = item
  })
  return index
}

function createSkyKnowledgeBase(base) {
  const source = text(base && base.source, 'unknown')
  const objects = Array.isArray(base && base.objects) ? base.objects : []
  const next = {
    source,
    reliable: !!(base && base.reliable),
    generatedAt: (base && base.generatedAt) || null,
    location: (base && base.location) || null,
    query: (base && base.query) || null,
    objects,
    selectedObject: (base && base.selectedObject) || null,
    promptText: text(base && base.promptText, ''),
    objectIndex: (base && base.objectIndex) || createObjectIndex(objects)
  }
  return next
}

function createSkyKnowledgePromptText(kb, pageData) {
  const data = pageData || {}
  const base = kb || data.skyKnowledgeBase || {}
  const objects = Array.isArray(base.objects) ? base.objects.slice(0, 8) : []
  const lines = objects.map((item, index) => {
    return [
      `${index + 1}. ${text(item.name, '未知目标')}`,
      `类型：${text(item.type || item.category, '未知')}`,
      `方向：${text(item.direction, '未知')}`,
      `高度：${text(item.altitudeText || item.altitude || item.alt, '未知')}`,
      `亮度：${text(item.magText || item.magnitude || item.mag, '未知')}`,
      `建议：${text(item.tip || item.locate || item.description, '暂无')}`
    ].join('；')
  }).join('\n')

  return [
    `位置：${base.location ? text(base.location.name, '当前位置') : text(data.locationName, '未知')}`,
    `数据来源：${text(base.source, 'unknown')}`,
    `是否实时可靠：${base.reliable ? '是' : '否'}`,
    `生成时间：${base.generatedAt || '未知'}`,
    `观测结论：${text(data.verdict, '暂无')}`,
    `观测条件：${text(data.condition, '暂无')}`,
    '',
    '当前可参考目标：',
    lines || '暂无'
  ].join('\n')
}

function updateSkyKnowledgeBase(previous, partial, pageData) {
  const base = createSkyKnowledgeBase(Object.assign({}, previous || {}, partial || {}))
  base.objectIndex = createObjectIndex(base.objects)
  base.promptText = createSkyKnowledgePromptText(base, pageData)
  return base
}

function retrieveSkyKnowledge(question, pageData) {
  const data = pageData || {}
  const kb = data.skyKnowledgeBase
  if (!kb || !Array.isArray(kb.objects) || !kb.objects.length) return ''

  const q = text(question, '')
  if (data.mode === 'detail' && data.selectedObject) {
    return [
      '当前选中目标：',
      createDetailObjectContext(data.selectedObject, data),
      '',
      '当前星图知识库：',
      kb.promptText || createSkyKnowledgePromptText(kb, data)
    ].join('\n')
  }

  if (
    q.indexOf('哪个') >= 0 ||
    q.indexOf('哪一个') >= 0 ||
    q.indexOf('最亮') >= 0 ||
    q.indexOf('更亮') >= 0 ||
    q.indexOf('容易') >= 0 ||
    q.indexOf('换一个') >= 0 ||
    q.indexOf('在哪') >= 0 ||
    q.indexOf('哪里') >= 0 ||
    q.indexOf('方向') >= 0 ||
    q.indexOf('看得到') >= 0 ||
    q.indexOf('能看到') >= 0
  ) {
    return kb.promptText || createSkyKnowledgePromptText(kb, data)
  }

  return ''
}

function createDetailObjectContext(target, pageData) {
  const object = target || FALLBACK_TARGETS[0]
  const data = pageData || {}
  const rows = [
    `当前页面：SkyMate 星体详情页`,
    `观测位置：${text(data.locationName, '当前位置未知')}`,
    `今晚判断：${text(data.verdict, '暂无整体判断')}`,
    `观测条件：${text(data.condition, '暂无观测条件')}`,
    `星体名称：${text(object.name, '未知目标')}`,
    `星体类型：${text(object.type, '天体')}`,
    `所在方向：${text(object.direction, '天空开阔处')}`,
    `高度：${text(object.altitude, '中等高度')}`,
    `亮度：${text(object.magnitude, '未知')}`,
    `最佳时间：${text(object.bestTime, '今晚')}`,
    `颜色：${createDetailFacts(object).color}`,
    `大小或尺度：${createDetailFacts(object).size}`,
    `天文知识：${createDetailFacts(object).knowledge}`,
    `简介：${createDetailIntro(object)}`,
    `页面给出的找法：${text(object.locate, '先按方向寻找明亮稳定的光点')}`
  ]
  return rows.join('\n')
}

function createDetailPrompt(target, question, pageData) {
  const object = target || FALLBACK_TARGETS[0]
  const data = pageData || {}
  const questionText = text(question, '我该怎么找？').trim()
  const history = Array.isArray(data.detailChatHistory) ? data.detailChatHistory.slice(-8) : []
  const historyText = history.map(item => {
    return `${item.role === 'user' ? '用户' : 'SkyMate'}：${item.content}`
  }).join('\n')
  return [
    '你是 SkyMate，一个运行在 Rokid Glasses 上的观星助手。',
    '你正在当前星体详情上下文中回答用户。',
    '优先参考当前星图知识库和当前选中目标。',
    '',
    '【星图知识库检索结果】',
    retrieveSkyKnowledge(questionText, data) || '暂无',
    '',
    '【当前选中目标】',
    createDetailObjectContext(object, pageData),
    '',
    '【最近对话】',
    historyText || '暂无',
    '',
    '【用户问题】',
    questionText,
    '',
    '【回答要求】',
    '1. 自然回答，不要强制方向、找法、知识三行格式。',
    '2. 如果用户问“它”“这个”，默认指当前选中目标。',
    '3. 当前观测事实优先参考星图知识库。',
    '4. 如果知识库来自 fallback 或不可靠，要说明不确定。',
    '5. 回答适合语音播报，通常 2 到 5 句话。'
  ].join('\n')
}

function createGeneralChatPrompt(question, pageData) {
  const data = pageData || {}
  const history = Array.isArray(data.generalChatHistory) ? data.generalChatHistory.slice(-8) : []
  const historyText = history.map(item => {
    return `${item.role === 'user' ? '用户' : 'SkyMate'}：${item.content}`
  }).join('\n')

  return [
    '你是 SkyMate，一个面向智能眼镜用户的观星助手。',
    '你可以回答观星、星体、星座、月亮、行星、流星、望远镜和观测技巧问题。',
    '',
    '【当前页面状态】',
    `mode：${text(data.mode, 'unknown')}`,
    `位置：${text(data.locationName, '未知')}`,
    `当前选中目标：${data.selectedObject ? text(data.selectedObject.name, '未知') : '暂无'}`,
    '',
    '【星图知识库检索结果】',
    retrieveSkyKnowledge(question, data) || '暂无',
    '',
    '【最近对话】',
    historyText || '暂无',
    '',
    '【用户问题】',
    text(question, ''),
    '',
    '【回答要求】',
    '1. 先给结论，再补充原因。',
    '2. 回答自然、简短，适合语音播报。',
    '3. 如果用户问当前能看到什么、哪个更亮、哪个更容易找，优先参考星图知识库。',
    '4. 如果知识库不可靠，要说明不确定。',
    '5. 如果问题需要位置但没有位置，请提示用户说城市或授权定位。'
  ].join('\n')
}

function isBackIntent(input) {
  const q = text(input, '').trim()
  return q === '返回' || q === '退出' || q === '回到首页' || q === '回到总览' || q.indexOf('返回上一') >= 0
}

function isSkyChartIntent(input) {
  const q = text(input, '')
  return q.indexOf('今晚') >= 0 ||
    q.indexOf('今天') >= 0 ||
    q.indexOf('能看到什么') >= 0 ||
    q.indexOf('看得到什么') >= 0 ||
    q.indexOf('查星空') >= 0 ||
    q.indexOf('星图') >= 0 ||
    q.indexOf('重新定位') >= 0 ||
    q.indexOf('刷新') >= 0
}

function isAstronomyQuestion(input) {
  const q = text(input, '')
  const words = ['星', '月亮', '行星', '恒星', '星座', '流星', '银河', '望远镜', '视星等', '观星', '天文']
  return words.some(word => q.indexOf(word) >= 0)
}

function hasLocationSignal(input) {
  return !!coordinateFromText(input) || !!cityFromText(input)
}

function isSwitchObjectIntent(input, context) {
  const q = text(input, '')
  const objects = context && Array.isArray(context.visibleObjects) ? context.visibleObjects : []
  if (!objects.length) return false
  if (q.indexOf('换一个') >= 0 || q.indexOf('下一个') >= 0 || q.indexOf('另一个') >= 0) return true
  return objects.some(item => q.indexOf(text(item.name, '')) >= 0)
}

function findObjectByHint(hint, objects, selectedKey) {
  const q = text(hint, '')
  const list = Array.isArray(objects) ? objects : []
  const named = list.find(item => q.indexOf(text(item.name, '')) >= 0 || q.indexOf(text(item.key, '')) >= 0)
  if (named) return named
  const currentIndex = Math.max(0, list.findIndex(item => item.key === selectedKey))
  if (q.indexOf('上一个') >= 0) return list[(currentIndex - 1 + list.length) % list.length]
  return list[(currentIndex + 1) % list.length] || list[0] || null
}

function createLocalGeneralAnswer(question, pageData) {
  const data = pageData || {}
  const q = text(question, '')
  const kb = data.skyKnowledgeBase || {}
  const objects = Array.isArray(kb.objects) ? kb.objects : []

  if (objects.length && (q.indexOf('最亮') >= 0 || q.indexOf('哪个') >= 0 || q.indexOf('容易') >= 0)) {
    const target = objects.slice().sort((left, right) => visibilityScore(left) - visibilityScore(right))[0]
    const reliability = kb.reliable ? '' : '不过这不是实时精确星图，'
    return `${reliability}当前列表里优先看 ${target.name}。它在${target.direction}方向，高度${target.altitude}，亮度${target.magnitude}，比较适合作为第一个目标。`
  }

  if (q.indexOf('视星等') >= 0) {
    return '视星等是天体看起来有多亮的量。数字越小越亮，负数会更亮；城市里通常优先看月亮、亮行星和低星等亮星。'
  }

  if (q.indexOf('银河') >= 0 || q.indexOf('光污染') >= 0) {
    return '城市里很难看到银河，主要是光污染把暗弱的银河背景淹没了。想看银河，需要远离城市灯光，选晴朗、少月光的夜晚。'
  }

  if (!data.currentPlace && isSkyChartIntent(q)) {
    return '我还没有拿到你眼镜的当前位置。请告诉我城市，或允许获取当前位置。'
  }

  return '可以。我会优先结合当前位置和当前星图回答；如果没有实时数据，我会说明不确定。'
}

function selectedObjectFromQuery(value, targets) {
  const parsed = parseJsonMaybe(value)
  if (parsed && typeof parsed === 'object') return normalizeTarget(parsed, 0)

  const raw = text(value, '')
  if (!raw) return null
  const list = (Array.isArray(targets) ? targets : []).concat(FALLBACK_TARGETS)
  const matched = list.find(item => raw === item.key || raw === item.name || raw.indexOf(item.name) >= 0)
  if (matched) return normalizeTarget(matched, 0)
  return normalizeTarget({ name: raw, type: '天体', locate: '请结合当前星图或用户描述确认方向。' }, 0)
}

function createDetailState(target, pageData, question, answer) {
  const object = target || FALLBACK_TARGETS[0]
  const questionText = text(question, '可以问：我该怎么找？')
  return {
    detailObjectContext: createDetailObjectContext(object, pageData),
    detailIntro: createDetailIntro(object),
    detailQuestion: questionText,
    detailAnswer: answer || detailGuideAnswer(object, question || ''),
    detailAgentStatus: 'ready'
  }
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
    currentPlace: null,
    skyKnowledgeBase: createSkyKnowledgeBase({}),
    detailChatHistory: [],
    generalChatHistory: [],
    lastIntent: '',
    detailQuestion: '可以问：我该怎么找？',
    detailAnswer: detailGuideAnswer(FALLBACK_TARGETS[0], ''),
    detailIntro: createDetailIntro(FALLBACK_TARGETS[0]),
    detailObjectContext: createDetailObjectContext(FALLBACK_TARGETS[0], null),
    detailAgentStatus: 'ready',
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

  skyKnowledgeRaw: null,
  detailAgentSession: null,
  generalAgentSession: null,

  onLoad(rawQuery) {
    console.log('[SkyMate] page onLoad', rawQuery || {})
    const query = queryFromRaw(rawQuery)
    const chart = parseJsonMaybe(query.skyChart || query.chart || query.rawResult || query.result)
    const targets = parseJsonMaybe(query.targets)
    const userText = query.userText || query.prompt || query.question || query.message || query.input
    const placeText = userText || query.locationName || query.city || query.location || ''
    const queryPlace = placeFromQuery(query)

    if (query.mode === 'detail' && query.selectedObject) {
      const normalizedTargets = Array.isArray(targets) ? targets.map((item, index) => normalizeTarget(item, index)) : []
      const selected = selectedObjectFromQuery(query.selectedObject, normalizedTargets)
      if (selected) {
        const visibleObjects = normalizedTargets.length ? normalizedTargets : [selected]
        const skyObjects = createSkyChartObjects(visibleObjects, selected.key)
        const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
          source: chart ? 'api' : 'page-query',
          reliable: !!chart,
          generatedAt: Date.now(),
          location: queryPlace || { name: text(query.locationName || query.city || query.location, '当前位置') },
          objects: visibleObjects,
          selectedObject: selected
        }, Object.assign({}, this.data, {
          mode: 'detail',
          locationName: text(query.locationName || query.city || query.location, this.data.locationName),
          visibleObjects,
          selectedObject: selected
        }))
        this.setData(Object.assign({
          currentPlace: queryPlace || this.data.currentPlace,
          locationName: text(query.locationName || query.city || query.location, this.data.locationName),
          visibleObjects,
          selectedKey: selected.key,
          selectedIndex: Math.max(0, visibleObjects.findIndex(item => item.key === selected.key)),
          selectedObject: selected,
          skyObjects,
          skyKnowledgeBase: knowledge,
          assistantLine: `正在围绕 ${selected.name} 回答。`,
          requestStatus: 'detail query',
          diagnosticLine: selected.key
        }, createHudSlots(visibleObjects, selected.key), createSelectedSkyOverlay(selected, 0), createDetailState(selected, this.data)))
        this.applyMode('detail')
        return
      }
    }

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
      this.setData({ assistantLine: userText ? `收到问题：${userText}` : '正在尝试读取当前位置。', diagnosticLine: 'query text' })
      if (placeText) this.handleConversationInput(placeText, 'page-query')
      else this.loadCurrentLocationOrFallback()
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

  onUnload() {
    this.destroyDetailAgentSession()
    if (this.generalAgentSession && typeof this.generalAgentSession.destroy === 'function') {
      this.generalAgentSession.destroy()
    }
    this.generalAgentSession = null
  },

  onVoiceWakeup(event) {
    console.log('[SkyMate] voice wakeup', event || {})
    this.reportEvent('voiceWakeup')
    this.startUnifiedAsr()
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

  startUnifiedAsr() {
    this.reportEvent('startUnifiedAsr')
    this.startAsr()
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
        assistantLine: '当前环境没有 ASR，请允许定位或说出支持的城市。'
      })
      return
    }

    const recognition = new Recognition()
    configureSpeechRecognition(recognition)

    recognition.onresult = (event) => {
      const transcript = extractTranscriptFromEvent(event)
      console.log('[SkyMate] ASR result', transcript, event || {})
      this.setData({
        asrStatus: transcript ? 'success' : 'empty',
        assistantLine: transcript ? `我听到：${transcript}` : '我听到了，正在判断。'
      })
      if (transcript) this.handleConversationInput(transcript, 'voice')
      else this.loadCurrentLocationOrFallback()
    }

    recognition.onerror = (event) => {
      console.log('[SkyMate] ASR error', event || {})
      this.setData({
        asrStatus: 'error',
        assistantLine: '这次语音没有成功，可以重试或允许定位。'
      })
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
        if (transcript) this.handleConversationInput(transcript, 'voice')
        else this.loadCurrentLocationOrFallback()
      }

      const onError = (error) => {
        console.log('[SkyMate] wx ASR error', error || {})
        this.setData({
          asrStatus: 'wx-error',
          assistantLine: 'Rokid 语音识别没有成功，可以重试或允许定位。'
        })
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

  startDetailAsr() {
    this.reportEvent('startDetailAsr')
    this.applyMode('detail')
    this.setData({
      asrStatus: 'detail-listening',
      detailAgentStatus: 'listening',
      detailQuestion: '正在听...',
      detailAnswer: '说出你想问的问题，比如“我该怎么找它？”',
      assistantLine: '我在听，可以继续追问当前星体。'
    })

    const Recognition = getSpeechRecognitionCandidate()
    if (!Recognition) {
      if (this.startWxDetailAsr()) return
      this.handleConversationInput('我该怎么找？', 'voice')
      return
    }

    const recognition = new Recognition()
    configureSpeechRecognition(recognition)

    recognition.onresult = (event) => {
      const transcript = extractTranscriptFromEvent(event)
      console.log('[SkyMate] detail ASR result', transcript)
      this.setData({
        asrStatus: transcript ? 'detail-success' : 'detail-empty'
      })
      this.handleConversationInput(transcript || '我该怎么找？', 'voice')
    }

    recognition.onerror = (event) => {
      console.log('[SkyMate] detail ASR error', event || {})
      const target = this.data.selectedObject || FALLBACK_TARGETS[0]
      this.setData({
        asrStatus: 'detail-error',
        detailAgentStatus: 'local',
        detailObjectContext: createDetailObjectContext(target, this.data),
        detailQuestion: '语音没有成功',
        detailAnswer: detailGuideAnswer(target, '我该怎么找？'),
        assistantLine: '语音没有成功，我先按当前星体给出找法。'
      })
    }

    recognition.onend = () => console.log('[SkyMate] detail ASR end')
    recognition.start()
  },

  startWxDetailAsr() {
    const runtime = typeof wx !== 'undefined' ? wx : null
    if (!runtime || typeof runtime.getSpeechRecognizer !== 'function') return false

    try {
      const recognizer = runtime.getSpeechRecognizer()
      if (!recognizer) return false

      const target = this.data.selectedObject || FALLBACK_TARGETS[0]
      this.setData({
        asrStatus: 'detail-wx-listening',
        detailAgentStatus: 'listening',
        detailObjectContext: createDetailObjectContext(target, this.data),
        assistantLine: `正在听你问 ${text(target.name, '这个目标')}。`
      })

      const onResult = (event) => {
        const transcript = extractTranscriptFromEvent(event)
        console.log('[SkyMate] wx detail ASR result', transcript, event || {})
        this.setData({ asrStatus: transcript ? 'detail-wx-success' : 'detail-wx-empty' })
        this.handleConversationInput(transcript || '我该怎么找？', 'voice')
      }

      const onError = (error) => {
        console.log('[SkyMate] wx detail ASR error', error || {})
        this.setData({
          asrStatus: 'detail-wx-error',
          detailAgentStatus: 'local',
          detailQuestion: '语音没有成功',
          detailAnswer: detailGuideAnswer(target, '我该怎么找？'),
          assistantLine: '语音没有成功，我先按当前星体给出找法。'
        })
      }

      if (typeof recognizer.onResult === 'function') recognizer.onResult(onResult)
      else recognizer.onresult = onResult

      if (typeof recognizer.onError === 'function') recognizer.onError(onError)
      else recognizer.onerror = onError

      if (typeof recognizer.onEnd === 'function') recognizer.onEnd(() => console.log('[SkyMate] wx detail ASR end'))
      else recognizer.onend = () => console.log('[SkyMate] wx detail ASR end')

      if (typeof recognizer.start === 'function') {
        recognizer.start({ lang: 'zh-CN' })
        return true
      }

      if (typeof recognizer.startRecognition === 'function') {
        recognizer.startRecognition({ lang: 'zh-CN' })
        return true
      }
    } catch (error) {
      console.log('[SkyMate] wx detail ASR setup failed', error || {})
    }
    return false
  },

  async getDetailAgentSession() {
    if (this.detailAgentSession) return this.detailAgentSession

    const LanguageModel = getLanguageModelCandidate()
    if (!LanguageModel || typeof LanguageModel.availability !== 'function' || typeof LanguageModel.create !== 'function') return null

    const availability = await LanguageModel.availability()
    if (availability !== 'available') return null

    this.detailAgentSession = await LanguageModel.create({
      initialPrompts: [
        {
          role: 'system',
          content: '你是 SkyMate，一个简短、自然、适合智能眼镜语音播报的观星助手。'
        }
      ]
    })

    return this.detailAgentSession
  },

  async getGeneralAgentSession() {
    if (this.generalAgentSession) return this.generalAgentSession

    const LanguageModel = getLanguageModelCandidate()
    if (!LanguageModel || typeof LanguageModel.availability !== 'function' || typeof LanguageModel.create !== 'function') return null

    const availability = await LanguageModel.availability()
    if (availability !== 'available') return null

    this.generalAgentSession = await LanguageModel.create({
      initialPrompts: [
        {
          role: 'system',
          content: '你是 SkyMate，一个面向智能眼镜用户的观星助手。回答要简短、自然、结论优先。'
        }
      ]
    })

    return this.generalAgentSession
  },

  destroyDetailAgentSession() {
    if (this.detailAgentSession && typeof this.detailAgentSession.destroy === 'function') {
      this.detailAgentSession.destroy()
    }
    this.detailAgentSession = null
  },

  async askDetailAgent(question) {
    const target = this.data.selectedObject || FALLBACK_TARGETS[0]
    const questionText = text(question, '我该怎么找？')
    const fallbackAnswer = detailGuideAnswer(target, questionText)
    const context = createDetailObjectContext(target, this.data)
    const userHistory = (this.data.detailChatHistory || []).concat({
      role: 'user',
      content: questionText
    }).slice(-10)

    this.setData({
      detailChatHistory: userHistory,
      detailObjectContext: context,
      detailQuestion: `你问：${questionText}`,
      detailAnswer: '正在结合当前星图回答...',
      detailAgentStatus: 'thinking',
      assistantLine: `正在围绕 ${text(target.name, '当前星体')} 回答。`
    })

    let session = null
    try {
      session = await this.getDetailAgentSession()
    } catch (error) {
      console.log('[SkyMate] detail session unavailable', error || {})
    }

    if (!session || typeof session.prompt !== 'function') {
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        detailChatHistory: nextHistory,
        detailAnswer: fallbackAnswer,
        detailAgentStatus: 'local',
        assistantLine: '当前没有大模型配置，已用星体上下文给出本地回答。'
      })
      return fallbackAnswer
    }

    try {
      const promptData = Object.assign({}, this.data, { detailChatHistory: userHistory })
      const modelAnswer = await session.prompt(createDetailPrompt(target, questionText, promptData))
      const answer = shortText(modelAnswer || fallbackAnswer, 150)
      const nextHistory = userHistory.concat({ role: 'assistant', content: answer }).slice(-10)
      this.setData({
        detailChatHistory: nextHistory,
        detailAnswer: answer,
        detailAgentStatus: 'model',
        assistantLine: answer
      })
      return answer
    } catch (error) {
      console.log('[SkyMate] detail agent fallback', error || {})
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        detailChatHistory: nextHistory,
        detailAnswer: fallbackAnswer,
        detailAgentStatus: 'local',
        assistantLine: '大模型暂时不可用，已按当前星体上下文回答。'
      })
      return fallbackAnswer
    }
  },

  async askGeneralAgent(question) {
    const questionText = text(question, '').trim()
    if (!questionText) return this.loadCurrentLocationOrFallback()

    const fallbackAnswer = createLocalGeneralAnswer(questionText, this.data)
    const userHistory = (this.data.generalChatHistory || []).concat({
      role: 'user',
      content: questionText
    }).slice(-10)

    this.applyMode('chat')
    this.setData({
      generalChatHistory: userHistory,
      assistantLine: '正在结合当前页面和星图上下文回答。',
      requestStatus: 'general thinking',
      diagnosticLine: shortText(questionText, 62)
    })

    let session = null
    try {
      session = await this.getGeneralAgentSession()
    } catch (error) {
      console.log('[SkyMate] general session unavailable', error || {})
    }

    if (!session || typeof session.prompt !== 'function') {
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        generalChatHistory: nextHistory,
        assistantLine: fallbackAnswer,
        requestStatus: 'general local'
      })
      return fallbackAnswer
    }

    try {
      const promptData = Object.assign({}, this.data, { generalChatHistory: userHistory })
      const modelAnswer = await session.prompt(createGeneralChatPrompt(questionText, promptData))
      const answer = shortText(modelAnswer || fallbackAnswer, 150)
      const nextHistory = userHistory.concat({ role: 'assistant', content: answer }).slice(-10)
      this.setData({
        generalChatHistory: nextHistory,
        assistantLine: answer,
        requestStatus: 'general model'
      })
      return answer
    } catch (error) {
      console.log('[SkyMate] general agent fallback', error || {})
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        generalChatHistory: nextHistory,
        assistantLine: fallbackAnswer,
        requestStatus: 'general local'
      })
      return fallbackAnswer
    }
  },

  async handleUserText(input) {
    this.reportEvent('handleUserText')
    return this.handleConversationInput(input, 'legacy')
  },

  getConversationContext() {
    return {
      mode: this.data.mode,
      currentPlace: this.data.currentPlace,
      locationName: this.data.locationName,
      visibleObjects: this.data.visibleObjects || [],
      selectedObject: this.data.selectedObject,
      skyKnowledgeBase: this.data.skyKnowledgeBase,
      verdict: this.data.verdict,
      condition: this.data.condition,
      detailChatHistory: this.data.detailChatHistory || [],
      generalChatHistory: this.data.generalChatHistory || [],
      lastIntent: this.data.lastIntent
    }
  },

  detectIntent(input, context) {
    const q = text(input, '')
    const mode = context && context.mode

    if (isBackIntent(q)) return { type: 'navigate_back' }
    if (isSwitchObjectIntent(q, context)) return { type: 'switch_object', targetHint: q }
    if (
      mode === 'detail' &&
      context &&
      context.selectedObject &&
      !hasLocationSignal(q) &&
      q.indexOf('刷新') < 0 &&
      q.indexOf('重新定位') < 0 &&
      q.indexOf('今晚能看到什么') < 0 &&
      q.indexOf('现在能看到什么') < 0
    ) {
      return { type: 'detail_question' }
    }
    if (hasLocationSignal(q) || isSkyChartIntent(q)) return { type: 'sky_chart_query' }
    if (isAstronomyQuestion(q)) return { type: 'general_astronomy_question' }
    return { type: 'general_astronomy_question' }
  },

  async handleConversationInput(input, source) {
    this.reportEvent(`conversation:${source || 'unknown'}`)
    console.log('[SkyMate] conversation input', source, input)
    const questionText = text(input, '').trim()
    if (!questionText) return this.loadCurrentLocationOrFallback()

    const context = this.getConversationContext()
    const intent = this.detectIntent(questionText, context)
    this.setData({ lastIntent: intent.type })

    if (intent.type === 'navigate_back') {
      this.goBack()
      return null
    }

    if (intent.type === 'switch_object') {
      return this.switchSelectedObject(intent)
    }

    if (intent.type === 'sky_chart_query') {
      return this.resolvePlaceAndLoadSkyChart(questionText)
    }

    if (intent.type === 'detail_question') {
      return this.askDetailAgent(questionText)
    }

    return this.askGeneralAgent(questionText)
  },

  async resolvePlaceFromText(input) {
    const coordinate = coordinateFromText(input)
    if (coordinate) {
      console.log('[SkyMate] text coordinate resolved', coordinate)
      return coordinate
    }

    const city = cityFromText(input)
    if (city) {
      console.log('[SkyMate] local city resolved', city)
      return city
    }

    const geocodedPlace = await this.resolveLocationWithOnlineGeocoder(input)
    if (geocodedPlace) return geocodedPlace

    const resolvedPlace = await this.resolveLocationWithModel(input)
    if (resolvedPlace) return resolvedPlace

    return null
  },

  async resolvePlaceAndLoadSkyChart(input) {
    const place = await this.resolvePlaceFromText(input)

    if (place) {
      this.setData({ currentPlace: place })
      this.loadSkyChart(place)
      return place
    }

    if (this.data.currentPlace && isSkyChartIntent(input)) {
      this.loadSkyChart(this.data.currentPlace)
      return this.data.currentPlace
    }

    try {
      const runtimePlace = await this.readRuntimeLocation()
      this.setData({ currentPlace: runtimePlace })
      this.loadSkyChart(runtimePlace)
      return runtimePlace
    } catch (error) {
      console.log('[SkyMate] conversation location unavailable', error || {})
      this.applyMode('chat')
      this.setData({
        requestStatus: 'location unresolved',
        diagnosticLine: shortText(errorText(error), 62),
        assistantLine: '我还没有拿到你眼镜的当前位置。请告诉我城市，或允许获取当前位置。'
      })
      return null
    }
  },

  switchSelectedObject(intent) {
    const targets = this.data.visibleObjects && this.data.visibleObjects.length ? this.data.visibleObjects : FALLBACK_TARGETS
    const target = findObjectByHint(intent && intent.targetHint, targets, this.data.selectedKey)
    if (!target) return this.askGeneralAgent(text(intent && intent.targetHint, '换一个'))
    const index = Math.max(0, targets.findIndex(item => item.key === target.key))
    this.destroyDetailAgentSession()
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      objects: targets,
      selectedObject: target
    }, Object.assign({}, this.data, { visibleObjects: targets, selectedObject: target }))
    this.setData(Object.assign({
      selectedIndex: index,
      selectedKey: target.key,
      selectedObject: target,
      skyObjects: createSkyChartObjects(this.data.skyObjects, target.key),
      skyKnowledgeBase: knowledge,
      detailChatHistory: [],
      assistantLine: `已切换到 ${target.name}，可以继续追问。`
    }, createHudSlots(targets, target.key), createSelectedSkyOverlay(target, index), createDetailState(target, this.data)))
    this.applyMode('detail')
    return target
  },

  async resolveLocationWithOnlineGeocoder(input) {
    const query = extractLocationQuery(input)
    const url = geocodingUrl(input)
    if (!url) return null

    this.setData({
      requestStatus: 'geocode',
      diagnosticLine: shortText(query, 62),
      assistantLine: `正在联网解析地点：${query}`
    })
    console.log('[SkyMate] geocode start', { query, url })

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: { accept: 'application/json' }
      })
      if (!response || !response.ok) {
        console.log('[SkyMate] geocode HTTP failed', response && response.status)
        return null
      }
      const json = await response.json()
      const place = placeFromGeocodingResult(json, query)
      console.log('[SkyMate] geocode result', place, json)
      if (!place) return null
      this.setData({
        requestStatus: 'geocode ok',
        diagnosticLine: `${place.lat},${place.lon}`,
        assistantLine: `已解析到 ${place.name}，正在查星空。`
      })
      return place
    } catch (error) {
      console.log('[SkyMate] geocode failed', error || {})
      return null
    }
  },

  async resolveLocationWithModel(input) {
    const query = text(input, '').trim()
    if (!query) return null

    const LanguageModel = getLanguageModelCandidate()
    if (!LanguageModel || typeof LanguageModel.availability !== 'function' || typeof LanguageModel.create !== 'function') {
      console.log('[SkyMate] location model unavailable')
      return null
    }

    this.setData({
      requestStatus: 'resolve location',
      diagnosticLine: shortText(query, 62),
      assistantLine: `正在解析地点：${query}`
    })

    let session = null
    try {
      const availability = await LanguageModel.availability()
      console.log('[SkyMate] location model availability', availability)
      if (availability !== 'available') return null

      session = await LanguageModel.create({
        initialPrompts: [
          {
            role: 'system',
            content: '你是地理编码助手。只输出严格 JSON，不输出解释。'
          }
        ]
      })

      const answer = await session.prompt(createLocationResolvePrompt(query))
      console.log('[SkyMate] location model answer', answer)
      const parsed = parseModelJson(answer)
      const place = normalizeResolvedPlace(parsed, query)
      console.log('[SkyMate] model resolved place', place, parsed)
      if (!place) return null

      this.setData({
        requestStatus: 'resolved location',
        diagnosticLine: `${place.lat},${place.lon}`,
        assistantLine: `已解析到 ${place.name}，正在查星空。`
      })
      return place
    } catch (error) {
      console.log('[SkyMate] location model resolve failed', error || {})
      return null
    } finally {
      if (session && typeof session.destroy === 'function') session.destroy()
    }
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
        currentPlace: place,
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
      this.setData({ currentPlace: place })
      this.loadSkyChart(place)
    } catch (error) {
      console.log('[SkyMate] location unavailable', error || {})
      this.setData({
        requestStatus: 'location unresolved',
        diagnosticLine: errorText(error),
        assistantLine: '我还没有拿到你眼镜的当前位置。请告诉我城市，或允许获取当前位置。'
      })
      this.applyMode('chat')
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
    this.loadSkyChart(cityFromText('上海') || CITY_COORDS[0])
  },

  async loadSkyChart(city) {
    const place = city || this.data.currentPlace
    if (!place) {
      this.applyMode('chat')
      this.setData({
        requestStatus: 'location unresolved',
        diagnosticLine: 'no place',
        assistantLine: '我需要知道你的位置，才能查当前星图。请告诉我城市，或允许获取当前位置。'
      })
      return
    }
    this.applyMode('loading')
    this.setData({
      currentPlace: place,
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
        source: 'sky-chart',
        place,
        query: payload
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
      total_limit: payload.total_limit || SKY_REQUEST_TARGET_LIMIT
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
    const targets = providedTargets ? providedTargets.map((item, index) => normalizeTarget(item, index)) : pickTargets(chart)
    const skyObjects = collectSkyObjects(chart || providedTargets, targets)
    const first = targets[0] || FALLBACK_TARGETS[0]
    const source = text(options && options.source, 'sky-chart')
    const place = (options && options.place) || this.data.currentPlace || { name: locationName }
    const targetNames = targets.slice(0, 2).map(item => item.name).join('、')
    const verdict = targets.length
      ? `${locationName}今晚优先看 ${targetNames}`
      : `${locationName}今晚先看亮星和亮行星`
    const condition = '城市里优先看亮星、行星和月亮；深空目标更适合望远镜或暗处。'
    const pageData = Object.assign({}, this.data, {
      locationName,
      verdict,
      condition,
      visibleObjects: targets,
      selectedObject: first
    })
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      source: 'api',
      reliable: true,
      generatedAt: Date.now(),
      location: place,
      query: options && options.query,
      objects: targets,
      selectedObject: first
    }, pageData)

    this.skyKnowledgeRaw = chart || null

    this.setData(Object.assign({
      currentPlace: place,
      visibleObjects: targets,
      selectedKey: first.key,
      selectedIndex: 0,
      selectedObject: first,
      locationName,
      skyObjects: createSkyChartObjects(skyObjects, first.key),
      skyKnowledgeBase: knowledge,
      verdict,
      condition,
      assistantLine: '已筛出最适合普通用户看的目标。',
      requestStatus: `success ${source}`,
      diagnosticLine: `targets=${targets.length} sky=${skyObjects.length}`
    }, createHudSlots(targets, first.key), createSelectedSkyOverlay(first, 0), createDetailState(first, {
      locationName,
      verdict,
      condition
    })))
    this.applyMode('overview')
  },

  showFallback(locationName, reason) {
    console.log('[SkyMate] fallback reason', reason || '')
    const verdict = `暂时查不到 ${locationName} 的实时星图`
    const condition = '下面是一般情况下较容易尝试的亮目标，不代表当前位置和当前时间的精确结果。'
    const fallbackPlace = this.data.currentPlace || { name: locationName }
    const pageData = Object.assign({}, this.data, {
      locationName,
      verdict,
      condition,
      visibleObjects: FALLBACK_TARGETS,
      selectedObject: FALLBACK_TARGETS[0]
    })
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      source: 'fallback',
      reliable: false,
      generatedAt: Date.now(),
      location: fallbackPlace,
      query: null,
      objects: FALLBACK_TARGETS,
      selectedObject: FALLBACK_TARGETS[0]
    }, pageData)
    this.setData(Object.assign({
      visibleObjects: FALLBACK_TARGETS,
      selectedKey: FALLBACK_TARGETS[0].key,
      selectedIndex: 0,
      selectedObject: FALLBACK_TARGETS[0],
      skyObjects: createSkyChartObjects(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key),
      skyKnowledgeBase: knowledge,
      locationName,
      verdict,
      condition,
      assistantLine: '实时星图暂时不可用，下面只是非实时兜底建议。',
      requestStatus: 'fallback',
      diagnosticLine: shortText(reason || 'fetch failed', 62)
    }, createHudSlots(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key), createSelectedSkyOverlay(FALLBACK_TARGETS[0], 0), createDetailState(FALLBACK_TARGETS[0], {
      locationName,
      verdict,
      condition
    })))
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
    const target = this.data.selectedObject || FALLBACK_TARGETS[0]
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      selectedObject: target
    }, Object.assign({}, this.data, { selectedObject: target }))
    this.setData(Object.assign({
      skyKnowledgeBase: knowledge
    }, createDetailState(target, this.data)))
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
      this.startDetailAsr()
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
    this.destroyDetailAgentSession()
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      objects: targets,
      selectedObject: target
    }, Object.assign({}, this.data, { visibleObjects: targets, selectedObject: target }))
    this.setData(Object.assign({
      selectedIndex: nextIndex,
      selectedKey: target.key,
      selectedObject: target,
      skyObjects: createSkyChartObjects(this.data.skyObjects, target.key),
      skyKnowledgeBase: knowledge,
      detailChatHistory: []
    }, createHudSlots(targets, target.key), createSelectedSkyOverlay(target, nextIndex), createDetailState(target, this.data)))
  },

  selectObject(event) {
    if (event && event.stopPropagation) event.stopPropagation()
    const dataset = (event && event.currentTarget && event.currentTarget.dataset) || {}
    const key = dataset.key || this.data.selectedKey
    const allObjects = (this.data.visibleObjects || []).concat(this.data.skyObjects || [])
    const target = allObjects.find(item => item.key === key) || this.data.visibleObjects[0] || FALLBACK_TARGETS[0]
    const index = Math.max(0, this.data.visibleObjects.findIndex(item => item.key === target.key))
    this.reportEvent(`selectObject:${key}`)
    this.destroyDetailAgentSession()
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      objects: this.data.visibleObjects,
      selectedObject: target
    }, Object.assign({}, this.data, { selectedObject: target }))
    this.setData(Object.assign({
      selectedIndex: index,
      selectedKey: target.key,
      selectedObject: target,
      skyObjects: createSkyChartObjects(this.data.skyObjects, target.key),
      skyKnowledgeBase: knowledge,
      detailChatHistory: []
    }, createHudSlots(this.data.visibleObjects, target.key), createSelectedSkyOverlay(target, index), createDetailState(target, this.data)))
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
      <view class="status-pill">
        <text class="status-pill-text">{{ pageTag }}</text>
      </view>
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
          catchtap="selectObject"
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
        <button class="target-btn {{ target0Class }}" data-key="{{ target0Key }}" catchtap="selectObject">
          <text class="target-name">{{ target0Name }}</text>
          <text class="target-meta">{{ target0Meta }}</text>
        </button>
        <button class="target-btn {{ target1Class }}" data-key="{{ target1Key }}" catchtap="selectObject">
          <text class="target-name">{{ target1Name }}</text>
          <text class="target-meta">{{ target1Meta }}</text>
        </button>
        <button class="target-btn {{ target2Class }}" data-key="{{ target2Key }}" catchtap="selectObject">
          <text class="target-name">{{ target2Name }}</text>
          <text class="target-meta">{{ target2Meta }}</text>
        </button>
        <button class="target-btn {{ target3Class }}" data-key="{{ target3Key }}" catchtap="selectObject">
          <text class="target-name">{{ target3Name }}</text>
          <text class="target-meta">{{ target3Meta }}</text>
        </button>
        <button class="target-btn {{ target4Class }}" data-key="{{ target4Key }}" catchtap="selectObject">
          <text class="target-name">{{ target4Name }}</text>
          <text class="target-meta">{{ target4Meta }}</text>
        </button>
      </view>
      <view class="button-grid compact overview-actions">
        <button class="btn ghost" bindtap="openHome">退出</button>
      </view>
    </view>

    <view class="content detail-panel" style="display: {{ detailDisplay }};">
      <view class="detail-layout">
        <view class="detail-left">
          <text class="kicker">{{ selectedObject.type }}</text>
          <text class="headline">{{ selectedObject.name }}</text>
          <text class="body detail-meta">{{ selectedObject.direction }} · 高度 {{ selectedObject.altitude }} · 亮度 {{ selectedObject.magnitude }}</text>
          <view class="detail-block">
            <text class="detail-label">简介</text>
            <text class="detail-text detail-intro-text">{{ detailIntro }}</text>
          </view>
          <view class="detail-block intro-block">
            <text class="detail-label">快速找法</text>
            <text class="detail-text">{{ selectedObject.locate }}</text>
          </view>
        </view>
        <view class="detail-agent">
          <text class="detail-agent-title">问 SkyMate</text>
          <text class="detail-agent-subtitle">已带入当前星体上下文</text>
          <text class="detail-agent-question">{{ detailQuestion }}</text>
          <text class="detail-agent-answer">{{ detailAnswer }}</text>
          <view class="button-grid compact detail-agent-actions">
            <button class="btn primary detail-talk-btn" bindtap="startDetailAsr">开始对话</button>
          </view>
        </view>
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
        <button class="btn secondary" bindtap="runSuzhouDemo">示例城市</button>
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

/* v10: detail page agent panel with object-scoped context. */
.shell.card.detail .content {
  left: 20px;
  top: 62px;
  width: 440px;
}

.detail-layout {
  display: flex;
  flex-direction: row;
  gap: 12px;
  width: 440px;
}

.detail-left {
  width: 166px;
  overflow: hidden;
}

.detail-left .headline {
  max-width: 166px;
  max-height: 30px;
  overflow: hidden;
  font-size: 22px;
  line-height: 27px;
}

.detail-left .detail-meta {
  max-width: 166px;
  max-height: 18px;
  margin-top: 3px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 10px;
  line-height: 14px;
}

.detail-left .detail-block {
  width: 166px;
  margin-top: 8px;
}

.detail-left .detail-text {
  max-width: 166px;
  max-height: 42px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 11px;
  line-height: 15px;
}

.detail-left .detail-intro-text {
  max-height: 72px;
}

.detail-agent {
  display: flex;
  flex-direction: column;
  width: 262px;
  height: 218px;
  box-sizing: border-box;
  padding: 12px;
  overflow: hidden;
  background: var(--sky-surface);
  border: 2px solid var(--border-color-accent);
  border-radius: 12px;
}

.detail-agent-title {
  display: block;
  height: 18px;
  overflow: hidden;
  color: var(--sky-primary);
  font-size: 15px;
  line-height: 18px;
  font-weight: 900;
}

.detail-agent-subtitle {
  display: block;
  height: 14px;
  margin-top: 2px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 10px;
  line-height: 14px;
}

.detail-agent-question {
  display: block;
  width: 234px;
  max-height: 34px;
  box-sizing: border-box;
  margin-top: 8px;
  padding: 4px 6px;
  overflow: hidden;
  color: var(--sky-primary);
  background: rgba(64, 255, 94, 0.06);
  border: 1px solid var(--border-color-muted);
  border-radius: 8px;
  font-size: 10px;
  line-height: 14px;
}

.detail-agent-answer {
  display: block;
  width: 234px;
  max-height: 88px;
  margin-top: 8px;
  overflow: hidden;
  color: var(--sky-muted);
  font-size: 11px;
  line-height: 15px;
}

.detail-agent-actions {
  width: 234px;
  margin-top: 10px;
  gap: 0;
}

.detail-agent-actions .btn {
  min-width: 112px;
  height: 32px;
  padding: 0 10px;
  font-size: 12px;
}

.detail-agent-actions .detail-talk-btn {
  min-width: 124px;
}

/* v10.1: center the top-right status title inside its pill. */
.status-pill {
  display: flex;
  flex-direction: row;
  justify-content: center;
  align-items: center;
  width: 78px;
  height: 26px;
  box-sizing: border-box;
  padding: 0;
  overflow: hidden;
  text-align: center;
  border: 1px solid var(--border-color-accent);
  border-radius: 14px;
  color: var(--sky-primary);
  background: rgba(64, 255, 94, 0.04);
  line-height: 26px;
}

.status-pill-text {
  display: block;
  width: 76px;
  height: 14px;
  overflow: hidden;
  color: var(--sky-primary);
  font-size: 11px;
  line-height: 14px;
  font-weight: 900;
  text-align: center;
  white-space: nowrap;
}

/* v10.2: compact the detail intro column to avoid text overlap. */
.detail-left .headline {
  max-height: 28px;
  font-size: 20px;
  line-height: 25px;
}

.detail-left .detail-meta {
  max-height: 14px;
  margin-top: 2px;
  font-size: 9px;
  line-height: 12px;
}

.detail-left .detail-block {
  margin-top: 6px;
}

.detail-left .detail-label {
  height: 14px;
  font-size: 10px;
  line-height: 14px;
}

.detail-left .detail-text {
  max-height: 28px;
  margin-top: 2px;
  font-size: 10px;
  line-height: 13px;
}

.detail-left .detail-intro-text {
  max-height: 52px;
}

</style>
