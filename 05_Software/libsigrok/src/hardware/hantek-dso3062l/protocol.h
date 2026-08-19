/*
 * This file is part of the libsigrok project.
 *
 * Copyright (C) 2026 DDP Engineering
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef LIBSIGROK_HARDWARE_HANTEK_DSO3062L_PROTOCOL_H
#define LIBSIGROK_HARDWARE_HANTEK_DSO3062L_PROTOCOL_H

#include <stdint.h>
#include <glib.h>
#include <libsigrok/libsigrok.h>
#include "libsigrok-internal.h"

#define LOG_PREFIX "hantek-dso3062l"

/*
 * The DSO-3062L is a mixed-signal instrument: a two-channel 60 MHz
 * oscilloscope with a sixteen-channel logic pod.
 *
 * It is not a variant of the hantek-dso driver. That driver serves the older
 * DSO-2xxx/5xxx boxes, which enumerate as a bare Cypress FX2 (04b4:xxxx) and
 * become 04b5:xxxx only after libsigrok uploads their firmware. This device
 * carries its own firmware, appears directly as 04b5:3062, and speaks an
 * entirely different command set. Only the USB plumbing matches:
 * configuration 1, interface 0, bulk OUT 0x02 and bulk IN 0x86.
 */
#define DSO3062L_VID			0x04b5
#define DSO3062L_PID			0x3062

#define DSO3062L_USB_CONFIGURATION	1
#define DSO3062L_USB_INTERFACE		0

#define DSO3062L_EP_OUT			0x02
#define DSO3062L_EP_IN			0x86

/* Both bulk endpoints are 512 bytes, which is why MXE's libusb RAW_IO patch
 * matters to this device: it applies to transfers divisible by 512. */
#define DSO3062L_EP_PACKET_SIZE		512

/* Vendor control requests. */
#define DSO3062L_CTRL_GETSPEED		0xb2
#define DSO3062L_CTRL_BEGINCOMMAND	0xb3

/* CTRL_GETSPEED returns a single byte; 0x01 means high speed. */
#define DSO3062L_SPEED_HIGH		0x01

/*
 * Every bulk command is preceded by this fixed control transfer. The payload
 * is a constant taken from the vendor DLL; its fields are not understood and
 * do not vary with the command that follows.
 */
#define DSO3062L_BEGIN_PAYLOAD_LEN	10

/* Command opcodes, byte 0 of the bulk OUT buffer. */
#define DSO3062L_CMD_FORCE_TRIGGER	0x02
#define DSO3062L_CMD_START_COLLECT	0x03
#define DSO3062L_CMD_START_TRIGGER	0x04
#define DSO3062L_CMD_GET_DATA		0x05
#define DSO3062L_CMD_GET_STATE		0x06
#define DSO3062L_CMD_SET_SAMPLERATE	0x0e
#define DSO3062L_CMD_SET_HTRIGGER_LEN	0x0f
#define DSO3062L_CMD_SET_READ_START	0x13
#define DSO3062L_CMD_SET_DAC		0x16
#define DSO3062L_CMD_GET_ADDRESS	0x17
#define DSO3062L_CMD_SET_READ_LEN	0x1b
#define DSO3062L_CMD_SET_LOGIC_THRESH	0x41
#define DSO3062L_CMD_WRITE_RELAY	0x12
#define DSO3062L_CMD_READ_RELAY		0x15
#define DSO3062L_CMD_SET_TRIGGER	0x0c
/*
 * Roll mode (continuous acquisition), decoded from the DLL's undocumented
 * dsoHT*RollMode exports and verified on hardware 2026-08-18. The command
 * is [0x19, 0, on, 0]; while it is on, 0x17 returns the live write pointer
 * and reads pull fresh data from the ring as the writer laps it.
 */
#define DSO3062L_CMD_ROLL_MODE		0x19

/*
 * 0x0c parameter values, from the SDK manual
 * (01_Documentation/SDK_3062L/Manual/SDK_HTHardDLL-EN.pdf).
 */
#define DSO3062L_SYNMODE_ANALOG		0	/* CH1, CH2 or EXT as source */
#define DSO3062L_SYNMODE_LOGIC		5	/* D0-D15 as source */
#define DSO3062L_TRIGMODE_EDGE		0
#define DSO3062L_TRIGMODE_PULSE		1
#define DSO3062L_SLOPE_RISING		0
#define DSO3062L_SLOPE_FALLING		1

/*
 * The vendor's own demo passes nVideoHsyncNumOption = 1 even when video
 * triggering is not in use, and the manual gives 1 as the minimum. Sending 0
 * is untested, so follow the demo.
 */
#define DSO3062L_VIDEO_HSYNC_MIN	1

/* 0x16 with byte 2 = 1 addresses the trigger level rather than a channel
 * position. The level is an 8-bit position, 0-255. */
#define DSO3062L_DAC_SEL_CHPOS		0
#define DSO3062L_DAC_SEL_TRIGLEVEL	1

/*
 * The analog front end's gain and coupling are a serial relay chain, not a
 * parallel register: each bit is clocked out on its own with a settling delay.
 * Bit n is addressed as (1 << (n + 3)).
 */
#define DSO3062L_RELAY_BIT_SHIFT	3
#define DSO3062L_RELAY_BITS		16
#define DSO3062L_RELAY_SETTLE_US	20000

/*
 * Relay bit 10 is CH1's AC-coupling relay, not a gain step. Proven with a
 * full-wave rectified input against a symmetric sine reference: with bit 10
 * set the signal's mean lands at zero (DC removed), with bit 12 its minimum
 * does (DC passed). The vendor's RELAYCONTROL carries coupling and volts/div
 * as independent fields serialised into the same chain, and the combination
 * of a gain bit with the coupling bit is confirmed live.
 */
#define DSO3062L_RELAY_AC_COUPLING	(1u << 10)

/*
 * CH2's slice of the relay chain, measured 2026-08-18 against the 2 Vpp
 * compensation output on CH2 in dual-channel mode. The layout mirrors CH1:
 * bits 8 and 9 are a gain pair with byte-identical behaviour (as 11 and 12
 * are for CH1) at the same 2 V = 130 counts, and bit 7 is AC coupling -
 * the all-positive compensation square's mean fell from count 193 to 129
 * with its span preserved, the same signature that identified bit 10.
 * CH2's finer gain steps, if it has them, are still hidden: they clip on a
 * 2 Vpp reference and no smaller source has been on CH2 yet.
 */
#define DSO3062L_RELAY_CH2_GAIN		(1u << 8)
#define DSO3062L_RELAY_CH2_AC		(1u << 7)


/*
 * The second 0x12 form's 24-bit word is two independent fields, decoded
 * 2026-08-18 by clearing candidate bit pairs from the working dual word and
 * watching which one phase-locked the record to CH2's edge (+1 sample on
 * every repeat):
 *
 *   bits 16-18, 21   channel field: set for dual-channel mode, clear for
 *                    CH1 alone
 *   bits 14-15       trigger-source field: 0b11 = CH1, 0b00 = CH2
 *
 * This also re-reads history: the old "CH1-only enable word" 0x00c000 was
 * never a channel enable - it is just the source-CH1 field with no dual
 * bits, which is why sweeping single bits never "enabled CH2". EXT and the
 * logic sources presumably use the remaining field values; untested.
 */
#define DSO3062L_ENABLE_DUAL		0x270000
#define DSO3062L_ENABLE_TRIGSRC_CH1	0x00c000
#define DSO3062L_ENABLE_TRIGSRC_CH2	0x000000
/* EXT: bits 14-15 clear like CH2, bit 13 set - the DLL's else-branch for
 * nTrigSource 18, verified by unlocked-phase captures from the EXT BNC. */
#define DSO3062L_ENABLE_TRIGSRC_EXT	0x002000

/*
 * The front end, decoded 2026-08-18: per channel,
 *
 *     gain = attenuator (relay chain) x PGA (enable-word volts/div group)
 *
 * The attenuator is two series /10 relay stages (bits 12 then 11 for CH1,
 * 8 then 9 for CH2); the PGA is a two-bit field in the enable word (bits
 * 7,6 for CH1 and 5,4 for CH2) with measured gains x1 (00), x2.544 (10)
 * and x5.033 (01) - the instrument's 1-2-5 sequence - and 11 disconnects
 * the input, which is the hardware's GND coupling. Three attenuator
 * states times three PGA gains are the nine advertised ranges.
 *
 * One range descriptor covers both channels; each channel has its own
 * table because the calibration anchors differ. `zero_count` is the ADC
 * count of 0 V at this range's `dac`; entries marked estimated in the
 * table carry offset errors up to roughly half a division.
 */
struct dso3062l_range {
	uint64_t p, q;		/* nominal volts per division */
	int atten;		/* 0 = x1, 1 = /10, 2 = /100 */
	int pga;		/* 0 = x1, 1 = x2.544, 2 = x5.033 */
	double volts_per_count;
	double zero_count;
	uint16_t dac;
	int digits;
};

#define DSO3062L_NUM_RANGES		9
SR_PRIV extern const struct dso3062l_range
	dso3062l_ranges_ch1[DSO3062L_NUM_RANGES];
SR_PRIV extern const struct dso3062l_range
	dso3062l_ranges_ch2[DSO3062L_NUM_RANGES];

/* 500 mV/div: the range that survives the 2 Vpp compensation output. */
#define DSO3062L_RANGE_DEFAULT		5

/* Enable-word bit 12: the 20 MHz trigger-path filter (bTrigFilt / the
 * vendor UI's "HF Rejection"). */
#define DSO3062L_ENABLE_TRIGFILT	(1u << 12)

/* PGA field encodings in the enable word. */
#define DSO3062L_PGA1_X25		(1u << 7)
#define DSO3062L_PGA1_X5		(1u << 6)
#define DSO3062L_PGA1_GND		((1u << 7) | (1u << 6))
#define DSO3062L_PGA2_X25		(1u << 5)
#define DSO3062L_PGA2_X5		(1u << 4)
#define DSO3062L_PGA2_GND		((1u << 5) | (1u << 4))

/* Attenuator relay stages. */
#define DSO3062L_RELAY_CH1_ATT1		(1u << 12)
#define DSO3062L_RELAY_CH1_ATT2		(1u << 11)
#define DSO3062L_RELAY_CH2_ATT1		(1u << 8)
#define DSO3062L_RELAY_CH2_ATT2		(1u << 9)

/* Coupling, per channel: the vendor's DC=0, AC=1, GND=2. */
enum dso3062l_coupling {
	DSO3062L_COUPLING_DC = 0,
	DSO3062L_COUPLING_AC = 1,
	DSO3062L_COUPLING_GND = 2,
};

/* Capture state, low three bits of the 0x06 reply. Any of these three means
 * the ring buffer holds a complete record. */
#define DSO3062L_STATE_READY_8BIT	2
#define DSO3062L_STATE_READY_2250	3
#define DSO3062L_STATE_READY_9BIT	7

/* The sample ring is 2^24 entries - the constant 16777216.0 at 0x10008098. */
#define DSO3062L_RING_SIZE		(1 << 24)
/* 2^24 - 1025, the clamp dsoHTSetHTriggerLength applies. */
#define DSO3062L_RING_LIMIT		0xfffbff

/*
 * The record depths offered to frontends. The lower bound is the vendor's
 * own minimum record. The upper bound is the deepest record verified
 * end-to-end (16 M points, zero anomalies): the ring holds 2^24 points, but
 * a record needs its post-trigger half to fit between the trigger and the
 * ring limit, and 16 M leaves just enough of a window for the force-trigger
 * clamp to hit. Advertising the range keeps frontends from offering depths
 * the instrument cannot deliver.
 */
#define DSO3062L_MIN_SAMPLES		10240
#define DSO3062L_MAX_SAMPLES		16000000

#define DSO3062L_USB_TIMEOUT_MS		1000
#define DSO3062L_BULK_TIMEOUT_MS	800

#define DSO3062L_NUM_ANALOG_CHANNELS	2
#define DSO3062L_NUM_LOGIC_CHANNELS	16
/* Two bytes of every four-byte group, so two bytes per logic sample. */
#define DSO3062L_LOGIC_UNITSIZE		2

/*
 * Logic sample rate.
 *
 * The stream is groups of four bytes. With one analog channel enabled, slots
 * 0 and 1 carry it from two time-interleaved ADC cores, and slots 2 and 3
 * carry logic D0-D7 and D8-D15 - one byte each per group. So logic advances
 * one sample per group, at the per-slot rate of 100 MHz / (ticks + 1).
 *
 * CONFIRMED 2026-08-17 against the instrument's own 1 kHz probe-compensation
 * output on CH1, at three settings:
 *
 *     reported 200 kHz -> 200 samples per period -> 1000.0 Hz
 *     reported 500 kHz -> 500 samples per period -> 1000.0 Hz
 *     reported 1 MHz   -> 1000 samples per period -> 1000.0 Hz
 *
 * This also settles a disagreement with
 * 05_Software/protocol_probe/probe_logic.py, which uses 200 MHz / (ticks + 1)
 * and is the source of the "200 kS/s" figure in the command catalogue. That
 * is wrong by a factor of two: it would have made the 1 kHz reference measure
 * 500 Hz. It describes an analog channel's rate when it has both ADC cores;
 * logic only ever gets one slot per group.
 */
#define DSO3062L_LOGIC_BASE_CLOCK_HZ	SR_MHZ(100)

/* Where the acquisition state machine has got to. Arming is spread across
 * timer callbacks rather than done in one blocking run: the vendor sequence
 * needs roughly a second of settling, and spending that inside a single
 * callback would freeze a GUI frontend. */
enum dso3062l_acq_state {
	DSO3062L_ACQ_IDLE = 0,
	DSO3062L_ACQ_START_COLLECT,
	DSO3062L_ACQ_START_TRIGGER,
	DSO3062L_ACQ_POLL,
	DSO3062L_ACQ_READ,
	DSO3062L_ACQ_DONE,
	/* Roll (continuous) path: after the one arming sequence, stream live
	 * ring data every tick until the frontend stops. */
	DSO3062L_ACQ_ROLL_ARM,
	DSO3062L_ACQ_ROLL_STREAM,
};

/* One roll read pulls at most this many points from the ring per tick. */
#define DSO3062L_ROLL_CHUNK_POINTS	65536
/* Stay this far behind the live write pointer. Reading right up to it
 * catches points the writer has not finished, which stalls the read and
 * wedges the bulk endpoint - the guard leaves that tail alone. */
#define DSO3062L_ROLL_GUARD_POINTS	16384

struct dev_context {
	gboolean speed_verified;

	/* Configuration. */
	uint64_t samplerate;
	uint64_t limit_samples;
	double logic_threshold;
	int vdiv_index;
	int ch2_vdiv_index;
	int ch1_coupling;
	int ch2_coupling;

	/* Trigger: edge, on CH1 or CH2, at an adjustable position. */
	int trigger_slope;
	int trigger_source;
	double trigger_level;
	uint64_t capture_ratio;

	/*
	 * Software logic pattern trigger (SR_CONF_TRIGGER_MATCH). Parsed
	 * from the session's sr_trigger into per-channel bit masks and
	 * matched host-side in the captured record - full sample rate, since
	 * the hardware sampled the record; only the trigger point is found
	 * in software. Single trigger stage supported.
	 */
	gboolean sw_trig;
	uint16_t sw_level_mask;		/* channels with a 0/1 condition */
	uint16_t sw_level_value;	/* their required levels */
	uint16_t sw_rise_mask;		/* channels needing a rising edge */
	uint16_t sw_fall_mask;		/* channels needing a falling edge */
	uint16_t sw_edge_mask;		/* channels needing any edge */
	/* The 20 MHz trigger-path filter - enable-word bit 12, the
	 * vendor's "HF Rejection". Signal path is unaffected. */
	gboolean trigger_hf_reject;

	/*
	 * Continuous (roll) acquisition. When set, capture streams the live
	 * ring indefinitely instead of reading one triggered record. The
	 * frontend's Run/Stop drives it; limit_samples still caps the total
	 * if the frontend set one. `roll_addr` is the next unread ring
	 * position, `roll_forwarded` the running count.
	 */
	gboolean continuous;
	uint32_t roll_addr;
	uint64_t roll_forwarded;

	/*
	 * Factory offset calibration, read from the device: 4 channels x 9
	 * ranges x 2 words (word0 = offset DAC at position 0, word1 = DAC at
	 * full position). The center-position DAC that lands 0 V at mid-scale
	 * is word0 + 128*(word1-word0)/255 - the vendor's own per-unit data,
	 * replacing the measured DAC/zero guesses when present.
	 */
	uint16_t cal[72];
	gboolean cal_valid;

	/*
	 * What the relay chain was last programmed to, and whether it has been
	 * programmed at all. Applying a setting costs sixteen clears plus one
	 * write per set bit, each with a 20 ms settle - about a third of a
	 * second. Worth paying once; not worth paying on every capture.
	 */
	uint16_t relay_applied;
	gboolean relay_valid;

	/* Acquisition state. */
	enum dso3062l_acq_state state;
	int settle_ticks;
	int poll_ticks;

	/*
	 * Write-pointer steering. The pointer starts near zero at arm,
	 * advances at the sample rate and wraps the ring indefinitely, and
	 * 0x17 reads zero until the trigger - so its position can only be
	 * estimated from the wall clock. Tick counts are NOT usable for
	 * this: the session timer schedules each callback after the
	 * previous handler returns, so every USB transaction inflates the
	 * nominal 50 ms period and the estimate fell 200 ms behind within
	 * a second. `collect_us` is the monotonic time 0x03 started the
	 * writer; `retries` counts re-arms after a record landed outside
	 * the readable window.
	 */
	gint64 collect_us;
	int retries;
};

SR_PRIV int hantek_dso3062l_get_speed(const struct sr_dev_inst *sdi,
	uint8_t *speed);
SR_PRIV int hantek_dso3062l_read_calibration(const struct sr_dev_inst *sdi);
SR_PRIV double hantek_dso3062l_cal_dac(const struct dev_context *devc,
	int ch, int range);
SR_PRIV double hantek_dso3062l_cal_zero(const struct dev_context *devc);
SR_PRIV int hantek_dso3062l_send_cmd(const struct sr_dev_inst *sdi,
	const uint8_t *cmd, int len);
SR_PRIV int hantek_dso3062l_read(const struct sr_dev_inst *sdi,
	uint8_t *buf, int len, int *transferred);

SR_PRIV int hantek_dso3062l_set_samplerate(const struct sr_dev_inst *sdi,
	uint64_t samplerate);
SR_PRIV int hantek_dso3062l_set_htrigger_length(const struct sr_dev_inst *sdi,
	uint32_t buflen, int position);
SR_PRIV int hantek_dso3062l_set_dac(const struct sr_dev_inst *sdi,
	int channel, uint16_t value);
SR_PRIV int hantek_dso3062l_set_logic_threshold(const struct sr_dev_inst *sdi,
	double volts);
SR_PRIV int hantek_dso3062l_set_relays(const struct sr_dev_inst *sdi,
	uint16_t word);
SR_PRIV int hantek_dso3062l_set_trigger(const struct sr_dev_inst *sdi,
	int synmode, int mode, int slope);
SR_PRIV int hantek_dso3062l_set_trigger_level(const struct sr_dev_inst *sdi,
	double volts);

SR_PRIV gboolean hantek_dso3062l_depth_feasible(
	const struct dev_context *devc);
SR_PRIV int hantek_dso3062l_get_state(const struct sr_dev_inst *sdi,
	uint8_t *state);
SR_PRIV int hantek_dso3062l_configure(const struct sr_dev_inst *sdi);
SR_PRIV void hantek_dso3062l_parse_trigger(const struct sr_dev_inst *sdi);
SR_PRIV int hantek_dso3062l_read_samples(const struct sr_dev_inst *sdi);
SR_PRIV int hantek_dso3062l_roll_mode(const struct sr_dev_inst *sdi,
	gboolean on);
SR_PRIV int hantek_dso3062l_roll_read(const struct sr_dev_inst *sdi);
SR_PRIV int hantek_dso3062l_receive_data(int fd, int revents, void *cb_data);

SR_PRIV uint32_t hantek_dso3062l_ticks_for_rate(uint64_t samplerate);

#endif
