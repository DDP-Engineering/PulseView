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
 * The wire carries an index into this table, not a frequency.
 *
 * The vendor's own list ends with 1 GHz, which this driver deliberately does
 * not offer: on a 16-channel DL16 Pro it silently truncates the record (32768
 * samples instead of the requested count) and returns data at the wrong rate
 * - a 1 MHz reference came back as 4.36 MHz. The vendor UI only allows 1 GHz
 * with eight channels or fewer, which this driver does not model, so the
 * option would be dead weight. Everything from 1 MHz to 500 MHz was measured
 * against a 1 MHz reference and is accurate to better than 1 %.
 */
SR_PRIV const uint64_t atk_dl16_samplerates[ATK_DL16_NUM_SAMPLERATES] = {
	SR_MHZ(1), SR_MHZ(2), SR_MHZ(4), SR_MHZ(5), SR_MHZ(10), SR_MHZ(20),
	SR_MHZ(25), SR_MHZ(40), SR_MHZ(50), SR_MHZ(100), SR_MHZ(200),
	SR_MHZ(250), SR_MHZ(500),
};

/* Comparator thresholds behind the vendor's logic-family labels:
 * 1.2 V CMOS, 1.5 V, 1.8 V, 2.5 V, 3.0 V, 3.3 V and 5.0 V CMOS. */
SR_PRIV const double atk_dl16_thresholds[ATK_DL16_NUM_THRESHOLDS] = {
	0.6, 0.7, 0.9, 1.2, 1.5, 1.6, 2.5,
};

/*
 * CRC-32 with the standard polynomial but an INITIAL VALUE OF ZERO.
 *
 * That single deviation from CRC-32/ISO-HDLC is why stock implementations
 * do not match: everything else - reflected in and out, final xor with
 * 0xffffffff - is textbook. Recovered by fitting nine frame/CRC pairs
 * captured from the vendor application; exactly one parameter set matched
 * all of them, across MCU, PWM and acquisition commands alike.
 *
 * Covers the command byte through the last data byte: the 0x0a header and
 * the 0x0b footer are excluded.
 */
SR_PRIV uint32_t atk_dl16_crc32(const uint8_t *data, size_t len)
{
	uint32_t crc = 0x00000000;
	size_t i;
	int b;

	for (i = 0; i < len; i++) {
		crc ^= data[i];
		for (b = 0; b < 8; b++)
			crc = (crc >> 1) ^ (0xedb88320 & (uint32_t)(-(int32_t)(crc & 1)));
	}

	return crc ^ 0xffffffff;
}

/*
 * The device's word interleave: the 2048-byte block is four 512-byte
 * segments, and consecutive 16-bit words are dealt across them in turn.
 * Word i of the logical stream lives at (i % 4) * 512 + (i / 4) * 2.
 *
 * This applies to sample data and - less obviously - to the acquisition
 * commands as well.
 */
static void interleave_block(const uint8_t *logical, uint8_t *dev)
{
	size_t i, off;

	for (i = 0; i < ATK_DL16_BLOCK_SIZE / 2; i++) {
		off = (i % 4) * ATK_DL16_SEGMENT_SIZE + (i / 4) * 2;
		dev[off + 0] = logical[i * 2 + 0];
		dev[off + 1] = logical[i * 2 + 1];
	}
}

SR_PRIV void atk_dl16_deinterleave(const uint8_t *src, uint8_t *dst,
	size_t blocks)
{
	size_t blk, i, off;

	for (blk = 0; blk < blocks; blk++) {
		const uint8_t *s = src + blk * ATK_DL16_BLOCK_SIZE;
		uint8_t *d = dst + blk * ATK_DL16_BLOCK_SIZE;
		for (i = 0; i < ATK_DL16_BLOCK_SIZE / 2; i++) {
			off = (i % 4) * ATK_DL16_SEGMENT_SIZE + (i / 4) * 2;
			d[i * 2 + 0] = s[off + 0];
			d[i * 2 + 1] = s[off + 1];
		}
	}
}

/*
 * Build a frame and put it on the bulk OUT endpoint.
 *
 * Acquisition commands must be interleaved and padded to a full block;
 * MCU-side commands (reset, PWM) go out as-is. In the interleaved form the
 * logical buffer starts with four zero words before the frame, which is
 * what the captures show.
 */
SR_PRIV int atk_dl16_send_frame(const struct sr_dev_inst *sdi, uint8_t cmd,
	const uint8_t *data, size_t datalen, gboolean interleave)
{
	struct sr_usb_dev_inst *usb = sdi->conn;
	uint8_t frame[64], logical[ATK_DL16_BLOCK_SIZE];
	uint8_t dev[ATK_DL16_BLOCK_SIZE];
	const uint8_t *out;
	size_t framelen, outlen;
	uint32_t crc;
	int ret, transferred;

	if (datalen + 8 > sizeof(frame))
		return SR_ERR_ARG;

	framelen = 0;
	frame[framelen++] = ATK_DL16_FRAME_HEADER;
	frame[framelen++] = cmd;
	frame[framelen++] = (uint8_t)(datalen + 1);	/* data + footer */
	if (datalen)
		memcpy(frame + framelen, data, datalen);
	framelen += datalen;
	frame[framelen++] = ATK_DL16_FRAME_FOOTER;

	/* CRC over cmd .. last data byte, i.e. excluding header and footer. */
	crc = atk_dl16_crc32(frame + 1, framelen - 2);
	frame[framelen++] = crc & 0xff;
	frame[framelen++] = (crc >> 8) & 0xff;
	frame[framelen++] = (crc >> 16) & 0xff;
	frame[framelen++] = (crc >> 24) & 0xff;

	if (interleave) {
		memset(logical, 0, sizeof(logical));
		memcpy(logical + ATK_DL16_INTERLEAVE_LEAD, frame, framelen);
		interleave_block(logical, dev);
		out = dev;
		outlen = ATK_DL16_BLOCK_SIZE;
	} else {
		out = frame;
		outlen = framelen;
	}

	ret = libusb_bulk_transfer(usb->devhdl, ATK_DL16_EP_OUT,
		(unsigned char *)out, (int)outlen, &transferred,
		ATK_DL16_USB_TIMEOUT_MS);
	if (ret < 0) {
		sr_err("Failed to send command 0x%02x: %s.", cmd,
			libusb_error_name(ret));
		return SR_ERR;
	}

	sr_spew("Sent 0x%02x (%zu data bytes, %s).", cmd, datalen,
		interleave ? "interleaved" : "raw");

	return SR_OK;
}

/*
 * 0x87: wake (1) or sleep (0) the FPGA. Not a bitstream upload - the image
 * is resident; this only toggles a reset line.
 *
 * This goes to the MCU, not the FPGA, and the MCU speaks a different dialect:
 * a fixed 512-byte write of which only the first three bytes matter. Adding a
 * length byte, a footer or a CRC here is wrong, even though the device is
 * lenient enough to have accepted it.
 *
 * Nothing captures unless this has been sent with 1 - the vendor application
 * puts the FPGA back to sleep whenever it is idle.
 */
SR_PRIV int atk_dl16_set_reset(const struct sr_dev_inst *sdi, gboolean active)
{
	struct sr_usb_dev_inst *usb = sdi->conn;
	uint8_t buf[ATK_DL16_MCU_WRITE_LEN];
	int ret, transferred;

	memset(buf, 0, sizeof(buf));
	buf[0] = ATK_DL16_FRAME_HEADER;
	buf[1] = ATK_DL16_CMD_SET_RESET;
	buf[2] = active ? 1 : 0;

	ret = libusb_bulk_transfer(usb->devhdl, ATK_DL16_EP_OUT, buf,
		(int)sizeof(buf), &transferred, ATK_DL16_USB_TIMEOUT_MS);
	if (ret < 0) {
		sr_err("Failed to set FPGA reset: %s.", libusb_error_name(ret));
		return SR_ERR;
	}

	return SR_OK;
}

static void put_le(uint8_t *p, uint64_t v, int bytes)
{
	int i;

	for (i = 0; i < bytes; i++)
		p[i] = (uint8_t)(v >> (8 * i));
}

static int rate_index(uint64_t rate)
{
	int i;

	for (i = 0; i < ATK_DL16_NUM_SAMPLERATES; i++)
		if (atk_dl16_samplerates[i] == rate)
			return i;

	return -1;
}

SR_PRIV int atk_dl16_send_param(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	uint8_t d[ATK_DL16_PARAM_LEN];
	uint64_t trigdepth;
	int idx, tenths;

	idx = rate_index(devc->samplerate);
	if (idx < 0) {
		sr_err("Unsupported sample rate %" PRIu64 " Hz.",
			devc->samplerate);
		return SR_ERR_ARG;
	}

	memset(d, 0, sizeof(d));

	d[0] = 0;
	if (!devc->continuous)
		d[0] |= ATK_DL16_FLAG_BUFFER;
	if (devc->rle)
		d[0] |= ATK_DL16_FLAG_RLE;

	/* Threshold in tenths of a volt, sign in bit 7. */
	tenths = (int)(devc->threshold * 10.0 + (devc->threshold < 0 ? -0.5 : 0.5));
	if (tenths < 0)
		d[1] = 0x80 | (uint8_t)((-tenths) & 0x7f);
	else
		d[1] = (uint8_t)(tenths & 0x7f);

	d[2] = (uint8_t)(idx + 1);

	/* Trigger depth is an absolute sample count: capture_ratio % of the
	 * record, matching SR_CONF_CAPTURE_RATIO. */
	trigdepth = devc->limit_samples * devc->capture_ratio / 100;
	put_le(&d[3], devc->limit_samples, ATK_DL16_DEPTH_BYTES);
	put_le(&d[8], trigdepth, ATK_DL16_DEPTH_BYTES);

	sr_dbg("Param: %s, thr %.1f V, rate idx %d (%" PRIu64 " Hz), "
		"depth %" PRIu64 ", trig depth %" PRIu64 ".",
		devc->continuous ? "stream" : "buffer", devc->threshold,
		idx, devc->samplerate, devc->limit_samples, trigdepth);

	return atk_dl16_send_frame(sdi, ATK_DL16_CMD_PARAM, d, sizeof(d), TRUE);
}

/*
 * Translate the session's trigger into the per-channel nibbles.
 *
 * Channels with no condition get ATK_DL16_TRG_ANY, not zero - see the note
 * in protocol.h. Disabled channels get zero.
 */
SR_PRIV void atk_dl16_parse_trigger(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	struct sr_trigger *trigger;
	struct sr_trigger_stage *stage;
	struct sr_trigger_match *m;
	struct sr_channel *ch;
	uint8_t nib[ATK_DL16_NUM_CHANNELS];
	GSList *l;
	int i;

	devc->trigger_set = FALSE;

	/* Start from "enabled, any state" for every enabled channel. */
	for (i = 0; i < ATK_DL16_NUM_CHANNELS; i++)
		nib[i] = 0;
	for (l = sdi->channels; l; l = l->next) {
		ch = l->data;
		if (ch->type != SR_CHANNEL_LOGIC || !ch->enabled)
			continue;
		if (ch->index >= 0 && ch->index < ATK_DL16_NUM_CHANNELS)
			nib[ch->index] = ATK_DL16_TRG_ENABLE | ATK_DL16_TRG_ANY;
	}

	trigger = sr_session_trigger_get(sdi->session);
	if (trigger && trigger->stages) {
		stage = trigger->stages->data;
		for (l = stage->matches; l; l = l->next) {
			m = l->data;
			if (!m->channel || m->channel->type != SR_CHANNEL_LOGIC)
				continue;
			i = m->channel->index;
			if (i < 0 || i >= ATK_DL16_NUM_CHANNELS)
				continue;
			switch (m->match) {
			case SR_TRIGGER_ZERO:
				nib[i] = ATK_DL16_TRG_ENABLE;
				break;
			case SR_TRIGGER_ONE:
				nib[i] = ATK_DL16_TRG_ENABLE | ATK_DL16_TRG_HIGH;
				break;
			case SR_TRIGGER_RISING:
				nib[i] = ATK_DL16_TRG_ENABLE | ATK_DL16_TRG_RISING;
				break;
			case SR_TRIGGER_FALLING:
				nib[i] = ATK_DL16_TRG_ENABLE | ATK_DL16_TRG_FALLING;
				break;
			case SR_TRIGGER_EDGE:
				nib[i] = ATK_DL16_TRG_ENABLE
					| ATK_DL16_TRG_RISING
					| ATK_DL16_TRG_FALLING;
				break;
			default:
				continue;
			}
			devc->trigger_set = TRUE;
		}
	}

	/* Even channel in the high nibble, odd in the low. */
	for (i = 0; i < 8; i++)
		devc->trigger_bytes[i] = (uint8_t)((nib[2 * i] << 4)
			| (nib[2 * i + 1] & 0x0f));
}

SR_PRIV int atk_dl16_send_trigger(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	uint8_t d[ATK_DL16_TRIGGER_LEN];

	memcpy(d, devc->trigger_bytes, 8);
	/* isInstantly: with no trigger configured, fire at once rather than
	 * waiting for a condition that will never be evaluated. */
	d[8] = devc->trigger_set ? 0 : 1;

	sr_dbg("Trigger: %02x %02x %02x %02x %02x %02x %02x %02x instant=%u",
		d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8]);

	return atk_dl16_send_frame(sdi, ATK_DL16_CMD_TRIGGER, d, sizeof(d),
		TRUE);
}

SR_PRIV int atk_dl16_stop(const struct sr_dev_inst *sdi)
{
	return atk_dl16_send_frame(sdi, ATK_DL16_CMD_STOP, NULL, 0, TRUE);
}

/*
 * PWM generator. Period and high time are counts of a 200 MHz clock, so
 * the duty is an absolute high-time rather than a percentage. The vendor
 * UI stops at 20 MHz because that leaves only ten ticks per period - a
 * duty-resolution floor, not a hardware limit.
 */
SR_PRIV int atk_dl16_pwm(const struct sr_dev_inst *sdi, int index,
	gboolean enable, uint64_t hz, int duty)
{
	uint8_t d[9];
	uint32_t period, high;

	if (!enable) {
		d[0] = index ? ATK_DL16_PWM1_STOP : ATK_DL16_PWM0_STOP;
		return atk_dl16_send_frame(sdi, ATK_DL16_CMD_PWM, d, 1, FALSE);
	}

	if (!hz)
		return SR_ERR_ARG;
	period = (uint32_t)((ATK_DL16_PWM_BASE_HZ + hz / 2) / hz);
	if (!period)
		period = 1;
	/* Round, as the vendor does (round(period * duty / 100)); truncating
	 * here shifts the duty by up to one tick on non-even divisions. */
	high = (uint32_t)(((uint64_t)period * duty + 50) / 100);

	d[0] = index ? ATK_DL16_PWM1_START : ATK_DL16_PWM0_START;
	put_le(&d[1], period, 4);
	put_le(&d[5], high, 4);

	return atk_dl16_send_frame(sdi, ATK_DL16_CMD_PWM, d, sizeof(d), FALSE);
}

/*
 * Push one generator's stored settings to the device.
 *
 * Wakes the FPGA first when enabling. The vendor application leaves the FPGA
 * asleep whenever it is not capturing, and a sleeping FPGA drives no output -
 * so without this a PWM configured while idle appears to be accepted and
 * produces nothing. It is left awake afterwards, since that is the only state
 * in which the generator keeps running.
 */
SR_PRIV int atk_dl16_pwm_apply(const struct sr_dev_inst *sdi, size_t index)
{
	struct dev_context *devc = sdi->priv;
	const struct atk_dl16_pwm *pwm;
	int duty;

	if (!devc || index >= ATK_DL16_NUM_PWM)
		return SR_ERR_ARG;
	if (!sdi->conn || sdi->status != SR_ST_ACTIVE)
		return SR_OK;	/* Stored; applied when the device is opened. */

	pwm = &devc->pwm[index];
	if (!pwm->enabled)
		return atk_dl16_pwm(sdi, (int)index, FALSE, 0, 0);

	if (atk_dl16_set_reset(sdi, TRUE) != SR_OK)
		return SR_ERR;

	duty = (int)(pwm->duty + 0.5);
	return atk_dl16_pwm(sdi, (int)index, TRUE, (uint64_t)pwm->freq, duty);
}

static void send_samples(const struct sr_dev_inst *sdi, const uint8_t *data,
	size_t nsamples)
{
	struct sr_datafeed_packet packet;
	struct sr_datafeed_logic logic;

	if (!nsamples)
		return;

	packet.type = SR_DF_LOGIC;
	packet.payload = &logic;
	logic.length = nsamples * ATK_DL16_UNITSIZE;
	logic.unitsize = ATK_DL16_UNITSIZE;
	logic.data = (void *)data;
	sr_session_send(sdi, &packet);
}

SR_PRIV void atk_dl16_free_buffers(struct dev_context *devc)
{
	int i;

	for (i = 0; i < ATK_DL16_NUM_CHANNELS; i++) {
		g_free(devc->chan_buf[i]);
		devc->chan_buf[i] = NULL;
		devc->chan_len[i] = 0;
		devc->chan_cap[i] = 0;
		devc->rle_pending[i] = FALSE;
		devc->rle_count[i] = 0;
		devc->chan_total[i] = 0;
		devc->expected[i] = 0;
	}
	g_free(devc->packbuf);
	devc->packbuf = NULL;
	devc->packcap = 0;
}

/* Append one frame's worth of bits to a channel's pending bitstream. */
static void chan_append(struct dev_context *devc, int ch, const uint8_t *data,
	size_t len)
{
	size_t need;

	if (ch < 0 || ch >= ATK_DL16_NUM_CHANNELS || !len)
		return;

	need = devc->chan_len[ch] + len;
	if (need > devc->chan_cap[ch]) {
		/* Round up generously; the round-robin keeps this rare. */
		devc->chan_cap[ch] = need * 2 + ATK_DL16_DATA_PER_FRAME;
		devc->chan_buf[ch] = g_realloc(devc->chan_buf[ch],
			devc->chan_cap[ch]);
	}
	memcpy(devc->chan_buf[ch] + devc->chan_len[ch], data, len);
	devc->chan_len[ch] = need;
	devc->chan_total[ch] += len;
}

/*
 * Expand a run-length encoded payload into the channel's bitstream.
 *
 * The encoding is byte-level, not sample-level: [count][value] pairs, where
 * `value` is one byte of the channel's bitstream repeated `count` times. The
 * count is a single byte, so runs cap at 255 and a long idle stretch becomes
 * a string of (255, 0x00) pairs. Counts of zero occur as end padding and
 * expand to nothing.
 *
 * This compresses an idle channel by about 100x and does nothing at all for
 * a signal with no repeating bytes - a 1 MHz square at 10 MHz has a 5-byte
 * period, so every count is 1 and the payload DOUBLES. That is inherent to
 * the format, not a fault.
 */
static void chan_append_rle(struct dev_context *devc, int ch,
	const uint8_t *data, size_t len)
{
	uint8_t run[256];
	size_t i = 0;
	uint8_t count;

	if (ch < 0 || ch >= ATK_DL16_NUM_CHANNELS)
		return;

	/* Finish a pair split across the previous frame. */
	if (devc->rle_pending[ch] && len) {
		count = devc->rle_count[ch];
		devc->rle_pending[ch] = FALSE;
		if (count) {
			memset(run, data[0], count);
			chan_append(devc, ch, run, count);
		}
		i = 1;
	}

	for (; i + 1 < len; i += 2) {
		count = data[i];
		if (!count)
			continue;
		memset(run, data[i + 1], count);
		chan_append(devc, ch, run, count);
	}

	/* Odd byte left over: a count awaiting its value. */
	if (i < len) {
		devc->rle_count[ch] = data[i];
		devc->rle_pending[ch] = TRUE;
	}
}

/*
 * Transpose whatever every channel has in common into libsigrok's packed
 * form and hand it to the session.
 *
 * Bit k of a channel byte is sample 8*b + k - LSB first, which is the order
 * the device's serialiser produces.
 */
static void flush_samples(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	size_t common, b, i, nsamples;
	uint16_t word;
	int ch, k;

	common = devc->chan_len[0];
	for (ch = 1; ch < ATK_DL16_NUM_CHANNELS; ch++)
		if (devc->chan_len[ch] < common)
			common = devc->chan_len[ch];
	if (!common)
		return;

	nsamples = common * 8;
	if (!devc->continuous) {
		if (devc->samples_sent >= devc->limit_samples)
			nsamples = 0;
		else if (devc->samples_sent + nsamples > devc->limit_samples)
			nsamples = devc->limit_samples - devc->samples_sent;
	}

	if (nsamples) {
		if (nsamples * ATK_DL16_UNITSIZE > devc->packcap) {
			devc->packcap = nsamples * ATK_DL16_UNITSIZE;
			devc->packbuf = g_realloc(devc->packbuf, devc->packcap);
		}
		for (i = 0; i < nsamples; i++) {
			b = i / 8;
			k = i % 8;
			word = 0;
			for (ch = 0; ch < ATK_DL16_NUM_CHANNELS; ch++)
				if ((devc->chan_buf[ch][b] >> k) & 1)
					word |= (uint16_t)1u << ch;
			devc->packbuf[i * 2 + 0] = word & 0xff;
			devc->packbuf[i * 2 + 1] = word >> 8;
		}
		send_samples(sdi, devc->packbuf, nsamples);
		devc->samples_sent += nsamples;
	}

	/* Retire the consumed bytes, keeping each channel's remainder. */
	for (ch = 0; ch < ATK_DL16_NUM_CHANNELS; ch++) {
		memmove(devc->chan_buf[ch], devc->chan_buf[ch] + common,
			devc->chan_len[ch] - common);
		devc->chan_len[ch] -= common;
	}
}

/* Decode one de-interleaved 2048-byte block. */
static void handle_block(const struct sr_dev_inst *sdi, const uint8_t *pc)
{
	struct dev_context *devc = sdi->priv;
	const uint8_t *payload;
	size_t len;
	uint8_t order, flags;
	int i, j;

	if (pc[0] != ATK_DL16_FRAME_HEADER)
		return;

	order = pc[1];
	len = (size_t)pc[2] | ((size_t)pc[3] << 8);
	if (len < 2 || ATK_DL16_RESP_HDR + len > ATK_DL16_BLOCK_SIZE)
		return;
	payload = pc + ATK_DL16_RESP_HDR;

	/*
	 * Everything before the device acknowledges this run's 0x12 belongs to
	 * the PREVIOUS capture. Draining beforehand is not enough on its own -
	 * residue can still be in flight - and a stale end-of-capture frame
	 * ends the new run instantly, which showed up as a 0-sample RLE
	 * capture right after a non-RLE one. The ack is the epoch boundary.
	 */
	if (!devc->armed && order != ATK_DL16_ORDER_ACK) {
		/*
		 * Sample data is itself proof the new run has started, so let
		 * it arm us too. Relying on the ack alone is brittle: miss it
		 * once and every subsequent frame is discarded, losing the
		 * whole capture to the read timeout. Admitting a few stale
		 * samples is much cheaper than that.
		 */
		if (order != ATK_DL16_ORDER_DATA) {
			sr_spew("Ignoring pre-arm order %u (%zu bytes).",
				order, len);
			return;
		}
		sr_dbg("Armed by first data frame (no ack seen).");
		devc->armed = TRUE;
	}

	switch (order) {
	case ATK_DL16_ORDER_DATA:
		if (devc->rle)
			chan_append_rle(devc, payload[0], payload + 2, len - 2);
		else
			chan_append(devc, payload[0], payload + 2, len - 2);
		break;
	case ATK_DL16_ORDER_TRIGPOS:
		/*
		 * Buffer mode also lists, per channel, exactly how many bytes
		 * this capture will deliver, followed by a flag byte:
		 *
		 *   [trigger pos:5] [byte count:5] x 16 [flags]
		 *
		 * That count is the only reliable completion signal. Ending on
		 * end-of-capture plus a quiet endpoint is guesswork, because
		 * the device emits order 6 early and pauses mid-transfer.
		 */
		/*
		 * Buffer mode only. In stream mode the frame is the same
		 * length but the per-channel counts are not there, and reading
		 * them anyway yields ~2^40 - which then looks like a capture
		 * that is permanently short.
		 */
		if (!devc->continuous && len >= 2 + ATK_DL16_TRIGPOS_LEN
		    && !devc->have_expected) {
			const uint8_t *p = payload + 2 + ATK_DL16_DEPTH_BYTES;
			for (i = 0; i < ATK_DL16_NUM_CHANNELS; i++) {
				devc->expected[i] = 0;
				for (j = 0; j < ATK_DL16_DEPTH_BYTES; j++)
					devc->expected[i] |=
						(uint64_t)p[i * ATK_DL16_DEPTH_BYTES + j]
						<< (8 * j);
			}
			devc->have_expected = TRUE;
			flags = payload[2 + ATK_DL16_TRIGPOS_LEN - 1];
			if (flags)
				sr_warn("Device reported capture overflow "
					"(flags 0x%02x): %s%s.", flags,
					(flags & 1) ? "capacity exceeded " : "",
					(flags & 2) ? "bandwidth exceeded" : "");
			sr_dbg("Expecting %" PRIu64 " bytes per channel.",
				devc->expected[0]);
		}
		if (len >= 2 + ATK_DL16_DEPTH_BYTES && !devc->trigger_pos_known) {
			devc->trigger_pos = 0;
			for (i = 0; i < ATK_DL16_DEPTH_BYTES; i++)
				devc->trigger_pos |= (uint64_t)payload[2 + i]
					<< (8 * i);
			devc->trigger_pos_known = TRUE;
			/*
			 * The device counts this from the END of the record,
			 * not the start. Verified by triggering on a 1 MHz
			 * square at 25 % capture ratio: the edge lands at
			 * limit - reported, i.e. at the ratio, which is what
			 * libsigrok means by the trigger position.
			 */
			sr_dbg("Trigger at sample %" PRIu64 " (device reported "
				"%" PRIu64 " from the end).",
				devc->limit_samples > devc->trigger_pos
					? devc->limit_samples - devc->trigger_pos
					: 0,
				devc->trigger_pos);
		}
		break;
	case ATK_DL16_ORDER_ACK:
		/*
		 * The device validates the trigger payload and reports the
		 * verdict here. Status 3 is "accepted"; anything else means it
		 * rejected the parameters and will never capture, so say so
		 * rather than sitting through the read timeout.
		 */
		if (len >= 4 && payload[2] == ATK_DL16_CMD_TRIGGER) {
			if (payload[3] != ATK_DL16_ACK_OK) {
				sr_err("Device rejected the acquisition "
					"parameters (status %u).", payload[3]);
				devc->failed = TRUE;
			} else if (!devc->armed) {
				sr_dbg("Armed; frames from here are ours.");
				devc->armed = TRUE;
			}
		}
		break;
	case ATK_DL16_ORDER_DONE:
		/*
		 * Capture finished. In stream mode the payload carries a flag
		 * that distinguishes "your capture ended" from "I could not
		 * keep up": the host is not draining the endpoint fast enough
		 * for the requested rate, and the device gave up. Without this
		 * an overrun looks like a successful short capture.
		 */
		if (devc->continuous && len >= 3 && payload[2] == 1
		    && !devc->overrun) {
			devc->overrun = TRUE;
			sr_warn("Device ran out of stream capacity at %"
				PRIu64 " Hz: USB cannot sustain %d channels "
				"at this rate. Lower the sample rate, or use "
				"buffered (non-continuous) acquisition.",
				devc->samplerate, ATK_DL16_NUM_CHANNELS);
		}
		/* The device repeats this as an idle heartbeat, so only the
		 * first one is interesting. */
		if (!devc->done_seen) {
			devc->done_seen = TRUE;
			sr_dbg("Device reported end of capture.");
		}
		break;
	case ATK_DL16_ORDER_PROGRESS:
		break;
	default:
		sr_spew("Unhandled response order %u (%zu bytes).", order, len);
		break;
	}
}

/*
 * Throw away anything the device still has queued.
 *
 * Needed at BOTH ends of a capture. Before arming, leftovers are the tail of
 * the previous run. After stopping, the backlog matters even more: the host
 * reaches its sample target while the device is still pushing, and leaving
 * that data in flight wedges the endpoint - the NEXT run then fails its very
 * first write with LIBUSB_ERROR_IO. RLE makes this easy to hit, because each
 * transferred byte expands to as many as 255, so the host finishes long
 * before the device does.
 */
SR_PRIV void atk_dl16_drain(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	struct sr_usb_dev_inst *usb = sdi->conn;
	int ret, transferred, i, empty;

	/*
	 * Be thorough. A previous capture can leave tens of megabytes queued,
	 * and anything left behind is not merely stale samples: it carries a
	 * stale end-of-capture frame that terminates the NEXT run early. That
	 * showed up as a 10 Msample request returning 4.6 Msamples.
	 */
	if (!devc->rxbuf)
		return;

	/*
	 * Require several consecutive empty reads. Breaking on the first one
	 * is not enough: the device pauses between bursts, so a single empty
	 * read means "nothing right now", not "nothing left". Residue that
	 * survives here carries the previous run's 0x12 ack and its
	 * end-of-capture, which together end the next run instantly.
	 */
	for (i = 0, empty = 0; i < 4096 && empty < 3; i++) {
		transferred = 0;
		ret = libusb_bulk_transfer(usb->devhdl, ATK_DL16_EP_IN,
			devc->rxbuf, ATK_DL16_READ_CHUNK, &transferred, 50);
		if (ret < 0)
			break;
		empty = transferred ? 0 : empty + 1;
	}
	if (i)
		sr_dbg("Drained %d stale transfer(s) before arming.", i);
}

SR_PRIV int atk_dl16_receive_data(int fd, int revents, void *cb_data)
{
	const struct sr_dev_inst *sdi = cb_data;
	struct dev_context *devc;
	struct sr_usb_dev_inst *usb;
	uint8_t *pc;
	size_t blocks, i;
	int ret, transferred, n;
	gboolean got_data, fatal, complete;

	(void)fd;
	(void)revents;

	if (!sdi || !(devc = sdi->priv))
		return TRUE;
	usb = sdi->conn;

	switch (devc->state) {
	case ATK_DL16_ACQ_ARM:
		if (atk_dl16_set_reset(sdi, TRUE) != SR_OK)
			break;
		g_usleep(50000);
		/*
		 * Drain only - do NOT send 0x15 here. The vendor's arming
		 * sequence is wake, drain, param, trigger, and slipping a stop
		 * in front of it makes the device cut captures short after a
		 * handful of frames. Stopping is the teardown's job.
		 */
		atk_dl16_drain(sdi);
		if (atk_dl16_send_param(sdi) != SR_OK)
			break;
		g_usleep(50000);
		if (atk_dl16_send_trigger(sdi) != SR_OK)
			break;
		devc->state = ATK_DL16_ACQ_READ;
		devc->started_us = g_get_monotonic_time();
		return TRUE;

	case ATK_DL16_ACQ_READ:
		got_data = FALSE;
		fatal = FALSE;
		for (n = 0; n < ATK_DL16_READS_PER_POLL; n++) {
			ret = libusb_bulk_transfer(usb->devhdl, ATK_DL16_EP_IN,
				devc->rxbuf, ATK_DL16_READ_CHUNK, &transferred,
				ATK_DL16_BULK_TIMEOUT_MS);
			if (ret == LIBUSB_ERROR_TIMEOUT || transferred == 0)
				break;
			if (ret < 0) {
				sr_err("Bulk read failed: %s.",
					libusb_error_name(ret));
				fatal = TRUE;
				break;
			}
			got_data = TRUE;
			devc->empty_polls = 0;

			blocks = (size_t)transferred / ATK_DL16_BLOCK_SIZE;
			if (!blocks)
				continue;
			pc = devc->pcbuf;
			atk_dl16_deinterleave(devc->rxbuf, pc, blocks);
			for (i = 0; i < blocks; i++)
				handle_block(sdi,
					pc + i * ATK_DL16_BLOCK_SIZE);

			if (devc->failed)
				break;
			/* Short transfer: the device has nothing more ready. */
			if ((size_t)transferred < ATK_DL16_READ_CHUNK)
				break;
		}

		if (!got_data) {
			/*
			 * A whole poll with nothing at all. Only now is an
			 * end-of-capture trustworthy: the device emits order 6
			 * more than once and can do so while frames are still
			 * queued, so acting on it any earlier truncates the
			 * record. A short transfer does NOT mean "finished" -
			 * it just means the next chunk is not ready yet.
			 */
			devc->empty_polls++;
			/*
			 * Several consecutive empty polls, not one. A single
			 * read timeout only means the next burst has not
			 * arrived yet - the device pauses for well over the
			 * 500 ms bulk timeout while streaming, and treating
			 * the first gap as the end truncated continuous
			 * captures roughly half the time.
			 */
			if (devc->done_seen
			    && devc->empty_polls >= ATK_DL16_EMPTY_POLLS_DONE) {
				/*
				 * The device promised a byte count and stopped
				 * short of it. Waiting does not help - the
				 * missing frames are never sent, confirmed by
				 * holding the endpoint open for 17 s. Say so
				 * rather than passing off a truncated record
				 * as a complete one.
				 */
				if (devc->have_expected
				    && devc->chan_total[0] < devc->expected[0]) {
					sr_err("Short capture: device sent %"
						PRIu64 " of %" PRIu64 " bytes "
						"per channel (%" PRIu64
						" samples of %" PRIu64
						"). The data is not recoverable;"
						" retry the acquisition.",
						devc->chan_total[0],
						devc->expected[0],
						devc->samples_sent,
						devc->limit_samples);
					break;
				}
				if (devc->samples_sent) {
					sr_info("Capture complete, %" PRIu64
						" samples.", devc->samples_sent);
				} else if (devc->rle) {
					/*
					 * Seen with RLE and an incompressible
					 * signal: every count is 1, so the
					 * payload is twice the raw size and the
					 * device abandons the capture at once.
					 */
					sr_err("Device ended the capture "
						"without returning data. With "
						"RLE this means the signal did "
						"not compress; turn RLE off.");
				} else {
					sr_err("Device ended the capture "
						"without returning any data.");
				}
				break;
			}
			/*
			 * End-of-capture with nothing received at all is far
			 * more likely to be a leftover frame than a real empty
			 * capture, so do not trust it - let the timeout below
			 * decide. A trigger that never fires ends up there too.
			 */
			/* Still waiting for the trigger, or between blocks. */
			if (!devc->continuous && devc->samples_sent == 0
			    && g_get_monotonic_time() - devc->started_us
				> 10 * G_TIME_SPAN_SECOND) {
				sr_err("No data within 10 s; giving up.");
				break;
			}
			return TRUE;
		}

		flush_samples(sdi);

		if (fatal || devc->failed)
			break;

		/*
		 * Authoritative completion: every channel has delivered the
		 * byte count order 3 promised. This is exact, so it finishes
		 * the moment the data is in rather than waiting out a quiet
		 * period, and it cannot be fooled by the early end-of-capture
		 * frame the device likes to send.
		 */
		if (devc->have_expected) {
			complete = TRUE;
			for (i = 0; i < ATK_DL16_NUM_CHANNELS; i++) {
				if (devc->chan_total[i] < devc->expected[i]) {
					complete = FALSE;
					break;
				}
			}
			if (complete) {
				sr_info("Acquired %" PRIu64 " samples.",
					devc->samples_sent);
				break;
			}
		}
		if (!devc->continuous
		    && devc->samples_sent >= devc->limit_samples) {
			sr_info("Acquired %" PRIu64 " samples.",
				devc->samples_sent);
			break;
		}
		return TRUE;

	default:
		break;
	}

	devc->state = ATK_DL16_ACQ_DONE;
	sr_dev_acquisition_stop((struct sr_dev_inst *)sdi);

	return TRUE;
}
