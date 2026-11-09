import Gio from 'gi://Gio'

import * as Main from 'resource:///org/gnome/shell/ui/main.js'

import { Extension }                    from 'resource:///org/gnome/shell/extensions/extension.js'
import { QuickToggle, SystemIndicator } from 'resource:///org/gnome/shell/ui/quickSettings.js'

const UNIT         = 'lid-inhibit.service'
const BUS_NAME     = 'org.freedesktop.systemd1'
const MANAGER_PATH = '/org/freedesktop/systemd1'

const ALREADY_SUBSCRIBED = 'org.freedesktop.systemd1.AlreadySubscribed'
const NOT_SUBSCRIBED     = 'org.freedesktop.systemd1.NotSubscribed'

const IDLE_SUBTITLE        = 'Suspend'
const UNAVAILABLE_SUBTITLE = 'Unavailable'

const SUBTITLES = {
  active       : 'Stay Awake',
  activating   : 'Stay Awake…',
  deactivating : 'Suspend…',
  failed       : 'Failed'
}

const CHECKED_STATES = [ 'active', 'activating' ]

const ManagerProxy = Gio.DBusProxy.makeProxyWrapper(`
<node>
  <interface name="org.freedesktop.systemd1.Manager">
    <method name="Subscribe"/>
    <method name="Unsubscribe"/>
    <method name="LoadUnit">
      <arg type="s" direction="in"/>
      <arg type="o" direction="out"/>
    </method>
    <method name="StartUnit">
      <arg type="s" direction="in"/>
      <arg type="s" direction="in"/>
      <arg type="o" direction="out"/>
    </method>
    <method name="StopUnit">
      <arg type="s" direction="in"/>
      <arg type="s" direction="in"/>
      <arg type="o" direction="out"/>
    </method>
  </interface>
</node>`)

const UnitProxy = Gio.DBusProxy.makeProxyWrapper(`
<node>
  <interface name="org.freedesktop.systemd1.Unit">
    <property name="LoadState"   type="s" access="read"/>
    <property name="ActiveState" type="s" access="read"/>
  </interface>
</node>`)

const sessionProxy = (Proxy, path, cancellable) =>
  Proxy.newAsync(Gio.DBus.session, BUS_NAME, path, cancellable)

const ignoringRemoteError = (name, promise) =>
  promise.catch(error => {
    if (Gio.DBusError.get_remote_error(error) !== name) {
      throw error
    }
  })

export default class LidInhibitExtension extends Extension {
  enable() {
    this._cancellable = new Gio.Cancellable()

    this._toggle = new QuickToggle({
      title    : 'Lid Close',
      subtitle : IDLE_SUBTITLE,
      iconName : 'computer-symbolic'
    })

    this._indicator = new SystemIndicator()
    this._indicator.quickSettingsItems.push(this._toggle)

    this._clickedId = this._toggle.connect('clicked', () => {
      this._request(!this._toggle.checked)
    })

    Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator)

    this._track()
  }

  disable() {
    this._cancellable?.cancel()

    if (this._changedId) {
      this._unit.disconnect(this._changedId)
    }

    if (this._manager) {
      ignoringRemoteError(NOT_SUBSCRIBED, this._manager.UnsubscribeAsync())
        .catch(console.error)
    }

    if (this._clickedId) {
      this._toggle.disconnect(this._clickedId)
    }

    this._indicator?.quickSettingsItems.forEach(item => item.destroy())
    this._indicator?.destroy()

    this._cancellable = null
    this._changedId   = 0
    this._clickedId   = 0
    this._unit        = null
    this._manager     = null
    this._toggle      = null
    this._indicator   = null
  }

  async _track() {
    const cancellable = this._cancellable

    try {
      const manager = await sessionProxy(ManagerProxy, MANAGER_PATH, cancellable)

      await ignoringRemoteError(ALREADY_SUBSCRIBED, manager.SubscribeAsync(cancellable))

      const [ unitPath ] = await manager.LoadUnitAsync(UNIT, cancellable)
      const unit         = await sessionProxy(UnitProxy, unitPath, cancellable)

      if (cancellable.is_cancelled()) {
        return
      }

      this._manager   = manager
      this._unit      = unit
      this._changedId = unit.connect('g-properties-changed', () => this._sync())

      this._sync()
    }
    catch (error) {
      if (cancellable.is_cancelled()) {
        return
      }

      console.error(error)

      this._markUnavailable()
    }
  }

  _sync() {
    if (!this._unit || !this._toggle) {
      return
    }

    if (this._unit.LoadState !== 'loaded') {
      this._markUnavailable()
      return
    }

    const state = this._unit.ActiveState

    this._toggle.reactive = true
    this._toggle.checked  = CHECKED_STATES.includes(state)
    this._toggle.subtitle = SUBTITLES[state] ?? IDLE_SUBTITLE
  }

  _markUnavailable() {
    this._toggle.reactive = false
    this._toggle.checked  = false
    this._toggle.subtitle = UNAVAILABLE_SUBTITLE
  }

  _request(inhibited) {
    const requested = inhibited
      ? this._manager?.StartUnitAsync(UNIT, 'replace')
      : this._manager?.StopUnitAsync(UNIT, 'replace')

    requested?.catch(console.error)
  }
}
