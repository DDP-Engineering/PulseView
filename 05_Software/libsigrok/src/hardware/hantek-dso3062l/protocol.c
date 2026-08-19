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

#include <config.h>
#include <string.h>
#include <libusb.h>
#include "protocol.h"

/*
 * Fixed preamble sent as a vendor control transfer before every bulk command.
 * Taken verbatim from the vendor DLL; the individual fields are not
 * understood, and it does not vary with the command that follows.
 */
static const uint8_t begin_payload[DSO3062L_BEGIN_PAYLOAD_LEN] = {
	0x0f, 0x03, 0x03, 0x03, 0x68, 0xac, 0xfe, 0x00, 0x01, 0x00,
};

/*
 * The nine ranges per channel: attenuator (x1, /10, /100) times PGA (x1,
 * x2.544, x5.033), nominal 1-2-5 labels 10 mV/div to 5 V/div.
 *
 * Volts-per-count anchors: /10+x1 = 2 V / 130 counts against the
 * compensation output (the strongest measurement); the fine path is that
 * divided by the measured stage ratio 9.5, the /100 path times the
 * measured second-stage ratio 8.65 (2 V spanning 15 counts). PGA steps
 * divide by the factors measured with per-step DAC re-centring.
 *
 * Zero counts: CH1's come from compensation-output minima (its low level
 * is ground) captured per PGA state at DAC 512 - measured for seven of
 * nine ranges, the /10 PGA variants interpolated from the same pattern.
 * CH2's fine zero comes from the same method at DAC 200 (its zero sits at
 * the top rail at DAC 512); its PGA-variant zeros are ESTIMATED from the
 * offset-scaling arithmetic and may be off by ten to twenty counts, i.e.
 * up to roughly half a division. Refining them needs a comp-style
 * ground-referenced source captured on CH2 at each range.
 */
SR_PRIV const struct dso3062l_range
		dso3062l_ranges_ch1[DSO3062L_NUM_RANGES] = {
	/* p, q, atten, pga, volts/count, zero, dac, digits */
	{ 10, 1000, 0, 2, 0.001620 / 5.033, 65.0, 512, 5 },
	{ 20, 1000, 0, 1, 0.001620 / 2.544, 104.0, 512, 4 },
	{ 50, 1000, 0, 0, 0.001620, 120.0, 512, 4 },
	{ 100, 1000, 1, 2, 0.015385 / 5.033, 70.0, 512, 4 },
	{ 200, 1000, 1, 1, 0.015385 / 2.544, 105.0, 512, 3 },
	{ 500, 1000, 1, 0, 0.015385, 119.0, 512, 3 },
	{ 1, 1, 2, 2, 0.133 / 5.033, 75.0, 512, 3 },
	{ 2, 1, 2, 1, 0.133 / 2.544, 107.0, 512, 2 },
	{ 5, 1, 2, 0, 0.133, 120.0, 512, 2 },
};

SR_PRIV const struct dso3062l_range
		dso3062l_ranges_ch2[DSO3062L_NUM_RANGES] = {
	/* p, q, atten, pga, volts/count, zero, dac, digits */
	{ 10, 1000, 0, 2, 0.001620 / 5.033, 90.0, 350, 5 },
	{ 20, 1000, 0, 1, 0.001620 / 2.544, 100.0, 300, 4 },
	{ 50, 1000, 0, 0, 0.001620, 43.0, 200, 4 },
	{ 100, 1000, 1, 2, 0.015385 / 5.033, 78.0, 300, 4 },
	{ 200, 1000, 1, 1, 0.015385 / 2.544, 105.0, 400, 3 },
	{ 500, 1000, 1, 0, 0.015385, 128.0, 512, 3 },
	{ 1, 1, 2, 2, 0.133 / 5.033, 78.0, 300, 3 },
	{ 2, 1, 2, 1, 0.133 / 2.544, 105.0, 400, 2 },
	{ 5, 1, 2, 0, 0.133, 128.0, 512, 2 },
};

SR_PRIV int hantek_dso3062l_get_speed(const struct sr_dev_inst *sdi,
	uint8_t *speed)
{
	struct sr_usb_dev_inst *usb;
	uint8_t buf;
	int ret;

	usb = sdi->conn;

	ret = libusb_control_transfer(usb->devhdl,
		LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR
			| LIBUSB_RECIPIENT_DEVICE,
		DSO3062L_CTRL_GETSPEED, 0, 0, &buf, sizeof(buf),
		DSO3062L_USB_TIMEOUT_MS);

	if (ret < 0) {
		sr_err("Failed to read device speed: %s.",
			libusb_error_name(ret));
		return SR_ERR;
	}
	if (ret != sizeof(buf)) {
		sr_err("Short read for device speed: %d byte(s).", ret);
		return SR_ERR;
	}

	*speed = buf;

	return SR_OK;
}

/*
 * Read the factory offset calibration.
 *
 * A vendor control-IN transfer (request 0xa2, wValue 0x1900, wIndex 1),
 * decoded from dsoHTReadCalibrationData -> sub_10003c70. Returns 72 little-
 * endian words: 4 channels x 9 ranges x (word0, word1), the offset-DAC
 * endpoints for position 0 and full. Unpopulated channels read 0xffff (this
 * is a two-channel instrument, so CH3/CH4 are absent). A read failure is not
 * fatal - the driver falls back to the measured constants.
 */
#define DSO3062L_CAL_REQUEST	0xa2
#define DSO3062L_CAL_VALUE	0x1900
#define DSO3062L_CAL_WORDS	72

SR_PRIV int hantek_dso3062l_read_calibration(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	struct sr_usb_dev_inst *usb = sdi->conn;
	uint8_t buf[DSO3062L_CAL_WORDS * 2];
	int ret, i;

	devc->cal_valid = FALSE;
	ret = libusb_control_transfer(usb->devhdl,
		LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR
			| LIBUSB_RECIPIENT_DEVICE,
		DSO3062L_CAL_REQUEST, DSO3062L_CAL_VALUE, 1, buf, sizeof(buf),
		DSO3062L_USB_TIMEOUT_MS);
	if (ret != (int)sizeof(buf)) {
		sr_warn("Factory calibration read returned %d; using measured "
			"constants instead.", ret);
		return SR_ERR;
	}

	for (i = 0; i < DSO3062L_CAL_WORDS; i++)
		devc->cal[i] = buf[i * 2] | (buf[i * 2 + 1] << 8);

	/* CH1 range 0 word0 = 0xffff would mean no calibration present. */
	if (devc->cal[0] == 0xffff) {
		sr_warn("Factory calibration is blank; using measured "
			"constants.");
		return SR_ERR;
	}

	devc->cal_valid = TRUE;
	sr_info("Factory offset calibration loaded.");

	return SR_OK;
}

/*
 * The center-position offset DAC for a channel (0 or 1) and range (0-8):
 * word0 + 128*(word1-word0)/255, from the SetCHPos formula (K = 1/255).
 * Positions ground at mid-scale, so 0 V reads at ADC count 128.
 */
SR_PRIV double hantek_dso3062l_cal_dac(const struct dev_context *devc,
	int ch, int range)
{
	int idx = 9 * ch + range;
	double w0 = devc->cal[2 * idx];
	double w1 = devc->cal[2 * idx + 1];

	return w0 + 128.0 * (w1 - w0) / 255.0;
}

/* With the center-position DAC set, ground sits at ADC mid-scale. */
SR_PRIV double hantek_dso3062l_cal_zero(const struct dev_context *devc)
{
	(void)devc;
	return 128.0;
}

/*
 * Every command is a control transfer carrying the fixed preamble, followed
 * by the actual opcode buffer on the bulk OUT endpoint. Skipping the control
 * transfer makes the device ignore the bulk write silently.
 */
SR_PRIV int hantek_dso3062l_send_cmd(const struct sr_dev_inst *sdi,
	const uint8_t *cmd, int len)
{
	struct sr_usb_dev_inst *usb;
	int ret, transferred;

	usb = sdi->conn;

	ret = libusb_control_transfer(usb->devhdl,
		LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR
			| LIBUSB_RECIPIENT_DEVICE,
		DSO3062L_CTRL_BEGINCOMMAND, 0, 0,
		(unsigned char *)begin_payload, sizeof(begin_payload),
		DSO3062L_USB_TIMEOUT_MS);
	if (ret < 0) {
		sr_err("BEGINCOMMAND failed for opcode 0x%02x: %s.",
			cmd[0], libusb_error_name(ret));
		return SR_ERR;
	}

	ret = libusb_bulk_transfer(usb->devhdl, DSO3062L_EP_OUT,
		(unsigned char *)cmd, len, &transferred,
		DSO3062L_USB_TIMEOUT_MS);
	if (ret < 0) {
		sr_err("Failed to send opcode 0x%02x: %s.",
			cmd[0], libusb_error_name(ret));
		return SR_ERR;
	}
	if (transferred != len) {
		sr_err("Short write for opcode 0x%02x: %d of %d bytes.",
			cmd[0], transferred, len);
		return SR_ERR;
	}

	return SR_OK;
}

SR_PRIV int hantek_dso3062l_read(const struct sr_dev_inst *sdi,
	uint8_t *buf, int len, int *transferred)
{
	struct sr_usb_dev_inst *usb;
	int ret;

	usb = sdi->conn;

	ret = libusb_bulk_transfer(usb->devhdl, DSO3062L_EP_IN,
		buf, len, transferred, DSO3062L_BULK_TIMEOUT_MS);
	if (ret < 0) {
		sr_dbg("Bulk read failed: %s.", libusb_error_name(ret));
		return SR_ERR;
	}

	return SR_OK;
}

SR_PRIV int hantek_dso3062l_get_state(const struct sr_dev_inst *sdi,
	uint8_t *state)
{
	uint8_t cmd[2] = { DSO3062L_CMD_GET_STATE, 0x00 };
	uint8_t buf[DSO3062L_EP_PACKET_SIZE];
	int ret, transferred;

	ret = hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
	if (ret != SR_OK)
		return ret;

	ret = hantek_dso3062l_read(sdi, buf, sizeof(buf), &transferred);
	if (ret != SR_OK || transferred < 1)
		return SR_ERR;

	*state = buf[0] & 7;

	return SR_OK;
}

/* 0x17 returns the ring-buffer address of the capture end, 24-bit LE. */
static int get_address(const struct sr_dev_inst *sdi, uint32_t *addr)
{
	uint8_t cmd[2] = { DSO3062L_CMD_GET_ADDRESS, 0x00 };
	uint8_t buf[DSO3062L_EP_PACKET_SIZE];
	int ret, transferred;

	ret = hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
	if (ret != SR_OK)
		return ret;

	ret = hantek_dso3062l_read(sdi, buf, sizeof(buf), &transferred);
	if (ret != SR_OK || transferred < 3)
		return SR_ERR;

	*addr = buf[0] | (buf[1] << 8) | (buf[2] << 16);

	return SR_OK;
}

/*
 * The eight-byte setup buffer shared by 0x13 and 0x1b.
 *
 * Byte 6 duplicating the low byte of the value is not a mistake in this code.
 * The vendor DLL computes it with `shr eax, 0x20`, which x86-32 masks to a
 * shift of zero, so an intended 40-bit field receives the low byte instead.
 * The firmware tolerates it. Reproduce it rather than "correcting" it.
 */
static int send_addr_cmd(const struct sr_dev_inst *sdi, uint8_t opcode,
	uint32_t value, uint8_t last)
{
	uint8_t cmd[8];

	cmd[0] = opcode;
	cmd[1] = 0x00;
	cmd[2] = value & 0xff;
	cmd[3] = (value >> 8) & 0xff;
	cmd[4] = (value >> 16) & 0xff;
	cmd[5] = (value >> 24) & 0xff;
	cmd[6] = value & 0xff;
	cmd[7] = last;

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * Sample rate is expressed as a tick divider. The vendor jump table holds the
 * clean 1-2-5 sequence 1, 4, 9, 19, 49, 99, 199, 499, 999 and so on, which is
 * simply (base / rate) - 1.
 */
SR_PRIV uint32_t hantek_dso3062l_ticks_for_rate(uint64_t samplerate)
{
	uint64_t ticks;

	if (samplerate == 0 || samplerate > DSO3062L_LOGIC_BASE_CLOCK_HZ)
		return 0;

	ticks = (DSO3062L_LOGIC_BASE_CLOCK_HZ / samplerate);
	if (ticks == 0)
		return 0;

	return (uint32_t)(ticks - 1);
}

SR_PRIV int hantek_dso3062l_set_samplerate(const struct sr_dev_inst *sdi,
	uint64_t samplerate)
{
	uint8_t cmd[12];
	uint32_t ticks, v;

	ticks = hantek_dso3062l_ticks_for_rate(samplerate);
	/* The divider goes on the wire negated. */
	v = (uint32_t)(-(int32_t)ticks);

	memset(cmd, 0, sizeof(cmd));
	cmd[0] = DSO3062L_CMD_SET_SAMPLERATE;
	cmd[1] = 0x00;
	/*
	 * The mode bits in byte 2 are not cosmetic. With mode 0 the divider is
	 * ignored outright and the instrument stays at full rate, which looks
	 * exactly like a sample-rate setting that did not take effect.
	 */
	cmd[2] = 3;
	cmd[3] = 0x00;
	cmd[4] = v & 0xff;
	cmd[5] = (v >> 8) & 0xff;
	cmd[6] = (v >> 16) & 0xff;
	cmd[7] = (v >> 24) & 0xff;

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * 0x0f carries two 24-bit ring pointers derived from record length and
 * trigger position. Both are offsets counted down from the ring limit, so a
 * longer record or a later trigger position moves them toward zero.
 */
SR_PRIV int hantek_dso3062l_set_htrigger_length(const struct sr_dev_inst *sdi,
	uint32_t buflen, int position)
{
	uint8_t cmd[12];
	uint32_t a, b, pre, post;

	if (buflen > DSO3062L_RING_LIMIT)
		buflen = DSO3062L_RING_LIMIT;

	if (position >= 100) {
		a = DSO3062L_RING_LIMIT - buflen;
		b = DSO3062L_RING_LIMIT;
	} else {
		pre = (uint32_t)(position * (uint64_t)buflen / 100);
		post = (uint32_t)((100 - position) * (uint64_t)buflen / 100);
		a = (pre > DSO3062L_RING_LIMIT) ? 0 : DSO3062L_RING_LIMIT - pre;
		b = (post > DSO3062L_RING_LIMIT) ? 0 : DSO3062L_RING_LIMIT - post;
	}

	memset(cmd, 0, sizeof(cmd));
	cmd[0] = DSO3062L_CMD_SET_HTRIGGER_LEN;
	cmd[1] = 0x00;
	cmd[2] = a & 0xff;
	cmd[3] = (a >> 8) & 0xff;
	cmd[4] = (a >> 16) & 0xff;
	cmd[5] = 0x00;
	cmd[6] = b & 0xff;
	cmd[7] = (b >> 8) & 0xff;
	cmd[8] = (b >> 16) & 0xff;
	cmd[9] = 0x00;

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * 0x16 carries a 12-bit DAC word. Byte 2 selects channel position (0) or
 * trigger level (1); the high nibble of byte 5 selects which DAC. Getting the
 * selector wrong is quiet: the write is accepted and lands on channel 1.
 */
static const uint8_t dac_channel_sel[] = { 0x10, 0x50, 0x90, 0xd0 };

SR_PRIV int hantek_dso3062l_set_dac(const struct sr_dev_inst *sdi,
	int channel, uint16_t value)
{
	uint8_t cmd[8];

	if (channel < 1 || channel > (int)ARRAY_SIZE(dac_channel_sel))
		return SR_ERR_ARG;

	value &= 0xfff;

	memset(cmd, 0, sizeof(cmd));
	cmd[0] = DSO3062L_CMD_SET_DAC;
	cmd[1] = 0x00;
	cmd[2] = 0x00;
	cmd[3] = 0x00;
	cmd[4] = value & 0xff;
	cmd[5] = ((value >> 8) & 0x0f) | dac_channel_sel[channel - 1];

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * 0x41 sets the logic comparator thresholds. There are two DACs, and they do
 * not split by byte: one drives the even-numbered logic channels and the
 * other the odd, across both D0-D7 and D8-D15.
 *
 * THE CONVERSION IS MEASURED, NOT THE DLL'S. Calibrated 2026-08-18
 * against a grounded, scope-verified square on D0 (low 0.026 V, high
 * 2.431 V by CH1 on the same node): toggling begins at DAC 96 (threshold
 * crosses the low) and ceases after DAC 125 (crosses the high), giving a
 * clean linear scale of 0.080 V per count:
 *
 *     dac = 95.2 + 12.47 * volts
 *
 * The DLL's constants (121.848 - 10.8696 * volts) have the wrong sign
 * and scale for this pod; the vendor corrects them with per-pod EEPROM
 * calibration this driver does not read. This measurement IS that
 * calibration for this unit; other pods may differ by a few counts. An
 * earlier fit from an UNGROUNDED hookup was off by 2x - the pod needs a
 * proper ground return or the comparator sees mush. Volts are clamped to
 * the panel's specified -6..+6 V.
 */
#define DSO3062L_LA_ZERO_DAC		95.2
#define DSO3062L_LA_DAC_PER_VOLT	12.47

SR_PRIV int hantek_dso3062l_set_logic_threshold(const struct sr_dev_inst *sdi,
	double volts)
{
	uint8_t cmd[4];
	double dac;

	if (volts < -6.0)
		volts = -6.0;
	if (volts > 6.0)
		volts = 6.0;
	dac = DSO3062L_LA_ZERO_DAC + DSO3062L_LA_DAC_PER_VOLT * volts;
	if (dac < 0)
		dac = 0;
	if (dac > 255)
		dac = 255;

	cmd[0] = DSO3062L_CMD_SET_LOGIC_THRESH;
	cmd[1] = 0x00;
	cmd[2] = (uint8_t)(dac + 0.5);
	cmd[3] = (uint8_t)(dac + 0.5);

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * The analog front end is a serial relay chain. `dsoHTSetCHAndTrigger` reads
 * the current word with 0x15, then clocks out only the differing bits, one
 * write each with a 20 ms settle. This is that single-bit primitive.
 */
static int write_relay_bit(const struct sr_dev_inst *sdi, int bit,
	gboolean on, uint16_t target)
{
	uint8_t cmd[10];
	uint32_t v;
	int ret;

	v = 1u << (bit + DSO3062L_RELAY_BIT_SHIFT);
	if (!on)
		v = ~v;

	cmd[0] = DSO3062L_CMD_WRITE_RELAY;
	cmd[1] = 0x00;
	cmd[2] = v & 0xff;
	cmd[3] = (v >> 8) & 0xff;
	cmd[4] = v & 0xff;
	cmd[5] = (v >> 8) & 0xff;
	cmd[6] = (v >> 16) & 0xff;
	cmd[7] = 0x00;
	cmd[8] = target & 0xff;
	cmd[9] = (target >> 8) & 0xff;

	ret = hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
	if (ret != SR_OK)
		return ret;

	g_usleep(DSO3062L_RELAY_SETTLE_US);

	return SR_OK;
}

/*
 * Apply a whole relay word.
 *
 * Every bit is cleared first, individually, before the wanted ones are set.
 * That is not defensive tidiness: relay state persists across writes, and
 * clearing only the previously-set bit contaminates the next setting. The
 * command catalogue records that mistake producing a table in which eleven of
 * sixteen bits looked identical, and a set/clear pair appearing to contradict
 * itself. With a full clear first, results repeat exactly.
 */
SR_PRIV int hantek_dso3062l_set_relays(const struct sr_dev_inst *sdi,
	uint16_t word)
{
	int bit, ret;

	for (bit = 0; bit < DSO3062L_RELAY_BITS; bit++) {
		ret = write_relay_bit(sdi, bit, FALSE, 0);
		if (ret != SR_OK)
			return ret;
	}

	for (bit = 0; bit < DSO3062L_RELAY_BITS; bit++) {
		if (!(word & (1u << bit)))
			continue;
		ret = write_relay_bit(sdi, bit, TRUE, word);
		if (ret != SR_OK)
			return ret;
	}

	sr_dbg("Relay word set to 0x%04x.", word);

	return SR_OK;
}

/* CH2 is index 1 among the analog channels. */
static gboolean ch2_enabled(const struct sr_dev_inst *sdi)
{
	GSList *l;

	for (l = sdi->channels; l; l = l->next) {
		struct sr_channel *c = l->data;
		if (c->type == SR_CHANNEL_ANALOG && c->index == 1)
			return c->enabled;
	}

	return FALSE;
}

/*
 * The second 0x12 form: which channels are on, and what the trigger looks at.
 *
 * Distinguished from the bit-serial relay write by bytes 2 and 3 being zero -
 * a serial pulse carries a mask there, this direct register write does not.
 */
static int set_enable_word(const struct sr_dev_inst *sdi, uint32_t word,
	uint16_t settings)
{
	uint8_t cmd[10];

	memset(cmd, 0, sizeof(cmd));
	cmd[0] = DSO3062L_CMD_WRITE_RELAY;
	cmd[1] = 0x00;
	cmd[2] = 0x00;
	cmd[3] = 0x00;
	cmd[4] = word & 0xff;
	cmd[5] = (word >> 8) & 0xff;
	cmd[6] = (word >> 16) & 0xff;
	cmd[7] = 0x00;
	cmd[8] = settings & 0xff;
	cmd[9] = (settings >> 8) & 0xff;

	sr_dbg("Enable word 0x%06x.", word);

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * 0x0c, decoded from sub_10003fa0 in HTHardDLL.dll. The vendor export
 * dsoHTSetTriggerAndSyncOutput is a thin wrapper that pushes eleven
 * parameters at this builder, which mallocs ten bytes, packs them and writes
 * them straight to the bulk endpoint.
 *
 * Only edge triggering is wired up here. The pulse-width, video and
 * sync-output fields are packed at their documented positions and left at
 * zero, so adding them later is a matter of passing values rather than
 * working out where they go.
 *
 * Two details are worth keeping in view because neither is guessable and
 * both are easy to get wrong: byte 2 carries a trailing shift, so every field
 * in it sits one bit above its own width and bit 0 is always clear; and the
 * pulse width is 27 bits, not 32.
 */
SR_PRIV int hantek_dso3062l_set_trigger(const struct sr_dev_inst *sdi,
	int synmode, int mode, int slope)
{
	uint8_t cmd[10];
	uint32_t pulse_width;
	int pw_condition, sync, video_standard, video_sync_select;
	int la_mode, hsync;
	uint8_t b;

	/* Everything the edge path does not use. */
	pulse_width = 0;
	pw_condition = 0;
	sync = 0;
	video_standard = 0;
	video_sync_select = 0;
	la_mode = mode;
	hsync = DSO3062L_VIDEO_HSYNC_MIN;

	memset(cmd, 0, sizeof(cmd));
	cmd[0] = DSO3062L_CMD_SET_TRIGGER;
	cmd[1] = 0x00;

	b = (uint8_t)((pw_condition & 3) | ((sync & 1) << 2));
	b = (uint8_t)((b << 2) | (mode & 3));
	b = (uint8_t)((b << 2) | (slope & 3));
	cmd[2] = (uint8_t)(b << 1);

	cmd[3] = (uint8_t)(((((synmode << 3) | (video_sync_select & 7)) << 1)
		| (video_standard & 1)) & 0xff);

	cmd[4] = pulse_width & 0xff;
	cmd[5] = (pulse_width >> 8) & 0xff;
	cmd[6] = (pulse_width >> 16) & 0xff;
	cmd[7] = (pulse_width >> 24) & 7;

	cmd[8] = hsync & 0xff;
	cmd[9] = (uint8_t)(((hsync >> 8) & 3) | (la_mode << 3));

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * The trigger level shares opcode 0x16 with the per-channel offset DACs;
 * byte 2 selects which. It is an 8-bit position rather than the 12-bit word
 * the channel positions use.
 *
 * Volts are converted with the same single-point calibration the analog path
 * uses, so the level means the same thing as the values on screen - and
 * inherits the same caveat about being valid only at the default gain.
 */
SR_PRIV int hantek_dso3062l_set_trigger_level(const struct sr_dev_inst *sdi,
	double volts)
{
	const struct dso3062l_range *rng;
	struct dev_context *devc;
	uint8_t cmd[8];
	double count, dac, zero;
	int coupling;
	uint16_t v;

	devc = sdi->priv;
	if (devc->trigger_source == 1) {
		rng = &dso3062l_ranges_ch2[devc->ch2_vdiv_index];
		coupling = devc->ch2_coupling;
	} else {
		/* EXT reuses CH1's conversion: its comparator input has its
		 * own unmeasured attenuation, so EXT levels are approximate
		 * - the observed usable band matches this mapping around
		 * logic-level signals, which is what EXT normally sees. */
		rng = &dso3062l_ranges_ch1[devc->vdiv_index];
		coupling = devc->ch1_coupling;
	}
	if (coupling != DSO3062L_COUPLING_DC)
		zero = 129.0;
	else if (devc->cal_valid)
		zero = hantek_dso3062l_cal_zero(devc);
	else
		zero = rng->zero_count;

	/*
	 * The wanted ADC count, then the 12-bit DAC that puts the comparator
	 * there. 0x16 carries a DAC word, not an ADC level - the SDK's
	 * nPos 0-255 is an index the vendor maps through its calibration
	 * table, which this does not have. The mapping below comes from the
	 * three measured points in the command catalogue, DAC 256, 512 and
	 * 768 giving counts 45, 126 and 197: linear at about 3.37 DAC units
	 * per count. Volts convert to counts through the calibration of
	 * whichever channel is the trigger source; the count-to-DAC step is
	 * post-gain and should not depend on it, though it has only been
	 * measured at the default.
	 */
	count = zero + volts / rng->volts_per_count;
	dac = 256.0 + (count - 45.0) * (768.0 - 256.0) / (197.0 - 45.0);
	if (dac < 0)
		dac = 0;
	if (dac > 0xfff)
		dac = 0xfff;
	v = (uint16_t)(dac + 0.5);

	memset(cmd, 0, sizeof(cmd));
	cmd[0] = DSO3062L_CMD_SET_DAC;
	cmd[1] = 0x00;
	cmd[2] = DSO3062L_DAC_SEL_TRIGLEVEL;
	cmd[3] = 0x00;
	cmd[4] = v & 0xff;
	/* The 0x10 bit of the high nibble is always set, on every 0x16. */
	cmd[5] = (uint8_t)(((v >> 8) & 0x0f) | 0x10);

	sr_dbg("Trigger level %.3f V -> count %.0f -> DAC %u.", volts, count, v);

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

SR_PRIV int hantek_dso3062l_configure(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc;
	uint32_t enable;
	uint16_t relay_word;
	gboolean ch2_active;
	int ret, ch;

	devc = sdi->priv;

	/*
	 * The relay word is the composition of the per-channel settings:
	 * each channel's gain relay and, for AC coupling, its coupling
	 * relay on top. The vendor serialises all of RELAYCONTROL's fields
	 * into this same chain. CH2's bits go in only when CH2 is enabled,
	 * so a logic-only or CH1-only session keeps the chain minimal.
	 */
	/* CH2's front end must be live to trigger on it, whether or not the
	 * channel is displayed. */
	ch2_active = ch2_enabled(sdi) || devc->trigger_source == 1;

	/*
	 * The relay chain carries each channel's attenuator stages and its
	 * AC-coupling relay; the PGA and GND coupling ride in the enable
	 * word below.
	 */
	relay_word = 0;
	if (dso3062l_ranges_ch1[devc->vdiv_index].atten >= 1)
		relay_word |= DSO3062L_RELAY_CH1_ATT1;
	if (dso3062l_ranges_ch1[devc->vdiv_index].atten >= 2)
		relay_word |= DSO3062L_RELAY_CH1_ATT2;
	if (devc->ch1_coupling == DSO3062L_COUPLING_AC)
		relay_word |= DSO3062L_RELAY_AC_COUPLING;
	if (ch2_active) {
		if (dso3062l_ranges_ch2[devc->ch2_vdiv_index].atten >= 1)
			relay_word |= DSO3062L_RELAY_CH2_ATT1;
		if (dso3062l_ranges_ch2[devc->ch2_vdiv_index].atten >= 2)
			relay_word |= DSO3062L_RELAY_CH2_ATT2;
		if (devc->ch2_coupling == DSO3062L_COUPLING_AC)
			relay_word |= DSO3062L_RELAY_CH2_AC;
	}

	/*
	 * The order below is the vendor's CHard::Init(), and it is not
	 * cosmetic. Three separate failures traced back to getting it wrong:
	 *
	 *  - the enable word is a 0x12, and so are the bit-serial relay
	 *    writes. Sent first, it is undone by them. The vendor writes it
	 *    once, at the very end of dsoHTSetCHAndTrigger.
	 *  - 0x41 reaches the analog offset DACs through one of its other
	 *    arms, so it has to precede the 0x16 writes, not follow them.
	 *  - without a 0x16 at all, a channel sits railed and reads like a
	 *    dead datapath rather than a mis-set one.
	 */
	ret = hantek_dso3062l_set_samplerate(sdi, devc->samplerate);
	if (ret != SR_OK)
		return ret;

	ret = hantek_dso3062l_set_htrigger_length(sdi,
		(uint32_t)devc->limit_samples, (int)devc->capture_ratio);
	if (ret != SR_OK)
		return ret;

	/* A third of a second of relay settling; only when it would change. */
	if (!devc->relay_valid || devc->relay_applied != relay_word) {
		ret = hantek_dso3062l_set_relays(sdi, relay_word);
		if (ret != SR_OK)
			return ret;
		devc->relay_applied = relay_word;
		devc->relay_valid = TRUE;
	}

	/*
	 * Enabling CH2 costs CH1 its second ADC core: slot 1 stops carrying
	 * CH1's core B and carries CH2 instead, so each analog channel then
	 * samples at the group rate rather than twice it. That is the
	 * instrument's 200 MS/s budget being split, not a fault.
	 */
	enable = ch2_active ? DSO3062L_ENABLE_DUAL : 0;
	switch (devc->trigger_source) {
	case 1:
		enable |= DSO3062L_ENABLE_TRIGSRC_CH2;
		break;
	case 2:
		enable |= DSO3062L_ENABLE_TRIGSRC_EXT;
		break;
	default:
		enable |= DSO3062L_ENABLE_TRIGSRC_CH1;
		break;
	}
	if (devc->trigger_hf_reject)
		enable |= DSO3062L_ENABLE_TRIGFILT;
	/* The PGA field; 11 disconnects the input, which is GND coupling. */
	if (devc->ch1_coupling == DSO3062L_COUPLING_GND) {
		enable |= DSO3062L_PGA1_GND;
	} else {
		switch (dso3062l_ranges_ch1[devc->vdiv_index].pga) {
		case 1: enable |= DSO3062L_PGA1_X25; break;
		case 2: enable |= DSO3062L_PGA1_X5; break;
		}
	}
	if (devc->ch2_coupling == DSO3062L_COUPLING_GND) {
		enable |= DSO3062L_PGA2_GND;
	} else if (ch2_active) {
		switch (dso3062l_ranges_ch2[devc->ch2_vdiv_index].pga) {
		case 1: enable |= DSO3062L_PGA2_X25; break;
		case 2: enable |= DSO3062L_PGA2_X5; break;
		}
	}
	ret = set_enable_word(sdi, enable, 0);
	if (ret != SR_OK)
		return ret;

	ret = hantek_dso3062l_set_trigger(sdi, DSO3062L_SYNMODE_ANALOG,
		DSO3062L_TRIGMODE_EDGE, devc->trigger_slope);
	if (ret != SR_OK)
		return ret;

	ret = hantek_dso3062l_set_logic_threshold(sdi, devc->logic_threshold);
	if (ret != SR_OK)
		return ret;

	for (ch = 1; ch <= 4; ch++) {
		/*
		 * Each channel's offset rides with its range AND coupling:
		 * DC uses the range's own DAC (some ranges park their zero
		 * at a rail with the generic 512), but under AC the signal
		 * centres on the coupling network's bias, which lands at
		 * count ~129 at DAC 512 - a lowered DAC would drag an AC
		 * signal into the bottom rail instead.
		 */
		uint16_t dac = 512;
		if (ch == 1 && devc->ch1_coupling == DSO3062L_COUPLING_DC)
			dac = devc->cal_valid
				? (uint16_t)(hantek_dso3062l_cal_dac(devc, 0,
					devc->vdiv_index) + 0.5)
				: dso3062l_ranges_ch1[devc->vdiv_index].dac;
		if (ch == 2 && devc->ch2_coupling == DSO3062L_COUPLING_DC)
			dac = devc->cal_valid
				? (uint16_t)(hantek_dso3062l_cal_dac(devc, 1,
					devc->ch2_vdiv_index) + 0.5)
				: dso3062l_ranges_ch2[devc->ch2_vdiv_index].dac;
		ret = hantek_dso3062l_set_dac(sdi, ch, dac);
		if (ret != SR_OK)
			return ret;
	}

	return hantek_dso3062l_set_trigger_level(sdi, devc->trigger_level);
}

/*
 * Forward CH1 from the same record the logic channels came out of.
 *
 * Two decisions here are forced by the hardware and are worth stating,
 * because both look like sloppiness otherwise.
 *
 * ADC COUNTS, NOT VOLTS. The relay word that sets the gain ladder is only
 * partly understood - the command catalogue records bits 3, 4, 10, 11 and 12
 * as affecting gain, with the mask's exact semantics still open, and no
 * verified counts-to-volts mapping at any setting. Reporting volts would mean
 * inventing a vertical axis and labelling it authoritatively. The samples go
 * out unitless, as the 0-255 counts they are, until the ladder is calibrated.
 * The waveform's shape and timing are correct; only its vertical scale is
 * uncalibrated.
 *
 * ONE SAMPLE PER GROUP, NOT TWO. With a single analog channel enabled, slots
 * 0 and 1 are CH1 sampled by two time-interleaved ADC cores, so CH1 genuinely
 * runs at twice the group rate. A libsigrok session carries one sample rate
 * for all channels, and logic advances one sample per group, so emitting both
 * cores would make one of the two wrong. Core A alone keeps analog and logic
 * on the same timebase. Recovering the full analog rate needs a way to
 * express the 2:1 relationship that the session model does not currently
 * offer.
 *
 * Taking only core A also sidesteps the roughly 1 LSB offset mismatch between
 * the cores, which would otherwise appear as a fixed sample-to-sample jitter
 * on every edge.
 */
static void send_analog(const struct sr_dev_inst *sdi, const uint8_t *payload,
	int groups, int index)
{
	struct sr_datafeed_packet packet;
	struct sr_datafeed_analog analog;
	struct sr_analog_encoding encoding;
	struct sr_analog_meaning meaning;
	struct sr_analog_spec spec;
	struct sr_channel *ch;
	const struct dso3062l_range *rng;
	struct dev_context *devc;
	GSList *l, *chl;
	float *data;
	double zero;
	int i, coupling;

	devc = sdi->priv;
	if (index == 1) {
		rng = &dso3062l_ranges_ch2[devc->ch2_vdiv_index];
		coupling = devc->ch2_coupling;
	} else {
		rng = &dso3062l_ranges_ch1[devc->vdiv_index];
		coupling = devc->ch1_coupling;
	}
	/*
	 * DC: with the factory centre DAC set, ground is at mid-scale (128);
	 * otherwise the range's measured zero. AC/GND centre on the coupling
	 * bias at count ~129 regardless of DAC.
	 */
	if (coupling != DSO3062L_COUPLING_DC)
		zero = 129.0;
	else if (devc->cal_valid)
		zero = hantek_dso3062l_cal_zero(devc);
	else
		zero = rng->zero_count;

	ch = NULL;
	for (l = sdi->channels; l; l = l->next) {
		struct sr_channel *c = l->data;
		if (c->type == SR_CHANNEL_ANALOG && c->index == index) {
			ch = c;
			break;
		}
	}
	if (!ch || !ch->enabled)
		return;

	/*
	 * Core A only, at the group rate.
	 *
	 * Measured 2026-08-17: emitting slots 0 and 1 as consecutive samples
	 * makes the 1 kHz reference span 400 samples instead of 200 at a
	 * reported 200 kHz, which proves they are two time-interleaved ADC
	 * cores of CH1 rather than CH1 and CH2. So CH1 genuinely samples at
	 * 200 MHz / (ticks + 1) when it is the only analog channel enabled -
	 * the instrument's 200 MS/s budget, undivided.
	 *
	 * Half of that is discarded here, deliberately. A libsigrok session
	 * carries a single sample rate for every channel, and logic advances
	 * one sample per group; emitting analog at twice the group rate would
	 * make the logic timebase wrong by a factor of two. Logic is this
	 * project's priority, so analog yields.
	 *
	 * Recovering the full analog rate means reporting the analog rate as
	 * the session rate and duplicating each logic sample, which keeps both
	 * timebases honest at the cost of claiming a logic resolution the
	 * hardware does not have. That trade is worth making deliberately, not
	 * by accident.
	 */
	data = g_try_malloc((gsize)groups * sizeof(float));
	if (!data)
		return;
	/* Each channel's own range calibration. */
	for (i = 0; i < groups; i++) {
		data[i] = (float)(((double)payload[i * 4 + index]
			- zero) * rng->volts_per_count);
	}

	sr_analog_init(&analog, &encoding, &meaning, &spec, 0);
	analog.num_samples = groups;
	analog.data = data;
	analog.meaning->mq = SR_MQ_VOLTAGE;
	analog.meaning->unit = SR_UNIT_VOLT;
	analog.meaning->mqflags = 0;
	chl = g_slist_append(NULL, ch);
	analog.meaning->channels = chl;
	/* One count of the channel's range is the honest resolution. */
	spec.spec_digits = rng->digits;

	packet.type = SR_DF_ANALOG;
	packet.payload = &analog;
	sr_session_send(sdi, &packet);

	g_slist_free(chl);
	g_free(data);
}

/*
 * Read the record and forward the logic channels.
 *
 * Only bytes 2 and 3 of each four-byte group are used. They carry D0-D7 and
 * D8-D15 respectively, which is exactly libsigrok's little-endian two-byte
 * logic unit, so the extraction is a copy rather than a bit shuffle. Slots 0
 * and 1 carry the analog channels.
 *
 * THE READ IS ONE CONTINUOUS STREAM, and most of the transfer machinery's
 * apparent complexity elsewhere came from not knowing that. Measured
 * 2026-08-18 (04_HardwareDocu/Protocol/Command_Catalogue.md):
 *
 *  - 0x17 returns the TRIGGER address, not the capture end. The record
 *    physically ends at trigger + post-trigger length.
 *
 *  - The 0x1b length is advisory: a read asked for 202 k words and the
 *    device streamed 28.8 MB. Once started, the stream runs from the read
 *    start to the record's physical end and stops there on its own.
 *
 *  - There is ONE read session per armed capture. A second 0x13/0x1b/0x05
 *    setup after a drain or a stall delivers nothing until the next arm;
 *    the vendor's nAlreadyReadLen tracks progress through one stream, not
 *    separate reads. Re-issuing the setup per segment produced variable
 *    seams at the boundaries, which is what killed the segmented design.
 *
 *  - Reads starting at an address past the record end stall after the
 *    2048-byte preamble - the signature that was mistaken for a memory
 *    depth limit. The write pointer resets on arm, so this happens when
 *    trigger + post overflows the ring: with a 16 M record the trigger
 *    must land in a window less than a million points wide. Depths to
 *    half the ring are geometrically safe; beyond that the arithmetic
 *    below checks and refuses rather than wedging the device.
 *
 * The stream is consumed in fixed-size chunks and each chunk is forwarded
 * immediately, so peak memory stays at the chunk size and the frontend sees
 * data arriving rather than a long silence.
 */
#define DSO3062L_CHUNK_POINTS	(1024 * 1024)
/* Post-stream tail: the device sends roughly 1-2 k points past the record
 * end; cap the cleanup drain rather than waiting out a timeout. */
#define DSO3062L_TAIL_PACKETS	64

static void forward_chunk(const struct sr_dev_inst *sdi,
	const uint8_t *groups, int npoints)
{
	struct sr_datafeed_packet packet;
	struct sr_datafeed_logic logic;
	uint8_t *out;
	int i;

	out = g_try_malloc((gsize)npoints * DSO3062L_LOGIC_UNITSIZE);
	if (!out)
		return;
	for (i = 0; i < npoints; i++) {
		out[i * 2 + 0] = groups[i * 4 + 2];
		out[i * 2 + 1] = groups[i * 4 + 3];
	}

	packet.type = SR_DF_LOGIC;
	packet.payload = &logic;
	logic.length = (uint64_t)npoints * DSO3062L_LOGIC_UNITSIZE;
	logic.unitsize = DSO3062L_LOGIC_UNITSIZE;
	logic.data = out;
	sr_session_send(sdi, &packet);
	g_free(out);

	send_analog(sdi, groups, npoints, 0);
	/*
	 * Slot 1 is CH2 only when the enable word says so; otherwise it is
	 * CH1's second ADC core and emitting it as CH2 would be a duplicate
	 * of CH1 wearing a different label.
	 */
	if (ch2_enabled(sdi))
		send_analog(sdi, groups, npoints, 1);
}

/*
 * Parse the session's logic trigger into per-channel bit masks. A single
 * stage is supported (PulseView's logic trigger is one stage); each match
 * on a logic channel becomes a bit in the level/edge masks below.
 */
SR_PRIV void hantek_dso3062l_parse_trigger(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	struct sr_trigger *trigger;
	struct sr_trigger_stage *stage;
	struct sr_trigger_match *m;
	GSList *l;

	devc->sw_trig = FALSE;
	devc->sw_level_mask = devc->sw_level_value = 0;
	devc->sw_rise_mask = devc->sw_fall_mask = devc->sw_edge_mask = 0;

	trigger = sr_session_trigger_get(sdi->session);
	if (!trigger || !trigger->stages)
		return;

	stage = trigger->stages->data;
	for (l = stage->matches; l; l = l->next) {
		m = l->data;
		if (!m->channel || m->channel->type != SR_CHANNEL_LOGIC)
			continue;
		if (m->channel->index < 0 || m->channel->index >= 16)
			continue;
		uint16_t bit = 1u << m->channel->index;
		switch (m->match) {
		case SR_TRIGGER_ZERO:
			devc->sw_level_mask |= bit;
			break;
		case SR_TRIGGER_ONE:
			devc->sw_level_mask |= bit;
			devc->sw_level_value |= bit;
			break;
		case SR_TRIGGER_RISING:
			devc->sw_rise_mask |= bit;
			break;
		case SR_TRIGGER_FALLING:
			devc->sw_fall_mask |= bit;
			break;
		case SR_TRIGGER_EDGE:
			devc->sw_edge_mask |= bit;
			break;
		default:
			continue;
		}
		devc->sw_trig = TRUE;
	}
	if (devc->sw_trig)
		sr_info("Software logic trigger: level 0x%04x=0x%04x, "
			"rise 0x%04x, fall 0x%04x, edge 0x%04x.",
			devc->sw_level_mask, devc->sw_level_value,
			devc->sw_rise_mask, devc->sw_fall_mask,
			devc->sw_edge_mask);
}

/* True if the logic word `cur` (with previous `prev`) meets every armed
 * condition. Edge conditions need a valid previous sample. */
static gboolean sw_trigger_match(const struct dev_context *devc,
	uint16_t cur, uint16_t prev, gboolean have_prev)
{
	uint16_t rose, fell, changed;

	if ((cur & devc->sw_level_mask) != devc->sw_level_value)
		return FALSE;

	if (!(devc->sw_rise_mask | devc->sw_fall_mask | devc->sw_edge_mask))
		return TRUE;
	if (!have_prev)
		return FALSE;

	rose = cur & ~prev;
	fell = ~cur & prev;
	changed = cur ^ prev;
	if ((devc->sw_rise_mask & rose) != devc->sw_rise_mask)
		return FALSE;
	if ((devc->sw_fall_mask & fell) != devc->sw_fall_mask)
		return FALSE;
	if ((devc->sw_edge_mask & changed) != devc->sw_edge_mask)
		return FALSE;

	return TRUE;
}

/*
 * Read the whole record into memory, find the logic pattern, and forward
 * the data aligned to it with an SR_DF_TRIGGER marker. Because the
 * hardware sampled the record at full rate, the match runs at full rate
 * too - only the trigger point is located in software. If the pattern
 * does not occur in the captured window, the record is forwarded as-is
 * (no marker) so the frontend still shows the data.
 */
static int read_samples_triggered(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	struct sr_datafeed_packet trig_packet;
	uint8_t cmd[2] = { DSO3062L_CMD_GET_DATA, 0x00 };
	uint8_t *rec;
	uint32_t trigaddr, rec_end, start, rem, words, post;
	uint64_t samples, got;
	int ret, transferred, skip, want, total;
	int64_t i, match, pre, prev_valid;
	uint16_t cur, prev;

	samples = devc->limit_samples;

	ret = get_address(sdi, &trigaddr);
	if (ret != SR_OK)
		return ret;
	post = (uint32_t)(samples - samples * devc->capture_ratio / 100);
	rec_end = trigaddr + post;
	if (rec_end > DSO3062L_RING_LIMIT || (uint64_t)rec_end < samples)
		return SR_ERR_NA;
	start = rec_end - (uint32_t)samples;
	rem = start & 0x1ff;
	words = 2 * ((uint32_t)samples + rem) + 0x800;
	if (words > 0xffffff)
		words = 0xffffff;

	ret = send_addr_cmd(sdi, DSO3062L_CMD_SET_READ_START,
		(start - rem) - 1, 0x80);
	if (ret != SR_OK)
		return ret;
	ret = send_addr_cmd(sdi, DSO3062L_CMD_SET_READ_LEN, words, 0x00);
	if (ret != SR_OK)
		return ret;
	ret = hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
	if (ret != SR_OK)
		return ret;

	/* One four-byte group per point; hold the whole record so the
	 * match can align logic and analog together. */
	rec = g_try_malloc((gsize)samples * 4);
	if (!rec) {
		sr_err("Cannot hold a %" PRIu64 "-sample record for software "
			"triggering; reduce the sample count.", samples);
		return SR_ERR_MALLOC;
	}

	skip = (int)(rem + 0x200) * 4;
	want = (int)((samples * 4) + skip);
	total = 0;
	got = 0;
	{
		uint8_t pkt[DSO3062L_EP_PACKET_SIZE];
		while (total < want && got < samples) {
			int n = MIN(DSO3062L_EP_PACKET_SIZE, want - total);
			ret = hantek_dso3062l_read(sdi, pkt, n, &transferred);
			if (ret != SR_OK || transferred == 0)
				break;
			int off = 0;
			if (skip > 0) {
				int s = MIN(skip, transferred);
				skip -= s; off = s;
			}
			int avail = transferred - off;
			int room = (int)((samples - got) * 4);
			if (avail > room)
				avail = room;
			if (avail > 0) {
				memcpy(rec + got * 4, pkt + off, avail);
				got += avail / 4;
			}
			total += transferred;
		}
	}

	/* Drain the tail so the endpoint is clean for the next capture. */
	{
		uint8_t sink[DSO3062L_EP_PACKET_SIZE];
		for (i = 0; i < DSO3062L_TAIL_PACKETS; i++) {
			if (hantek_dso3062l_read(sdi, sink, sizeof(sink),
					&transferred) != SR_OK
			    || transferred == 0)
				break;
		}
	}

	if (got == 0) {
		g_free(rec);
		return SR_ERR;
	}

	/* Scan for the first matching point. */
	match = -1;
	prev = 0;
	prev_valid = 0;
	for (i = 0; i < (int64_t)got; i++) {
		cur = rec[i * 4 + 2] | (rec[i * 4 + 3] << 8);
		if (sw_trigger_match(devc, cur, prev, prev_valid)) {
			match = i;
			break;
		}
		prev = cur;
		prev_valid = 1;
	}

	if (match < 0) {
		sr_info("Trigger pattern not found in the %" PRIu64 "-sample "
			"window; forwarding untriggered.", got);
		forward_chunk(sdi, rec, (int)got);
		g_free(rec);
		return SR_OK;
	}

	/* Keep up to capture_ratio% of the record before the match. */
	pre = (int64_t)(samples * devc->capture_ratio / 100);
	if (pre > match)
		pre = match;

	if (pre > 0)
		forward_chunk(sdi, rec + (match - pre) * 4, (int)pre);
	trig_packet.type = SR_DF_TRIGGER;
	trig_packet.payload = NULL;
	sr_session_send(sdi, &trig_packet);
	forward_chunk(sdi, rec + match * 4, (int)(got - match));

	sr_info("Software trigger matched at sample %" PRId64 " of %"
		PRIu64 ".", match, got);
	g_free(rec);

	return SR_OK;
}

SR_PRIV int hantek_dso3062l_read_samples(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc;
	uint8_t cmd[2] = { DSO3062L_CMD_GET_DATA, 0x00 };
	uint8_t *buf;
	uint32_t trig, rec_end, start, rem, words, post;
	uint64_t samples, forwarded;
	int ret, transferred, skip, fill, take, i;

	devc = sdi->priv;

	if (devc->sw_trig)
		return read_samples_triggered(sdi);

	samples = devc->limit_samples;

	ret = get_address(sdi, &trig);
	if (ret != SR_OK) {
		sr_err("Failed to read the trigger address.");
		return ret;
	}

	/*
	 * Record geometry. The post-trigger share follows the configured
	 * capture ratio, and the stream terminus is that physical end.
	 * SR_ERR_NA tells the caller this is a placement miss - the arm can
	 * be retried at a better write-pointer position - rather than a
	 * hard failure.
	 */
	post = (uint32_t)(samples - samples * devc->capture_ratio / 100);
	rec_end = trig + post;
	if (rec_end > DSO3062L_RING_LIMIT || (uint64_t)rec_end < samples) {
		sr_warn("Record landed outside the readable window: trigger "
			"at 0x%06x, record end 0x%06x for %" PRIu64
			" samples.", trig, rec_end, samples);
		return SR_ERR_NA;
	}
	start = rec_end - (uint32_t)samples;
	rem = start & 0x1ff;

	/*
	 * Advisory, but set it to the honest value anyway: two 16-bit words
	 * per point, clamped to the 24-bit register for records too deep to
	 * express - the device stops at the record end regardless.
	 */
	words = 2 * ((uint32_t)samples + rem) + 0x800;
	if (words > 0xffffff)
		words = 0xffffff;

	ret = send_addr_cmd(sdi, DSO3062L_CMD_SET_READ_START,
		(start - rem) - 1, 0x80);
	if (ret != SR_OK)
		return ret;
	ret = send_addr_cmd(sdi, DSO3062L_CMD_SET_READ_LEN, words, 0x00);
	if (ret != SR_OK)
		return ret;
	ret = hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
	if (ret != SR_OK)
		return ret;

	/* One packet of headroom: the forward threshold is only checked
	 * after a packet lands, so fill can sit just under the chunk size
	 * when the next 512 bytes arrive. */
	buf = g_try_malloc(DSO3062L_CHUNK_POINTS * 4 + DSO3062L_EP_PACKET_SIZE);
	if (!buf) {
		sr_err("Failed to allocate the chunk buffer.");
		return SR_ERR_MALLOC;
	}

	/*
	 * One 512-byte packet per transfer, which is what the vendor DLL's
	 * own loop does; larger requests time out. The first rem + 512
	 * points of the stream are preamble.
	 */
	skip = (int)(rem + 0x200) * 4;
	forwarded = 0;
	fill = 0;
	while (forwarded < samples) {
		ret = hantek_dso3062l_read(sdi, buf + fill,
			DSO3062L_EP_PACKET_SIZE, &transferred);
		if (ret != SR_OK || transferred == 0)
			break;
		if (skip > 0) {
			take = MIN(skip, transferred);
			skip -= take;
			if (take < transferred)
				memmove(buf + fill, buf + fill + take,
					transferred - take);
			transferred -= take;
		}
		fill += transferred;
		if (fill >= (int)(DSO3062L_CHUNK_POINTS * 4)
		    || (uint64_t)(fill / 4) >= samples - forwarded) {
			take = MIN(fill / 4,
				(int)MIN((uint64_t)DSO3062L_CHUNK_POINTS,
					samples - forwarded));
			forward_chunk(sdi, buf, take);
			forwarded += take;
			if (take * 4 < fill)
				memmove(buf, buf + take * 4,
					fill - take * 4);
			fill -= take * 4;
		}
	}

	/* Swallow the short tail past the record end so nothing is left
	 * queued; bounded, so a healthy stop costs one timeout at most. */
	for (i = 0; i < DSO3062L_TAIL_PACKETS; i++) {
		ret = hantek_dso3062l_read(sdi, buf,
			DSO3062L_EP_PACKET_SIZE, &transferred);
		if (ret != SR_OK || transferred == 0)
			break;
	}

	g_free(buf);

	if (forwarded < samples) {
		sr_err("Stream ended early: %" PRIu64 " of %" PRIu64
			" samples.", forwarded, samples);
		return SR_ERR;
	}

	sr_info("Forwarded %" PRIu64 " logic samples.", forwarded);

	return SR_OK;
}

/*
 * Roll mode: continuous acquisition of the live ring.
 *
 * Decoded from the DLL's undocumented dsoHT*RollMode exports and verified
 * on hardware 2026-08-18. Entered with 0x19 [0] [on] [0]; while on, 0x17
 * returns the LIVE write pointer (unlike the one-shot path, where it stays
 * zero until a trigger), and 0x13/0x1b/0x05 reads pull fresh data from the
 * ring as the writer laps it.
 */
SR_PRIV int hantek_dso3062l_roll_mode(const struct sr_dev_inst *sdi,
	gboolean on)
{
	uint8_t cmd[4] = { DSO3062L_CMD_ROLL_MODE, 0x00, on ? 0x01 : 0x00,
		0x00 };

	return hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
}

/*
 * One roll iteration: read whatever the writer has produced since the last
 * call and forward it, gap-free.
 *
 * `roll_addr` is the next unread ring position. The read follows the same
 * mechanics as the one-shot path (§ read_samples): align the start down to
 * 512, ask for the wanted points plus the device's rem+512 preamble, and
 * discard that preamble. Advancing `roll_addr` by exactly the forwarded
 * count keeps successive chunks contiguous.
 *
 * Overrun: if the writer has run more than half the ring ahead of the read
 * cursor, the host has fallen behind (sample rate above the ~1 M point/s
 * bulk-IN ceiling). That is the "roll" case - resync to the live pointer,
 * report the gap, and carry on rather than emitting stale or torn data.
 */
SR_PRIV int hantek_dso3062l_roll_read(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc;
	uint8_t cmd[2] = { DSO3062L_CMD_GET_DATA, 0x00 };
	uint8_t *buf;
	uint32_t ptr, avail, chunk, rem, words;
	int ret, transferred, want, total, skip;

	devc = sdi->priv;

	/*
	 * A transient USB hiccup here must not end the stream - roll mode
	 * runs until the frontend stops it. Skip this tick and try again.
	 */
	ret = get_address(sdi, &ptr);
	if (ret != SR_OK)
		return SR_OK;

	avail = (ptr - devc->roll_addr) & (DSO3062L_RING_SIZE - 1);

	if (avail > DSO3062L_RING_SIZE / 2) {
		sr_warn("Roll overrun: host behind the writer, resyncing "
			"(a gap in the stream). Lower the sample rate for "
			"gap-free continuous capture.");
		devc->roll_addr = ptr;
		return SR_OK;
	}

	/*
	 * Read only up to a guard behind the live pointer: the last points
	 * before it may not be fully written, and reading them stalls the
	 * endpoint. Below the guard there is nothing safe to take yet.
	 */
	if (avail <= DSO3062L_ROLL_GUARD_POINTS)
		return SR_OK;
	avail -= DSO3062L_ROLL_GUARD_POINTS;

	chunk = MIN(avail, (uint32_t)DSO3062L_ROLL_CHUNK_POINTS);

	rem = devc->roll_addr & 0x1ff;
	words = 2 * (chunk + rem + 0x200);

	ret = send_addr_cmd(sdi, DSO3062L_CMD_SET_READ_START,
		(devc->roll_addr - rem) - 1, 0x80);
	if (ret != SR_OK)
		return ret;
	ret = send_addr_cmd(sdi, DSO3062L_CMD_SET_READ_LEN, words, 0x00);
	if (ret != SR_OK)
		return ret;
	ret = hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
	if (ret != SR_OK)
		return ret;

	want = (int)(2 * words);
	buf = g_try_malloc(want);
	if (!buf)
		return SR_ERR_MALLOC;

	total = 0;
	while (total < want) {
		int n = MIN(DSO3062L_EP_PACKET_SIZE, want - total);
		ret = hantek_dso3062l_read(sdi, buf + total, n, &transferred);
		if (ret != SR_OK || transferred == 0)
			break;
		total += transferred;
	}

	/*
	 * A short read means the device stopped mid-request; whatever it
	 * left queued would desync the next command. Drain it (bounded)
	 * so the following 0x17 starts clean. `got` below still only
	 * forwards up to `chunk` valid points, so the drained tail is
	 * discarded, not double-counted - roll_addr advances by what was
	 * forwarded, keeping the stream gap-free.
	 */
	if (total < want) {
		uint8_t sink[DSO3062L_EP_PACKET_SIZE];
		int i;
		for (i = 0; i < DSO3062L_TAIL_PACKETS; i++) {
			if (hantek_dso3062l_read(sdi, sink,
					sizeof(sink), &transferred) != SR_OK
			    || transferred == 0)
				break;
		}
	}

	skip = (int)(rem + 0x200) * 4;
	if (total > skip) {
		int got = (total - skip) / 4;
		if ((uint32_t)got > chunk)
			got = (int)chunk;
		forward_chunk(sdi, buf + skip, got);
		devc->roll_addr = (devc->roll_addr + got)
			& (DSO3062L_RING_SIZE - 1);
		devc->roll_forwarded += got;
	}
	sr_spew("roll: avail %u chunk %u total %d/%d forwarded %" PRIu64,
		avail, chunk, total, want, devc->roll_forwarded);

	g_free(buf);

	return SR_OK;
}

/*
 * Timer-driven acquisition.
 *
 * The vendor arming sequence needs roughly a quarter of a second of settling
 * between each of its three steps. Doing that inline would block the session
 * for about a second, which a GUI frontend shows as a freeze, so the steps
 * are spread across timer callbacks instead.
 */

/*
 * The write-pointer window in which the trigger must land for the record to
 * be readable: far enough in that the whole record lies behind the pointer,
 * short enough of the ring limit that the post-trigger half still fits. The
 * margin covers host timing jitter - half a tick of pointer travel plus a
 * fixed floor. Returns FALSE when no window exists at this rate and depth.
 */
static gboolean arm_window(const struct dev_context *devc, uint64_t *lo,
	uint64_t *hi)
{
	uint64_t pre = devc->limit_samples * devc->capture_ratio / 100;
	uint64_t post = devc->limit_samples - pre;
	/* Pointer travel during ~10 ms of command latency, plus a floor. */
	uint64_t margin = devc->samplerate / 100 + 20000;

	*lo = pre + margin;
	if ((uint64_t)DSO3062L_RING_LIMIT < pre + margin)
		return FALSE;
	if ((uint64_t)DSO3062L_RING_LIMIT < post + margin)
		return FALSE;
	*hi = DSO3062L_RING_LIMIT - post - margin;

	/* Hittable only if wider than ~10 ms of pointer travel: the final
	 * approach is a precise g_usleep, but command latency still moves
	 * the pointer between the sleep and the device acting. */
	return *hi > *lo && (*hi - *lo) > devc->samplerate / 100;
}

/* For the API layer: is this rate and depth combination readable at all?
 * Exposed so acquisition can refuse at start - a visible frontend error -
 * rather than dying silently in a timer callback. */
SR_PRIV gboolean hantek_dso3062l_depth_feasible(
	const struct dev_context *devc)
{
	uint64_t lo, hi;

	return arm_window(devc, &lo, &hi);
}

/* Estimated write-pointer position: it starts near zero at 0x03, advances
 * one point per sample period and wraps the ring forever. 0x17 reads zero
 * until the trigger, so the wall clock is all there is to go on. */
static uint64_t writer_pos(const struct dev_context *devc)
{
	gint64 us = g_get_monotonic_time() - devc->collect_us;

	return ((uint64_t)us * devc->samplerate / 1000000)
		% DSO3062L_RING_SIZE;
}

SR_PRIV int hantek_dso3062l_receive_data(int fd, int revents, void *cb_data)
{
	const struct sr_dev_inst *sdi;
	struct dev_context *devc;
	uint8_t cmd[2];
	uint8_t state;
	uint64_t lo, hi, pos, wait_pts;
	int ret;

	(void)fd;
	(void)revents;

	sdi = cb_data;
	if (!sdi || !(devc = sdi->priv))
		return TRUE;

	/* Settling between arming steps, counted in timer ticks. */
	if (devc->settle_ticks > 0) {
		devc->settle_ticks--;
		return TRUE;
	}

	switch (devc->state) {
	case DSO3062L_ACQ_ROLL_ARM:
		/*
		 * Roll needs the writer running, which still requires 0x04
		 * even though roll never waits for a trigger (found live).
		 * After arming, seed the read cursor at the current pointer
		 * and stream from there.
		 */
		cmd[0] = DSO3062L_CMD_START_TRIGGER;
		cmd[1] = 0x00;
		if (hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd)) != SR_OK)
			break;
		if (get_address(sdi, &devc->roll_addr) != SR_OK)
			break;
		devc->state = DSO3062L_ACQ_ROLL_STREAM;
		return TRUE;
	case DSO3062L_ACQ_ROLL_STREAM:
		if (hantek_dso3062l_roll_read(sdi) != SR_OK)
			break;
		return TRUE;
	case DSO3062L_ACQ_START_COLLECT:
		if (!arm_window(devc, &lo, &hi)) {
			sr_err("%" PRIu64 " samples cannot fit the ring at "
				"%" PRIu64 " Hz with any trigger timing - "
				"reduce the sample count.",
				devc->limit_samples, devc->samplerate);
			break;
		}
		cmd[0] = DSO3062L_CMD_START_COLLECT;
		cmd[1] = 0x00;
		if (hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd)) != SR_OK)
			break;
		devc->collect_us = g_get_monotonic_time();
		devc->state = DSO3062L_ACQ_START_TRIGGER;
		devc->settle_ticks = 5;
		return TRUE;
	case DSO3062L_ACQ_START_TRIGGER:
		/*
		 * Steer the arm into the window. A live trigger source
		 * fires the moment triggering is armed, so where the write
		 * pointer is RIGHT NOW is where the trigger will land -
		 * get the pointer inside the readable window before
		 * sending 0x04.
		 *
		 * Two-phase approach, because timer ticks cannot do this
		 * alone: the nominal 50 ms callback period measures ~65 ms
		 * in practice, so a wait computed in ticks overshoots by
		 * megasamples and can lap forever when the window is
		 * narrower than one real tick. Coarse-wait in ticks
		 * assuming a pessimistic 80 ms each - guaranteed to arrive
		 * early - then close the last stretch with g_usleep, whose
		 * millisecond precision is a few thousand points.
		 */
		arm_window(devc, &lo, &hi);
		pos = writer_pos(devc);
		if (pos < lo || pos > hi) {
			uint64_t target, wait_us;

			target = lo + MIN((hi - lo) / 4, 100000);
			wait_pts = (pos < target) ? target - pos
				: (DSO3062L_RING_SIZE - pos) + target;
			wait_us = wait_pts * 1000000 / devc->samplerate;
			if (wait_us > 120000) {
				devc->settle_ticks =
					MAX((int)(wait_us / 80000), 1);
				sr_dbg("Steering: pos %" PRIu64 " outside "
					"[%" PRIu64 ", %" PRIu64 "], "
					"coarse wait %d ticks.",
					pos, lo, hi, devc->settle_ticks);
				return TRUE;
			}
			g_usleep((gulong)wait_us);
			pos = writer_pos(devc);
		}
		sr_dbg("Steering: arming at pos %" PRIu64 " in [%" PRIu64
			", %" PRIu64 "].", pos, lo, hi);
		cmd[0] = DSO3062L_CMD_START_TRIGGER;
		cmd[1] = 0x00;
		if (hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd)) != SR_OK)
			break;
		devc->state = DSO3062L_ACQ_POLL;
		devc->poll_ticks = 0;
		return TRUE;
	case DSO3062L_ACQ_POLL: {
		int limit_tick = 160
			+ (int)(40 * devc->limit_samples / devc->samplerate);

		if (hantek_dso3062l_get_state(sdi, &state) != SR_OK)
			break;
		if (state == DSO3062L_STATE_READY_8BIT
		    || state == DSO3062L_STATE_READY_2250
		    || state == DSO3062L_STATE_READY_9BIT) {
			devc->state = DSO3062L_ACQ_READ;
			return TRUE;
		}
		devc->poll_ticks++;
		if (devc->poll_ticks > limit_tick) {
			sr_err("Timed out waiting for the capture to complete "
				"(last state %u).", state);
			break;
		}
		/*
		 * Auto-trigger, the way a scope's AUTO mode behaves: wait
		 * for the configured condition, and force a capture if
		 * nothing arrives within a second. The force is gated on
		 * the write pointer sitting inside the readable window -
		 * the device silently drops a force before pre-fill (the
		 * window's lower edge covers that), and a force past the
		 * window's upper edge would make the record unreadable.
		 * When the window is narrower than a callback period the
		 * gate would rarely sample open, so a nearby window is
		 * reached with the same precise sleep the arming uses.
		 */
		if (devc->poll_ticks >= 20) {
			arm_window(devc, &lo, &hi);
			pos = writer_pos(devc);
			if (pos < lo || pos > hi) {
				uint64_t target, wait_us;

				target = lo + MIN((hi - lo) / 4, 100000);
				wait_pts = (pos < target) ? target - pos
					: (DSO3062L_RING_SIZE - pos) + target;
				wait_us = wait_pts * 1000000
					/ devc->samplerate;
				if (wait_us > 120000)
					return TRUE;
				g_usleep((gulong)wait_us);
			}
			cmd[0] = DSO3062L_CMD_FORCE_TRIGGER;
			cmd[1] = 0x00;
			if (hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd))
					!= SR_OK)
				break;
		}
		return TRUE;
	}
	case DSO3062L_ACQ_READ:
		ret = hantek_dso3062l_read_samples(sdi);
		/*
		 * A geometry miss means a real trigger fired while the
		 * write pointer was outside the readable window - possible
		 * with a sparse trigger source, since the pointer keeps
		 * lapping the ring while armed. Re-arming rolls new
		 * placement; three misses in a row means the source fires
		 * persistently at unusable pointer positions.
		 */
		if (ret == SR_ERR_NA && devc->retries < 3) {
			devc->retries++;
			sr_warn("Re-arming after a geometry miss (attempt "
				"%d of 3).", devc->retries);
			devc->state = DSO3062L_ACQ_START_COLLECT;
			devc->settle_ticks = 0;
			return TRUE;
		}
		break;
	default:
		break;
	}

	devc->state = DSO3062L_ACQ_DONE;
	sr_dev_acquisition_stop((struct sr_dev_inst *)sdi);

	return TRUE;
}
