/**
 * @name 示例源·Apple 试听
 * @description 洛雪 iOS 内置演示源，返回 Apple 官方 30 秒试听链接
 * @version 1.0.0
 * @author LX Music iOS
 * @homepage https://github.com/lyswhut/lx-music-desktop
 *
 * 这是一份完全遵循 LX Music《自定义源脚本编写说明》的示例：
 *   - 脚本只负责提供 musicUrl / lyric / pic，不负责搜索
 *   - 换成任意现成的洛雪音源脚本，即可播放对应平台的完整歌曲
 */

const { EVENT_NAMES, on, send, request, env } = globalThis.lx

const httpRequest = (url, options) => new Promise((resolve, reject) => {
  request(url, options || {}, (err, resp) => {
    if (err) return reject(err)
    resolve(resp.body)
  })
})

const lookupPreview = (musicInfo) => {
  const id = musicInfo.trackId || musicInfo.songId || (musicInfo.meta && musicInfo.meta.songId)
  if (!id) return Promise.reject('缺少歌曲 ID，无法查询试听链接')
  return httpRequest('https://itunes.apple.com/lookup?id=' + encodeURIComponent(String(id)) + '&entity=song&country=cn')
    .then(body => {
      const data = JSON.parse(body)
      const item = (data.results || [])[0]
      if (item && item.previewUrl) return item.previewUrl
      throw new Error('该歌曲没有可用的试听链接')
    })
}

on(EVENT_NAMES.request, ({ source, action, info }) => {
  const m = info.musicInfo || {}
  switch (action) {
    case 'musicUrl':
      if (m.previewUrl) return Promise.resolve(m.previewUrl)
      if (m.url && String(m.url).indexOf('http') === 0) return Promise.resolve(m.url)
      if (m.musicUrl && String(m.musicUrl).indexOf('http') === 0) return Promise.resolve(m.musicUrl)
      return lookupPreview(m)

    case 'pic':
      return Promise.resolve(m.artworkUrl100 || m.picUrl || (m.meta && m.meta.picUrl) || '')

    case 'lyric':
      return Promise.resolve({ lyric: '', tlyric: null, rlyric: null, lxlyric: null })

    default:
      return Promise.reject('action not support: ' + action)
  }
})

send(EVENT_NAMES.inited, {
  status: true,
  openDevTools: false,
  sources: {
    itunes: {
      name: 'Apple 试听',
      type: 'music',
      actions: ['musicUrl', 'pic', 'lyric'],
      qualitys: ['128k'],
    },
    local: {
      name: '本地音乐',
      type: 'music',
      actions: ['musicUrl', 'lyric', 'pic'],
      qualitys: [],
    },
  },
})
