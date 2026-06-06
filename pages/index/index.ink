<script def>
{
  "navigationBarTitleText": "SkyMate",
  "description": "SkyMate 观星卡片：按 mode 展示首页、总览、详情或寻找步骤。",
  "schema": {
    "data": {
      "type": "object",
      "properties": {
        "mode": {
          "type": "string",
          "description": "home/chat/overview/detail/locate"
        },
        "object": {
          "type": "string",
          "description": "星体 key 或名称"
        },
        "selectedObject": {
          "type": "string",
          "description": "详情星体 key 或名称"
        },
        "verdict": {
          "type": "string",
          "description": "观星结论"
        },
        "condition": {
          "type": "string",
          "description": "天气或可见性摘要"
        },
        "locationName": {
          "type": "string",
          "description": "位置名称"
        },
        "dataTime": {
          "type": "string",
          "description": "数据时间"
        },
        "skyChart": {
          "type": "string",
          "description": "sky_chart JSON 字符串"
        },
        "chart": {
          "type": "string",
          "description": "skyChart 别名"
        },
        "rawResult": {
          "type": "string",
          "description": "skyChart 别名"
        },
        "serviceUrl": {
          "type": "string",
          "description": "数据来源地址"
        },
        "detailAnswer": {
          "type": "string",
          "description": "/sky/ask 回答"
        },
        "objectDetail": {
          "type": "string",
          "description": "详情 JSON 字符串"
        },
        "facts": {
          "type": "string",
          "description": "/sky/facts JSON 字符串"
        },
        "targets": {
          "type": "string",
          "description": "目标数组 JSON 字符串"
        }
      }
    }
  }
}
</script>

<script setup>
const SKY_CHART_ENDPOINT = 'https://sky.eunoia.top/sky/chart'

const PRESET_OBJECTS = {
  moon: {
    key: 'moon',
    name: '月亮',
    type: 'moon',
    typeLabel: '月亮',
    englishName: 'Moon',
    direction: '东南',
    altitude: '35°',
    bestTime: '今晚',
    magnitude: '很亮',
    intro: '最适合城市里快速观察的目标，肉眼就很明显。',
    summary: '如果云不厚，月亮通常比星星更容易看到。',
    locateSteps: ['先找天空最亮的白色圆面。', '避开楼体遮挡，朝开阔方向看。', '云层变薄时再停下来观察细节。'],
    className: 'tone-moon',
    left: '278px',
    top: '38px'
  },
  jupiter: {
    key: 'jupiter',
    name: '木星',
    type: 'planet',
    typeLabel: '行星',
    englishName: 'Jupiter',
    direction: '东南',
    altitude: '35°',
    bestTime: '21:00 - 23:00',
    magnitude: '很亮',
    intro: '太阳系中体积最大的行星，亮度高，适合新手辨认。',
    summary: '它通常不明显闪烁，看起来像稳定的亮点。',
    locateSteps: ['面向东南方向寻找视野开阔处。', '把视线抬到地平线以上约 35°。', '优先寻找明亮且光点稳定的目标。'],
    className: 'tone-planet',
    left: '234px',
    top: '76px'
  },
  venus: {
    key: 'venus',
    name: '金星',
    type: 'planet',
    typeLabel: '行星',
    englishName: 'Venus',
    direction: '西方',
    altitude: '20°',
    bestTime: '日落后',
    magnitude: '极亮',
    intro: '傍晚或清晨最显眼的行星之一，常被叫作启明星或长庚星。',
    summary: '它非常亮，低空时要注意楼房和树木遮挡。',
    locateSteps: ['先确认日落后的西方低空。', '找最亮且不太闪烁的光点。', '如果地平线被挡住，换到更开阔的位置。'],
    className: 'tone-planet',
    left: '86px',
    top: '94px'
  },
  mars: {
    key: 'mars',
    name: '火星',
    type: 'planet',
    typeLabel: '行星',
    englishName: 'Mars',
    direction: '南方',
    altitude: '40°',
    bestTime: '夜间',
    magnitude: '偏亮',
    intro: '火星常带一点橙红色，适合和普通白色亮星区分。',
    summary: '亮度会随季节变化，不确定时可以先找颜色特征。',
    locateSteps: ['面向南方或东南方的开阔天空。', '寻找略带橙红色的稳定亮点。', '和附近白色亮星对比颜色。'],
    className: 'tone-planet',
    left: '184px',
    top: '62px'
  },
  sirius: {
    key: 'sirius',
    name: '天狼星',
    type: 'star',
    typeLabel: '亮星',
    englishName: 'Sirius',
    direction: '东南',
    altitude: '30°',
    bestTime: '20:30 - 22:30',
    magnitude: '最亮恒星',
    intro: '夜空中最亮的恒星之一，通常非常显眼。',
    summary: '靠近地平线时会闪烁，城市里也比较容易看到。',
    locateSteps: ['面向东南方向，从低空区域开始搜索。', '优先锁定最亮的白色光点。', '如果已找到猎户座，可沿腰带延长线向下寻找。'],
    className: 'tone-star',
    left: '308px',
    top: '96px'
  },
  orion: {
    key: 'orion',
    name: '猎户座',
    type: 'constellation',
    typeLabel: '星座',
    englishName: 'Orion',
    direction: '南方',
    altitude: '45°',
    bestTime: '20:00 - 22:00',
    magnitude: '明亮',
    intro: '冬季夜空最容易辨认的星座之一，适合做方位参照。',
    summary: '先找三颗近乎成一直线的亮星，再看上下轮廓。',
    locateSteps: ['面向南方，先找三颗成线的亮星。', '确认腰带后，再看上下两侧的亮星轮廓。', '用猎户座继续定位附近亮星。'],
    className: 'tone-constellation',
    left: '166px',
    top: '86px'
  },
  meteor: {
    key: 'meteor',
    name: '流星雨',
    type: 'meteor',
    typeLabel: '流星雨',
    englishName: 'Meteor Shower',
    direction: '天空开阔处',
    altitude: '抬头约 45°',
    bestTime: '后半夜',
    magnitude: '不稳定',
    intro: '流星雨需要耐心等待，也更依赖黑暗天空。',
    summary: '城市里不太适合专门看，最好远离灯光。',
    locateSteps: ['找灯少、视野开阔的位置。', '不要只盯着辐射点，放松看大范围天空。', '至少预留 20 分钟让眼睛适应黑暗。'],
    className: 'tone-meteor',
    left: '112px',
    top: '40px'
  }
}

const FALLBACK_TARGETS = [PRESET_OBJECTS.moon, PRESET_OBJECTS.jupiter, PRESET_OBJECTS.sirius, PRESET_OBJECTS.orion]

function hasValue(value) {
  return value !== undefined && value !== null && value !== ''
}

function toText(value, fallback) {
  if (hasValue(value)) {
    return String(value)
  }
  return fallback || ''
}

function toKey(value) {
  return toText(value, '')
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^\w\u4e00-\u9fa5-]/g, '')
}

function normalizeType(value) {
  const typeText = toText(value, '').toLowerCase()
  if (typeText.indexOf('moon') >= 0 || typeText.indexOf('月') >= 0) return 'moon'
  if (typeText.indexOf('planet') >= 0 || typeText.indexOf('行星') >= 0) return 'planet'
  if (typeText.indexOf('constellation') >= 0 || typeText.indexOf('星座') >= 0) return 'constellation'
  if (typeText.indexOf('meteor') >= 0 || typeText.indexOf('流星') >= 0) return 'meteor'
  if (typeText.indexOf('deep') >= 0 || typeText.indexOf('星云') >= 0 || typeText.indexOf('星团') >= 0) return 'deepSky'
  return 'star'
}

function typeLabel(type) {
  const labels = {
    moon: '月亮',
    planet: '行星',
    star: '亮星',
    constellation: '星座',
    meteor: '流星雨',
    deepSky: '深空'
  }
  return labels[type] || '目标'
}

function classNameForType(type) {
  const classes = {
    moon: 'tone-moon',
    planet: 'tone-planet',
    star: 'tone-star',
    constellation: 'tone-constellation',
    meteor: 'tone-meteor',
    deepSky: 'tone-deepsky'
  }
  return classes[type] || 'tone-star'
}

function directionLeft(direction, fallbackIndex) {
  const text = toText(direction, '')
  if (text.indexOf('西') >= 0) return '86px'
  if (text.indexOf('东') >= 0) return '292px'
  if (text.indexOf('南') >= 0) return '190px'
  if (text.indexOf('北') >= 0) return '186px'
  return `${96 + fallbackIndex * 68}px`
}

function altitudeTop(altitude, fallbackIndex) {
  const number = parseFloat(toText(altitude, '').replace('°', ''))
  if (!isNaN(number)) {
    const bounded = Math.max(8, Math.min(110, 126 - number * 1.35))
    return `${Math.round(bounded)}px`
  }
  return `${42 + fallbackIndex * 16}px`
}

function normalizeTarget(rawTarget, index) {
  if (typeof rawTarget === 'string') {
    const preset = findPreset(rawTarget)
    return preset || Object.assign({}, PRESET_OBJECTS.sirius, {
      key: toKey(rawTarget) || `target-${index + 1}`,
      name: rawTarget
    })
  }

  const raw = rawTarget || {}
  const rawName = raw.name || raw.zhName || raw.cnName || raw.title || raw.objectName || raw.object || raw.body || raw.designation || raw.id
  const preset = findPreset(raw.key || rawName)
  const base = preset || {}
  const type = normalizeType(raw.type || raw.category || base.type)
  const name = toText(rawName, base.name || `目标 ${index + 1}`)
  const key = toKey(raw.key || raw.id || base.key || name) || `target-${index + 1}`
  const direction = toText(raw.direction || raw.azimuthText || raw.cardinalDirection || raw.azimuthDirection || raw.compass || base.direction, '天空开阔处')
  const altitude = toText(raw.altitude || raw.altitudeDeg || raw.alt || raw.elevation || raw.height || base.altitude, '中低空')

  return {
    key,
    name,
    type,
    typeLabel: typeLabel(type),
    englishName: toText(raw.englishName || raw.enName || raw.latinName || raw.nameEn || base.englishName, ''),
    direction,
    altitude,
    bestTime: toText(raw.bestTime || raw.visibleTime || raw.timeWindow || raw.riseSet || raw.time || raw.transitTime || base.bestTime, '今晚'),
    magnitude: toText(raw.magnitude || raw.brightness || raw.mag || raw.apparentMagnitude || base.magnitude, '可见'),
    intro: toText(raw.intro || raw.description || raw.detail || base.intro, '这个目标适合继续了解位置和观测方法。'),
    summary: toText(raw.summary || raw.reason || raw.tip || raw.observationTip || base.summary, '可以先根据方位和高度大致寻找，不需要追求很精确。'),
    locateSteps: raw.locateSteps || raw.steps || base.locateSteps || ['先确认大致方位。', '寻找天空中最显眼的亮点或轮廓。', '如果云层遮挡，就等几分钟再看。'],
    className: classNameForType(type),
    left: toText(raw.left || raw.x, directionLeft(direction, index)),
    top: toText(raw.top || raw.y, altitudeTop(altitude, index))
  }
}

function findPreset(value) {
  const key = toKey(value)
  if (PRESET_OBJECTS[key]) return PRESET_OBJECTS[key]

  const text = toText(value, '').toLowerCase()
  const names = Object.keys(PRESET_OBJECTS)
  for (let index = 0; index < names.length; index += 1) {
    const preset = PRESET_OBJECTS[names[index]]
    if (text === preset.name || text === preset.englishName.toLowerCase()) {
      return preset
    }
  }
  return null
}

function parseTargets(value) {
  if (Array.isArray(value)) return value
  if (!hasValue(value)) return []

  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value)
      return Array.isArray(parsed) ? parsed : []
    } catch (error) {
      return value.split(',').map(item => item.trim()).filter(Boolean)
    }
  }

  if (Array.isArray(value.targets)) return value.targets
  if (Array.isArray(value.objects)) return value.objects
  if (Array.isArray(value.visibleObjects)) return value.visibleObjects
  return []
}

function parseObjectValue(value) {
  if (!hasValue(value)) return null
  if (typeof value === 'string') {
    try {
      return JSON.parse(value)
    } catch (error) {
      return null
    }
  }
  return value
}

function pushArrayTargets(bucket, value) {
  if (!Array.isArray(value)) return
  value.forEach(item => {
    if (item && typeof item === 'object') {
      bucket.push(item)
    }
  })
}

function pushSingleTarget(bucket, value, fallbackType) {
  if (!value || typeof value !== 'object') return
  const target = Object.assign({}, value)
  if (!target.type && fallbackType) {
    target.type = fallbackType
  }
  bucket.push(target)
}

function extractTargetsFromChart(chart) {
  const source = parseObjectValue(chart)
  const bucket = []
  if (!source || typeof source !== 'object') return bucket

  pushArrayTargets(bucket, source.targets)
  pushArrayTargets(bucket, source.objects)
  pushArrayTargets(bucket, source.visibleObjects)
  pushArrayTargets(bucket, source.visible_objects)
  pushArrayTargets(bucket, source.bodies)
  pushArrayTargets(bucket, source.celestialBodies)
  pushArrayTargets(bucket, source.celestial_objects)
  pushArrayTargets(bucket, source.recommendations)
  pushArrayTargets(bucket, source.recommended)
  pushArrayTargets(bucket, source.planets)
  pushArrayTargets(bucket, source.stars)
  pushArrayTargets(bucket, source.constellations)
  pushArrayTargets(bucket, source.deepSky)
  pushArrayTargets(bucket, source.deep_sky)
  pushArrayTargets(bucket, source.meteorShowers)
  pushArrayTargets(bucket, source.meteor_showers)

  pushSingleTarget(bucket, source.moon, 'moon')

  if (source.data && source.data !== source) {
    bucket.push(...extractTargetsFromChart(source.data))
  }

  if (source.result && source.result !== source) {
    bucket.push(...extractTargetsFromChart(source.result))
  }

  return bucket
}

function uniqueTargets(targets) {
  const seen = {}
  const result = []
  targets.forEach((target, index) => {
    const normalized = normalizeTarget(target, index)
    const key = normalized.key || normalized.name
    if (!seen[key]) {
      seen[key] = true
      result.push(normalized)
    }
  })
  return result
}

function chartText(chart, keys, fallback) {
  const source = parseObjectValue(chart) || {}
  for (let index = 0; index < keys.length; index += 1) {
    const key = keys[index]
    if (hasValue(source[key])) return String(source[key])
    if (source.data && hasValue(source.data[key])) return String(source.data[key])
    if (source.result && hasValue(source.result[key])) return String(source.result[key])
  }
  return fallback || ''
}

function detailText(value) {
  const source = parseObjectValue(value)
  if (!source) return toText(value, '')
  return toText(
    source.answer ||
    source.detail ||
    source.description ||
    source.summary ||
    source.text ||
    source.content ||
    source.message,
    ''
  )
}

function findDetailObject(value, selectedName) {
  const source = parseObjectValue(value)
  if (!source || typeof source !== 'object') return null

  const selectedKey = toKey(selectedName)
  const candidates = []
  pushSingleTarget(candidates, source.object)
  pushSingleTarget(candidates, source.target)
  pushSingleTarget(candidates, source.detail)
  pushArrayTargets(candidates, source.targets)
  pushArrayTargets(candidates, source.objects)
  pushArrayTargets(candidates, source.facts)

  for (let index = 0; index < candidates.length; index += 1) {
    const item = candidates[index]
    if (!selectedKey) return item
    if (toKey(item.key || item.name || item.objectName || item.title) === selectedKey) {
      return item
    }
  }

  return source.name || source.objectName || source.title ? source : null
}

function normalizeQuery(query) {
  if (!query) return {}
  if (typeof query === 'string') {
    try {
      return JSON.parse(query)
    } catch (error) {
      return {}
    }
  }
  if (query.data && typeof query.data === 'string') {
    try {
      return Object.assign({}, query, JSON.parse(query.data))
    } catch (error) {
      return query
    }
  }
  if (query.data && typeof query.data === 'object') {
    return Object.assign({}, query, query.data)
  }
  return query
}

export default {
  data: {
    pageTitle: 'SkyMate 天文助手',
    pageTag: '首页',
    mode: 'home',
    locationName: '当前位置',
    verdict: '唤醒乐奇后，我会帮你判断今晚值不值得看星星。',
    condition: '等待眼镜位置、时间、天气和天体工具结果。',
    assistantLine: '你可以直接说：乐奇，今晚适合观星吗？',
    dataTime: '',
    dataSource: SKY_CHART_ENDPOINT,
    dataMeta: '首页星体只是展示，真实结果会在工具返回后出现。',
    dataMetaDisplay: 'none',
    hasRealData: false,
    currentObjectKey: 'moon',
    currentObject: PRESET_OBJECTS.moon,
    visibleObjects: FALLBACK_TARGETS,

    homeDisplay: 'block',
    chatDisplay: 'none',
    overviewDisplay: 'none',
    detailDisplay: 'none',
    locateDisplay: 'none',

    tip: '首页会先做简短引导；进入对话后，工具结果会变成可点击的星体。'
  },

  onLoad(rawQuery) {
    const query = normalizeQuery(rawQuery)
    const chartResult = query.skyChart || query.chart || query.rawResult || query.result
    const targets = parseTargets(query.targets || query.objects || query.visibleObjects)
    const chartTargets = extractTargetsFromChart(chartResult)
    const realTargets = targets.length ? targets : chartTargets
    const normalizedObjects = uniqueTargets(realTargets.length ? realTargets : FALLBACK_TARGETS).slice(0, 4)

    const selectedName = query.selectedObject || query.object || query.target || ''
    const mode = this.normalizeMode(query.mode, realTargets.length, selectedName)
    const detailObject = findDetailObject(query.objectDetail || query.facts, selectedName)
    const detailAnswer = detailText(query.detailAnswer || query.objectDetail || query.detail || '')
    const resolvedObject = this.resolveObject(selectedName, normalizedObjects)
    const currentObject = detailObject || detailAnswer
      ? this.mergeObjectDetail(resolvedObject, detailObject, detailAnswer)
      : resolvedObject

    this.setData({
      visibleObjects: normalizedObjects,
      locationName: toText(query.locationName || query.location || query.city || chartText(chartResult, ['locationName', 'location', 'city'], ''), '当前位置'),
      verdict: toText(query.verdict || query.answer || query.conclusion || chartText(chartResult, ['verdict', 'conclusion', 'summary'], ''), this.data.verdict),
      condition: toText(query.condition || query.weather || query.weatherSummary || chartText(chartResult, ['condition', 'weather', 'weatherSummary'], ''), this.data.condition),
      assistantLine: toText(query.assistantLine || query.prompt, realTargets.length ? '这些是真实星图数据筛出的目标，点一个可以听详情。' : this.data.assistantLine),
      dataTime: toText(query.dataTime || query.time || chartText(chartResult, ['dataTime', 'localTime', 'time', 'utc'], ''), ''),
      dataSource: toText(query.serviceUrl || chartText(chartResult, ['serviceUrl', 'source'], ''), SKY_CHART_ENDPOINT),
      dataMeta: this.buildDataMeta(realTargets.length, query, chartResult),
      dataMetaDisplay: realTargets.length ? 'block' : 'none',
      hasRealData: realTargets.length > 0
    })

    this.applyState(mode, currentObject.key)
  },

  normalizeMode(value, targetCount, selectedName) {
    const supportedModes = {
      home: true,
      chat: true,
      overview: true,
      detail: true,
      locate: true
    }

    if (supportedModes[value]) return value
    if (selectedName) return 'detail'
    if (targetCount > 0) return 'overview'
    return 'home'
  },

  buildDataMeta(targetCount, query, chartResult) {
    if (!targetCount) {
      return '首页星体只是展示，真实结果会在工具返回后出现。'
    }

    const time = toText(query.dataTime || query.time || chartText(chartResult, ['dataTime', 'localTime', 'time', 'utc'], ''), '当前时刻')
    const source = toText(query.serviceUrl || chartText(chartResult, ['serviceUrl', 'source'], ''), SKY_CHART_ENDPOINT)
    return `${time} · ${source}`
  },

  mergeObjectDetail(baseObject, detailObject, detailAnswer) {
    const normalizedDetail = detailObject ? normalizeTarget(detailObject, 0) : {}
    const merged = Object.assign({}, baseObject, normalizedDetail)
    const answer = detailAnswer || detailText(detailObject)

    if (answer) {
      merged.intro = answer
      merged.summary = toText(normalizedDetail.summary || baseObject.summary, '这是根据真实星图服务返回的详情整理出的说明。')
    }

    if (!merged.locateSteps || !merged.locateSteps.length) {
      merged.locateSteps = baseObject.locateSteps
    }

    return merged
  },

  resolveObject(value, visibleObjects) {
    const key = toKey(value)
    const objects = visibleObjects && visibleObjects.length ? visibleObjects : this.data.visibleObjects

    for (let index = 0; index < objects.length; index += 1) {
      const object = objects[index]
      if (object.key === key || toKey(object.name) === key || toKey(object.englishName) === key) {
        return object
      }
    }

    return objects[0] || PRESET_OBJECTS.moon
  },

  applyState(mode, objectKey) {
    const currentObject = this.resolveObject(objectKey, this.data.visibleObjects)
    const modeKey = this.normalizeMode(mode, this.data.visibleObjects.length, currentObject.key)

    const titleMap = {
      home: 'SkyMate 天文助手',
      chat: '乐奇已唤醒',
      overview: '今晚可看目标',
      detail: `${currentObject.name} ${currentObject.englishName}`,
      locate: `寻找${currentObject.name}`
    }

    const tagMap = {
      home: '首页',
      chat: '对话',
      overview: '总览',
      detail: '详情',
      locate: '寻找'
    }

    const tipMap = {
      home: '说“乐奇，今晚适合观星吗”，进入对话后我会结合天气和星图判断。',
      chat: '我会先拿当前位置和时间，再调用天气与天体工具。',
      overview: '点一个星体，我就切到它的详情；用户语音追问时也可以由 AI 自动打开。',
      detail: `当前聚焦 ${currentObject.name}，适合继续问它怎么找。`,
      locate: `按大致方向找 ${currentObject.name} 就行，不需要追求精确角度。`
    }

    this.setData({
      pageTitle: titleMap[modeKey],
      pageTag: tagMap[modeKey],
      mode: modeKey,
      currentObjectKey: currentObject.key,
      currentObject,
      homeDisplay: modeKey === 'home' ? 'block' : 'none',
      chatDisplay: modeKey === 'chat' ? 'block' : 'none',
      overviewDisplay: modeKey === 'overview' ? 'block' : 'none',
      detailDisplay: modeKey === 'detail' ? 'block' : 'none',
      locateDisplay: modeKey === 'locate' ? 'block' : 'none',
      tip: tipMap[modeKey]
    })
  },

  startChat() {
    this.applyState('chat', this.data.currentObjectKey)
  },

  openHome() {
    this.applyState('home', this.data.currentObjectKey)
  },

  openOverview() {
    this.applyState('overview', this.data.currentObjectKey)
  },

  openDetail() {
    this.applyState('detail', this.data.currentObjectKey)
  },

  openLocate() {
    this.applyState('locate', this.data.currentObjectKey)
  },

  selectObject(event) {
    const dataset = (event && event.currentTarget && event.currentTarget.dataset) || (event && event.target && event.target.dataset) || {}
    const objectKey = dataset.key || this.data.currentObjectKey
    this.applyState('detail', objectKey)
  }
}
</script>

<page>
  <view class="shell">
    <view class="header">
      <view class="brand">
        <text class="brand-mark">S</text>
        <view class="brand-copy">
          <text class="title">{{ pageTitle }}</text>
          <text class="subtitle">{{ locationName }}</text>
        </view>
      </view>
      <text class="tag">{{ pageTag }}</text>
    </view>

    <view class="home-panel" style="display: {{ homeDisplay }};">
      <view class="hero-row">
        <view class="orbit-scene">
          <text class="scene-label">SkyMate</text>
          <text class="horizon-line"></text>
          <text class="home-star home-star-a">·</text>
          <text class="home-star home-star-b">·</text>
          <text class="home-star home-star-c">·</text>
          <text class="home-moon">◐</text>
          <text class="home-planet">●</text>
        </view>
        <view class="intro">
          <text class="eyebrow">智能眼镜观星助手</text>
          <text class="intro-title">抬头之前，先判断值不值得出门。</text>
          <text class="intro-copy">我会结合你眼镜的位置、当前时间、天气和天体工具，给出短结论。</text>
        </view>
      </view>

      <view class="guide-row">
        <view class="guide-step active-step">
          <text class="step-index">1</text>
          <text class="step-copy">唤醒乐奇</text>
        </view>
        <view class="guide-step">
          <text class="step-index">2</text>
          <text class="step-copy">询问今晚能看什么</text>
        </view>
        <view class="guide-step">
          <text class="step-index">3</text>
          <text class="step-copy">点选星体听详情</text>
        </view>
      </view>

      <button class="wide-action primary-action" bindtap="startChat">进入对话界面</button>
    </view>

    <view class="chat-panel" style="display: {{ chatDisplay }};">
      <view class="chat-stream">
        <view class="bubble assistant-bubble">
          <text class="bubble-name">乐奇</text>
          <text class="bubble-text">我在。你可以问：今晚适合观星吗？</text>
        </view>
        <view class="bubble user-bubble">
          <text class="bubble-name">你</text>
          <text class="bubble-text">今晚能看到什么？</text>
        </view>
      <view class="tool-card">
          <text class="tool-title">正在准备观星判断</text>
          <text class="tool-line">当前位置：get_context_param</text>
          <text class="tool-line">当前时间：get_current_time</text>
          <text class="tool-line">天空目标：sky_chart → sky.eunoia.top</text>
        </view>
      </view>

      <button class="wide-action secondary-action" bindtap="openHome">返回首页</button>
    </view>

    <view class="overview-panel" style="display: {{ overviewDisplay }};">
      <view class="verdict-band">
        <text class="verdict">{{ verdict }}</text>
        <text class="condition">{{ condition }}</text>
        <text class="data-meta" style="display: {{ dataMetaDisplay }};">{{ dataMeta }}</text>
      </view>

      <view class="sky-stage">
        <text class="direction west">西</text>
        <text class="direction south">南</text>
        <text class="direction east">东</text>
        <text class="alt-line alt-high">高空</text>
        <text class="alt-line alt-low">低空</text>
        <text
          class="sky-object {{ skyItem.className }}"
          ink:for="{{ visibleObjects }}"
          ink:for-item="skyItem"
          ink:key="key"
          data-key="{{ skyItem.key }}"
          bindtap="selectObject"
          style="left: {{ skyItem.left }}; top: {{ skyItem.top }};"
        >
          {{ skyItem.name }}
        </text>
      </view>

      <view class="object-grid">
        <button
          class="object-button {{ objectItem.className }}"
          ink:for="{{ visibleObjects }}"
          ink:for-item="objectItem"
          ink:key="key"
          data-key="{{ objectItem.key }}"
          bindtap="selectObject"
        >
          <text class="object-button-name">{{ objectItem.name }}</text>
          <text class="object-button-meta">{{ objectItem.typeLabel }} · {{ objectItem.direction }}</text>
        </button>
      </view>

      <view class="action-row overview-actions">
        <button class="action secondary-action" bindtap="openHome">返回首页</button>
      </view>
    </view>

    <view class="detail-panel" style="display: {{ detailDisplay }};">
      <view class="detail-hero {{ currentObject.className }}">
        <view class="detail-main">
          <text class="detail-type">{{ currentObject.typeLabel }}</text>
          <text class="detail-name">{{ currentObject.name }}</text>
          <text class="detail-en">{{ currentObject.englishName }}</text>
        </view>
        <view class="detail-orbit">
          <text class="detail-dot">●</text>
        </view>
      </view>

      <view class="detail-info">
        <text class="detail-intro">{{ currentObject.intro }}</text>
        <view class="metric-row">
          <view class="metric">
            <text class="metric-label">方向</text>
            <text class="metric-value">{{ currentObject.direction }}</text>
          </view>
          <view class="metric">
            <text class="metric-label">高度</text>
            <text class="metric-value">{{ currentObject.altitude }}</text>
          </view>
          <view class="metric">
            <text class="metric-label">时间</text>
            <text class="metric-value">{{ currentObject.bestTime }}</text>
          </view>
        </view>
        <text class="detail-summary">{{ currentObject.summary }}</text>
      </view>

      <view class="action-row">
        <button class="action primary-action" bindtap="openLocate">寻找它</button>
        <button class="action secondary-action" bindtap="openOverview">返回总览</button>
        <button class="action secondary-action" bindtap="openHome">返回首页</button>
      </view>
    </view>

    <view class="locate-panel" style="display: {{ locateDisplay }};">
      <view class="locate-compass">
        <text class="compass-target">{{ currentObject.name }}</text>
        <text class="compass-direction">{{ currentObject.direction }}</text>
        <text class="compass-arc"></text>
      </view>

      <view class="locate-steps">
        <text class="locate-title">怎么找</text>
        <text class="step-line">1. {{ currentObject.locateSteps[0] }}</text>
        <text class="step-line">2. {{ currentObject.locateSteps[1] }}</text>
        <text class="step-line">3. {{ currentObject.locateSteps[2] }}</text>
      </view>

      <view class="action-row">
        <button class="action primary-action" bindtap="openDetail">查看详情</button>
        <button class="action secondary-action" bindtap="openOverview">返回总览</button>
        <button class="action secondary-action" bindtap="openHome">返回首页</button>
      </view>
    </view>

    <view class="footer">
      <text class="assistant-line">{{ assistantLine }}</text>
      <text class="footer-tip">{{ tip }}</text>
    </view>
  </view>
</page>

<style>
.shell {
  width: 448px;
  min-height: 264px;
  box-sizing: border-box;
  overflow: hidden;
  color: #f4f7f1;
  background: linear-gradient(150deg, #060807 0%, #101814 46%, #211d13 100%);
  border: 1px solid rgba(205, 245, 194, 0.18);
  border-radius: 14px;
  padding: 12px;
}

.header {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
}

.brand {
  display: flex;
  flex-direction: row;
  align-items: center;
}

.brand-mark {
  width: 28px;
  height: 28px;
  line-height: 28px;
  text-align: center;
  margin-right: 8px;
  border-radius: 7px;
  color: #07100d;
  background: #b7f7bf;
  font-size: 16px;
  font-weight: 700;
}

.brand-copy {
  display: flex;
  flex-direction: column;
}

.title {
  color: #f7ffe9;
  font-size: 17px;
  line-height: 20px;
  font-weight: 700;
}

.subtitle {
  color: rgba(244, 247, 241, 0.62);
  font-size: 11px;
  line-height: 14px;
}

.tag {
  height: 22px;
  line-height: 22px;
  padding: 0 8px;
  border-radius: 6px;
  color: #b7f7bf;
  background: rgba(183, 247, 191, 0.12);
  border: 1px solid rgba(183, 247, 191, 0.26);
  font-size: 12px;
}

.hero-row {
  display: flex;
  flex-direction: row;
  gap: 10px;
  margin-bottom: 10px;
}

.orbit-scene {
  position: relative;
  width: 184px;
  height: 112px;
  overflow: hidden;
  border-radius: 8px;
  background: radial-gradient(circle at 72% 24%, rgba(250, 223, 142, 0.22), transparent 28%), linear-gradient(180deg, #0a1010, #151a12);
  border: 1px solid rgba(250, 223, 142, 0.2);
}

.scene-label {
  position: absolute;
  left: 12px;
  top: 10px;
  color: rgba(244, 247, 241, 0.64);
  font-size: 11px;
}

.horizon-line {
  position: absolute;
  left: 12px;
  right: 12px;
  bottom: 23px;
  height: 1px;
  background: rgba(183, 247, 191, 0.32);
}

.home-star,
.home-moon,
.home-planet {
  position: absolute;
  line-height: 1;
}

.home-star {
  color: #f4f7f1;
  font-size: 22px;
}

.home-star-a {
  left: 44px;
  top: 40px;
}

.home-star-b {
  left: 96px;
  top: 22px;
}

.home-star-c {
  left: 130px;
  top: 58px;
}

.home-moon {
  right: 22px;
  top: 26px;
  color: #f6d67b;
  font-size: 26px;
}

.home-planet {
  left: 76px;
  bottom: 30px;
  color: #9ee6ff;
  font-size: 16px;
}

.intro {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.eyebrow {
  color: #b7f7bf;
  font-size: 11px;
  line-height: 15px;
  margin-bottom: 3px;
}

.intro-title {
  color: #f7ffe9;
  font-size: 17px;
  line-height: 22px;
  font-weight: 700;
  margin-bottom: 5px;
}

.intro-copy {
  color: rgba(244, 247, 241, 0.72);
  font-size: 12px;
  line-height: 17px;
}

.guide-row {
  display: flex;
  flex-direction: row;
  gap: 8px;
  margin-bottom: 10px;
}

.guide-step {
  flex: 1;
  height: 48px;
  box-sizing: border-box;
  padding: 7px;
  border-radius: 7px;
  background: rgba(255, 255, 255, 0.045);
  border: 1px solid rgba(244, 247, 241, 0.08);
}

.active-step {
  border-color: rgba(183, 247, 191, 0.32);
  background: rgba(183, 247, 191, 0.1);
}

.step-index {
  display: block;
  color: #f6d67b;
  font-size: 12px;
  line-height: 14px;
  font-weight: 700;
}

.step-copy {
  display: block;
  color: rgba(244, 247, 241, 0.82);
  font-size: 11px;
  line-height: 15px;
}

.chat-stream {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 10px;
}

.bubble {
  width: 310px;
  box-sizing: border-box;
  padding: 8px 10px;
  border-radius: 8px;
}

.assistant-bubble {
  background: rgba(183, 247, 191, 0.1);
  border: 1px solid rgba(183, 247, 191, 0.18);
}

.user-bubble {
  margin-left: 112px;
  background: rgba(246, 214, 123, 0.11);
  border: 1px solid rgba(246, 214, 123, 0.2);
}

.bubble-name {
  display: block;
  color: rgba(244, 247, 241, 0.54);
  font-size: 11px;
  line-height: 14px;
}

.bubble-text {
  display: block;
  color: #f7ffe9;
  font-size: 12px;
  line-height: 17px;
}

.tool-card {
  padding: 9px 10px;
  border-radius: 8px;
  background: rgba(8, 11, 10, 0.54);
  border: 1px solid rgba(158, 230, 255, 0.18);
}

.tool-title {
  display: block;
  color: #9ee6ff;
  font-size: 12px;
  line-height: 16px;
  font-weight: 700;
  margin-bottom: 3px;
}

.tool-line {
  display: block;
  color: rgba(244, 247, 241, 0.72);
  font-size: 11px;
  line-height: 15px;
}

.verdict-band {
  padding: 8px 10px;
  margin-bottom: 10px;
  border-radius: 8px;
  background: linear-gradient(90deg, rgba(183, 247, 191, 0.13), rgba(246, 214, 123, 0.09));
  border: 1px solid rgba(183, 247, 191, 0.2);
}

.verdict {
  display: block;
  color: #f7ffe9;
  font-size: 14px;
  line-height: 19px;
  font-weight: 700;
}

.condition {
  display: block;
  color: rgba(244, 247, 241, 0.72);
  font-size: 11px;
  line-height: 15px;
}

.data-meta {
  display: block;
  color: rgba(183, 247, 191, 0.62);
  font-size: 10px;
  line-height: 14px;
  margin-top: 3px;
}

.sky-stage {
  position: relative;
  height: 134px;
  margin-bottom: 10px;
  overflow: hidden;
  border-radius: 8px;
  background: radial-gradient(circle at 50% 108%, rgba(183, 247, 191, 0.16), transparent 38%), linear-gradient(180deg, #080d0d, #151910);
  border: 1px solid rgba(244, 247, 241, 0.1);
}

.direction,
.alt-line {
  position: absolute;
  color: rgba(244, 247, 241, 0.42);
  font-size: 11px;
  line-height: 13px;
}

.west {
  left: 16px;
  bottom: 9px;
}

.south {
  left: 210px;
  bottom: 9px;
}

.east {
  right: 16px;
  bottom: 9px;
}

.alt-high {
  left: 16px;
  top: 12px;
}

.alt-low {
  left: 16px;
  bottom: 28px;
}

.sky-object {
  position: absolute;
  min-width: 48px;
  height: 26px;
  line-height: 26px;
  text-align: center;
  padding: 0 7px;
  border-radius: 7px;
  font-size: 11px;
  font-weight: 700;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.18);
}

.object-grid {
  display: flex;
  flex-direction: row;
  gap: 8px;
}

.overview-actions {
  margin-top: 9px;
}

.object-button {
  flex: 1;
  height: 52px;
  padding: 7px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.14);
  background: rgba(255, 255, 255, 0.055);
  text-align: left;
}

.object-button-name {
  display: block;
  color: #f7ffe9;
  font-size: 12px;
  line-height: 16px;
  font-weight: 700;
}

.object-button-meta {
  display: block;
  color: rgba(244, 247, 241, 0.58);
  font-size: 10px;
  line-height: 14px;
}

.tone-moon {
  color: #fff1b8;
  border-color: rgba(246, 214, 123, 0.34);
  background: rgba(246, 214, 123, 0.12);
}

.tone-planet {
  color: #c6f6ff;
  border-color: rgba(158, 230, 255, 0.34);
  background: rgba(158, 230, 255, 0.1);
}

.tone-star {
  color: #eef8ff;
  border-color: rgba(238, 248, 255, 0.3);
  background: rgba(238, 248, 255, 0.08);
}

.tone-constellation {
  color: #b7f7bf;
  border-color: rgba(183, 247, 191, 0.34);
  background: rgba(183, 247, 191, 0.1);
}

.tone-meteor,
.tone-deepsky {
  color: #ffd1a3;
  border-color: rgba(255, 209, 163, 0.34);
  background: rgba(255, 209, 163, 0.1);
}

.detail-hero {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  height: 82px;
  box-sizing: border-box;
  padding: 11px 12px;
  margin-bottom: 9px;
  border-radius: 8px;
}

.detail-main {
  display: flex;
  flex-direction: column;
}

.detail-type {
  color: rgba(244, 247, 241, 0.66);
  font-size: 11px;
  line-height: 14px;
}

.detail-name {
  color: #f7ffe9;
  font-size: 22px;
  line-height: 28px;
  font-weight: 800;
}

.detail-en {
  color: rgba(244, 247, 241, 0.58);
  font-size: 11px;
  line-height: 14px;
}

.detail-orbit {
  position: relative;
  width: 68px;
  height: 58px;
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 50%;
}

.detail-dot {
  position: absolute;
  right: 10px;
  top: 14px;
  font-size: 18px;
}

.detail-info {
  margin-bottom: 9px;
}

.detail-intro {
  display: block;
  color: rgba(244, 247, 241, 0.86);
  font-size: 12px;
  line-height: 17px;
  margin-bottom: 8px;
}

.metric-row {
  display: flex;
  flex-direction: row;
  gap: 8px;
  margin-bottom: 8px;
}

.metric {
  flex: 1;
  height: 46px;
  box-sizing: border-box;
  padding: 6px 7px;
  border-radius: 7px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.metric-label {
  display: block;
  color: rgba(244, 247, 241, 0.5);
  font-size: 10px;
  line-height: 13px;
}

.metric-value {
  display: block;
  color: #f7ffe9;
  font-size: 12px;
  line-height: 17px;
  font-weight: 700;
}

.detail-summary {
  display: block;
  color: rgba(244, 247, 241, 0.7);
  font-size: 11px;
  line-height: 16px;
}

.locate-compass {
  position: relative;
  height: 86px;
  margin-bottom: 9px;
  border-radius: 8px;
  background: linear-gradient(180deg, rgba(183, 247, 191, 0.1), rgba(255, 255, 255, 0.035));
  border: 1px solid rgba(183, 247, 191, 0.18);
  overflow: hidden;
}

.compass-target {
  position: absolute;
  left: 14px;
  top: 12px;
  color: #f7ffe9;
  font-size: 16px;
  line-height: 20px;
  font-weight: 800;
}

.compass-direction {
  position: absolute;
  left: 14px;
  top: 38px;
  color: #b7f7bf;
  font-size: 12px;
  line-height: 16px;
}

.compass-arc {
  position: absolute;
  right: 30px;
  top: 12px;
  width: 72px;
  height: 72px;
  border-radius: 50%;
  border: 1px solid rgba(246, 214, 123, 0.32);
}

.locate-steps {
  margin-bottom: 9px;
}

.locate-title {
  display: block;
  color: #f7ffe9;
  font-size: 13px;
  line-height: 18px;
  font-weight: 700;
  margin-bottom: 4px;
}

.step-line {
  display: block;
  color: rgba(244, 247, 241, 0.76);
  font-size: 12px;
  line-height: 18px;
}

.wide-action,
.action {
  height: 40px;
  border-radius: 7px;
  font-size: 13px;
  font-weight: 700;
  border: 1px solid rgba(255, 255, 255, 0.14);
}

.wide-action {
  width: 100%;
}

.action-row {
  display: flex;
  flex-direction: row;
  gap: 8px;
}

.action {
  flex: 1;
}

.primary-action {
  color: #07100d;
  background: #b7f7bf;
  border-color: rgba(183, 247, 191, 0.78);
}

.secondary-action {
  color: #f4f7f1;
  background: rgba(255, 255, 255, 0.06);
}

.footer {
  margin-top: 9px;
  padding-top: 8px;
  border-top: 1px solid rgba(244, 247, 241, 0.08);
}

.assistant-line {
  display: block;
  color: #f6d67b;
  font-size: 11px;
  line-height: 15px;
  text-align: center;
}

.footer-tip {
  display: block;
  color: rgba(244, 247, 241, 0.48);
  font-size: 10px;
  line-height: 14px;
  text-align: center;
}
</style>
