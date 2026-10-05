// Shared between the daemon, the HIPChargeTM tweak and the Control Center modules.
// The daemon owns the state and publishes it as the notify state of HIPCHARGE_STATE
// (posting the same name on every change). Control Center modules run as mobile in
// SpringBoard and can't write the thermal prefs, so they post one of the commands instead.
#ifndef hipcharge_ipc_h
#define hipcharge_ipc_h

#define HIPCHARGE_STATE "com.supremeinspirit.hipcharge.state"
#define HIPCHARGE_STATE_VALID    (1ULL << 0) // set once the daemon has published
#define HIPCHARGE_STATE_ENABLED  (1ULL << 1) // HIPCharge reacts to plug/unplug
#define HIPCHARGE_STATE_SIMULATE (1ULL << 2) // Simulate HIP is on

#define HIPCHARGE_CMD_ENABLE   "com.supremeinspirit.hipcharge.cmd.enable"
#define HIPCHARGE_CMD_DISABLE  "com.supremeinspirit.hipcharge.cmd.disable"
#define HIPCHARGE_CMD_SIM_ON   "com.supremeinspirit.hipcharge.cmd.simulate-on"
#define HIPCHARGE_CMD_SIM_OFF  "com.supremeinspirit.hipcharge.cmd.simulate-off"

#endif /* hipcharge_ipc_h */
