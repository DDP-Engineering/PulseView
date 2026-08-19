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

#ifndef LIBSIGROK_HARDWARE_ATK_DL16_PROTOCOL_H
#define LIBSIGROK_HARDWARE_ATK_DL16_PROTOCOL_H

#include <stdint.h>
#include <glib.h>
#include <libsigrok/libsigrok.h>
#include "libsigrok-internal.h"

#define LOG_PREFIX "atk-dl16"

/*
 * ALIENTEK ATK DL16 (DL16 Plus / Pro): a 16-channel USB logic analyzer.
 *
 * The vendor application is not PulseView and does not use libsigrok - it is
 * a separate Qt/QML program with its own libusb layer. Only its protocol
 * decoders are shared with sigrok. This driver therefore talks to the
 * instrument directly; the wire protocol was recovered from the vendor's
 * GPL-3.0 sources and verified against hardware with USB captures.
 *
 * Protocol reference: 04_HardwareDocu/ATK_DL16/Protocol_Extraction.md
 */
#define ATK_DL16_VID			0x1a86
#define ATK_DL16_PID			0xffcc

#define ATK_DL16_USB_CONFIGURATION	1
#define ATK_DL16_USB_INTERFACE		0

#define ATK_DL16_EP_OUT			0x02
#define ATK_DL16_EP_IN			0x81

/*
 * Frame layout, confirmed on the wire:
 *
 *     [0x0A] [cmd] [len] [data ...] [0x0B] [CRC32 little-endian]
 *
 * `len` counts the data bytes PLUS the 0x0B footer, so a command with no
 * payload carries len = 1.
 */
#define ATK_DL16_FRAME_HEADER		0x0a
#define ATK_DL16_FRAME_FOOTER		0x0b

/* Commands. */
#define ATK_DL16_CMD_GET_DATA		0x10
#define ATK_DL16_CMD_PARAM		0x11
#define ATK_DL16_CMD_TRIGGER		0x12
#define ATK_DL16_CMD_STOP		0x15
#define ATK_DL16_CMD_PWM		0x17
#define ATK_DL16_CMD_EXIT		0x18
#define ATK_DL16_CMD_MCU_VERSION	0x81
#define ATK_DL16_CMD_SET_RESET		0x87
#define ATK_DL16_CMD_GET_RESET		0x88

/*
 * Three transport classes, a distinction only visible on the wire:
 *
 *   - Acquisition commands (0x11, 0x12, 0x15) are word-interleaved and
 *     padded to 2048 bytes, exactly like sample data.
 *   - MCU-side commands (0x87 reset control) are NOT frames at all: a plain
 *     512-byte write whose only meaningful content is 0x0a, the opcode and
 *     one argument byte. No length, no 0x0b footer, no CRC.
 *   - PWM (0x17) goes out as a short, un-interleaved frame.
 *
 * The CRC is always computed over the LOGICAL frame, before interleaving.
 */
#define ATK_DL16_MCU_WRITE_LEN		512
#define ATK_DL16_BLOCK_SIZE		2048
#define ATK_DL16_SEGMENT_SIZE		512
/* The interleaved form begins with four zero words before the frame. */
#define ATK_DL16_INTERLEAVE_LEAD	8

/*
 * Bulk IN transfers for sample data. A whole number of blocks, so a transfer
 * never splits a frame.
 *
 * The session source is a timed poll, so one read per callback caps the
 * driver at chunk/interval regardless of what USB can do - at 16 KiB per
 * 10 ms that is 1.6 MB/s, and a 50 Msample capture took 102 s. Read a batch
 * per callback instead, bounded so the session loop still gets a turn.
 */
#define ATK_DL16_READ_CHUNK		65536
#define ATK_DL16_READS_PER_POLL		48
/* Consecutive fully-empty polls before an end-of-capture is acted on. */
#define ATK_DL16_EMPTY_POLLS_DONE	4

/*
 * Response framing. Every bulk-IN block carries EXACTLY ONE logical frame,
 * at block offset 0 once de-interleaved, with the tail padded out using
 * 0x0b 0x00 filler words. There is no need to scan for the 0x0a header and
 * no frame ever straddles a block boundary - which is just as well, since
 * sample payloads are opaque and would defeat any search.
 *
 *     [0x0a] [order] [len16] [chanID] [0x00] [data ...] [0x0b] [padding]
 *
 * `len` counts the two bytes after it plus the data, so data is len - 2.
 * The chanID byte is 0xff on every frame that is not sample data.
 */
#define ATK_DL16_RESP_HDR		4
#define ATK_DL16_RESP_NOCHAN		0xff

/* Response `order` codes. */
#define ATK_DL16_ORDER_DATA		1	/* per-channel bitstream */
#define ATK_DL16_ORDER_TRIGPOS		3	/* trigger position */
#define ATK_DL16_ORDER_ACK		4	/* command acknowledge */
#define ATK_DL16_ORDER_PROGRESS		5	/* samples captured so far */
#define ATK_DL16_ORDER_DONE		6	/* capture/transfer finished */

/* Status byte in an order-4 acknowledgement of 0x12 that means "accepted". */
#define ATK_DL16_ACK_OK			3

/*
 * Order 3 in buffer mode: 5-byte trigger position, then a 5-byte byte count
 * for each channel, then one flag byte (bit0 capacity, bit1 bandwidth).
 */
#define ATK_DL16_TRIGPOS_LEN	(ATK_DL16_DEPTH_BYTES * (1 + ATK_DL16_NUM_CHANNELS) + 1)

#define ATK_DL16_USB_TIMEOUT_MS		1000
#define ATK_DL16_BULK_TIMEOUT_MS	500

#define ATK_DL16_NUM_CHANNELS		16
/* libsigrok wants one little-endian 16-bit word per sample, one bit per
 * channel. The device does NOT send that: it sends each channel's bits as
 * a separate stream, so the driver has to transpose. */
#define ATK_DL16_UNITSIZE		2
/* Bitstream payload carried by a full sample frame (2034 - 2 header bytes). */
#define ATK_DL16_DATA_PER_FRAME		2032

/*
 * ParameterSetting (0x11) payload, 13 bytes:
 *
 *   [0]     flags: bit7 = buffer mode, bit6 = RLE
 *   [1]     threshold: bit7 = sign, bits 0-6 = |volts| * 10
 *   [2]     sample-rate index + 1
 *   [3..7]  sampling depth, 5-byte little-endian
 *   [8..12] trigger-position depth, 5-byte little-endian
 */
#define ATK_DL16_PARAM_LEN		13
#define ATK_DL16_FLAG_BUFFER		0x80
#define ATK_DL16_FLAG_RLE		0x40
#define ATK_DL16_DEPTH_BYTES		5

/*
 * SimpleTrigger (0x12) payload, 9 bytes: eight channel bytes packing two
 * channels each, then isInstantly. There is deliberately no roll/stream byte
 * here - buffer versus stream is chosen by bit 7 of the ParameterSetting
 * flags and nowhere else.
 *
 * Even channel = high nibble, odd channel = low nibble (proven by driving
 * D1 alone and watching the low nibble change). Per nibble:
 *
 *   bit3 enable   bit2 high level   bit1 falling   bit0 rising
 *
 * The condition bits are a MASK OF STATES THAT SATISFY the trigger, which
 * has a consequence that is easy to get wrong: an enabled channel with no
 * condition must be 0xF (all three set = "any state"), NOT 0x0. Leaving
 * them clear requests LOW LEVEL on every channel and never triggers.
 */
#define ATK_DL16_TRIGGER_LEN		9
#define ATK_DL16_TRG_ENABLE		0x8
#define ATK_DL16_TRG_HIGH		0x4
#define ATK_DL16_TRG_FALLING		0x2
#define ATK_DL16_TRG_RISING		0x1
#define ATK_DL16_TRG_ANY		(ATK_DL16_TRG_HIGH | \
					 ATK_DL16_TRG_FALLING | \
					 ATK_DL16_TRG_RISING)

/* PWM (0x17): period and high time in ticks of a 200 MHz base clock. */
#define ATK_DL16_PWM_BASE_HZ		SR_MHZ(200)
#define ATK_DL16_PWM0_START		0x11
#define ATK_DL16_PWM1_START		0x21
#define ATK_DL16_PWM0_STOP		0x10
#define ATK_DL16_PWM1_STOP		0x20

/*
 * The device accepts only these discrete rates - the wire carries an index
 * into this table, not a frequency. Note the floor of 1 MHz: there is no
 * sub-megahertz sampling, and the ladder is not a clean 1-2-5.
 */
#define ATK_DL16_NUM_SAMPLERATES	13
SR_PRIV extern const uint64_t atk_dl16_samplerates[ATK_DL16_NUM_SAMPLERATES];

/*
 * Threshold presets. The vendor UI labels these by logic family - "3.3 V
 * CMOS" and so on - but the value sent is the comparator threshold, which
 * is a different number entirely. Confirmed on the wire and against the
 * application's own Vth readout.
 */
#define ATK_DL16_NUM_THRESHOLDS		7
SR_PRIV extern const double atk_dl16_thresholds[ATK_DL16_NUM_THRESHOLDS];

enum atk_dl16_acq_state {
	ATK_DL16_ACQ_IDLE = 0,
	ATK_DL16_ACQ_ARM,
	ATK_DL16_ACQ_READ,
	ATK_DL16_ACQ_DONE,
};

struct dev_context {
	/* Configuration. */
	uint64_t samplerate;
	uint64_t limit_samples;
	uint64_t capture_ratio;
	double threshold;
	gboolean continuous;
	gboolean rle;

	/* Trigger, parsed from the session into per-channel nibbles. */
	uint8_t trigger_bytes[8];
	gboolean trigger_set;

	/* Acquisition state. */
	enum atk_dl16_acq_state state;
	uint64_t samples_sent;
	uint8_t *rxbuf;
	uint8_t *pcbuf;		/* de-interleaved scratch, same size as rxbuf */
	size_t rxlen;
	int64_t started_us;

	/*
	 * Per-channel bitstreams, waiting to be transposed. The device deals
	 * frames out round-robin, so these stay within a frame or two of each
	 * other; whatever length they all share can be emitted and dropped.
	 */
	uint8_t *chan_buf[ATK_DL16_NUM_CHANNELS];
	size_t chan_len[ATK_DL16_NUM_CHANNELS];
	size_t chan_cap[ATK_DL16_NUM_CHANNELS];
	uint8_t *packbuf;
	size_t packcap;
	/*
	 * RLE reassembly. A pair can straddle a frame boundary, so each
	 * channel remembers a count byte whose value has not arrived yet.
	 */
	uint8_t rle_count[ATK_DL16_NUM_CHANNELS];
	gboolean rle_pending[ATK_DL16_NUM_CHANNELS];
	uint64_t trigger_pos;
	gboolean trigger_pos_known;
	gboolean done_seen;
	gboolean armed;
	gboolean overrun;
	int empty_polls;
	/* Bytes delivered so far, and the per-channel totals order 3 promises. */
	uint64_t chan_total[ATK_DL16_NUM_CHANNELS];
	uint64_t expected[ATK_DL16_NUM_CHANNELS];
	gboolean have_expected;
	gboolean failed;
};

SR_PRIV uint32_t atk_dl16_crc32(const uint8_t *data, size_t len);
SR_PRIV int atk_dl16_send_frame(const struct sr_dev_inst *sdi, uint8_t cmd,
	const uint8_t *data, size_t datalen, gboolean interleave);
SR_PRIV void atk_dl16_deinterleave(const uint8_t *src, uint8_t *dst,
	size_t blocks);

SR_PRIV int atk_dl16_set_reset(const struct sr_dev_inst *sdi, gboolean active);
SR_PRIV int atk_dl16_send_param(const struct sr_dev_inst *sdi);
SR_PRIV int atk_dl16_send_trigger(const struct sr_dev_inst *sdi);
SR_PRIV int atk_dl16_stop(const struct sr_dev_inst *sdi);
SR_PRIV void atk_dl16_drain(const struct sr_dev_inst *sdi);
SR_PRIV int atk_dl16_pwm(const struct sr_dev_inst *sdi, int index,
	gboolean enable, uint64_t hz, int duty);

SR_PRIV void atk_dl16_parse_trigger(const struct sr_dev_inst *sdi);
SR_PRIV int atk_dl16_receive_data(int fd, int revents, void *cb_data);
SR_PRIV void atk_dl16_free_buffers(struct dev_context *devc);

#endif
