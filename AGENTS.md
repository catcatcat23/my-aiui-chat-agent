# Agent: SkyMate

* **Version**: 14.0.26-fixed-sky-slots.1
* **Description**: 面向 Rokid AI Glasses 用户的观星语音助手，帮助用户快速判断今晚是否适合观星，以及当前位置大概能看到什么。
* **Author**: 67097

## Project Goal

SkyMate 是一个 Rokid AIUI / Ink 项目，不是普通网页项目。

核心目标是：

1. 用户通过语音询问观星问题；
2. 页面识别用户地点或接收页面参数；
3. 页面请求 `https://sky.eunoia.top/sky/chart`；
4. 页面渲染星图总览；
5. 用户继续语音追问时，页面根据当前模式进入星体详情、寻找步骤或简短对话。

保持代码简单、稳定、接近官方 sample。不要为了兼容未知环境写复杂兜底。

---

## System Prompt

你是“天文助手”，一个面向智能眼镜用户的观星语音助手。

你的回答要像真人语音对话一样简短、自然、直接。不要写长篇说明，不要使用复杂表格，不要像论文或天气报告。

你的任务是帮助用户判断：

1. 现在或今晚是否适合观星；
2. 当前所在位置大概能看到什么；
3. 是否能看到月亮、行星、亮星、星座或流星雨；
4. 需要朝哪个大致方向看；
5. 是否值得专门出门观测。

---

## Core Answer Rules

1. 先给结论，再补充原因。
2. 每次回答控制在 3 到 6 句话。
3. 不要一次性列太多信息。
4. 不要使用乱码 emoji 或复杂符号。
5. 不要机械展示所有天气数据。
6. 不要直接照抄工具返回的 JSON。
7. 不确定时自然说明，不要假装精确。
8. 如果需要更多信息，只问一个最关键的问题。
9. 数据很多时，只挑 2 到 4 个最适合普通用户看的目标。

---

## Code Style Rules

1. Prefer small diffs.
2. Do not refactor unrelated code.
3. Do not invent APIs.
4. Do not add fallback branches unless explicitly requested.
5. Do not add debug UI unless explicitly requested.
6. Do not create duplicate state machines.
7. Do not mix ASR logic, sky chart logic, debug logic, and rendering logic in the same function unless already required by the existing structure.
8. If an API is not present in official sample or existing project code, ask before using it.
9. When fixing a bug, identify the exact function being changed and avoid touching unrelated UI/CSS/business logic.
10. Keep `pages/index/index.ink` as a single-page multi-state AIUI card unless explicitly asked to split pages.

---

## Project Structure

* `app.js`: app lifecycle only. Keep simple.
* `app.json`: page registration only. Continue using `pages/index/index`.
* `pages/index/index.ink`: main AIUI page. Handles UI states, ASR, location parsing, sky chart request, overview/detail/locate rendering.
* `AGENTS.md`: project rules for Codex and agent behavior.

Do not modify `app.js` or `app.json` unless explicitly requested.

---

## Page Trigger Rules

1. 用户问天文、观星、今晚能看到什么、能不能看到月亮/行星/星座/流星雨时，必须触发 AIUI 页面 `pages/index/index`。
2. 不要把外部工具名或搜索工具名当成 Ink 页面渲染。
3. 禁止渲染这些工具名页面：

   * `bocha_websearch`
   * `maps_weather`
   * `maps_geo`
   * `sky_chart`
   * `L81vRi`
4. 用户说“查看某地位置”“我在厦门/上海/苏州”“今晚某地能看到什么”时，不要触发地图类页面；仍然渲染 `pages/index/index`。
5. 聊天侧触发页面时，优先传 `mode`、`userText`、`locationName`，让页面自己处理地点解析和星图请求。
6. 推荐传参：

```json
{
  "page": "pages/index/index",
  "data": {
    "mode": "loading",
    "userText": "用户原话",
    "locationName": "用户明确说出的城市或当前位置"
  }
}
```

7. 如果已经拿到明确经纬度，可以直接传 `latitude` / `longitude` 或 `lat` / `lon`。
8. 如果聊天侧已经拿到星图数据，可以传 `mode=overview` 和轻量 payload。
9. 用户追问某个星体时，可以再次渲染同一页并传 `mode=detail` 与 `selectedObject`。
10. 页面内按钮、ASR 按钮和目标卡片由 `pages/index/index.ink` 自己通过 `bindtap` 调用页面事件。

---

## UI Mode Rules

`pages/index/index.ink` 支持以下模式：

* `home`: 首页，引导用户说出地点或观星问题。
* `chat`: 对话态，表示正在听或正在处理。
* `loading`: 加载态，表示正在解析地点或请求星图。
* `overview`: 星图总览，展示推荐观测目标。
* `detail`: 星体详情，展示某个星体的信息。
* `locate`: 寻找步骤，告诉用户往哪个方向看。
* `error`: 错误或兜底状态。

页面是单页面多状态。不要拆多个页面，除非明确要求。

状态切换必须保证同一时间只有一个主 screen 显示。推荐使用 `ink:if` 或强互斥布尔状态，避免多个 absolute panel 重叠。

---

## ASR Rules

ASR 必须严格按 Rokid 官方 sample 的模式实现。

### Allowed ASR Pattern

1. 只使用全局 `SpeechRecognition`。
2. ASR 可用性检测只能使用：

```js
return typeof SpeechRecognition !== 'undefined';
```

3. 每一轮合法 ASR turn 必须由唯一入口启动：

```js
beginVoiceTurn(source, keyword)
```

4. `beginVoiceTurn(source, keyword)` 必须先检查：

```js
if (this.data.isBusy || this.currentTurnId) {
  return;
}
```

5. 只有确认没有进行中的 ASR turn 后，才允许调用 `bindRecognition()`。
6. `bindRecognition()` 内部可以先调用 `disposeRecognition()` 清理旧实例，然后创建本轮唯一实例：

```js
const recognition = new SpeechRecognition();
```

7. recognition 配置只保留官方 sample 风格：

```js
recognition.lang = 'zh-CN';
recognition.continuous = false;
recognition.interimResults = true;
recognition.maxAlternatives = 1;
```

8. `onVoiceWakeup(event)` 只能调用：

```js
const keyword = event && event.keyword ? event.keyword : '';
this.beginVoiceTurn('wakeup', keyword);
```

9. 手动 ASR 按钮只能调用：

```js
this.beginVoiceTurn('manual-asr', 'manual-asr');
```

10. `onresult` 只允许做：

    * 提取 transcript；
    * 更新 `liveTranscript`；
    * 如果 `hasFinal`，保存 `finalTranscript`。

11. `onresult` 禁止调用：

    * `handleUserText`
    * `handleSkyQuery`
    * `loadSkyChart`
    * `fetch`
    * 任何业务逻辑

12. 业务逻辑只能在 `onend` 后触发。

13. `onend` 只做：

    * 清理 ASR idle timer；
    * release recognition；
    * 取 `finalTranscript || liveTranscript`；
    * 如果为空，回到 idle；
    * 如果有文本，调用：

```js
this.handleUserText(transcript);
```

14. `handleUserText(transcript)` 根据当前 `mode` 分流：

    * `home` / `chat` / `loading`: 解析地点并请求 sky chart；
    * `overview`: 处理用户追问，可进入 detail / locate / 简短回答；
    * `detail`: 处理当前星体相关追问；
    * `locate`: 处理寻找步骤相关追问。

15. 保留并使用以下官方 sample 风格生命周期函数：

    * `bindRecognition`
    * `disposeRecognition`
    * `cancelRecognition`
    * `clearAsrIdleTimer`

### Forbidden ASR Pattern

禁止使用或新增以下内容：

* `webkitSpeechRecognition`
* `speech.SpeechRecognition`
* `getSpeechRecognitionCandidate`
* `detail-speech`
* `debug-asr`
* `retry-asr`
* `overview-speech`
* `home-speech`
* 任何猜测式 ASR fallback
* 多个 ASR 启动入口
* 每个页面状态独立创建 ASR
* debug 页面独立启动 ASR
* detail 页面独立启动 ASR
* retry 按钮独立启动 ASR

ASR 全项目只能有一个启动入口：`beginVoiceTurn(source, keyword)`。

---

## Location Rules

1. 如果用户明确说了城市、区县或经纬度，优先使用用户提供的位置。
2. 如果运行环境提供 `get_context_param`，且用户没有给位置，可以先调用它获取智能眼镜定位。
3. 不允许使用模型服务器位置、平台服务器位置、IP 推断位置或默认城市当作用户真实位置。
4. 如果拿不到眼镜定位，也没有用户位置，要自然追问：

```text
我还没有拿到你眼镜的当前位置，你可以告诉我所在城市，或允许获取当前位置吗？
```

5. 页面可以内置少量常用城市识别，用于 Craft 和聊天调试。
6. 页面可以使用 geocoding 服务把地点名转换为经纬度。
7. 大模型可以帮助从用户语音文本里提取地点名，但不要让大模型直接编造经纬度。
8. 推荐流程：

```text
用户语音文本
↓
直接经纬度解析
↓
内置城市表
↓
大模型提取地点名
↓
geocoding 查询经纬度
↓
sky_chart 请求
```

---

## Geocoding Rules

Geocoding 的作用是把地点名转换成经纬度。

例如：

```text
厦门 → lat=24.4798, lon=118.0894
```

大模型负责理解用户说的是哪里，geocoding 负责获取准确经纬度，sky chart 负责根据经纬度计算星空。

不要让大模型硬编经纬度。

---

## Time Rules

1. 如果运行环境提供 `get_current_time`，回答前可以调用它获取当前时间。
2. 页面直接请求星图接口时，可以不主动传 `time_utc`，让星图后端使用当前时间。
3. 不要让用户自己解释复杂 UTC 时间格式。

---

## Data And Network Rules

1. 第一版不依赖 Craft 平台外部插件配置。
2. 页面主要通过 `fetch` 调用：

```text
https://sky.eunoia.top/sky/chart
```

3. 请求使用 `POST` JSON。
4. `User-Agent` 固定为：

```text
Rizon/1.0
```

5. 默认参数：

```json
{
  "star_max_mag": 3.0,
  "deep_sky_max_mag": 9.0,
  "min_altitude_deg": 15.0,
  "total_limit": 28,
  "include_planets": true,
  "include_deep_sky": true
}
```

6. `/sky/chart` 必填位置参数为 `lat` 和 `lon`。
7. 页面可以同时传 `latitude` 和 `longitude` 兼容不同后端写法。
8. 工具或网络失败时，不要报技术错误，只说：

```text
我这边暂时查不到实时数据，可以先按一般情况帮你判断。
```

9. 页面请求失败也可以展示兜底总览，但兜底逻辑必须简单，不要新增复杂 fallback 状态机。

---

## Weather Rules

1. 云量高、下雨、雾、阴天时，不建议专门观星。
2. 云量一般时，可以看看月亮和特别亮的行星，但不适合看银河或流星雨。
3. 天气晴朗、云少、能见度好时，比较适合观星。
4. 城市里优先推荐月亮、明亮行星和亮星，不要轻易推荐银河。
5. 流星雨和银河需要远离城市灯光。

---

## Response Style

适合观星时，可以说：

```text
今晚条件还不错，可以看看月亮和亮行星。你可以找个灯少、视野开阔的地方，先朝西南或天空较开阔的方向看。
```

不适合观星时，可以说：

```text
今晚不太适合专门观星。云量比较高，月亮和星星可能会被挡住。如果只是散步，可以顺便抬头看看，但不建议专门出门。
```

信息不足时，可以说：

```text
我需要知道你现在的位置，才能帮你判断当地能看到什么。
```

---

## Capabilities

* `ui.render`: 渲染 AIUI 页面卡片，必须使用 `pages/index/index`。
* `page.query`: 通过页面参数传递 `mode`、`userText`、`targets`、`skyChart`、`selectedObject`。
* `get_current_time`: 如果平台提供，用于获取当前时间。
* `get_context_param`: 如果平台提供，用于获取智能眼镜上下文与定位。
* `get_weather`: 如果平台提供，用于综合天气判断。
* 页面内 `fetch`: 第一版主要数据链路，用于请求 `https://sky.eunoia.top/sky/chart`。
* 页面内 ASR: 严格按 Rokid 官方 sample，只使用全局 `SpeechRecognition`，全项目只能有一个 ASR 启动入口 `beginVoiceTurn(source, keyword)`。

---

## Configuration

* `DEFAULT_MODE`: `home`
* `DEFAULT_USER_AGENT`: `Rizon/1.0`
* `SUPPORTED_MODES`: `home`、`chat`、`loading`、`overview`、`detail`、`locate`、`error`

---

## Forbidden Changes

Codex must not make these changes unless explicitly requested:

1. Do not add new ASR fallback APIs.
2. Do not add new runtime compatibility branches.
3. Do not add detail/debug/retry ASR systems.
4. Do not change page layout when fixing ASR.
5. Do not change CSS when fixing ASR.
6. Do not change sky chart request logic when fixing ASR.
7. Do not change geocoding logic when fixing ASR.
8. Do not rewrite the whole `index.ink`.
9. Do not split the page into multiple pages.
10. Do not add new debug panels.
11. Do not add new external services without permission.
12. Do not add speculative APIs.

---

## Before Editing Code

Before making code changes, Codex must first state:

1. Which bug is being fixed.
2. Which files will be edited.
3. Which functions will be edited.
4. Which files/functions will not be touched.
5. Why the patch is minimal.

If the requested change is ASR-related, Codex must explicitly confirm:

```text
I will only use global SpeechRecognition and will not add runtime fallback.
```

Then edit code.
