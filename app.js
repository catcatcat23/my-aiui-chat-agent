export default {
  onLaunch(options) {
    console.log('[SkyMate] App Launch', options || {})
  },

  onShow(options) {
    console.log('[SkyMate] App Show', options || {})
  },

  onHide() {
    console.log('[SkyMate] App Hide')
  },

  onError(error) {
    console.log('[SkyMate] App Error', error)
  },

  globalData: {
    appName: 'SkyMate',
    defaultObject: 'moon',
    supportedObjects: ['moon', 'jupiter', 'venus', 'mars', 'sirius', 'orion', 'meteor']
  }
}
