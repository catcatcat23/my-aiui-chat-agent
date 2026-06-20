<script def>
{
  "navigationBarTitleText": "SkyMate",
  "description": "智能眼镜观星助手。支持 Craft 按钮事件、ASR 入口、外部星图接口请求和单页状态切换。",
  "schema": {
    "data": {
      "type": "object",
      "properties": {
        "mode": {
          "type": "string",
          "description": "home/chat/loading/overview/detail/locate/error"
        },
        "locationName": {
          "type": "string",
          "description": "观测位置"
        },
        "targets": {
          "type": "string",
          "description": "推荐目标 JSON 字符串"
        },
        "selectedObject": {
          "type": "string",
          "description": "当前选中的星体"
        }
      }
    }
  }
}
</script>

<script setup>
const SKY_CHART_ENDPOINT = 'https://sky.eunoia.top/sky/chart'
const BUILD_VERSION = 'v2.6-no-time-utc'

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
    key: 'jupiter',
    name: '木星',
    type: '行星',
    typeClass: 'planet',
    direction: '东南',
    altitude: '35°',
    magnitude: '很亮',
    bestTime: '今晚',
    intro: '城市里也比较容易认出来，像一个稳定不闪的亮点。',
    locate: '先找东南方向开阔处，再看地平线上方一段距离。'
  },
  {
    key: 'vega',
    name: '织女星',
    type: '亮星',
    typeClass: 'star',
    direction: '东北',
    altitude: '55°',
    magnitude: '很亮',
    bestTime: '入夜后',
    intro: '夏季夜空非常显眼，适合新手先定位。',
    locate: '朝东北较高的天空看，找一颗清亮的白色亮星。'
  },
  {
    key: 'arcturus',
    name: '大角星',
    type: '亮星',
    typeClass: 'star',
    direction: '西南',
    altitude: '65°',
    magnitude: '很亮',
    bestTime: '今晚',
    intro: '亮度高，城市里也更有机会看到。',
    locate: '朝西南偏高处找一颗略带暖色的亮星。'
  }
]

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

function angleText(value) {
  if (!hasValue(value)) return ''
  if (typeof value === 'number') return `${Math.round(value * 10) / 10}°`
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
    if (Array.isArray(source[name])) {
      source[name].forEach(item => bucket.push(item))
    }
  })

  if (source.moon && typeof source.moon === 'object') {
    bucket.push(Object.assign({ type: 'moon' }, source.moon))
  }

  if (source.data && source.data !== source) collectTargets(source.data, bucket)
  if (source.result && source.result !== source) collectTargets(source.result, bucket)
  if (source.sky_chart && source.sky_chart !== source) collectTargets(source.sky_chart, bucket)
  if (source.skyChart && source.skyChart !== source) collectTargets(source.skyChart, bucket)
  if (source.chart && source.chart !== source) collectTargets(source.chart, bucket)
}

function normalizeTarget(raw, index) {
  const object = raw || {}
  const name = text(readAny(object, ['name', 'display_name', 'name_zh', 'name_en', '名称', 'title', 'objectName', 'designation', 'id']), `目标 ${index + 1}`)
  const typeInfo = targetType(readAny(object, ['type', '类型', 'category', 'kind', 'objectType', 'object_type']))
  const azimuth = readAny(object, ['azimuth', '方位角', 'azimuth_deg', 'azimuthDeg', 'az'])
  const altitude = readAny(object, ['altitude', '高度角', 'altitude_deg', 'altitudeDeg', 'alt', 'elevation'])
  const direction = text(readAny(object, ['direction', '方向', 'azimuthText', 'cardinalDirection']) || directionFromAzimuth(azimuth), '开阔天空')
  const magnitude = text(readAny(object, ['magnitude', '星等', 'mag', 'brightness', 'apparentMagnitude']), '可见')
  const key = keyOf(readAny(object, ['key', 'id']) || name) || `target-${index + 1}`

  return {
    key,
    name,
    type: typeInfo.label,
    typeClass: typeInfo.className,
    rank: typeInfo.rank,
    direction,
    altitude: angleText(altitude) || '中等高度',
    magnitude,
    bestTime: text(readAny(object, ['bestTime', '最佳时间', 'visibleTime', 'timeWindow', 'time']), '今晚'),
    intro: text(readAny(object, ['intro', 'description', '描述', 'summary', 'reason']), `${name} 可以作为今晚的观测目标。`),
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
    .sort((left, right) => {
      if (left.rank !== right.rank) return left.rank - right.rank
      const leftMag = parseFloat(left.magnitude)
      const rightMag = parseFloat(right.magnitude)
      if (!isNaN(leftMag) && !isNaN(rightMag)) return leftMag - rightMag
      return 0
    })

  return (targets.length ? targets : FALLBACK_TARGETS).slice(0, 4)
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
  const keys = Object.keys(payload || {})
  return keys
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
    } catch (error) {
      // Some runtimes only allow the response body to be consumed once.
    }
  }

  if (typeof response.text !== 'function') return statusText

  try {
    const body = await response.text()
    if (!body) return statusText
    return `${statusText}: ${String(body).slice(0, 180)}`
  } catch (error) {
    return statusText
  }
}

export default {
  data: {
    mode: 'home',
    pageTitle: 'SkyMate 观星助手',
    pageTag: '首页',
    locationName: '等待位置',
    verdict: '我会先判断值不值得出门。',
    condition: '可以用 Craft 测试按钮，或在真机上用语音提问。',
    assistantLine: '你可以问：今晚苏州能看到什么星星？',
    tip: '第一版不依赖平台插件，直接请求 sky.eunoia.top。',
    eventStatus: 'event: waiting',
    asrStatus: 'asr: idle',
    requestStatus: 'request: idle',
    debugText: 'ready',
    buildVersion: BUILD_VERSION,
    selectedKey: 'jupiter',
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
      this.setData({
        assistantLine: '收到经纬度，正在查当前位置星空。',
        debugText: 'page-query lat/lon'
      })
      this.loadSkyChart(queryPlace)
      return
    }

    if (placeText || query.mode === 'loading') {
      this.setData({
        assistantLine: `收到问题：${userText}`,
        debugText: userText ? 'page-query userText' : 'page-query location/loading'
      })
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

  onVoiceWakeup(event) {
    console.log('[SkyMate] voice wakeup', event || {})
    this.reportEvent('voiceWakeup')
    this.startAsr()
  },

  reportEvent(name) {
    console.log('[SkyMate] page event', name)
    this.setData({
      eventStatus: `event: ${name}`,
      debugText: `last event: ${name}`
    })
  },

  applyMode(mode) {
    const modeKey = ['home', 'chat', 'loading', 'overview', 'detail', 'locate', 'error'].indexOf(mode) >= 0 ? mode : 'home'
    const titleMap = {
      home: 'SkyMate 观星助手',
      chat: '语音输入',
      loading: '正在查星空',
      overview: '今晚推荐',
      detail: '星体详情',
      locate: '怎么找',
      error: '暂时查不到'
    }
    const tagMap = {
      home: '首页',
      chat: '聆听',
      loading: '查询中',
      overview: '总览',
      detail: '详情',
      locate: '定位',
      error: '兜底'
    }

    this.setData({
      mode: modeKey,
      pageTitle: titleMap[modeKey],
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
      asrStatus: 'asr: listening',
      assistantLine: '我在听，你可以说：今晚苏州能看到什么？'
    })

    const Recognition = getSpeechRecognitionCandidate()

    if (!Recognition) {
      if (this.startWxAsr()) return
      console.log('[SkyMate] SpeechRecognition not available, fallback to Suzhou demo')
      this.setData({
        asrStatus: 'asr: unavailable',
        assistantLine: 'Craft 里可能没有 ASR，我先用苏州测试链路跑一遍。'
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
        asrStatus: 'asr: success',
        assistantLine: transcript ? `我听到：${transcript}` : '我听到了，正在判断。'
      })
      this.handleUserText(transcript || '今晚苏州能看到什么')
    }

    recognition.onerror = (event) => {
      console.log('[SkyMate] ASR error', event || {})
      this.setData({
        asrStatus: 'asr: error',
        assistantLine: '这次语音没有成功，我先用苏州测试链路帮你验证。'
      })
      this.runSuzhouDemo()
    }

    recognition.onend = () => {
      console.log('[SkyMate] ASR end')
    }

    recognition.start()
  },

  startWxAsr() {
    const runtime = typeof wx !== 'undefined' ? wx : null
    if (!runtime || typeof runtime.getSpeechRecognizer !== 'function') {
      return false
    }

    try {
      const recognizer = runtime.getSpeechRecognizer()
      if (!recognizer) return false

      console.log('[SkyMate] wx speech recognizer available')
      this.setData({
        asrStatus: 'asr: wx-listening',
        assistantLine: '我正在调用 Rokid 语音识别。'
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
          asrStatus: 'asr: wx-success',
          assistantLine: transcript ? `我听到：${transcript}` : '我听到了，正在判断。'
        })
        this.handleUserText(transcript || '今晚苏州能看到什么')
      }

      const onError = (error) => {
        console.log('[SkyMate] wx ASR error', error || {})
        this.setData({
          asrStatus: 'asr: wx-error',
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

      return false
    } catch (error) {
      console.log('[SkyMate] wx ASR setup failed', error || {})
      return false
    }
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
      requestStatus: 'location: resolving',
      debugText: 'try wx/navigator location',
      assistantLine: '我先尝试读取设备当前位置。'
    })

    try {
      const place = await this.readRuntimeLocation()
      this.loadSkyChart(place)
    } catch (error) {
      console.log('[SkyMate] location unavailable', error || {})
      this.setData({
        requestStatus: 'location: fallback',
        debugText: errorText(error)
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
          {
            enableHighAccuracy: false,
            timeout: 5000,
            maximumAge: 300000
          }
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
      requestStatus: 'request: loading',
      assistantLine: `正在查${place.name}今晚的星空。`,
      debugText: `fetch ${SKY_CHART_ENDPOINT}`
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
      requestStatus: 'request: fetch start',
      debugText: `POST lat=${payload.lat} lon=${payload.lon} limit=${payload.total_limit}`
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

      console.log('[SkyMate] sky fetch ok', response.status)
      this.setData({
        requestStatus: `request: http ${response.status}`,
        debugText: 'fetch ok with User-Agent'
      })
      return response
    } catch (firstError) {
      console.log('[SkyMate] sky fetch primary failed', errorText(firstError))
      this.setData({
        requestStatus: 'request: retry no-UA',
        debugText: errorText(firstError)
      })
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
      this.setData({
        requestStatus: 'request: retry GET',
        debugText: retryError
      })

      const getUrl = `${SKY_CHART_ENDPOINT}?${queryStringFromPayload(retryPayload)}`
      const getResponse = await fetch(getUrl, {
        method: 'GET',
        headers: {
          'X-User-Agent': 'Rizon/1.0'
        }
      })

      if (!getResponse.ok) throw new Error(await responseErrorText(getResponse, 'GET HTTP'))

      console.log('[SkyMate] sky fetch GET ok', getResponse.status)
      this.setData({
        requestStatus: `request: GET http ${getResponse.status}`,
        debugText: 'fetch ok with GET query'
      })
      return getResponse
    }

    console.log('[SkyMate] sky fetch retry ok', retryResponse.status)
    this.setData({
      requestStatus: `request: retry http ${retryResponse.status}`,
      debugText: 'fetch ok with minimal payload'
    })
    return retryResponse
  },

  showChartResult(options) {
    const chart = options && options.chart
    const providedTargets = options && options.targets
    const locationName = text(options && options.locationName, '当前位置')
    const targets = providedTargets ? providedTargets.map((item, index) => normalizeTarget(item, index)) : pickTargets(chart)
    const first = targets[0] || FALLBACK_TARGETS[0]
    const source = text(options && options.source, 'sky-chart')
    const verdict = targets.length
      ? `今晚${locationName}可以优先看${targets.slice(0, 2).map(item => item.name).join('和')}。`
      : `今晚${locationName}可以先看亮星和亮行星。`

    this.setData({
      visibleObjects: targets,
      selectedKey: first.key,
      selectedObject: first,
      locationName,
      verdict,
      condition: '城市里优先看亮行星和亮星，深空目标需要望远镜或更暗的环境。',
      assistantLine: '我已经把最适合普通用户看的目标放到卡片里了。',
      requestStatus: `request: success (${source})`,
      debugText: `targets: ${targets.length}`
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
      verdict: `我这边暂时查不到${locationName}的实时星图。`,
      condition: '可以先按一般情况看月亮、亮行星和亮星；深空目标不要在城市里强求。',
      assistantLine: '外部接口失败时会走兜底展示，方便你继续调试页面。',
      requestStatus: `request: fallback ${reason ? `(${reason})` : ''}`,
      debugText: reason || 'fetch failed'
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
      <text class="pill">{{ pageTag }}</text>
    </view>

    <view class="debug-strip">
      <text class="debug-strip-line">{{ buildVersion }}</text>
      <text class="debug-strip-line">{{ requestStatus }}</text>
      <text class="debug-strip-line">{{ debugText }}</text>
    </view>

    <view class="panel home" style="display: {{ homeDisplay }};">
      <view class="sky-preview">
        <text class="star s1">✦</text>
        <text class="star s2">✧</text>
        <text class="star s3">✦</text>
        <text class="planet-dot"></text>
      </view>
      <view class="hero-copy">
        <text class="kicker">智能眼镜观星助手</text>
        <text class="headline">先判断值不值得出门。</text>
        <text class="body">这版不依赖平台插件。按钮、ASR、外部星图请求和页面切换都在同一个 Ink 页面里完成。</text>
      </view>

      <view class="button-grid">
        <button class="btn primary" bindtap="runCurrentLocation">当前位置</button>
        <button class="btn primary" bindtap="runSuzhouDemo">测试苏州星空</button>
        <button class="btn secondary" bindtap="runShanghaiDemo">测试上海星空</button>
        <button class="btn secondary" bindtap="startAsr">ASR 语音输入</button>
        <button class="btn ghost" bindtap="startChat">进入对话页</button>
      </view>
    </view>

    <view class="panel chat" style="display: {{ chatDisplay }};">
      <text class="headline small">我在听。</text>
      <text class="body">真机上可以直接说“今晚苏州能看到什么”。Craft 如果没有 ASR，会自动跑苏州测试链路。</text>
      <view class="button-grid">
        <button class="btn primary" bindtap="startAsr">开始 ASR</button>
        <button class="btn secondary" bindtap="runCurrentLocation">读取定位</button>
        <button class="btn secondary" bindtap="runSuzhouDemo">不用语音，直接测试</button>
        <button class="btn ghost" bindtap="openHome">返回首页</button>
      </view>
    </view>

    <view class="panel loading" style="display: {{ loadingDisplay }};">
      <view class="loader"></view>
      <text class="headline small">正在查询星空</text>
      <text class="body">我正在请求 sky.eunoia.top，并把结果整理成 2 到 4 个适合普通用户看的目标。</text>
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
          <text class="target-meta">{{ item.type }} · {{ item.direction }} · {{ item.altitude }}</text>
          <text class="target-tip">点我看详情</text>
        </button>
      </view>

      <view class="button-grid">
        <button class="btn secondary" bindtap="runSuzhouDemo">刷新苏州</button>
        <button class="btn ghost" bindtap="openHome">返回首页</button>
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
      <view class="button-grid">
        <button class="btn primary" bindtap="openLocate">怎么找</button>
        <button class="btn secondary" bindtap="openOverview">返回总览</button>
        <button class="btn ghost" bindtap="openHome">返回首页</button>
      </view>
    </view>

    <view class="panel locate" style="display: {{ locateDisplay }};">
      <text class="kicker">寻找 {{ selectedObject.name }}</text>
      <text class="headline small">朝 {{ selectedObject.direction }} 看。</text>
      <text class="body">{{ selectedObject.locate }}</text>
      <view class="compass">
        <text class="compass-label">{{ selectedObject.direction }}</text>
      </view>
      <view class="button-grid">
        <button class="btn secondary" bindtap="openDetail">返回详情</button>
        <button class="btn ghost" bindtap="openOverview">返回总览</button>
      </view>
    </view>

    <view class="panel error" style="display: {{ errorDisplay }};">
      <text class="headline small">暂时查不到实时数据。</text>
      <text class="body">可以先按一般情况看月亮、亮行星和亮星。Craft 里可以继续用测试按钮验证页面事件。</text>
      <button class="btn primary" bindtap="runSuzhouDemo">重新测试</button>
    </view>

    <view class="status">
      <text class="status-line">{{ assistantLine }}</text>
      <text class="status-chip">{{ eventStatus }}</text>
      <text class="status-chip">{{ asrStatus }}</text>
      <text class="status-chip">{{ requestStatus }}</text>
      <text class="debug">{{ debugText }}</text>
    </view>
  </view>
</page>

<style>
.shell {
  width: 448px;
  min-height: 150px;
  box-sizing: border-box;
  padding: 8px 10px;
  color: #f4f7f1;
  background:
    radial-gradient(circle at 18% 18%, rgba(126, 255, 162, 0.18), transparent 26%),
    radial-gradient(circle at 88% 10%, rgba(255, 209, 102, 0.12), transparent 24%),
    linear-gradient(145deg, #050706 0%, #0d1511 48%, #1c1a10 100%);
  border: 1px solid rgba(180, 244, 188, 0.22);
  border-radius: 16px;
  overflow: hidden;
}

.topbar {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 4px;
}

.debug-strip {
  display: flex;
  flex-direction: row;
  gap: 6px;
  min-height: 18px;
  margin-bottom: 6px;
  padding: 3px 6px;
  border-radius: 7px;
  background: rgba(109, 255, 136, 0.10);
  border: 1px solid rgba(109, 255, 136, 0.24);
}

.debug-strip-line {
  display: block;
  max-width: 208px;
  overflow: hidden;
  color: #8effa6;
  font-size: 9px;
  line-height: 12px;
}

.brand {
  display: block;
  font-size: 22px;
  line-height: 24px;
  font-weight: 900;
  letter-spacing: -1px;
}

.subtitle {
  display: block;
  color: rgba(244, 247, 241, 0.58);
  font-size: 11px;
  line-height: 14px;
}

.pill {
  min-width: 42px;
  height: 24px;
  line-height: 24px;
  text-align: center;
  border-radius: 12px;
  color: #c9ffd2;
  background: rgba(64, 255, 94, 0.08);
  border: 1px solid rgba(64, 255, 94, 0.32);
  font-size: 11px;
  font-weight: 700;
}

.panel {
  display: block;
}

.home {
  display: flex;
  flex-direction: row;
  gap: 12px;
}

.sky-preview {
  position: relative;
  width: 150px;
  height: 118px;
  flex-shrink: 0;
  border-radius: 12px;
  border: 1px solid rgba(244, 247, 241, 0.12);
  background: radial-gradient(circle at 50% 68%, rgba(255, 214, 115, 0.24), transparent 10%), #030504;
}

.star {
  position: absolute;
  color: #dfffe4;
  font-size: 14px;
}

.s1 {
  left: 28px;
  top: 32px;
}

.s2 {
  right: 30px;
  top: 26px;
}

.s3 {
  left: 70px;
  top: 70px;
}

.planet-dot {
  position: absolute;
  left: 71px;
  top: 58px;
  width: 14px;
  height: 14px;
  border-radius: 7px;
  background: #ffd66f;
  box-shadow: 0 0 18px rgba(255, 214, 111, 0.75);
}

.hero-copy {
  flex: 1;
}

.kicker {
  display: block;
  color: #aaf7b8;
  font-size: 11px;
  line-height: 15px;
  font-weight: 700;
}

.headline {
  display: block;
  margin-top: 4px;
  color: #ffffff;
  font-size: 22px;
  line-height: 26px;
  font-weight: 900;
}

.headline.small {
  font-size: 15px;
  line-height: 18px;
}

.body {
  display: block;
  margin-top: 3px;
  color: rgba(244, 247, 241, 0.72);
  font-size: 10px;
  line-height: 13px;
}

.button-grid {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 6px;
}

.btn {
  min-width: 78px;
  height: 26px;
  line-height: 26px;
  padding: 0 8px;
  border-radius: 8px;
  font-size: 10px;
  font-weight: 800;
  border: 1px solid rgba(244, 247, 241, 0.16);
}

.primary {
  color: #031006;
  background: #6dff88;
}

.secondary {
  color: #dfffe5;
  background: rgba(109, 255, 136, 0.10);
  border-color: rgba(109, 255, 136, 0.42);
}

.ghost {
  color: rgba(244, 247, 241, 0.78);
  background: rgba(255, 255, 255, 0.06);
}

.loader {
  width: 34px;
  height: 34px;
  margin: 12px auto;
  border-radius: 17px;
  border: 2px solid rgba(109, 255, 136, 0.25);
  background: radial-gradient(circle, rgba(109, 255, 136, 0.8), transparent 34%);
}

.verdict {
  padding: 6px 8px;
  border-radius: 9px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(244, 247, 241, 0.10);
}

.target-list {
  display: flex;
  flex-direction: row;
  gap: 6px;
  margin-top: 6px;
}

.target-card {
  width: 88px;
  min-height: 58px;
  padding: 6px;
  border-radius: 9px;
  text-align: left;
  background: rgba(255, 255, 255, 0.07);
  border: 1px solid rgba(244, 247, 241, 0.13);
}

.target-card.planet {
  border-color: rgba(255, 214, 111, 0.55);
}

.target-card.star {
  border-color: rgba(160, 225, 255, 0.48);
}

.target-card.moon {
  border-color: rgba(244, 247, 241, 0.62);
}

.target-name {
  display: block;
  color: #ffffff;
  font-size: 14px;
  line-height: 17px;
  font-weight: 900;
}

.target-meta,
.target-tip {
  display: block;
  margin-top: 4px;
  color: rgba(244, 247, 241, 0.65);
  font-size: 10px;
  line-height: 14px;
}

.target-tip {
  color: #aaf7b8;
}

.metric-row {
  display: flex;
  flex-direction: row;
  gap: 8px;
  margin: 10px 0;
}

.metric {
  flex: 1;
  padding: 8px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.06);
}

.metric-label,
.metric-value {
  display: block;
  font-size: 10px;
  line-height: 13px;
}

.metric-label {
  color: rgba(244, 247, 241, 0.52);
}

.metric-value {
  margin-top: 3px;
  color: #ffffff;
  font-weight: 800;
}

.compass {
  position: relative;
  height: 58px;
  margin-top: 10px;
  border-radius: 14px;
  background: radial-gradient(circle, rgba(109, 255, 136, 0.16), transparent 58%);
  border: 1px solid rgba(109, 255, 136, 0.20);
}

.compass-label {
  display: block;
  text-align: center;
  line-height: 58px;
  color: #dfffe5;
  font-size: 18px;
  font-weight: 900;
}

.status {
  margin-top: 10px;
  padding-top: 8px;
  border-top: 1px solid rgba(244, 247, 241, 0.10);
}

.status-line,
.status-chip,
.debug {
  display: block;
  color: rgba(244, 247, 241, 0.72);
  font-size: 10px;
  line-height: 14px;
}

.status-chip {
  color: #aaf7b8;
}

.debug {
  color: rgba(160, 225, 255, 0.72);
}
</style>
