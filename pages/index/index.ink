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
        "topMetaLine": { "type": "string", "description": "Short update time shown under the app title" },
        "observationMetaLine": { "type": "string", "description": "Short location and update time shown in compact UI metadata" },
        "latitude": { "type": "number", "description": "Observer latitude" },
        "longitude": { "type": "number", "description": "Observer longitude" },
        "targets": { "type": "string", "description": "Recommended targets JSON string" },
        "skyChart": { "type": "string", "description": "Raw sky chart JSON string" },
        "selectedObject": { "type": "string", "description": "Selected target key or object JSON" },
        "detailIntro": { "type": "string", "description": "Generated object intro shown on the detail page" },
        "detailLocate": { "type": "string", "description": "Compact object locating guide shown on the detail page" },
        "detailQuestion": { "type": "string", "description": "Latest user question asked on the object detail page" },
        "detailAnswer": { "type": "string", "description": "Latest SkyMate answer on the object detail page" },
        "detailObjectContext": { "type": "string", "description": "Object-scoped context passed to the detail page agent" }
      }
    }
  }
}
</script>

<script setup>
const BUILD_VERSION = 'v14.0.3-merged.1'
const SKY_CHART_ENDPOINT = 'https://sky.eunoia.top/sky/chart'
const GEOCODING_ENDPOINT = 'https://geocoding-api.open-meteo.com/v1/search'
const HUD_TARGET_SLOT_COUNT = 5
const SKY_REQUEST_TARGET_LIMIT = 30
const HUD_BG_SLOT_COUNT = 8
const SKY_OBJECT_LIMIT = 32
const SKY_MAP_SIZE = 184
const DISPLAY_TIMEZONE_OFFSET_MINUTES = 8 * 60

const SKY_OPTIONS = {
  star_max_mag: 3.0,
  deep_sky_max_mag: 9.0,
  min_altitude_deg: 15.0,
  total_limit: SKY_REQUEST_TARGET_LIMIT,
  include_planets: true,
  include_deep_sky: true
}

const ASR_TRANSCRIPT_DISPLAY_LIMIT = 22
const ASR_DETAIL_QUESTION_DISPLAY_LIMIT = 30
const ASR_MIN_LISTEN_MS = 2600
const ASR_SILENCE_SUBMIT_MS = 2600
const ASR_MAX_LISTEN_MS = 10000
const ASR_SHORT_FINAL_GRACE_MS = 1800
const MODEL_GENERAL_DISPLAY_LIMIT = 34
const MODEL_DETAIL_DISPLAY_LIMIT = 72
const TTS_MAX_CHARS = 96

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
    displayName: '织女星',
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
    displayName: '大角星',
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
    displayName: '木星',
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

function displayText(value, maxLength) {
  const valueText = text(value, '').replace(/\s+/g, ' ').trim()
  const limit = maxLength || 24
  return valueText.length > limit ? `${valueText.slice(0, Math.max(1, limit - 1))}…` : valueText
}

function displayName(value, maxLength) {
  return displayText(value, maxLength || 10)
}

function displayMeta(value, maxLength) {
  return displayText(value, maxLength || 18)
}

function asrTranscriptLine(value) {
  return `我听到：${shortText(value, ASR_TRANSCRIPT_DISPLAY_LIMIT)}`
}

function asrQuestionLine(value) {
  return `你问：${shortText(value, ASR_DETAIL_QUESTION_DISPLAY_LIMIT)}`
}

function modelGeneralDisplay(value) {
  return shortText(value, MODEL_GENERAL_DISPLAY_LIMIT)
}

function modelDetailDisplay(value) {
  return shortText(value, MODEL_DETAIL_DISPLAY_LIMIT)
}

function padTimePart(value) {
  return String(value).padStart(2, '0')
}

function formatClockLabel(value) {
  const timestamp = parseTimeValue(value)
  const safeTimestamp = isNaN(timestamp) ? Date.now() : timestamp
  const displayDate = new Date(safeTimestamp + DISPLAY_TIMEZONE_OFFSET_MINUTES * 60000)
  return `${padTimePart(displayDate.getUTCHours())}:${padTimePart(displayDate.getUTCMinutes())}`
}

function shortLocationLabel(value) {
  const valueText = text(value, '观测位置').replace(/\s+/g, '')
  return valueText.length > 5 ? `${valueText.slice(0, 5)}...` : valueText
}

function readChartTimeValue(chart) {
  const raw = chart || {}
  const sources = [
    raw,
    raw.sky_chart,
    raw.skyChart,
    raw.chart,
    raw.data,
    raw.result,
    raw.data && raw.data.sky_chart,
    raw.data && raw.data.skyChart,
    raw.result && raw.result.sky_chart,
    raw.result && raw.result.skyChart,
    raw.chart && raw.chart.sky_chart,
    raw.chart && raw.chart.skyChart
  ]
  for (let index = 0; index < sources.length; index += 1) {
    const value = readAny(sources[index], ['time_utc', 'timeUtc', 'generated_at', 'generatedAt', 'dataTime', 'timestamp', 'observation_time'])
    if (hasValue(value)) return value
  }
  return undefined
}

function parseTimeValue(value) {
  if (value instanceof Date) return value.getTime()
  if (typeof value === 'number') return value < 100000000000 ? value * 1000 : value
  const raw = text(value, '')
  if (!raw) return NaN
  if (/^\d+$/.test(raw)) {
    const numericTimestamp = parseInt(raw, 10)
    return numericTimestamp < 100000000000 ? numericTimestamp * 1000 : numericTimestamp
  }
  const matched = raw.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z)?$/)
  if (matched) {
    return Date.UTC(
      parseInt(matched[1], 10),
      parseInt(matched[2], 10) - 1,
      parseInt(matched[3], 10),
      parseInt(matched[4], 10),
      parseInt(matched[5], 10),
      parseInt(matched[6] || '0', 10)
    )
  }
  return new Date(raw).getTime()
}

function safeGeneratedAt(value) {
  const timestamp = parseTimeValue(value)
  return isNaN(timestamp) ? Date.now() : timestamp
}

function createTopMetaLine(timeValue, label) {
  const clock = formatClockLabel(timeValue || Date.now())
  const updateLabel = label || '更新于'
  return clock ? `${updateLabel} ${clock}` : updateLabel
}

function createObservationMetaLine(locationName, timeValue, label) {
  const clock = formatClockLabel(timeValue || Date.now())
  const updateLabel = label || '更新于'
  return `基于${shortLocationLabel(locationName)} · ${updateLabel} ${clock}`
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
    displayName: displayName(name, 10),
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
      selectedSkyMarkerStyle: hiddenStyle()
    }
  }

  const point = skyChartPoint(target, index || 0)
  const size = Math.max(skyObjectSize(target) + 2, 8)
  return {
    selectedSkyMarkerStyle: dotStyle(point, size)
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
    slots[`target${index}Name`] = displayName(target.name, 12)
    slots[`target${index}Meta`] = displayMeta(`${windowStart + index + 1}/${allTargets.length} · ${target.type} · ${target.direction}`, 20)
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
      selectedClass: target && target.key === selectedKey ? 'selected' : '',
      labelStyle: hiddenStyle(),
      mapLabel: displayName(target.name, 7)
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
    name: text(raw.locationName || raw.city || raw.location, '观测位置'),
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
  safeAssignRecognitionOption(recognition, 'continuous', true)
  safeAssignRecognitionOption(recognition, 'interimResults', true)
  safeAssignRecognitionOption(recognition, 'maxAlternatives', 1)
}

const ASR_SHORT_QUERY_WORDS = [
  '月亮', '月球', '火星', '木星', '金星', '土星', '水星',
  '太阳', '星星', '星图', '观星', '猎户座', '北斗', '银河',
  '苏州', '太仓', '厦门', '福州', '海南', '上海', '杭州', '南京',
  '北京', '长沙', '广州', '深圳', '成都', '重庆', '武汉', '西安'
]

function isAllowedShortAsrQuery(value) {
  const normalized = text(value, '').replace(/[，。！？、,.!?\s]/g, '')
  if (normalized.length >= 3) return true
  return ASR_SHORT_QUERY_WORDS.indexOf(normalized) >= 0
}

function extractSpeechRecognitionParts(event) {
  const result = event || {}
  const results = result.results
  if (!results || typeof results.length !== 'number') {
    const direct = text(result.transcript || result.text || result.result, '').trim()
    return { finalText: direct, interimText: '', displayText: direct, hasResultFlags: false }
  }

  const finalParts = []
  const interimParts = []
  let hasResultFlags = false
  for (let index = 0; index < results.length; index += 1) {
    const item = results[index]
    const transcript = text(
      (item && item.transcript) ||
      (item && item[0] && item[0].transcript) ||
      '',
      ''
    ).trim()
    if (!transcript) continue
    if (item && typeof item.isFinal === 'boolean') hasResultFlags = true
    if (item && item.isFinal === true) finalParts.push(transcript)
    else interimParts.push(transcript)
  }
  const finalText = finalParts.join('')
  const interimText = interimParts.join('')
  return {
    finalText,
    interimText,
    displayText: `${finalText}${interimText}`,
    hasResultFlags
  }
}

function asrStartOptions() {
  return {
    lang: 'zh-CN',
    continuous: true,
    interimResults: true,
    timeout: ASR_MAX_LISTEN_MS,
    maxDuration: ASR_MAX_LISTEN_MS,
    vadTimeout: ASR_SILENCE_SUBMIT_MS,
    endSilenceTimeout: ASR_SILENCE_SUBMIT_MS
  }
}

function cleanSpeechText(value) {
  return text(value, '')
    .replace(/[*#`_~]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, TTS_MAX_CHARS)
}

function getSpeechSynthesisCandidate(root) {
  const runtime = root || getRuntimeRoot()
  const speechModule = runtime.speech || runtime.aiuiSpeech || runtime.rokidSpeech || {}
  return {
    synthesis: runtime.speechSynthesis || speechModule.speechSynthesis || speechModule.synthesis || null,
    Utterance: runtime.SpeechSynthesisUtterance || speechModule.SpeechSynthesisUtterance || speechModule.Utterance || null
  }
}

function speakAnswerText(value, owner) {
  const speechText = cleanSpeechText(value)
  if (!speechText) return { source: 'empty' }
  const speech = getSpeechSynthesisCandidate()
  if (!speech.synthesis || typeof speech.Utterance !== 'function' || typeof speech.synthesis.speak !== 'function') {
    return { source: 'unavailable' }
  }

  try {
    const utterance = new speech.Utterance(speechText)
    if (owner) owner.activeUtterance = utterance
    speech.synthesis.speak(utterance, 'immediate')
    return { source: 'speechSynthesis', method: 'speak', mode: 'immediate' }
  } catch (error) {
    console.log('[SkyMate] speechSynthesis failed', error || {})
    return { source: 'error' }
  }
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
  return displayText(base, 52)
}

function createDetailLocate(target) {
  const object = target || FALLBACK_TARGETS[0]
  return displayText(text(object.locate, `朝${text(object.direction, '开阔天空')}方向寻找较亮、稳定的光点。`), 40)
}

function extractTranscriptFromEvent(event) {
  const result = event || {}
  const direct = result.transcript || result.text || result.result
  if (direct) return direct

  const results = result.results
  if (!results || typeof results.length !== 'number') return ''
  const parts = []
  for (let index = 0; index < results.length; index += 1) {
    const item = results[index]
    const value = text(
      (item && item.transcript) ||
      (item && item[0] && item[0].transcript) ||
      '',
      ''
    ).trim()
    if (value) parts.push(value)
  }
  return parts.join('')
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

function geocodingUrl(locationName) {
  const query = text(locationName, '').trim()
  if (!query) return ''
  return `${GEOCODING_ENDPOINT}?name=${encodeURIComponent(query)}&count=5&language=zh&format=json`
}

function placeFromGeocodingResult(result, fallbackName) {
  const list = result && Array.isArray(result.results) ? result.results : []
  if (!list.length) return null
  const query = compactIntentText(fallbackName).toLowerCase()
  const ranked = list.slice().sort((left, right) => {
    const score = (item) => {
      const name = compactIntentText(item && item.name).toLowerCase()
      const admin = compactIntentText(`${text(item && item.admin1)}${text(item && item.admin2)}`).toLowerCase()
      let value = 0
      if (name === query) value += 100
      else if (name.indexOf(query) >= 0 || query.indexOf(name) >= 0) value += 60
      if (admin.indexOf(query) >= 0) value += 20
      if (text(item && item.feature_code).indexOf('PPLA') === 0) value += 8
      value += Math.min(6, Math.log10(Math.max(1, numeric(item && item.population, 1))))
      return value
    }
    return score(right) - score(left)
  })
  const first = ranked[0]
  return normalizeResolvedPlace({
    name: first.name || fallbackName,
    lat: first.latitude,
    lon: first.longitude
  }, fallbackName)
}

function createLocationNameExtractPrompt(input) {
  return [
    '请从用户输入中抽取一个最可能的城市名，用于地理编码接口查询。',
    '只返回 JSON，不要解释，不要 Markdown。',
    '格式：{"location":"城市名","confidence":0到1}',
    '如果没有明确城市，返回 {"location":"","confidence":0}。',
    '如果用户提到区县、景点、地标，但城市很明确，优先返回城市名。',
    '示例：输入“给我长沙的星图”，输出 {"location":"长沙","confidence":0.95}',
    `用户输入：${text(input, '')}`
  ].join('\n')
}

function locationNameFromModelAnswer(value) {
  const parsed = parseModelJson(value) || {}
  const location = text(parsed.location || parsed.city || parsed.locationName || parsed.name, '').trim()
  if (!location) return ''
  const confidence = parseFloat(parsed.confidence)
  if (Number.isFinite(confidence) && confidence <= 0) return ''
  return location
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
    `位置：${base.location ? text(base.location.name, '观测位置') : text(data.locationName, '未知')}`,
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
    `观测位置：${text(data.locationName, '未知')}`,
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
    '5. 如果问题需要位置但没有位置，请提示用户说城市名。'
  ].join('\n')
}

function isBackIntent(input) {
  const q = text(input, '').trim()
  return q === '返回' || q === '退出' || q === '回到首页' || q === '回到总览' || q.indexOf('返回上一') >= 0
}

function compactIntentText(input) {
  return text(input, '').replace(/\s+/g, '').trim()
}

function isCurrentLocationIntent(input) {
  return false
}

function hasObjectReferenceCue(input) {
  const q = compactIntentText(input)
  if (!q) return false
  return q.indexOf('这个') >= 0 ||
    q.indexOf('那个') >= 0 ||
    q.indexOf('它') >= 0 ||
    q.indexOf('他') >= 0 ||
    q.indexOf('她') >= 0 ||
    q.indexOf('这颗') >= 0 ||
    q.indexOf('那颗') >= 0 ||
    q.indexOf('当前目标') >= 0 ||
    q.indexOf('当前星体') >= 0 ||
    q.indexOf('这个目标') >= 0 ||
    q.indexOf('这个星体') >= 0 ||
    q.indexOf('该目标') >= 0 ||
    q.indexOf('该星体') >= 0
}

function hasNonLocationQuestionCue(input) {
  const q = compactIntentText(input)
  if (!q) return false
  return hasObjectReferenceCue(q) ||
    /(什么|怎么|为什么|哪里|哪个|多少|多久|多亮|吗|呢|么|吧|亮吗|亮度|亮|暗|颜色|大小|距离|高度|方向|简介|介绍|找法|寻找|解释|意思|是不是|是否|换一个|下一个|上一个|另一个)/.test(q)
}

function hasAstronomyKeyword(input) {
  const q = text(input, '')
  const words = ['星', '月亮', '月球', '行星', '恒星', '星座', '流星', '银河', '望远镜', '视星等', '观星', '天文', '太阳', '金星', '木星', '火星', '水星', '土星', '天王星', '海王星', '猎户', '北斗', '织女', '牛郎', '北极星']
  return words.some(word => q.indexOf(word) >= 0)
}

function roughNamedLocationCandidate(input) {
  let value = compactIntentText(input)
  if (!value) return ''
  value = value
    .replace(/(请|帮我|给我|帮忙|麻烦|查一下|查查|查询|查|看看|看一下|看|显示|生成|打开|切到|换到|基于|位于|我在|在|到|的)/g, '')
    .replace(/(今晚|今天|明天|现在|当前|当地|这里|那边|附近|当前位置|我的位置|星图|星空|天空|观星|观测|推荐|列表|结果)/g, '')
    .replace(/(能不能|能否|可不可以|可以|适合|看到|看见|看得到|能看到|能看|有什么|什么|吗|呢|啊|呀)/g, '')
    .replace(/(月亮|月球|行星|恒星|星座|流星雨|流星|银河|太阳|金星|木星|火星|水星|土星|天王星|海王星|猎户座|北斗|北极星)/g, '')
    .replace(/[，。！？,.!?]/g, '')
    .trim()
  return value
}

function isLikelyStandalonePlaceName(input) {
  const raw = text(input, '').trim()
  const q = compactIntentText(raw).replace(/[，。！？,.!?]/g, '')
  if (!q || /[?？]/.test(raw)) return false
  if (isCurrentLocationIntent(q)) return false
  if (hasAstronomyKeyword(q)) return false
  if (hasNonLocationQuestionCue(q)) return false
  if (/(什么|怎么|为什么|哪里|哪个|能不能|能否|可不可以|可以|适合|看到|看见|看得到|能看到|能看|今晚|今天|明天|现在|当前|这里|那边|附近|本地|当地|使用|用|请|帮我|给我|查|看看|看一下|看|观测|推荐|列表|结果)/.test(q)) return false
  if (/^(返回|退出|开始|定位|刷新|重试|继续|换一个|下一个|上一个|另一个|你好|谢谢|好的|可以|不行|不是|是的|对|嗯|啊)$/.test(q)) return false
  if (/^[\u4e00-\u9fa5]{2,12}$/.test(q)) {
    return q.length <= 8 || /[市县区州省岛镇村]$/.test(q)
  }
  return /^[A-Za-z][A-Za-z\s.'-]{1,39}$/.test(raw)
}

function hasNamedLocationRequest(input) {
  if (coordinateFromText(input) || cityFromText(input) || isLikelyStandalonePlaceName(input)) return true
  if (isCurrentLocationIntent(input)) return false
  const candidate = roughNamedLocationCandidate(input)
  if (!candidate) return false
  if (/^(我|你|它|这个|那个|这里|那里)$/.test(candidate)) return false
  if (hasNonLocationQuestionCue(candidate)) return false
  if (hasAstronomyKeyword(candidate)) return false
  if (/^[\u4e00-\u9fa5]{2,12}$/.test(candidate)) {
    return candidate.length <= 8 || /[市县区州省岛镇村]$/.test(candidate)
  }
  return /^[A-Za-z][A-Za-z\s.'-]{1,39}$/.test(candidate)
}

function isSkyChartIntent(input) {
  const q = text(input, '')
  return q.indexOf('今晚') >= 0 ||
    q.indexOf('今天') >= 0 ||
    q.indexOf('能看到什么') >= 0 ||
    q.indexOf('能看什么') >= 0 ||
    q.indexOf('能不能看') >= 0 ||
    q.indexOf('能否看') >= 0 ||
    q.indexOf('看得到什么') >= 0 ||
    q.indexOf('看得到') >= 0 ||
    q.indexOf('看见') >= 0 ||
    q.indexOf('查星空') >= 0 ||
    q.indexOf('观星') >= 0 ||
    q.indexOf('观测') >= 0 ||
    q.indexOf('看一下') >= 0 ||
    q.indexOf('帮我看看') >= 0 ||
    q.indexOf('星图') >= 0 ||
    q.indexOf('刷新') >= 0 ||
    ((q.indexOf('有什么') >= 0 || q.indexOf('看什么') >= 0) && (q.indexOf('星') >= 0 || q.indexOf('天空') >= 0 || q.indexOf('这里') >= 0 || q.indexOf('今晚') >= 0))
}

function hasSkyChartActionCue(input) {
  const q = compactIntentText(input)
  if (!q) return false
  return q.indexOf('星图') >= 0 ||
    q.indexOf('星空') >= 0 ||
    q.indexOf('观星') >= 0 ||
    q.indexOf('观测') >= 0 ||
    q.indexOf('推荐') >= 0 ||
    q.indexOf('列表') >= 0 ||
    q.indexOf('刷新') >= 0 ||
    q.indexOf('查') >= 0 ||
    q.indexOf('查询') >= 0 ||
    q.indexOf('换到') >= 0 ||
    q.indexOf('切到') >= 0 ||
    q.indexOf('换成') >= 0 ||
    q.indexOf('改成') >= 0 ||
    q.indexOf('基于') >= 0 ||
    q.indexOf('城市') >= 0 ||
    q.indexOf('地点') >= 0 ||
    q.indexOf('位置') >= 0 ||
    q.indexOf('能看到什么') >= 0 ||
    q.indexOf('能看什么') >= 0 ||
    q.indexOf('能不能看') >= 0 ||
    q.indexOf('能否看') >= 0 ||
    q.indexOf('可不可以看') >= 0 ||
    q.indexOf('看得到') >= 0 ||
    q.indexOf('看见') >= 0 ||
    q.indexOf('有什么') >= 0
}

function hasSelectedObjectReference(input, context) {
  const q = compactIntentText(input)
  if (!q) return false
  if (hasObjectReferenceCue(q)) return true
  const selected = context && context.selectedObject
  const name = compactIntentText(selected && selected.name)
  const displayName = compactIntentText(selected && selected.displayName)
  return !!((name && q.indexOf(name) >= 0) || (displayName && q.indexOf(displayName) >= 0))
}

function isDetailSkyChartQuery(input, context) {
  const q = compactIntentText(input)
  if (!q) return false
  if (q.indexOf('刷新') >= 0) return true

  const objectReferenced = hasSelectedObjectReference(q, context)
  if (objectReferenced && !hasLocationSignal(q)) return false

  const hasPlace = hasLocationSignal(q) || hasNamedLocationRequest(q)
  if (hasPlace && hasSkyChartActionCue(q)) return true

  if (!objectReferenced) {
    return q.indexOf('星图') >= 0 ||
      q.indexOf('星空') >= 0 ||
      q.indexOf('观星') >= 0 ||
      q.indexOf('观测列表') >= 0 ||
      q.indexOf('推荐列表') >= 0 ||
      q.indexOf('今晚能看到什么') >= 0 ||
      q.indexOf('现在能看到什么') >= 0 ||
      q.indexOf('能看到什么') >= 0
  }

  return false
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
    return '我还没有观测城市。请告诉我城市名，例如“苏州”或“杭州”。'
  }

  return '可以。我会优先结合当前星图回答；如果没有实时数据，我会说明不确定。'
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
    detailLocate: createDetailLocate(object),
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
    topMetaLine: '等待更新',
    observationMetaLine: '等待城市 · 等待更新',
    verdict: 'SkyMate 帮你看今晚星空。',
    condition: '说出城市后，我会给出今晚的观星建议。',
    assistantLine: '可说：今晚苏州能看到什么 / 杭州可以看到金星吗。',
    diagnosticLine: 'ready',
    requestStatus: 'idle',
    asrStatus: 'idle',
    eventStatus: 'waiting',
    locationLine: '说城市名开始。',
    currentPlace: null,
    skyKnowledgeBase: createSkyKnowledgeBase({}),
    detailChatHistory: [],
    generalChatHistory: [],
    lastIntent: '',
    detailQuestion: '可以问：我该怎么找？',
    detailAnswer: detailGuideAnswer(FALLBACK_TARGETS[0], ''),
    detailIntro: createDetailIntro(FALLBACK_TARGETS[0]),
    detailLocate: createDetailLocate(FALLBACK_TARGETS[0]),
    detailObjectContext: createDetailObjectContext(FALLBACK_TARGETS[0], null),
    detailAgentStatus: 'ready',
    selectedIndex: 0,
    selectedKey: FALLBACK_TARGETS[0].key,
    selectedObject: FALLBACK_TARGETS[0],
    visibleObjects: FALLBACK_TARGETS,
    rawSkyObjects: FALLBACK_TARGETS,
    skyObjects: createSkyChartObjects(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key)
  }, createHudSlots(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key), createSelectedSkyOverlay(FALLBACK_TARGETS[0], 0)),

  skyKnowledgeRaw: null,
  detailAgentSession: null,
  generalAgentSession: null,
  skyRequestId: 0,
  activeUtterance: null,
  activeAsrRecognizer: null,
  activeAsrSubmitTimer: null,
  activeAsrMaxTimer: null,
  activeAsrSubmitToken: 0,
  activeAsrStartedAt: 0,
  activeAsrLastInputAt: 0,
  activeAsrLatestText: '',
  activeAsrInterimText: '',
  activeAsrHasFinalText: false,
  activeAsrSubmitOptions: null,
  activeAsrSubmitted: false,
  pendingConfirmTimer: null,
  pendingConfirmToken: 0,
  pageActive: true,
  detailRequestToken: 0,
  generalRequestToken: 0,
  locationRequestToken: 0,
  detailSessionToken: 0,
  generalSessionToken: 0,

  onLoad(rawQuery) {
    this.pageActive = true
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
        const cachedObjects = this.data.rawSkyObjects && this.data.rawSkyObjects.length ? this.data.rawSkyObjects : []
        const baseVisibleObjects = normalizedTargets.length ? normalizedTargets : (cachedObjects.length ? cachedObjects : FALLBACK_TARGETS)
        const visibleObjects = baseVisibleObjects.some(item => item.key === selected.key)
          ? baseVisibleObjects
          : [selected].concat(baseVisibleObjects)
        const rawSkyObjects = collectSkyObjects(chart || visibleObjects, visibleObjects)
        const skyObjects = createSkyChartObjects(rawSkyObjects, selected.key)
        const locationName = text(query.locationName || query.city || query.location, this.data.locationName)
        const generatedAt = safeGeneratedAt(readChartTimeValue(chart))
        const topMetaLine = createTopMetaLine(generatedAt)
        const observationMetaLine = createObservationMetaLine(locationName, generatedAt)
        const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
          source: chart ? 'api' : 'page-query',
          reliable: !!chart,
          generatedAt,
          location: queryPlace || { name: text(query.locationName || query.city || query.location, '观测位置') },
          objects: visibleObjects,
          selectedObject: selected
        }, Object.assign({}, this.data, {
          mode: 'detail',
          locationName,
          topMetaLine,
          observationMetaLine,
          visibleObjects,
          rawSkyObjects,
          selectedObject: selected
        }))
        this.setData(Object.assign({
          currentPlace: queryPlace || this.data.currentPlace,
          locationName,
          topMetaLine,
          observationMetaLine,
          visibleObjects,
          rawSkyObjects,
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
        locationName: text(query.locationName || query.city || query.location, '观测位置'),
        source: 'page-query'
      })
      return
    }

    if (queryPlace) {
      const latText = Number.isFinite(queryPlace.lat) ? queryPlace.lat.toFixed(4) : '--'
      const lonText = Number.isFinite(queryPlace.lon) ? queryPlace.lon.toFixed(4) : '--'
      this.applyMode('chat')
      this.setData({
        currentPlace: queryPlace,
        locationName: queryPlace.name || '观测位置',
        topMetaLine: createTopMetaLine(Date.now()),
        observationMetaLine: createObservationMetaLine(queryPlace.name || '观测位置', Date.now()),
        requestStatus: 'location ok',
        diagnosticLine: `lat=${latText} lon=${lonText}`,
        assistantLine: `已收到 ${queryPlace.name || '传入位置'}，可以说“查看星图”。`,
        locationLine: `传入位置：${latText}, ${lonText}`
      })
      return
    }

    if (placeText || query.mode === 'loading') {
      this.setData({ assistantLine: userText ? `收到问题：${userText}` : '请说城市名后再查询星图。', diagnosticLine: 'query text' })
      if (placeText) this.handleConversationInput(placeText, 'page-query')
      else this.promptForCity('page-query')
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
    this.pageActive = false
    this.skyRequestId += 1
    this.detailRequestToken += 1
    this.generalRequestToken += 1
    this.locationRequestToken += 1
    this.detailSessionToken += 1
    this.generalSessionToken += 1
    this.clearPendingConfirm()
    this.clearAsrWindow({ stop: true })
    this.stopAnswerSpeech()
    this.destroyDetailAgentSession()
    if (this.generalAgentSession && typeof this.generalAgentSession.destroy === 'function') {
      this.generalAgentSession.destroy()
    }
    this.generalAgentSession = null
  },

  onVoiceWakeup(event) {
    console.log('[SkyMate] voice wakeup', event || {})
    const keyword = text(event && event.keyword, 'leqi')
    if (keyword && keyword !== 'leqi') {
      this.reportEvent(`voiceWakeupIgnored:${keyword}`)
      return
    }
    this.reportEvent('voiceWakeup')
    this.startUnifiedAsr()
  },

  onKeyUp(event) {
    const code = event && (event.code || event.key || event.keyCode)
    const isBack = code === 'Backspace' || code === 'Escape' || code === 'Back' || code === 'GoBack' || code === 4 || code === 8 || code === 27
    const isUp = code === 'ArrowUp' || code === 'Up' || code === 19
    const isDown = code === 'ArrowDown' || code === 'Down' || code === 20
    const isGlobalHook = code === 'GlobalHook'
    const isConfirm = code === 'Enter' || code === 'NumpadEnter' || code === 'Select' || code === 'OK' || code === 13

    if (isBack) {
      if (event && event.preventDefault) event.preventDefault()
      this.clearPendingConfirm()
      this.goBack()
      return
    }

    if (isUp || isDown) {
      if (event && event.preventDefault) event.preventDefault()
      this.clearPendingConfirm()
      this.moveSelection(isUp ? -1 : 1)
      return
    }

    if (isGlobalHook) {
      if (event && event.preventDefault) event.preventDefault()
      this.queueDelayedActivation('globalHook')
      return
    }

    if (isConfirm) {
      if (event && event.preventDefault) event.preventDefault()
      this.clearPendingConfirm()
      this.activateSelection()
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
      pageTag: tagMap[modeKey]
    })
  },

  startChat() {
    this.reportEvent('startChat')
    this.applyMode('chat')
  },

  stopActiveAsrRecognizer() {
    const recognizer = this.activeAsrRecognizer
    this.activeAsrRecognizer = null
    if (!recognizer) return
    try {
      if (typeof recognizer.stop === 'function') {
        recognizer.stop()
        return
      }
      if (typeof recognizer.stopRecognition === 'function') {
        recognizer.stopRecognition()
        return
      }
      if (typeof recognizer.abort === 'function') recognizer.abort()
    } catch (error) {
      console.log('[SkyMate] ASR stop ignored', error || {})
    }
  },

  clearAsrWindow(options) {
    if (this.activeAsrSubmitTimer) {
      clearTimeout(this.activeAsrSubmitTimer)
      this.activeAsrSubmitTimer = null
    }
    if (this.activeAsrMaxTimer) {
      clearTimeout(this.activeAsrMaxTimer)
      this.activeAsrMaxTimer = null
    }
    this.activeAsrSubmitToken += 1
    if (options && options.stop) this.stopActiveAsrRecognizer()
    this.activeAsrStartedAt = 0
    this.activeAsrLastInputAt = 0
    this.activeAsrLatestText = ''
    this.activeAsrInterimText = ''
    this.activeAsrHasFinalText = false
    this.activeAsrSubmitOptions = null
    this.activeAsrSubmitted = false
  },

  beginAsrWindow(options) {
    this.clearAsrWindow({ stop: true })
    const now = Date.now()
    this.activeAsrSubmitToken += 1
    this.activeAsrStartedAt = now
    this.activeAsrLastInputAt = now
    this.activeAsrLatestText = ''
    this.activeAsrInterimText = ''
    this.activeAsrHasFinalText = false
    this.activeAsrSubmitOptions = options || {}
    this.activeAsrSubmitted = false
    const token = this.activeAsrSubmitToken

    if (typeof setTimeout === 'function') {
      this.activeAsrMaxTimer = setTimeout(() => {
        if (this.activeAsrSubmitToken !== token || this.activeAsrSubmitted) return
        this.submitAsrWindow('max')
      }, ASR_MAX_LISTEN_MS)
    }
  },

  recordAsrResult(transcript, options) {
    if (this.activeAsrSubmitted) return this.activeAsrLatestText
    if (!this.activeAsrStartedAt) this.beginAsrWindow(options)
    const value = text(transcript, '').trim()
    if (value) {
      this.activeAsrLatestText = value
      this.activeAsrHasFinalText = !!(options && options.isFinal)
      this.activeAsrLastInputAt = Date.now()
    }
    this.activeAsrSubmitOptions = Object.assign({}, this.activeAsrSubmitOptions || {}, options || {})
    this.scheduleAsrWindowSubmit()
    return this.activeAsrLatestText
  },

  scheduleAsrWindowSubmit() {
    if (this.activeAsrSubmitted) return
    if (this.activeAsrSubmitTimer) {
      clearTimeout(this.activeAsrSubmitTimer)
      this.activeAsrSubmitTimer = null
    }

    const now = Date.now()
    const startedAt = this.activeAsrStartedAt || now
    const lastInputAt = this.activeAsrLastInputAt || startedAt
    const submitAt = Math.min(
      startedAt + ASR_MAX_LISTEN_MS,
      Math.max(startedAt + ASR_MIN_LISTEN_MS, lastInputAt + ASR_SILENCE_SUBMIT_MS)
    )
    const delay = Math.max(0, submitAt - now)
    const token = this.activeAsrSubmitToken

    if (typeof setTimeout !== 'function') {
      this.submitAsrWindow('direct')
      return
    }

    this.activeAsrSubmitTimer = setTimeout(() => {
      if (this.activeAsrSubmitToken !== token || this.activeAsrSubmitted) return
      this.submitAsrWindow('silence')
    }, delay)
  },

  submitAsrWindow(reason) {
    if (this.activeAsrSubmitted) return
    let value = text(this.activeAsrLatestText, '').trim()
    const options = this.activeAsrSubmitOptions || {}
    const successStatus = options.successStatus || (options.detail ? 'detail-success' : 'success')
    const emptyStatus = options.emptyStatus || (options.detail ? 'detail-empty' : 'empty')
    const canSubmitShort = isAllowedShortAsrQuery(value)
    const finalOrFallback = this.activeAsrHasFinalText || !!options.unflaggedResult
    if (value && !canSubmitShort && reason === 'max') {
      const rejectedShortText = value
      value = ''
      this.activeAsrLatestText = ''
      this.activeAsrInterimText = ''
      this.activeAsrHasFinalText = false
      this.activeAsrSubmitOptions = Object.assign({}, options, { rejectedShortText })
    } else if (value && !canSubmitShort && (!finalOrFallback || reason !== 'max')) {
      this.activeAsrLastInputAt = Date.now()
      this.setData({
        asrStatus: options.detail ? 'detail-listening' : 'listening',
        assistantLine: '听到的内容还不完整，请继续说。',
        diagnosticLine: `asr-hold-short:${reason || 'window'}`
      })
      if (typeof setTimeout === 'function') {
        const token = this.activeAsrSubmitToken
        this.activeAsrSubmitTimer = setTimeout(() => {
          if (this.activeAsrSubmitToken !== token || this.activeAsrSubmitted) return
          this.submitAsrWindow('max')
        }, ASR_SHORT_FINAL_GRACE_MS)
      }
      return
    }

    this.activeAsrSubmitted = true
    if (this.activeAsrSubmitTimer) {
      clearTimeout(this.activeAsrSubmitTimer)
      this.activeAsrSubmitTimer = null
    }
    if (this.activeAsrMaxTimer) {
      clearTimeout(this.activeAsrMaxTimer)
      this.activeAsrMaxTimer = null
    }
    this.activeAsrSubmitToken += 1
    this.stopActiveAsrRecognizer()

    this.setData({
      asrStatus: value ? successStatus : emptyStatus,
      assistantLine: value ? asrTranscriptLine(value) : '这次没有听清，请重新说一遍。',
      diagnosticLine: `asr-submit:${reason || 'window'}`
    })

    this.activeAsrStartedAt = 0
    this.activeAsrLastInputAt = 0
    this.activeAsrLatestText = ''
    this.activeAsrInterimText = ''
    this.activeAsrHasFinalText = false
    this.activeAsrSubmitOptions = null

    if (options.detail) {
      this.handleConversationInput(value || '我该怎么找？', 'voice')
      return
    }

    if (value) this.handleConversationInput(value, 'voice')
    else this.setData({ assistantLine: '这次没有听清，请重新聆听。' })
  },

  startUnifiedAsr() {
    this.reportEvent('startUnifiedAsr')
    this.startAsr()
  },

  startAsr() {
    this.reportEvent('startAsr')
    this.beginAsrWindow({
      successStatus: 'success',
      emptyStatus: 'empty'
    })
    this.applyMode('chat')
    this.setData({
      asrStatus: 'listening',
      assistantLine: '我在听，可以说城市名或观测问题。'
    })

    if (this.startWxAsr()) return

    const Recognition = getSpeechRecognitionCandidate()
    if (!Recognition) {
      this.clearAsrWindow({ stop: true })
      this.setData({
        asrStatus: 'unavailable',
        assistantLine: '当前环境没有 ASR，请说城市名。'
      })
      return
    }

    const recognition = new Recognition()
    configureSpeechRecognition(recognition)
    this.activeAsrRecognizer = recognition
    const recognitionToken = this.activeAsrSubmitToken

    recognition.onresult = (event) => {
      if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
      const parts = extractSpeechRecognitionParts(event)
      const displayValue = text(parts.displayText, '').trim()
      let buffered = this.activeAsrLatestText
      this.activeAsrInterimText = parts.interimText
      if (parts.finalText || (!parts.hasResultFlags && displayValue)) {
        buffered = this.recordAsrResult(parts.finalText || displayValue, {
          successStatus: 'success',
          emptyStatus: 'empty',
          isFinal: !!parts.finalText,
          unflaggedResult: !parts.hasResultFlags
        })
      }
      console.log('[SkyMate] ASR result', parts, { buffered, event: event || {} })
      this.setData({
        asrStatus: displayValue ? 'listening' : 'empty',
        assistantLine: displayValue ? asrTranscriptLine(displayValue) : '我在听，请继续说完整问题。'
      })
    }

    recognition.onerror = (event) => {
      if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
      console.log('[SkyMate] ASR error', event || {})
      this.clearAsrWindow({ stop: true })
      this.setData({
        asrStatus: 'error',
        assistantLine: '这次语音没有成功，可以重试或直接说城市名。'
      })
    }

    recognition.onend = () => {
      console.log('[SkyMate] ASR end')
      if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
      if (this.activeAsrSubmitted) return
      if (this.activeAsrHasFinalText) {
        this.submitAsrWindow('end-final')
        return
      }
      this.setData({
        asrStatus: 'ended',
        assistantLine: this.activeAsrInterimText ? '语音提前结束，请重新说完整问题。' : '没有听到完整内容，请重试。'
      })
      this.clearAsrWindow({ stop: false })
    }
    try {
      recognition.start()
    } catch (error) {
      console.log('[SkyMate] ASR start failed', error || {})
      this.clearAsrWindow({ stop: true })
      this.setData({ asrStatus: 'start-error', assistantLine: '无法启动语音识别，请检查权限后重试。' })
    }
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
      this.activeAsrRecognizer = recognizer
      const recognitionToken = this.activeAsrSubmitToken

      const onResult = (event) => {
        if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
        const transcript = text(extractTranscriptFromEvent(event), '').trim()
        const buffered = this.recordAsrResult(transcript, {
          successStatus: 'wx-success',
          emptyStatus: 'wx-empty',
          unflaggedResult: true
        })
        console.log('[SkyMate] wx ASR result', transcript, { buffered, event: event || {} })
        this.setData({
          asrStatus: buffered ? 'wx-listening' : 'wx-empty',
          assistantLine: buffered ? asrTranscriptLine(buffered) : '我在听，请继续说完整问题。'
        })
      }

      const onError = (error) => {
        if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
        console.log('[SkyMate] wx ASR error', error || {})
        this.clearAsrWindow({ stop: true })
        this.setData({
          asrStatus: 'wx-error',
          assistantLine: 'Rokid 语音识别没有成功，可以重试或直接说城市名。'
        })
      }

      if (typeof recognizer.onResult === 'function') recognizer.onResult(onResult)
      else recognizer.onresult = onResult

      if (typeof recognizer.onError === 'function') recognizer.onError(onError)
      else recognizer.onerror = onError

      const onEnd = () => {
        console.log('[SkyMate] wx ASR end')
        if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken || this.activeAsrSubmitted) return
        if (this.activeAsrLatestText) this.submitAsrWindow('wx-end')
        else this.clearAsrWindow({ stop: false })
      }
      if (typeof recognizer.onEnd === 'function') recognizer.onEnd(onEnd)
      else recognizer.onend = onEnd

      if (typeof recognizer.start === 'function') {
        recognizer.start(asrStartOptions())
        return true
      }

      if (typeof recognizer.startRecognition === 'function') {
        recognizer.startRecognition(asrStartOptions())
        return true
      }
    } catch (error) {
      console.log('[SkyMate] wx ASR setup failed', error || {})
    }
    return false
  },

  startDetailAsr() {
    this.reportEvent('startDetailAsr')
    this.beginAsrWindow({
      detail: true,
      successStatus: 'detail-success',
      emptyStatus: 'detail-empty'
    })
    this.applyMode('detail')
    this.setData({
      asrStatus: 'detail-listening',
      detailAgentStatus: 'listening',
      detailQuestion: '正在听...',
      detailAnswer: '说出你想问的问题，比如“我该怎么找它？”',
      assistantLine: '我在听，可以继续追问当前星体。'
    })

    if (this.startWxDetailAsr()) return

    const Recognition = getSpeechRecognitionCandidate()
    if (!Recognition) {
      this.clearAsrWindow({ stop: true })
      this.handleConversationInput('我该怎么找？', 'voice')
      return
    }

    const recognition = new Recognition()
    configureSpeechRecognition(recognition)
    this.activeAsrRecognizer = recognition
    const recognitionToken = this.activeAsrSubmitToken

    recognition.onresult = (event) => {
      if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
      const parts = extractSpeechRecognitionParts(event)
      const displayValue = text(parts.displayText, '').trim()
      let buffered = this.activeAsrLatestText
      this.activeAsrInterimText = parts.interimText
      if (parts.finalText || (!parts.hasResultFlags && displayValue)) {
        buffered = this.recordAsrResult(parts.finalText || displayValue, {
          detail: true,
          successStatus: 'detail-success',
          emptyStatus: 'detail-empty',
          isFinal: !!parts.finalText,
          unflaggedResult: !parts.hasResultFlags
        })
      }
      console.log('[SkyMate] detail ASR result', parts, { buffered, event: event || {} })
      this.setData({
        asrStatus: displayValue ? 'detail-listening' : 'detail-empty',
        detailQuestion: displayValue ? asrQuestionLine(displayValue) : '正在听...'
      })
    }

    recognition.onerror = (event) => {
      if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
      console.log('[SkyMate] detail ASR error', event || {})
      this.clearAsrWindow({ stop: true })
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

    recognition.onend = () => {
      console.log('[SkyMate] detail ASR end')
      if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
      if (this.activeAsrSubmitted) return
      if (this.activeAsrHasFinalText) {
        this.submitAsrWindow('end-final')
        return
      }
      this.setData({
        asrStatus: 'detail-ended',
        detailQuestion: '语音提前结束',
        detailAnswer: '请重新开始对话并说完整问题。'
      })
      this.clearAsrWindow({ stop: false })
    }
    try {
      recognition.start()
    } catch (error) {
      console.log('[SkyMate] detail ASR start failed', error || {})
      this.clearAsrWindow({ stop: true })
      this.setData({
        asrStatus: 'detail-start-error',
        detailQuestion: '无法启动语音',
        detailAnswer: '请检查麦克风权限后重试。'
      })
    }
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
      this.activeAsrRecognizer = recognizer
      const recognitionToken = this.activeAsrSubmitToken

      const onResult = (event) => {
        if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
        const transcript = text(extractTranscriptFromEvent(event), '').trim()
        const buffered = this.recordAsrResult(transcript, {
          detail: true,
          successStatus: 'detail-wx-success',
          emptyStatus: 'detail-wx-empty',
          unflaggedResult: true
        })
        console.log('[SkyMate] wx detail ASR result', transcript, { buffered, event: event || {} })
        this.setData({
          asrStatus: buffered ? 'detail-wx-listening' : 'detail-wx-empty',
          detailQuestion: buffered ? asrQuestionLine(buffered) : '正在听...'
        })
      }

      const onError = (error) => {
        if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken) return
        console.log('[SkyMate] wx detail ASR error', error || {})
        this.clearAsrWindow({ stop: true })
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

      const onEnd = () => {
        console.log('[SkyMate] wx detail ASR end')
        if (!this.pageActive || recognitionToken !== this.activeAsrSubmitToken || this.activeAsrSubmitted) return
        if (this.activeAsrLatestText) this.submitAsrWindow('wx-detail-end')
        else this.clearAsrWindow({ stop: false })
      }
      if (typeof recognizer.onEnd === 'function') recognizer.onEnd(onEnd)
      else recognizer.onend = onEnd

      if (typeof recognizer.start === 'function') {
        recognizer.start(asrStartOptions())
        return true
      }

      if (typeof recognizer.startRecognition === 'function') {
        recognizer.startRecognition(asrStartOptions())
        return true
      }
    } catch (error) {
      console.log('[SkyMate] wx detail ASR setup failed', error || {})
    }
    return false
  },

  async getDetailAgentSession() {
    if (this.detailAgentSession) return this.detailAgentSession
    const sessionToken = this.detailSessionToken + 1
    this.detailSessionToken = sessionToken

    const LanguageModel = getLanguageModelCandidate()
    if (!LanguageModel || typeof LanguageModel.availability !== 'function' || typeof LanguageModel.create !== 'function') return null

    const availability = await LanguageModel.availability()
    if (!this.pageActive || sessionToken !== this.detailSessionToken) return null
    if (availability !== 'available') return null

    const session = await LanguageModel.create({
      initialPrompts: [
        {
          role: 'system',
          content: '你是 SkyMate，一个简短、自然、适合智能眼镜语音播报的观星助手。'
        }
      ]
    })
    if (!this.pageActive || sessionToken !== this.detailSessionToken) {
      if (session && typeof session.destroy === 'function') session.destroy()
      return null
    }
    this.detailAgentSession = session
    return session
  },

  async getGeneralAgentSession() {
    if (this.generalAgentSession) return this.generalAgentSession
    const sessionToken = this.generalSessionToken + 1
    this.generalSessionToken = sessionToken

    const LanguageModel = getLanguageModelCandidate()
    if (!LanguageModel || typeof LanguageModel.availability !== 'function' || typeof LanguageModel.create !== 'function') return null

    const availability = await LanguageModel.availability()
    if (!this.pageActive || sessionToken !== this.generalSessionToken) return null
    if (availability !== 'available') return null

    const session = await LanguageModel.create({
      initialPrompts: [
        {
          role: 'system',
          content: '你是 SkyMate，一个面向智能眼镜用户的观星助手。回答要简短、自然、结论优先。'
        }
      ]
    })
    if (!this.pageActive || sessionToken !== this.generalSessionToken) {
      if (session && typeof session.destroy === 'function') session.destroy()
      return null
    }
    this.generalAgentSession = session
    return session
  },

  destroyDetailAgentSession() {
    this.detailSessionToken += 1
    if (this.detailAgentSession && typeof this.detailAgentSession.destroy === 'function') {
      this.detailAgentSession.destroy()
    }
    this.detailAgentSession = null
  },

  stopAnswerSpeech() {
    this.activeUtterance = null
  },

  speakAnswer(answer) {
    this.stopAnswerSpeech()
    const result = speakAnswerText(answer, this)
    const source = text(result && result.source, 'unavailable')
    console.log('[SkyMate] TTS result', result || {})
    this.setData({
      asrStatus: source === 'unavailable' ? 'tts-off' : source === 'error' ? 'tts-error' : source === 'empty' ? 'tts-empty' : 'tts-submitted'
    })
    return result
  },

  async askDetailAgent(question, source) {
    const requestToken = this.detailRequestToken + 1
    this.detailRequestToken = requestToken
    const target = this.data.selectedObject || FALLBACK_TARGETS[0]
    const questionText = text(question, '我该怎么找？')
    const questionDisplay = source === 'voice' ? asrQuestionLine(questionText) : `你问：${questionText}`
    const fallbackAnswer = detailGuideAnswer(target, questionText)
    const context = createDetailObjectContext(target, this.data)
    const userHistory = (this.data.detailChatHistory || []).concat({
      role: 'user',
      content: questionText
    }).slice(-10)

    this.setData({
      detailChatHistory: userHistory,
      detailObjectContext: context,
      detailQuestion: questionDisplay,
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
    if (!this.pageActive || requestToken !== this.detailRequestToken) return ''

    if (!session || typeof session.prompt !== 'function') {
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        detailChatHistory: nextHistory,
        detailAnswer: fallbackAnswer,
        detailAgentStatus: 'local',
        assistantLine: '当前没有大模型配置，已用星体上下文给出本地回答。'
      })
      this.speakAnswer(fallbackAnswer)
      return fallbackAnswer
    }

    try {
      const promptData = Object.assign({}, this.data, { detailChatHistory: userHistory })
      const modelAnswer = await session.prompt(createDetailPrompt(target, questionText, promptData))
      if (!this.pageActive || requestToken !== this.detailRequestToken) return ''
      const answer = text(modelAnswer || fallbackAnswer, '')
      const answerDisplay = modelDetailDisplay(answer)
      const nextHistory = userHistory.concat({ role: 'assistant', content: answer }).slice(-10)
      this.setData({
        detailChatHistory: nextHistory,
        detailAnswer: answerDisplay,
        detailAgentStatus: 'model',
        assistantLine: modelGeneralDisplay(answer)
      })
      this.speakAnswer(answer)
      return answer
    } catch (error) {
      console.log('[SkyMate] detail agent fallback', error || {})
      if (!this.pageActive || requestToken !== this.detailRequestToken) return ''
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        detailChatHistory: nextHistory,
        detailAnswer: fallbackAnswer,
        detailAgentStatus: 'local',
        assistantLine: '大模型暂时不可用，已按当前星体上下文回答。'
      })
      this.speakAnswer(fallbackAnswer)
      return fallbackAnswer
    }
  },

  async askGeneralAgent(question) {
    const requestToken = this.generalRequestToken + 1
    this.generalRequestToken = requestToken
    const questionText = text(question, '').trim()
    if (!questionText) return this.promptForCity('empty-general')

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
    if (!this.pageActive || requestToken !== this.generalRequestToken) return ''

    if (!session || typeof session.prompt !== 'function') {
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        generalChatHistory: nextHistory,
        assistantLine: fallbackAnswer,
        requestStatus: 'general local'
      })
      this.speakAnswer(fallbackAnswer)
      return fallbackAnswer
    }

    try {
      const promptData = Object.assign({}, this.data, { generalChatHistory: userHistory })
      const modelAnswer = await session.prompt(createGeneralChatPrompt(questionText, promptData))
      if (!this.pageActive || requestToken !== this.generalRequestToken) return ''
      const answer = text(modelAnswer || fallbackAnswer, '')
      const answerDisplay = modelGeneralDisplay(answer)
      const nextHistory = userHistory.concat({ role: 'assistant', content: answer }).slice(-10)
      this.setData({
        generalChatHistory: nextHistory,
        assistantLine: answerDisplay,
        requestStatus: 'general model'
      })
      this.speakAnswer(answer)
      return answer
    } catch (error) {
      console.log('[SkyMate] general agent fallback', error || {})
      if (!this.pageActive || requestToken !== this.generalRequestToken) return ''
      const nextHistory = userHistory.concat({ role: 'assistant', content: fallbackAnswer }).slice(-10)
      this.setData({
        generalChatHistory: nextHistory,
        assistantLine: fallbackAnswer,
        requestStatus: 'general local'
      })
      this.speakAnswer(fallbackAnswer)
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
    if (
      mode === 'detail' &&
      context &&
      context.selectedObject
    ) {
      if (isDetailSkyChartQuery(q, context)) return { type: 'sky_chart_query' }
      if (isSwitchObjectIntent(q, context)) return { type: 'switch_object', targetHint: q }
      return { type: 'detail_question' }
    }
    if (isSwitchObjectIntent(q, context)) return { type: 'switch_object', targetHint: q }
    if (isCurrentLocationIntent(q) || hasLocationSignal(q) || hasNamedLocationRequest(q) || isSkyChartIntent(q)) return { type: 'sky_chart_query' }
    if (isAstronomyQuestion(q)) return { type: 'general_astronomy_question' }
    return { type: 'general_astronomy_question' }
  },

  async handleConversationInput(input, source) {
    this.reportEvent(`conversation:${source || 'unknown'}`)
    console.log('[SkyMate] conversation input', source, input)
    const questionText = text(input, '').trim()
    if (!questionText) return this.promptForCity('empty-conversation')

    if (isCurrentLocationIntent(questionText)) {
      this.setData({ lastIntent: 'sky_chart_query' })
      return this.promptForCity('current-location-disabled')
    }

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
      return this.askDetailAgent(questionText, source)
    }

    return this.askGeneralAgent(questionText)
  },

  async resolvePlaceFromText(input) {
    const result = await this.resolvePlaceFromTextWithMeta(input)
    return result.place
  },

  async resolvePlaceFromTextWithMeta(input) {
    const namedLocationRequested = hasNamedLocationRequest(input)
    const coordinate = coordinateFromText(input)
    if (coordinate) {
      console.log('[SkyMate] text coordinate resolved', coordinate)
      return {
        place: coordinate,
        namedLocationRequested: true,
        query: coordinate.name,
        stage: 'coordinate'
      }
    }

    const city = cityFromText(input)
    if (city) {
      console.log('[SkyMate] local city resolved', city)
      return {
        place: city,
        namedLocationRequested: true,
        query: city.name,
        stage: 'local-city'
      }
    }

    const locationToken = this.locationRequestToken
    const extractedLocationName = await this.extractLocationNameWithModel(input, locationToken)
    if (extractedLocationName) {
      if (!this.pageActive || locationToken !== this.locationRequestToken) {
        return { place: null, namedLocationRequested: true, query: extractedLocationName, stage: 'stale' }
      }
      const geocodedPlace = await this.resolveLocationWithOnlineGeocoder(extractedLocationName, locationToken)
      return {
        place: geocodedPlace,
        namedLocationRequested: true,
        query: extractedLocationName,
        stage: geocodedPlace ? 'geocode' : 'geocode-failed'
      }
    }

    return {
      place: null,
      namedLocationRequested,
      query: namedLocationRequested ? roughNamedLocationCandidate(input) || text(input, '').trim() : '',
      stage: 'unresolved'
    }
  },

  async resolvePlaceAndLoadSkyChart(input) {
    const requestToken = this.locationRequestToken + 1
    this.locationRequestToken = requestToken
    if (isCurrentLocationIntent(input)) {
      return this.promptForCity('current-location-disabled')
    }

    const resolved = await this.resolvePlaceFromTextWithMeta(input)
    if (!this.pageActive || requestToken !== this.locationRequestToken) return null
    const place = resolved.place

    if (place) {
      this.setData({ currentPlace: place })
      this.loadSkyChart(place)
      return place
    }

    if (resolved.namedLocationRequested) {
      this.applyMode('chat')
      this.setData({
        requestStatus: 'location unresolved',
        diagnosticLine: shortText(`${resolved.stage}: ${resolved.query || text(input, '')}`, 62),
        assistantLine: `没有解析到 ${shortText(resolved.query || text(input, ''), 12)}，请换个城市名再试。`
      })
      return null
    }

    if (this.data.currentPlace && isSkyChartIntent(input)) {
      this.loadSkyChart(this.data.currentPlace)
      return this.data.currentPlace
    }

    return this.promptForCity('location-required')
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
      skyObjects: createSkyChartObjects(
        this.data.rawSkyObjects && this.data.rawSkyObjects.length ? this.data.rawSkyObjects : targets,
        target.key
      ),
      skyKnowledgeBase: knowledge,
      detailChatHistory: [],
      assistantLine: `已切换到 ${target.name}，可以继续追问。`
    }, createHudSlots(targets, target.key), createSelectedSkyOverlay(target, index), createDetailState(target, this.data)))
    this.applyMode('detail')
    return target
  },

  async resolveLocationWithOnlineGeocoder(locationName, requestToken) {
    const query = text(locationName, '').trim()
    const url = geocodingUrl(query)
    if (!url) return null

    if (!this.pageActive || (requestToken && requestToken !== this.locationRequestToken)) return null
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
      if (!this.pageActive || (requestToken && requestToken !== this.locationRequestToken)) return null
      if (!response || !response.ok) {
        console.log('[SkyMate] geocode HTTP failed', response && response.status)
        return null
      }
      const json = await response.json()
      if (!this.pageActive || (requestToken && requestToken !== this.locationRequestToken)) return null
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

  async extractLocationNameWithModel(input, requestToken) {
    const query = text(input, '').trim()
    if (!query) return ''

    const LanguageModel = getLanguageModelCandidate()
    if (!LanguageModel || typeof LanguageModel.availability !== 'function' || typeof LanguageModel.create !== 'function') {
      console.log('[SkyMate] location extraction model unavailable')
      return ''
    }

    if (!this.pageActive || (requestToken && requestToken !== this.locationRequestToken)) return ''
    this.setData({
      requestStatus: 'extract location',
      diagnosticLine: shortText(query, 62),
      assistantLine: '正在从问题中提取城市。'
    })

    let session = null
    try {
      const availability = await LanguageModel.availability()
      if (!this.pageActive || (requestToken && requestToken !== this.locationRequestToken)) return ''
      console.log('[SkyMate] location model availability', availability)
      if (availability !== 'available') return ''

      session = await LanguageModel.create({
        initialPrompts: [
          {
            role: 'system',
            content: '你是地点抽取助手。只输出严格 JSON，不输出解释。'
          }
        ]
      })
      if (!this.pageActive || (requestToken && requestToken !== this.locationRequestToken)) return ''

      const answer = await session.prompt(createLocationNameExtractPrompt(query))
      if (!this.pageActive || (requestToken && requestToken !== this.locationRequestToken)) return ''
      console.log('[SkyMate] location extraction answer', answer)
      const locationName = locationNameFromModelAnswer(answer)
      console.log('[SkyMate] extracted location name', locationName)
      if (!locationName) return ''

      this.setData({
        requestStatus: 'location extracted',
        diagnosticLine: shortText(locationName, 62),
        assistantLine: `已提取城市：${locationName}，正在联网查询坐标。`
      })
      return locationName
    } catch (error) {
      console.log('[SkyMate] location extraction failed', error || {})
      return ''
    } finally {
      if (session && typeof session.destroy === 'function') session.destroy()
    }
  },

  promptForCity(reason) {
    this.reportEvent('promptForCity')
    this.applyMode('chat')
    this.setData({
      requestStatus: 'city required',
      diagnosticLine: shortText(reason || 'no city', 62),
      assistantLine: '请直接说城市名，例如“杭州”或“今晚苏州能看到什么”。',
      locationLine: '等待城市名'
    })
    return null
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
        assistantLine: '需要位置：请说城市名。'
      })
      return
    }
    const requestId = this.skyRequestId + 1
    this.skyRequestId = requestId
    this.applyMode('loading')
    this.setData({
      currentPlace: place,
      locationName: place.name,
      topMetaLine: createTopMetaLine(Date.now()),
      observationMetaLine: createObservationMetaLine(place.name, Date.now()),
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
      const response = await this.fetchSkyChart(payload, requestId)
      const chart = await response.json()
      if (!this.pageActive || requestId !== this.skyRequestId) return
      console.log('[SkyMate] sky chart result', chart)
      this.showChartResult({
        chart,
        locationName: place.name,
        source: 'sky-chart',
        place,
        query: payload
      })
    } catch (error) {
      if (!this.pageActive || requestId !== this.skyRequestId) return
      console.log('[SkyMate] sky chart failed', error || {})
      this.showFallback(place.name, errorText(error))
    }
  },

  async fetchSkyChart(payload, requestId) {
    const isCurrent = () => this.pageActive && (!requestId || requestId === this.skyRequestId)
    console.log('[SkyMate] sky fetch start', {
      url: SKY_CHART_ENDPOINT,
      lat: payload.lat,
      lon: payload.lon,
      total_limit: payload.total_limit
    })
    if (!isCurrent()) throw new Error('stale sky request')
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
      if (!isCurrent()) throw new Error('stale sky request')
      this.setData({ requestStatus: `http ${response.status}`, diagnosticLine: 'POST ok' })
      return response
    } catch (firstError) {
      if (!isCurrent()) throw firstError
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
    if (!isCurrent()) throw new Error('stale sky request')

    if (!retryResponse.ok) {
      const retryError = await responseErrorText(retryResponse, 'retry HTTP')
      console.log('[SkyMate] sky fetch retry POST failed', retryError)
      this.setData({ requestStatus: 'retry GET', diagnosticLine: shortText(retryError, 62) })

      const getUrl = `${SKY_CHART_ENDPOINT}?${queryStringFromPayload(retryPayload)}`
      const getResponse = await fetch(getUrl, {
        method: 'GET',
        headers: { 'X-User-Agent': 'Rizon/1.0' }
      })
      if (!isCurrent()) throw new Error('stale sky request')

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
    const locationName = text(options && options.locationName, '观测位置')
    const targets = providedTargets ? providedTargets.map((item, index) => normalizeTarget(item, index)) : pickTargets(chart)
    const skyObjects = collectSkyObjects(chart || providedTargets, targets)
    const first = targets[0] || FALLBACK_TARGETS[0]
    const source = text(options && options.source, 'sky-chart')
    const place = (options && options.place) || this.data.currentPlace || { name: locationName }
    const generatedAt = safeGeneratedAt(readChartTimeValue(chart))
    const topMetaLine = createTopMetaLine(generatedAt)
    const observationMetaLine = createObservationMetaLine(locationName, generatedAt)
    const verdict = '今晚推荐'
    const condition = '城市里优先看亮星、行星和月亮；深空目标更适合望远镜或暗处。'
    const pageData = Object.assign({}, this.data, {
      locationName,
      topMetaLine,
      observationMetaLine,
      verdict: displayText(verdict, 12),
      condition,
      visibleObjects: targets,
      rawSkyObjects: skyObjects,
      selectedObject: first
    })
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      source: 'api',
      reliable: true,
      generatedAt,
      location: place,
      query: options && options.query,
      objects: targets,
      selectedObject: first
    }, pageData)

    this.skyKnowledgeRaw = chart || null

    this.setData(Object.assign({
      currentPlace: place,
      visibleObjects: targets,
      rawSkyObjects: skyObjects,
      selectedKey: first.key,
      selectedIndex: 0,
      selectedObject: first,
      locationName,
      skyObjects: createSkyChartObjects(skyObjects, first.key),
      skyKnowledgeBase: knowledge,
      topMetaLine,
      observationMetaLine,
      verdict: displayText(verdict, 12),
      condition,
      assistantLine: '已筛出最适合普通用户看的目标。',
      requestStatus: displayMeta(`ok ${source}`, 18),
      diagnosticLine: `targets=${targets.length} sky=${skyObjects.length}`
    }, createHudSlots(targets, first.key), createSelectedSkyOverlay(first, 0), createDetailState(first, {
      locationName,
      topMetaLine,
      observationMetaLine,
      verdict: displayText(verdict, 12),
      condition
    })))
    this.applyMode('overview')
  },

  showFallback(locationName, reason) {
    console.log('[SkyMate] fallback reason', reason || '')
    const generatedAt = Date.now()
    const topMetaLine = createTopMetaLine(generatedAt)
    const observationMetaLine = createObservationMetaLine(locationName, generatedAt)
    const verdict = '本地推荐'
    const condition = '下面是一般情况下较容易尝试的亮目标，不代表观测位置和当前时间的精确结果。'
    const fallbackPlace = this.data.currentPlace || { name: locationName }
    const pageData = Object.assign({}, this.data, {
      locationName,
      topMetaLine,
      observationMetaLine,
      verdict: displayText(verdict, 12),
      condition,
      visibleObjects: FALLBACK_TARGETS,
      rawSkyObjects: FALLBACK_TARGETS,
      selectedObject: FALLBACK_TARGETS[0]
    })
    const knowledge = updateSkyKnowledgeBase(this.data.skyKnowledgeBase, {
      source: 'fallback',
      reliable: false,
      generatedAt,
      location: fallbackPlace,
      query: null,
      objects: FALLBACK_TARGETS,
      selectedObject: FALLBACK_TARGETS[0]
    }, pageData)
    this.setData(Object.assign({
      visibleObjects: FALLBACK_TARGETS,
      rawSkyObjects: FALLBACK_TARGETS,
      selectedKey: FALLBACK_TARGETS[0].key,
      selectedIndex: 0,
      selectedObject: FALLBACK_TARGETS[0],
      skyObjects: createSkyChartObjects(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key),
      skyKnowledgeBase: knowledge,
      locationName,
      topMetaLine,
      observationMetaLine,
      verdict: displayText(verdict, 12),
      condition,
      assistantLine: '实时星图暂时不可用，下面只是非实时兜底建议。',
      requestStatus: 'fallback',
      diagnosticLine: shortText(reason || 'fetch failed', 62)
    }, createHudSlots(FALLBACK_TARGETS, FALLBACK_TARGETS[0].key), createSelectedSkyOverlay(FALLBACK_TARGETS[0], 0), createDetailState(FALLBACK_TARGETS[0], {
      locationName,
      topMetaLine,
      observationMetaLine,
      verdict: displayText(verdict, 12),
      condition
    })))
    this.applyMode('overview')
  },

  openHome() {
    this.reportEvent('openHome')
    this.clearPendingConfirm()
    this.applyMode('home')
  },

  openOverview() {
    this.reportEvent('openOverview')
    this.clearPendingConfirm()
    this.restoreOverviewState()
  },

  openDetail() {
    this.reportEvent('openDetail')
    this.clearPendingConfirm()
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
    this.clearPendingConfirm()
    this.applyMode('locate')
  },

  goBack() {
    const mode = this.data.mode
    this.reportEvent(`back:${mode}`)
    if (mode === 'detail' || mode === 'locate') {
      this.restoreOverviewState()
      return
    }
    if (mode === 'overview' || mode === 'chat' || mode === 'loading' || mode === 'error') {
      this.applyMode('home')
      return
    }
    this.applyMode('home')
  },

  activateSelection() {
    const mode = this.data.mode
    this.reportEvent(`activate:${mode}`)
    if (mode === 'overview') {
      this.openDetail()
      return
    }
    if (mode === 'detail') {
      this.startDetailAsr()
      return
    }
    if (mode === 'locate') {
      this.openDetail()
      return
    }
    if (mode === 'chat') {
      this.startAsr()
      return
    }
    if (mode === 'error') {
      this.promptForCity('error')
      return
    }
    if (mode === 'home') {
      this.startAsr()
    }
  },

  confirmCurrent() {
    this.activateSelection()
  },

  clearPendingConfirm() {
    this.pendingConfirmToken += 1
    if (this.pendingConfirmTimer) {
      clearTimeout(this.pendingConfirmTimer)
      this.pendingConfirmTimer = null
    }
  },

  queueDelayedActivation(reason) {
    this.clearPendingConfirm()
    const token = this.pendingConfirmToken
    this.reportEvent(`${reason || 'confirm'}:pending`)
    this.pendingConfirmTimer = setTimeout(() => {
      if (!this.pageActive || token !== this.pendingConfirmToken) return
      this.pendingConfirmTimer = null
      this.activateSelection()
    }, 160)
  },

  queueOverviewConfirm(event) {
    if (event && event.stopPropagation) event.stopPropagation()
    if (event && event.preventDefault) event.preventDefault()
    if (this.data.mode !== 'overview') return
    this.queueDelayedActivation('overviewPress')
  },

  restoreOverviewState() {
    const rawObjects = this.data.rawSkyObjects && this.data.rawSkyObjects.length
      ? this.data.rawSkyObjects
      : (this.data.visibleObjects && this.data.visibleObjects.length ? this.data.visibleObjects : FALLBACK_TARGETS)
    const visibleObjects = this.data.visibleObjects && this.data.visibleObjects.length
      ? this.data.visibleObjects
      : rawObjects
    const requestedKey = this.data.selectedKey || (this.data.selectedObject && this.data.selectedObject.key)
    const selected = visibleObjects.find(item => item.key === requestedKey) ||
      rawObjects.find(item => item.key === requestedKey) ||
      visibleObjects[0] ||
      rawObjects[0] ||
      FALLBACK_TARGETS[0]
    const selectedIndex = Math.max(0, visibleObjects.findIndex(item => item.key === selected.key))
    this.setData(Object.assign({
      mode: 'overview',
      pageTag: '今晚推荐',
      rawSkyObjects: rawObjects,
      visibleObjects,
      selectedObject: selected,
      selectedKey: selected.key,
      selectedIndex,
      skyObjects: createSkyChartObjects(rawObjects, selected.key)
    }, createHudSlots(visibleObjects, selected.key), createSelectedSkyOverlay(selected, selectedIndex)))
  },

  moveSelection(offset) {
    const mode = this.data.mode
    if (mode !== 'overview' && mode !== 'detail' && mode !== 'locate') return
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
      skyObjects: createSkyChartObjects(
        this.data.rawSkyObjects && this.data.rawSkyObjects.length ? this.data.rawSkyObjects : targets,
        target.key
      ),
      skyKnowledgeBase: knowledge,
      detailChatHistory: []
    }, createHudSlots(targets, target.key), createSelectedSkyOverlay(target, nextIndex), createDetailState(target, this.data)))
  },

  selectObject(event) {
    if (event && event.stopPropagation) event.stopPropagation()
    const currentTarget = event && event.currentTarget
    const dataset = (currentTarget && currentTarget.dataset) || {}
    const attributes = (currentTarget && currentTarget.attributes) || {}
    const key = dataset.key || attributes['data-key'] || this.data.selectedKey
    const allObjects = (this.data.visibleObjects || []).concat(this.data.rawSkyObjects || [])
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
      skyObjects: createSkyChartObjects(
        this.data.rawSkyObjects && this.data.rawSkyObjects.length ? this.data.rawSkyObjects : this.data.visibleObjects,
        target.key
      ),
      skyKnowledgeBase: knowledge,
      detailChatHistory: []
    }, createHudSlots(this.data.visibleObjects, target.key), createSelectedSkyOverlay(target, index), createDetailState(target, this.data)))
    this.applyMode('detail')
  }
}
</script>

<page>
  <view class="shell card {{ mode }}" tabindex="0" focusable="true">
    <view class="top-row">
      <view>
        <text class="brand">SkyMate</text>
      </view>
      <view class="status-pill">
        <text class="status-pill-text">{{ pageTag }}</text>
      </view>
    </view>

    <view class="sky-panel" ink:if="{{ mode === 'overview' }}">
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
        <view
          class="sky-target {{ item.typeClass }} {{ item.selectedClass }}"
          style="{{ item.style }}"
          ink:for="{{ skyObjects }}"
          ink:for-item="item"
          ink:key="key"
        ></view>
        <text
          class="selected-sky-marker {{ selectedObject.typeClass }}"
          style="{{ selectedSkyMarkerStyle }}"
        ></text>
      </view>
    </view>

    <view class="content home-panel" ink:if="{{ mode === 'home' }}">
      <text class="kicker">语音观星</text>
      <text class="headline">说出城市或观测问题</text>
      <text class="body">例如：杭州 / 今晚苏州能看到什么 / 上海今晚能看金星吗。</text>
      <view class="button-grid home-actions">
        <button class="btn primary" bindtap="runSuzhouDemo" tabindex="0">示例城市</button>
      </view>
    </view>

    <view class="content chat-panel" ink:if="{{ mode === 'chat' }}">
      <text class="kicker">语音查询</text>
      <text class="headline">说出城市或问题</text>
      <text class="body">例如：杭州 / 今晚苏州能看到什么 / 上海今晚能看金星吗。</text>
      <view class="asr-guide">
        <text class="guide-dot"></text>
        <text class="guide-text">{{ assistantLine }}</text>
      </view>
      <text class="location-readout">{{ locationLine }}</text>
    </view>

    <view class="content loading-panel" ink:if="{{ mode === 'loading' }}">
      <text class="headline">正在查星空</text>
      <text class="body">{{ assistantLine }}</text>
      <text class="debug-line">{{ diagnosticLine }}</text>
    </view>

    <view class="content overview-panel" ink:if="{{ mode === 'overview' }}">
      <text class="headline">{{ verdict }}</text>
      <text class="body">{{ observationMetaLine }}</text>
      <view class="target-row">
        <button class="target-btn {{ target0Class }}" bindtap="queueOverviewConfirm" tabindex="0">
          <text class="target-name">{{ target0Name }}</text>
          <text class="target-meta">{{ target0Meta }}</text>
        </button>
        <button class="target-btn {{ target1Class }}" bindtap="queueOverviewConfirm" tabindex="1">
          <text class="target-name">{{ target1Name }}</text>
          <text class="target-meta">{{ target1Meta }}</text>
        </button>
        <button class="target-btn {{ target2Class }}" bindtap="queueOverviewConfirm" tabindex="2">
          <text class="target-name">{{ target2Name }}</text>
          <text class="target-meta">{{ target2Meta }}</text>
        </button>
        <button class="target-btn {{ target3Class }}" bindtap="queueOverviewConfirm" tabindex="3">
          <text class="target-name">{{ target3Name }}</text>
          <text class="target-meta">{{ target3Meta }}</text>
        </button>
        <button class="target-btn {{ target4Class }}" bindtap="queueOverviewConfirm" tabindex="4">
          <text class="target-name">{{ target4Name }}</text>
          <text class="target-meta">{{ target4Meta }}</text>
        </button>
      </view>
    </view>

    <view class="content detail-panel" ink:if="{{ mode === 'detail' }}">
      <view class="detail-layout">
        <view class="detail-left">
          <text class="kicker">{{ selectedObject.type }}</text>
      <text class="headline">{{ selectedObject.displayName }}</text>
          <text class="body detail-meta">{{ observationMetaLine }}</text>
          <view class="detail-block">
            <text class="detail-label">简介</text>
            <text class="detail-text detail-intro-text">{{ detailIntro }}</text>
          </view>
          <view class="detail-block intro-block">
            <text class="detail-label">快速找法</text>
            <text class="detail-text">{{ detailLocate }}</text>
          </view>
        </view>
        <view class="detail-agent">
          <text class="detail-agent-title">问 SkyMate</text>
          <text class="detail-agent-subtitle">已带入当前星体上下文</text>
          <text class="detail-agent-question">{{ detailQuestion }}</text>
          <text class="detail-agent-answer">{{ detailAnswer }}</text>
          <view class="button-grid compact detail-agent-actions">
            <button class="btn primary detail-talk-btn" bindtap="startDetailAsr" tabindex="0">开始对话</button>
          </view>
        </view>
      </view>
    </view>

    <view class="content locate-panel" ink:if="{{ mode === 'locate' }}">
      <text class="headline">朝 {{ selectedObject.direction }} 看</text>
      <text class="body">{{ selectedObject.locate }}</text>
      <view class="button-grid compact">
        <button class="btn secondary" bindtap="openDetail" tabindex="0">详情</button>
        <button class="btn ghost" bindtap="openOverview" tabindex="1">总览</button>
      </view>
    </view>

    <view class="content error-panel" ink:if="{{ mode === 'error' }}">
      <text class="headline">暂时查不到实时数据</text>
      <text class="body">可以先按一般情况看月亮、亮星和行星。</text>
      <view class="button-grid compact">
        <button class="btn primary" bindtap="runSuzhouDemo" tabindex="0">示例城市</button>
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
  --green: #40FF5E;
  --green-82: rgba(64, 255, 94, 0.82);
  --green-62: rgba(64, 255, 94, 0.62);
  --green-42: rgba(64, 255, 94, 0.42);
  --green-26: rgba(64, 255, 94, 0.26);
  --green-16: rgba(64, 255, 94, 0.16);
  --green-08: rgba(64, 255, 94, 0.08);
  --black-92: rgba(0, 0, 0, 0.92);
  --black-72: rgba(0, 0, 0, 0.72);
  --black-42: rgba(0, 0, 0, 0.42);
  position: relative;
  width: 480px;
  height: 320px;
  min-height: 320px;
  box-sizing: border-box;
  padding: 18px 20px 14px;
  overflow: hidden;
  color: var(--green);
  background: #000000;
  border: 2px solid var(--green-26);
  border-radius: 12px;
  font-family: sans-serif;
}

.top-row {
  position: relative;
  z-index: 20;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-start;
  width: 440px;
  height: 38px;
  overflow: hidden;
}

.brand {
  display: block;
  width: 180px;
  height: 24px;
  overflow: hidden;
  color: var(--green);
  font-size: 22px;
  line-height: 24px;
  font-weight: 900;
  white-space: nowrap;
}

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
  background: var(--black-42);
  border: 1px solid var(--green-62);
  border-radius: 12px;
}

.status-pill-text {
  display: block;
  width: 72px;
  height: 14px;
  overflow: hidden;
  color: var(--green);
  font-size: 10px;
  line-height: 14px;
  font-weight: 900;
  text-align: center;
  white-space: nowrap;
}

.content {
  position: absolute;
  left: 22px;
  top: 74px;
  z-index: 10;
  width: 436px;
  height: 218px;
  overflow: hidden;
}

.kicker {
  display: block;
  width: 420px;
  height: 16px;
  margin-bottom: 5px;
  overflow: hidden;
  color: var(--green);
  font-size: 12px;
  line-height: 16px;
  font-weight: 900;
  white-space: nowrap;
}

.headline {
  display: block;
  width: 420px;
  height: 58px;
  overflow: hidden;
  color: var(--green);
  font-size: 24px;
  line-height: 29px;
  font-weight: 900;
  white-space: normal;
  word-break: break-all;
}

.body {
  display: block;
  width: 414px;
  height: 42px;
  margin-top: 8px;
  overflow: hidden;
  color: var(--green-62);
  font-size: 13px;
  line-height: 19px;
  white-space: normal;
  word-break: break-all;
}

.button-grid,
.button-grid.compact {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 14px;
}

.btn {
  display: block;
  min-width: 70px;
  height: 34px;
  box-sizing: border-box;
  padding: 0 12px;
  overflow: hidden;
  color: var(--green);
  background: var(--black-42);
  border: 1px solid var(--green-42);
  border-radius: 10px;
  font-size: 12px;
  line-height: 32px;
  font-weight: 900;
  text-align: center;
  white-space: nowrap;
}

.btn.primary {
  color: #000000;
  background: var(--green);
  border-color: var(--green);
}

.btn.secondary {
  color: var(--green);
  background: var(--green-08);
}

.btn.ghost {
  color: var(--green-62);
  background: transparent;
}

.home-actions {
  margin-top: 16px;
}

.asr-guide {
  display: flex;
  flex-direction: row;
  align-items: center;
  width: 300px;
  height: 48px;
  box-sizing: border-box;
  margin-top: 10px;
  padding: 6px 10px;
  overflow: hidden;
  background: var(--black-42);
  border: 1px solid var(--green-42);
  border-radius: 10px;
}

.guide-dot {
  display: block;
  width: 8px;
  height: 8px;
  margin-right: 8px;
  flex-shrink: 0;
  background: var(--green);
  border-radius: 4px;
}

.guide-text {
  display: block;
  width: 254px;
  height: 30px;
  overflow: hidden;
  color: var(--green-62);
  font-size: 10px;
  line-height: 15px;
  white-space: normal;
  word-break: break-all;
}

.location-readout,
.debug-line {
  display: block;
  width: 404px;
  height: 16px;
  margin-top: 8px;
  overflow: hidden;
  color: var(--green-42);
  font-size: 9px;
  line-height: 16px;
  white-space: nowrap;
}

.overview-panel {
  left: 18px;
  top: 56px;
  width: 210px;
  height: 230px;
}

.overview-panel .headline {
  width: 210px;
  height: 21px;
  font-size: 18px;
  line-height: 21px;
  white-space: nowrap;
}

.overview-panel .body {
  width: 206px;
  height: 30px;
  margin-top: 5px;
  font-size: 10px;
  line-height: 15px;
}

.target-row {
  display: flex;
  flex-direction: column;
  gap: 3px;
  width: 204px;
  height: 132px;
  margin-top: 7px;
  overflow: hidden;
}

.target-btn {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: flex-start;
  flex-shrink: 0;
  width: 204px;
  height: 24px;
  min-height: 24px;
  box-sizing: border-box;
  padding: 0 8px;
  overflow: hidden;
  color: var(--green);
  background: var(--black-42);
  border: 2px solid var(--green-26);
  border-radius: 7px;
  text-align: left;
}

.target-btn.planet,
.target-btn.moon {
  border-color: var(--green-62);
}

.target-btn.selected {
  background: var(--green-16);
  border-color: var(--green);
}

.target-name {
  display: block;
  width: 184px;
  height: 11px;
  overflow: hidden;
  white-space: nowrap;
  color: var(--green);
  font-size: 9px;
  line-height: 11px;
  font-weight: 900;
}

.target-meta {
  display: block;
  width: 184px;
  height: 8px;
  overflow: hidden;
  color: var(--green-62);
  font-size: 7px;
  line-height: 8px;
  white-space: nowrap;
}

.sky-panel {
  position: absolute;
  right: 14px;
  top: 54px;
  z-index: 9;
  width: 224px;
  height: 230px;
  box-sizing: border-box;
  padding: 9px 10px;
  overflow: hidden;
  background: var(--black-42);
  border: 1px solid var(--green-26);
  border-radius: 12px;
}

.home .sky-panel,
.chat .sky-panel,
.loading .sky-panel,
.detail .sky-panel,
.locate .sky-panel,
.error .sky-panel {
  display: none;
}

.sky-panel-title {
  display: block;
  width: 202px;
  height: 14px;
  overflow: hidden;
  color: var(--green);
  font-size: 11px;
  line-height: 14px;
  font-weight: 900;
  white-space: nowrap;
}

.sky-panel-meta {
  display: block;
  width: 202px;
  height: 12px;
  margin-top: 2px;
  overflow: hidden;
  color: var(--green-62);
  font-size: 8px;
  line-height: 12px;
  white-space: nowrap;
}

.sky-map {
  position: absolute;
  left: 20px;
  top: 36px;
  width: 184px;
  height: 184px;
  overflow: hidden;
  background: var(--green-08);
  border-radius: 92px;
}

.sky-circle {
  position: absolute;
  box-sizing: border-box;
  border: 1px solid var(--green-26);
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
  position: absolute;
  background: var(--green-16);
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
  position: absolute;
  color: var(--green);
  font-size: 8px;
  line-height: 10px;
  font-weight: 900;
}

.cardinal-n { left: 88px; top: 3px; }
.cardinal-e { right: 4px; top: 87px; }
.cardinal-s { left: 88px; bottom: 3px; }
.cardinal-w { left: 4px; top: 87px; }

.sky-target {
  position: absolute;
  z-index: 8;
  display: block;
  min-width: 0;
  min-height: 0;
  box-sizing: border-box;
  padding: 0;
  background: var(--green-62);
  border: 1px solid var(--green-82);
  border-radius: 50%;
}

.sky-target.selected,
.selected-sky-marker {
  position: absolute;
  z-index: 12;
  display: block;
  min-width: 0;
  min-height: 0;
  box-sizing: border-box;
  padding: 0;
  background: var(--green-26);
  border: 2px solid var(--green);
  border-radius: 50%;
}

.detail-panel {
  left: 20px;
  top: 62px;
  width: 440px;
  height: 226px;
}

.detail-layout {
  position: relative;
  display: block;
  width: 440px;
  height: 226px;
  overflow: hidden;
}

.detail-left {
  position: absolute;
  left: 0;
  top: 0;
  width: 170px;
  height: 226px;
  overflow: hidden;
}

.detail-left .kicker {
  width: 166px;
  height: 14px;
  margin: 0 0 3px;
  font-size: 10px;
  line-height: 14px;
}

.detail-left .headline {
  width: 166px;
  height: 25px;
  font-size: 19px;
  line-height: 25px;
  white-space: nowrap;
}

.detail-left .detail-meta {
  width: 166px;
  height: 13px;
  margin-top: 2px;
  font-size: 9px;
  line-height: 13px;
  white-space: nowrap;
}

.detail-block {
  width: 166px;
  height: 65px;
  margin-top: 7px;
  overflow: hidden;
}

.detail-block.intro-block {
  height: 54px;
  margin-top: 8px;
}

.detail-label {
  display: block;
  width: 166px;
  height: 14px;
  overflow: hidden;
  color: var(--green);
  font-size: 10px;
  line-height: 14px;
  font-weight: 900;
  white-space: nowrap;
}

.detail-text {
  display: block;
  width: 166px;
  height: 39px;
  margin-top: 2px;
  overflow: hidden;
  color: var(--green-62);
  font-size: 10px;
  line-height: 13px;
  white-space: normal;
  word-break: break-all;
}

.detail-intro-text {
  height: 52px;
}

.detail-agent {
  position: absolute;
  left: 178px;
  top: 0;
  display: block;
  width: 262px;
  height: 218px;
  box-sizing: border-box;
  padding: 12px;
  overflow: hidden;
  background: var(--black-72);
  border: 2px solid var(--green-62);
  border-radius: 12px;
}

.detail-agent-title {
  display: block;
  width: 234px;
  height: 18px;
  overflow: hidden;
  color: var(--green);
  font-size: 14px;
  line-height: 18px;
  font-weight: 900;
  white-space: nowrap;
}

.detail-agent-subtitle {
  display: block;
  width: 234px;
  height: 14px;
  margin-top: 2px;
  overflow: hidden;
  color: var(--green-62);
  font-size: 9px;
  line-height: 14px;
  white-space: nowrap;
}

.detail-agent-question {
  display: block;
  width: 234px;
  height: 32px;
  box-sizing: border-box;
  margin-top: 7px;
  padding: 3px 6px;
  overflow: hidden;
  color: var(--green);
  background: var(--green-08);
  border: 1px solid var(--green-26);
  border-radius: 7px;
  font-size: 9px;
  line-height: 13px;
  white-space: normal;
  word-break: break-all;
}

.detail-agent-answer {
  display: block;
  width: 234px;
  height: 60px;
  margin-top: 8px;
  overflow: hidden;
  color: var(--green-62);
  font-size: 11px;
  line-height: 15px;
  white-space: normal;
  word-break: break-all;
}

.detail-agent-actions {
  width: 234px;
  height: 32px;
  margin-top: 8px;
  overflow: hidden;
}

.detail-talk-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 124px;
  min-width: 124px;
  height: 30px;
  padding: 0 8px;
  font-size: 11px;
  line-height: 12px;
  text-align: center;
}

.locate-panel .headline,
.error-panel .headline {
  height: 58px;
}

.bottom-row {
  position: absolute;
  left: 20px;
  bottom: 12px;
  z-index: 20;
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
  width: 440px;
  height: 20px;
  box-sizing: border-box;
  overflow: hidden;
  border-top: 1px solid var(--green-16);
}

.hint {
  display: block;
  width: 302px;
  height: 13px;
  overflow: hidden;
  color: var(--green-42);
  font-size: 10px;
  line-height: 13px;
  white-space: nowrap;
}

.hint.right {
  width: 90px;
  color: var(--green-62);
  text-align: right;
}
</style>
