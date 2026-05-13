#!/usr/bin/env python3
"""BlueZ auto-pairing agent — accepts all connections without user interaction."""

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

AGENT_IFACE = "org.bluez.Agent1"
AGENT_PATH = "/org/bluez/agent"
MANAGER_IFACE = "org.bluez.AgentManager1"


class AutoAcceptAgent(dbus.service.Object):
    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        print(f"[agent] Authorizing service {uuid} for {device}")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        return "0000"

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        return dbus.UInt32(0)

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        print(f"[agent] Passkey: {passkey:06d}")

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        print(f"[agent] Pin: {pincode}")

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        print(f"[agent] Auto-confirming passkey {passkey:06d} for {device}")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        print(f"[agent] Auto-authorizing {device}")

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        pass


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    agent = AutoAcceptAgent(bus, AGENT_PATH)

    manager = dbus.Interface(
        bus.get_object("org.bluez", "/org/bluez"),
        MANAGER_IFACE,
    )
    manager.RegisterAgent(AGENT_PATH, "NoInputNoOutput")
    manager.RequestDefaultAgent(AGENT_PATH)

    print("[agent] Running — auto-accepting all Bluetooth connections")
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
