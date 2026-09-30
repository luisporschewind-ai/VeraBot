"""天气工具：Open-Meteo 地理编码 + 天气预报（免费、无需 Key）。
Open-Meteo 失败（如 429 限流）时自动降级到 wttr.in（同样免 Key）。"""
import asyncio
import logging
import time

import httpx

from .registry import ToolContext, tool

WMO = {0: "晴", 1: "大部晴朗", 2: "局部多云", 3: "阴", 45: "雾", 48: "雾凇", 51: "小毛毛雨", 53: "毛毛雨",
       55: "大毛毛雨", 61: "小雨", 63: "中雨", 65: "大雨", 66: "冻雨", 67: "强冻雨", 71: "小雪", 73: "中雪",
       75: "大雪", 77: "雪粒", 80: "阵雨", 81: "中阵雨", 82: "强阵雨", 85: "阵雪", 86: "强阵雪",
       95: "雷暴", 96: "雷暴伴冰雹", 99: "强雷暴伴冰雹"}


_CACHE: dict[str, tuple[float, dict]] = {}  # 简单内存缓存，降低免费 API 限流（429）风险
_TTL = 600


async def _get_json(client: httpx.AsyncClient, url: str, params: dict) -> dict:
    key = url + "?" + "&".join(f"{k}={v}" for k, v in sorted(params.items()))
    hit = _CACHE.get(key)
    if hit and time.time() - hit[0] < _TTL:
        return hit[1]
    for attempt in range(3):
        r = await client.get(url, params=params)
        if r.status_code == 429 and attempt < 2 and "Daily" not in r.text:
            await asyncio.sleep(1.5 * (attempt + 1))
            continue
        r.raise_for_status()
        data = r.json()
        _CACHE[key] = (time.time(), data)
        return data
    raise RuntimeError("unreachable")


async def _geocode(client: httpx.AsyncClient, city: str):
    for name in dict.fromkeys([city, city.rstrip("市")]):
        data = await _get_json(client, "https://geocoding-api.open-meteo.com/v1/search",
                               {"name": name, "count": 1, "language": "zh", "format": "json"})
        res = data.get("results") or []
        if res:
            return res[0]
    return None


@tool("get_weather", "查询某个城市的实时天气和未来 3 天预报。city 用城市名，例如 石家庄 / Beijing。",
      {"type": "object", "properties": {"city": {"type": "string", "description": "城市名"}}, "required": ["city"]})
async def get_weather(ctx: ToolContext, city: str):
    try:
        return await _weather(city)
    except httpx.HTTPError as primary:
        try:
            return await _wttr(city)
        except Exception as fallback:
            logging.getLogger("verabot.tools").warning("weather fallback failed: %r (primary %r)", fallback, primary)
            code = getattr(getattr(primary, "response", None), "status_code", None)
            return {"error": "天气服务限流，请稍后再试" if code == 429 else f"天气服务不可用：{type(primary).__name__}"}


async def _wttr(city: str):
    """备用数据源 wttr.in（JSON 格式 j1）。"""
    async with httpx.AsyncClient(timeout=12) as client:
        d = await _get_json(client, f"https://wttr.in/{city.strip()}", {"format": "j1", "lang": "zh"})
    cur = d["current_condition"][0]
    desc = lambda x: ((x.get("lang_zh") or x.get("weatherDesc") or [{}])[0].get("value", "")).strip()
    labels = ["今天", "明天", "后天"]
    days = [{"date": w["date"], "label": labels[i] if i < 3 else "", "weather": desc(w["hourly"][4]),
             "max_c": float(w["maxtempC"]), "min_c": float(w["mintempC"]),
             "precip_prob": max(int(h.get("chanceofrain", 0)) for h in w["hourly"])}
            for i, w in enumerate(d.get("weather", []))]
    area = d.get("nearest_area", [{}])[0]
    region = (area.get("region") or [{}])[0].get("value", "")
    return {"location": f"{region} {city}".strip(), "country": (area.get("country") or [{}])[0].get("value"),
            "current": {"time": cur.get("localObsDateTime"), "temp_c": float(cur["temp_C"]),
                        "feels_like_c": float(cur["FeelsLikeC"]), "humidity": int(cur["humidity"]),
                        "wind_kmh": float(cur["windspeedKmph"]), "weather": desc(cur)},
            "forecast": days, "source": "wttr.in（Open-Meteo 不可用时的备用源）"}


async def _weather(city: str):
    async with httpx.AsyncClient(timeout=10) as client:
        geo = await _geocode(client, city.strip())
        if not geo:
            return {"error": f"找不到城市：{city}"}
        d = await _get_json(client, "https://api.open-meteo.com/v1/forecast", {
            "latitude": geo["latitude"], "longitude": geo["longitude"], "timezone": "auto", "forecast_days": 3,
            "current": "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        })
    cur, daily = d.get("current", {}), d.get("daily", {})
    labels = ["今天", "明天", "后天"]
    days = [{"date": daily["time"][i], "label": labels[i] if i < 3 else "", "weather": WMO.get(daily["weather_code"][i], str(daily["weather_code"][i])),
             "max_c": daily["temperature_2m_max"][i], "min_c": daily["temperature_2m_min"][i],
             "precip_prob": (daily.get("precipitation_probability_max") or [None] * 3)[i]}
            for i in range(len(daily.get("time", [])))]
    return {"location": f'{geo.get("admin1", "")} {geo["name"]}'.strip(), "country": geo.get("country"),
            "current": {"time": cur.get("time"), "temp_c": cur.get("temperature_2m"),
                        "feels_like_c": cur.get("apparent_temperature"),
                        "humidity": cur.get("relative_humidity_2m"),
                        "wind_kmh": cur.get("wind_speed_10m"),
                        "weather": WMO.get(cur.get("weather_code"), str(cur.get("weather_code")))},
            "forecast": days, "source": "Open-Meteo"}
