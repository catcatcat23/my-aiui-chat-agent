<script def>
{
  "navigationBarTitleText": "SkyMate",
  "description": "SkyMate smart-glasses astronomy assistant. Supports page events, ASR, location, external sky chart fetch, and single-page state switching.",
  "schema": {
    "data": {
      "type": "object",
      "properties": {
        "mode": { "type": "string", "description": "home/chat/loading/overview/detail/locate/error" },
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
const BUILD_VERSION = 'v3.0-usable'
const SKY_CHART_ENDPOINT = 'https://sky.eunoia.top/sky/chart'

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

  return (targets.length ? targets : FALLBACK_TARGETS).slice(0, 3)
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
  data: {
    mode: 'home',
    buildVersion: BUILD_VERSION,
    pageTag: '待唤醒',
    locationName: '等待位置',
    verdict: '我会先判断值不值得出门。',
    condition: '可以说：今晚能看到什么？',
    assistantLine: '可用语音、当前位置或城市测试开始。',
    diagnosticLine: 'ready',
    requestStatus: 'idle',
    asrStatus: 'idle',
    eventStatus: 'waiting',
    selectedKey: FALLBACK_TARGETS[0].key,
    selectedObject: FALLBACK_TARGETS[0],
    visibleObjects: FALLBACK_TARGETS,
    homeDisplay: 'block',
    chatDisplay: 'none',
    loadingDisplay: 'none',
    overviewDisplay: 'none',
    detailDisplay: 'none',
    locateDisplay: 'none',
    errorDisplay: 'none'
  },

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
    const code = event && event.code
    console.log('[SkyMate] key up', code)
    this.reportEvent(`key:${code || 'unknown'}`)

    if (code === 'Backspace' || code === 'Escape' || code === 'Back') {
      if (event && event.preventDefault) event.preventDefault()
      if (event && event.stopPropagation) event.stopPropagation()
      this.openHome()
      return
    }

    if (code === 'Enter' || code === 'GlobalHook') {
      if (event && event.preventDefault) event.preventDefault()
      this.runSuzhouDemo()
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
      assistantLine: '我在听，你可以说：今晚苏州能看到什么？'
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
    this.loadSkyChart(CITY_COORDS[2])
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
    const targets = providedTargets ? providedTargets.map((item, index) => normalizeTarget(item, index)).slice(0, 3) : pickTargets(chart)
    const first = targets[0] || FALLBACK_TARGETS[0]
    const source = text(options && options.source, 'sky-chart')
    const targetNames = targets.slice(0, 2).map(item => item.name).join('、')
    const verdict = targets.length
      ? `${locationName}今晚优先看 ${targetNames}`
      : `${locationName}今晚先看亮星和亮行星`

    this.setData({
      visibleObjects: targets,
      selectedKey: first.key,
      selectedObject: first,
      locationName,
      verdict,
      condition: '城市里优先看亮星、行星和月亮；深空目标更适合望远镜或暗处。',
      assistantLine: '已筛出最适合普通用户看的目标。',
      requestStatus: `success ${source}`,
      diagnosticLine: `targets=${targets.length}`
    })
    this.applyMode('overview')
  },

  showFallback(locationName, reason) {
    console.log('[SkyMate] fallback reason', reason || '')
    this.setData({
      visibleObjects: FALLBACK_TARGETS,
      selectedKey: FALLBACK_TARGETS[0].key,
      selectedObject: FALLBACK_TARGETS[0],
      locationName,
      verdict: `暂时查不到 ${locationName} 的实时星图`,
      condition: '可以先按一般情况看月亮、亮星和行星；深空目标不要在城市里强求。',
      assistantLine: '实时接口不可用时，已切到安全兜底建议。',
      requestStatus: 'fallback',
      diagnosticLine: shortText(reason || 'fetch failed', 62)
    })
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

  selectObject(event) {
    const dataset = (event && event.currentTarget && event.currentTarget.dataset) || {}
    const key = dataset.key || this.data.selectedKey
    const target = this.data.visibleObjects.find(item => item.key === key) || this.data.visibleObjects[0] || FALLBACK_TARGETS[0]
    this.reportEvent(`selectObject:${key}`)
    this.setData({
      selectedKey: target.key,
      selectedObject: target
    })
    this.applyMode('detail')
  }
}
</script>

<page>
  <view class="shell" tabindex="0" focusable="true" bindkeyup="onKeyUp">
    <view class="topbar">
      <view>
        <text class="brand">SkyMate</text>
        <text class="subtitle">{{ locationName }}</text>
      </view>
      <view class="right-stack">
        <text class="pill">{{ pageTag }}</text>
        <text class="diag">{{ buildVersion }} · {{ requestStatus }}</text>
      </view>
    </view>

    <view class="panel home" style="display: {{ homeDisplay }};">
      <view class="hero">
        <view class="mini-sky">
          <text class="dot d1"></text>
          <text class="dot d2"></text>
          <text class="dot d3"></text>
          <text class="glow"></text>
        </view>
        <view class="hero-copy">
          <text class="headline">先判断值不值得出门</text>
          <text class="body">读当前位置或城市，挑 2 到 3 个今晚最容易看的目标。</text>
        </view>
      </view>

      <view class="button-grid">
        <button class="btn primary" bindtap="runCurrentLocation">当前位置</button>
        <button class="btn secondary" bindtap="runSuzhouDemo">苏州</button>
        <button class="btn secondary" bindtap="runShanghaiDemo">上海</button>
        <button class="btn secondary" bindtap="startChat">对话</button>
        <button class="btn ghost" bindtap="startAsr">语音</button>
      </view>
    </view>

    <view class="panel chat" style="display: {{ chatDisplay }};">
      <text class="headline small">我在听</text>
      <text class="body">你可以说：今晚能看到什么，或直接说城市名。</text>
      <view class="button-grid">
        <button class="btn primary" bindtap="startAsr">开始 ASR</button>
        <button class="btn secondary" bindtap="runCurrentLocation">读取定位</button>
        <button class="btn secondary" bindtap="runSuzhouDemo">苏州测试</button>
        <button class="btn ghost" bindtap="openHome">返回</button>
      </view>
    </view>

    <view class="panel loading" style="display: {{ loadingDisplay }};">
      <view class="loading-row">
        <view class="loader"></view>
        <view>
          <text class="headline small">正在查星空</text>
          <text class="body">{{ assistantLine }}</text>
        </view>
      </view>
      <text class="debug-line">{{ diagnosticLine }}</text>
    </view>

    <view class="panel overview" style="display: {{ overviewDisplay }};">
      <view class="verdict">
        <text class="headline small">{{ verdict }}</text>
        <text class="body">{{ condition }}</text>
      </view>

      <view class="target-list">
        <button
          class="target-card {{ item.typeClass }}"
          ink:for="{{ visibleObjects }}"
          ink:for-item="item"
          ink:key="key"
          data-key="{{ item.key }}"
          bindtap="selectObject"
        >
          <text class="target-name">{{ item.name }}</text>
          <text class="target-meta">{{ item.direction }} · {{ item.altitude }}</text>
        </button>
      </view>

      <view class="button-grid slim">
        <button class="btn secondary" bindtap="runCurrentLocation">刷新当前位置</button>
        <button class="btn secondary" bindtap="runSuzhouDemo">苏州</button>
        <button class="btn ghost" bindtap="openHome">首页</button>
      </view>
    </view>

    <view class="panel detail" style="display: {{ detailDisplay }};">
      <text class="kicker">{{ selectedObject.type }}</text>
      <text class="headline small">{{ selectedObject.name }}</text>
      <view class="metric-row">
        <view class="metric">
          <text class="metric-label">方向</text>
          <text class="metric-value">{{ selectedObject.direction }}</text>
        </view>
        <view class="metric">
          <text class="metric-label">高度</text>
          <text class="metric-value">{{ selectedObject.altitude }}</text>
        </view>
        <view class="metric">
          <text class="metric-label">亮度</text>
          <text class="metric-value">{{ selectedObject.magnitude }}</text>
        </view>
      </view>
      <text class="body">{{ selectedObject.intro }}</text>
      <view class="button-grid slim">
        <button class="btn primary" bindtap="openLocate">怎么找</button>
        <button class="btn secondary" bindtap="openOverview">总览</button>
        <button class="btn ghost" bindtap="openHome">首页</button>
      </view>
    </view>

    <view class="panel locate" style="display: {{ locateDisplay }};">
      <text class="kicker">寻找 {{ selectedObject.name }}</text>
      <text class="headline small">朝 {{ selectedObject.direction }} 看</text>
      <text class="body">{{ selectedObject.locate }}</text>
      <view class="button-grid slim">
        <button class="btn secondary" bindtap="openDetail">详情</button>
        <button class="btn ghost" bindtap="openOverview">总览</button>
      </view>
    </view>

    <view class="panel error" style="display: {{ errorDisplay }};">
      <text class="headline small">暂时查不到实时数据</text>
      <text class="body">可以先看月亮、亮星和行星。请换个位置或稍后重试。</text>
      <view class="button-grid slim">
        <button class="btn primary" bindtap="runCurrentLocation">重新定位</button>
        <button class="btn secondary" bindtap="runSuzhouDemo">苏州兜底</button>
      </view>
    </view>

    <view class="status">
      <text class="status-line">{{ assistantLine }}</text>
      <text class="debug-line">{{ eventStatus }} · {{ asrStatus }} · {{ diagnosticLine }}</text>
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
</style>
