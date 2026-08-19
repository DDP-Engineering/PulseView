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

/*
 * ALIENTEK ATK DL16: 16-channel USB logic analyzer.
 *
 * Unlike most logic analyzers in this tree, the trigger is done in HARDWARE:
 * the instrument accepts a per-channel condition mask, so SR_CONF_TRIGGER_MATCH
 * maps one-to-one onto the wire format and no host-side matching is needed.
 */

#include <config.h>
#include <libusb.h>
#include "protocol.h"

static const uint32_t scanopts[] = {
	SR_CONF_CONN,
};

static const uint32_t drvopts[] = {
	SR_CONF_LOGIC_ANALYZER,
};

static const uint32_t devopts[] = {
	SR_CONF_CONN | SR_CONF_GET,
	SR_CONF_SAMPLERATE | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_LIMIT_SAMPLES | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_CAPTURE_RATIO | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_VOLTAGE_THRESHOLD | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_LOGIC_THRESHOLD_CUSTOM | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_CONTINUOUS | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_RLE | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_TRIGGER_MATCH | SR_CONF_LIST,
};

/*
 * Per-channel-group options. The logic group carries nothing of its own -
 * everything meaningful for capture is a device-level option - but it has to
 * exist so the group can be listed alongside the PWM ones.
 */
static const uint32_t devopts_cg_logic[] = {
	SR_CONF_TRIGGER_MATCH | SR_CONF_LIST,
};

static const uint32_t devopts_cg_pwm[] = {
	SR_CONF_ENABLED | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_OUTPUT_FREQUENCY | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_DUTY_CYCLE | SR_CONF_GET | SR_CONF_SET,
};

/* The device evaluates all of these in hardware, per channel. */
static const int32_t trigger_matches[] = {
	SR_TRIGGER_ZERO,
	SR_TRIGGER_ONE,
	SR_TRIGGER_RISING,
	SR_TRIGGER_FALLING,
	SR_TRIGGER_EDGE,
};

/*
 * Threshold presets, as low/high pairs. The instrument has a single
 * comparator level rather than a hysteresis band, so both halves of each
 * pair carry the same value.
 */
static double threshold_ranges[ATK_DL16_NUM_THRESHOLDS][2];

/*
 * Depth limits.
 *
 * The wire field is five bytes and the manual quotes 1 Gbit of capture
 * memory, which is where the old 1 G sample ceiling came from. Measured, the
 * device stops at about 266.3 Msamples across all 16 channels: asking for
 * 500 M or 1 G returns 266,336,384 and 266,334,336 samples respectively -
 * short, and WITHOUT reporting an error, so an over-large request silently
 * yields a truncated record.
 *
 * Advertise a round number safely below that, so the limit is enforced up
 * front with a clear message instead of surfacing as a partial capture.
 */
#define ATK_DL16_MIN_SAMPLES	1024
#define ATK_DL16_MAX_SAMPLES	(256 * 1000 * 1000)

#define ATK_DL16_DEFAULT_SAMPLERATE	SR_MHZ(10)
#define ATK_DL16_DEFAULT_SAMPLES	1000000
#define ATK_DL16_DEFAULT_THRESHOLD	1.6	/* the 3.3 V CMOS preset */
#define ATK_DL16_DEFAULT_PWM_HZ		1000.0
#define ATK_DL16_DEFAULT_PWM_DUTY	50.0

static struct sr_dev_driver atk_dl16_driver_info;

static GSList *scan(struct sr_dev_driver *di, GSList *options)
{
	struct drv_context *drvc;
	struct dev_context *devc;
	struct sr_dev_inst *sdi;
	struct sr_config *src;
	struct sr_channel *ch;
	struct sr_channel_group *cg;
	struct sr_usb_dev_inst *usb;
	struct libusb_device_descriptor des;
	libusb_device **devlist;
	GSList *l, *devices, *conn_devices;
	const char *conn;
	char connection_id[64];
	char channel_name[8];
	int i, j;

	drvc = di->context;
	devices = NULL;
	conn = NULL;

	for (l = options; l; l = l->next) {
		src = l->data;
		if (src->key == SR_CONF_CONN) {
			conn = g_variant_get_string(src->data, NULL);
			break;
		}
	}

	conn_devices = conn ? sr_usb_find(drvc->sr_ctx->libusb_ctx, conn) : NULL;

	libusb_get_device_list(drvc->sr_ctx->libusb_ctx, &devlist);
	for (i = 0; devlist[i]; i++) {
		if (conn) {
			usb = NULL;
			for (l = conn_devices; l; l = l->next) {
				usb = l->data;
				if (usb->bus == libusb_get_bus_number(devlist[i])
				    && usb->address == libusb_get_device_address(devlist[i]))
					break;
			}
			if (!l)
				continue;
		}

		libusb_get_device_descriptor(devlist[i], &des);
		if (des.idVendor != ATK_DL16_VID || des.idProduct != ATK_DL16_PID)
			continue;
		if (usb_get_port_path(devlist[i], connection_id,
				sizeof(connection_id)) < 0)
			continue;

		sdi = g_malloc0(sizeof(struct sr_dev_inst));
		sdi->status = SR_ST_INITIALIZING;
		sdi->vendor = g_strdup("ALIENTEK");
		sdi->model = g_strdup("ATK DL16");
		sdi->connection_id = g_strdup(connection_id);
		sdi->inst_type = SR_INST_USB;
		sdi->conn = sr_usb_dev_inst_new(
			libusb_get_bus_number(devlist[i]),
			libusb_get_device_address(devlist[i]), NULL);

		/* A logic channel's index is its bit position in the packed
		 * sample word, so D0 must be index 0. */
		cg = sr_channel_group_new(sdi, "Logic", NULL);
		for (j = 0; j < ATK_DL16_NUM_CHANNELS; j++) {
			g_snprintf(channel_name, sizeof(channel_name), "D%d", j);
			ch = sr_channel_new(sdi, j, SR_CHANNEL_LOGIC, TRUE,
				channel_name);
			cg->channels = g_slist_append(cg->channels, ch);
		}

		/*
		 * The two PWM generators. Named for what the vendor UI calls
		 * them, so "PWM0" here is the pin labelled PWM0 on the device.
		 * Their channels are analog and disabled by default: they are
		 * outputs, and nothing about them is ever captured.
		 */
		for (j = 0; j < ATK_DL16_NUM_PWM; j++) {
			g_snprintf(channel_name, sizeof(channel_name), "PWM%d", j);
			cg = sr_channel_group_new(sdi, channel_name, NULL);
			ch = sr_channel_new(sdi, ATK_DL16_NUM_CHANNELS + j,
				SR_CHANNEL_ANALOG, FALSE, channel_name);
			cg->channels = g_slist_append(cg->channels, ch);
		}

		devc = g_malloc0(sizeof(struct dev_context));
		devc->samplerate = ATK_DL16_DEFAULT_SAMPLERATE;
		devc->limit_samples = ATK_DL16_DEFAULT_SAMPLES;
		devc->capture_ratio = 1;
		devc->threshold = ATK_DL16_DEFAULT_THRESHOLD;
		devc->continuous = FALSE;
		devc->rle = FALSE;
		for (j = 0; j < ATK_DL16_NUM_PWM; j++) {
			devc->pwm[j].enabled = FALSE;
			devc->pwm[j].freq = ATK_DL16_DEFAULT_PWM_HZ;
			devc->pwm[j].duty = ATK_DL16_DEFAULT_PWM_DUTY;
		}
		sdi->priv = devc;

		devices = g_slist_append(devices, sdi);
	}
	libusb_free_device_list(devlist, 1);
	g_slist_free_full(conn_devices, (GDestroyNotify)sr_usb_dev_inst_free);

	return std_scan_complete(di, devices);
}

static int dev_open(struct sr_dev_inst *sdi)
{
	struct sr_dev_driver *di = sdi->driver;
	struct drv_context *drvc = di->context;
	struct sr_usb_dev_inst *usb = sdi->conn;
	struct dev_context *devc;
	size_t i;
	int ret;

	ret = sr_usb_open(drvc->sr_ctx->libusb_ctx, usb);
	if (ret != SR_OK)
		return ret;

	/*
	 * On Windows the device is normally bound to WinUSB by the vendor's
	 * installer (libwdi); if something else owns it, say so plainly
	 * rather than returning a bare error code.
	 */
	ret = libusb_claim_interface(usb->devhdl, ATK_DL16_USB_INTERFACE);
	if (ret < 0) {
		sr_err("Failed to claim interface %d: %s.",
			ATK_DL16_USB_INTERFACE, libusb_error_name(ret));
		if (ret == LIBUSB_ERROR_ACCESS || ret == LIBUSB_ERROR_BUSY)
			sr_err("The device is claimed by another driver or "
				"application. Close ATK-Logic; on Windows the "
				"interface must be bound to WinUSB.");
		sr_usb_close(usb);
		return SR_ERR;
	}

	/*
	 * Push any PWM settings made before the device was opened. config_set
	 * stores them and returns early when there is no connection yet, which
	 * is the normal order for `sigrok-cli --config`.
	 */
	sdi->status = SR_ST_ACTIVE;
	for (i = 0; i < ATK_DL16_NUM_PWM; i++) {
		devc = sdi->priv;
		if (devc && devc->pwm[i].enabled)
			atk_dl16_pwm_apply(sdi, i);
	}

	return SR_OK;
}

static int dev_close(struct sr_dev_inst *sdi)
{
	struct sr_usb_dev_inst *usb = sdi->conn;

	if (!usb || !usb->devhdl)
		return SR_ERR_BUG;

	libusb_release_interface(usb->devhdl, ATK_DL16_USB_INTERFACE);
	sr_usb_close(usb);

	return SR_OK;
}

/*
 * Which channel group is this? Returns the PWM index in *pwm_idx when the
 * group is one of the generators.
 *
 * Groups are created in a fixed order in scan(): "Logic" first, then "PWM0"
 * and "PWM1". Matching on position rather than on the name avoids depending
 * on string comparison for something that is structural.
 */
enum atk_dl16_cg_type {
	ATK_DL16_CG_NONE = 0,	/* no group given: a device-level option */
	ATK_DL16_CG_LOGIC,
	ATK_DL16_CG_PWM,
};

static enum atk_dl16_cg_type cg_kind(const struct sr_dev_inst *sdi,
	const struct sr_channel_group *cg, size_t *pwm_idx)
{
	GSList *l;
	size_t i;

	if (pwm_idx)
		*pwm_idx = 0;
	if (!cg)
		return ATK_DL16_CG_NONE;

	l = sdi->channel_groups;
	if (l && cg == l->data)
		return ATK_DL16_CG_LOGIC;

	for (i = 0; i < ATK_DL16_NUM_PWM; i++) {
		if (!l || !(l = l->next))
			break;
		if (cg == l->data) {
			if (pwm_idx)
				*pwm_idx = i;
			return ATK_DL16_CG_PWM;
		}
	}

	return ATK_DL16_CG_NONE;
}

static int config_get(uint32_t key, GVariant **data,
	const struct sr_dev_inst *sdi, const struct sr_channel_group *cg)
{
	struct dev_context *devc;
	struct sr_usb_dev_inst *usb;
	size_t pwm_idx;

	if (!sdi)
		return SR_ERR_ARG;
	devc = sdi->priv;

	if (cg_kind(sdi, cg, &pwm_idx) == ATK_DL16_CG_PWM) {
		switch (key) {
		case SR_CONF_ENABLED:
			*data = g_variant_new_boolean(devc->pwm[pwm_idx].enabled);
			return SR_OK;
		case SR_CONF_OUTPUT_FREQUENCY:
			*data = g_variant_new_double(devc->pwm[pwm_idx].freq);
			return SR_OK;
		case SR_CONF_DUTY_CYCLE:
			*data = g_variant_new_double(devc->pwm[pwm_idx].duty);
			return SR_OK;
		default:
			return SR_ERR_NA;
		}
	}

	switch (key) {
	case SR_CONF_CONN:
		if (!sdi->conn)
			return SR_ERR_ARG;
		usb = sdi->conn;
		*data = g_variant_new_printf("%d.%d", usb->bus, usb->address);
		break;
	case SR_CONF_SAMPLERATE:
		*data = g_variant_new_uint64(devc->samplerate);
		break;
	case SR_CONF_LIMIT_SAMPLES:
		*data = g_variant_new_uint64(devc->limit_samples);
		break;
	case SR_CONF_CAPTURE_RATIO:
		*data = g_variant_new_uint64(devc->capture_ratio);
		break;
	case SR_CONF_LOGIC_THRESHOLD_CUSTOM:
		*data = g_variant_new_double(devc->threshold);
		break;
	case SR_CONF_VOLTAGE_THRESHOLD:
		*data = std_gvar_tuple_double(devc->threshold, devc->threshold);
		break;
	case SR_CONF_CONTINUOUS:
		*data = g_variant_new_boolean(devc->continuous);
		break;
	case SR_CONF_RLE:
		*data = g_variant_new_boolean(devc->rle);
		break;
	default:
		return SR_ERR_NA;
	}

	return SR_OK;
}

static int config_set(uint32_t key, GVariant *data,
	const struct sr_dev_inst *sdi, const struct sr_channel_group *cg)
{
	struct dev_context *devc;
	uint64_t v;
	double d;
	size_t pwm_idx;
	int idx;

	if (!sdi)
		return SR_ERR_ARG;
	devc = sdi->priv;

	/*
	 * PWM settings take effect immediately when the device is open, so the
	 * generator responds to a config change without waiting for a capture
	 * that may never be started - these are outputs, and driving a signal
	 * is often the only thing the user wants from them.
	 */
	if (cg_kind(sdi, cg, &pwm_idx) == ATK_DL16_CG_PWM) {
		switch (key) {
		case SR_CONF_ENABLED:
			devc->pwm[pwm_idx].enabled = g_variant_get_boolean(data);
			break;
		case SR_CONF_OUTPUT_FREQUENCY:
			d = g_variant_get_double(data);
			if (d <= 0.0 || d > (double)ATK_DL16_PWM_MAX_HZ) {
				sr_err("PWM frequency must be above 0 and at most "
					"%" PRIu64 " Hz.",
					(uint64_t)ATK_DL16_PWM_MAX_HZ);
				return SR_ERR_ARG;
			}
			devc->pwm[pwm_idx].freq = d;
			break;
		case SR_CONF_DUTY_CYCLE:
			d = g_variant_get_double(data);
			if (d <= 0.0 || d >= 100.0) {
				sr_err("PWM duty cycle must be between 0 and 100 "
					"percent, exclusive.");
				return SR_ERR_ARG;
			}
			devc->pwm[pwm_idx].duty = d;
			break;
		default:
			return SR_ERR_NA;
		}
		return atk_dl16_pwm_apply(sdi, pwm_idx);
	}

	switch (key) {
	case SR_CONF_SAMPLERATE:
		v = g_variant_get_uint64(data);
		/*
		 * The wire carries an index into a fixed table, so an
		 * unlisted rate cannot be approximated - reject it rather
		 * than silently capturing at something else.
		 */
		for (idx = 0; idx < ATK_DL16_NUM_SAMPLERATES; idx++) {
			if (atk_dl16_samplerates[idx] == v) {
				devc->samplerate = v;
				return SR_OK;
			}
		}
		sr_err("Unsupported sample rate %" PRIu64 " Hz.", v);
		return SR_ERR_ARG;
	case SR_CONF_LIMIT_SAMPLES:
		v = g_variant_get_uint64(data);
		if (v < ATK_DL16_MIN_SAMPLES || v > ATK_DL16_MAX_SAMPLES) {
			sr_err("Sample count %" PRIu64 " outside %d..%d.", v,
				ATK_DL16_MIN_SAMPLES, ATK_DL16_MAX_SAMPLES);
			return SR_ERR_ARG;
		}
		devc->limit_samples = v;
		break;
	case SR_CONF_CAPTURE_RATIO:
		v = g_variant_get_uint64(data);
		/* The vendor UI allows 1..90 %. */
		if (v < 1 || v > 90)
			return SR_ERR_ARG;
		devc->capture_ratio = v;
		break;
	case SR_CONF_LOGIC_THRESHOLD_CUSTOM:
		devc->threshold = g_variant_get_double(data);
		break;
	case SR_CONF_VOLTAGE_THRESHOLD:
		idx = std_double_tuple_idx(data,
			ARRAY_AND_SIZE(threshold_ranges));
		if (idx < 0)
			return SR_ERR_ARG;
		devc->threshold = threshold_ranges[idx][0];
		break;
	case SR_CONF_CONTINUOUS:
		devc->continuous = g_variant_get_boolean(data);
		break;
	case SR_CONF_RLE:
		devc->rle = g_variant_get_boolean(data);
		break;
	default:
		return SR_ERR_NA;
	}

	return SR_OK;
}

static int config_list(uint32_t key, GVariant **data,
	const struct sr_dev_inst *sdi, const struct sr_channel_group *cg)
{
	enum atk_dl16_cg_type kind;

	kind = sdi ? cg_kind(sdi, cg, NULL) : ATK_DL16_CG_NONE;

	if (kind == ATK_DL16_CG_PWM) {
		if (key != SR_CONF_DEVICE_OPTIONS)
			return SR_ERR_NA;
		*data = std_gvar_array_u32(ARRAY_AND_SIZE(devopts_cg_pwm));
		return SR_OK;
	}
	if (kind == ATK_DL16_CG_LOGIC) {
		switch (key) {
		case SR_CONF_DEVICE_OPTIONS:
			*data = std_gvar_array_u32(ARRAY_AND_SIZE(devopts_cg_logic));
			return SR_OK;
		case SR_CONF_TRIGGER_MATCH:
			*data = std_gvar_array_i32(ARRAY_AND_SIZE(trigger_matches));
			return SR_OK;
		default:
			return SR_ERR_NA;
		}
	}

	switch (key) {
	case SR_CONF_SAMPLERATE:
		*data = std_gvar_samplerates(atk_dl16_samplerates,
			ATK_DL16_NUM_SAMPLERATES);
		break;
	case SR_CONF_LIMIT_SAMPLES:
		*data = std_gvar_tuple_u64(ATK_DL16_MIN_SAMPLES,
			ATK_DL16_MAX_SAMPLES);
		break;
	case SR_CONF_VOLTAGE_THRESHOLD:
		*data = std_gvar_thresholds(ARRAY_AND_SIZE(threshold_ranges));
		break;
	case SR_CONF_TRIGGER_MATCH:
		*data = std_gvar_array_i32(ARRAY_AND_SIZE(trigger_matches));
		break;
	default:
		return STD_CONFIG_LIST(key, data, sdi, cg, scanopts, drvopts,
			devopts);
	}

	return SR_OK;
}

static int dev_acquisition_start(const struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;

	atk_dl16_parse_trigger(sdi);

	devc->rxbuf = g_try_malloc(ATK_DL16_READ_CHUNK);
	devc->pcbuf = g_try_malloc(ATK_DL16_READ_CHUNK);
	if (!devc->rxbuf || !devc->pcbuf) {
		g_free(devc->rxbuf);
		g_free(devc->pcbuf);
		devc->rxbuf = devc->pcbuf = NULL;
		return SR_ERR_MALLOC;
	}

	devc->state = ATK_DL16_ACQ_ARM;
	devc->samples_sent = 0;
	devc->rxlen = 0;
	devc->trigger_pos_known = FALSE;
	devc->done_seen = FALSE;
	devc->armed = FALSE;
	devc->overrun = FALSE;
	devc->empty_polls = 0;
	devc->have_expected = FALSE;
	devc->failed = FALSE;
	atk_dl16_free_buffers(devc);

	std_session_send_df_header(sdi);

	/* Timer-driven: the capture is paced by polling the bulk endpoint,
	 * not by asynchronous transfer completion. */
	sr_session_source_add(sdi->session, -1, 0, 10,
		atk_dl16_receive_data, (void *)sdi);

	return SR_OK;
}

static int dev_acquisition_stop(struct sr_dev_inst *sdi)
{
	struct dev_context *devc = sdi->priv;
	gboolean pwm_busy;
	size_t i;

	sr_session_source_remove(sdi->session, -1);

	/* Halt the capture. Best effort: the session is ending either way. */
	atk_dl16_stop(sdi);
	/* Drain before sleeping the FPGA: the device is very likely still
	 * pushing a backlog, and leaving it queued wedges the endpoint for
	 * the next run. Mirrors the vendor application's own teardown. */
	atk_dl16_drain(sdi);

	/*
	 * Only sleep the FPGA if nothing still needs it. A running PWM does:
	 * sleeping here would stop the generator the moment a capture ended,
	 * which is not what "enabled" means for an output.
	 */
	pwm_busy = FALSE;
	for (i = 0; i < ATK_DL16_NUM_PWM; i++) {
		if (devc->pwm[i].enabled)
			pwm_busy = TRUE;
	}
	if (!pwm_busy)
		atk_dl16_set_reset(sdi, FALSE);
	else
		sr_dbg("Leaving the FPGA awake: a PWM output is still running.");

	g_free(devc->rxbuf);
	g_free(devc->pcbuf);
	devc->rxbuf = devc->pcbuf = NULL;
	atk_dl16_free_buffers(devc);
	devc->state = ATK_DL16_ACQ_IDLE;

	std_session_send_df_end(sdi);

	return SR_OK;
}

static int driver_init(struct sr_dev_driver *di, struct sr_context *sr_ctx)
{
	int i;

	/* The threshold list is derived from the measured preset values so
	 * the two cannot drift apart. */
	for (i = 0; i < ATK_DL16_NUM_THRESHOLDS; i++) {
		threshold_ranges[i][0] = atk_dl16_thresholds[i];
		threshold_ranges[i][1] = atk_dl16_thresholds[i];
	}

	return std_init(di, sr_ctx);
}

static struct sr_dev_driver atk_dl16_driver_info = {
	.name = "atk-dl16",
	.longname = "ALIENTEK ATK DL16",
	.api_version = 1,
	.init = driver_init,
	.cleanup = std_cleanup,
	.scan = scan,
	.dev_list = std_dev_list,
	.dev_clear = std_dev_clear,
	.config_get = config_get,
	.config_set = config_set,
	.config_list = config_list,
	.dev_open = dev_open,
	.dev_close = dev_close,
	.dev_acquisition_start = dev_acquisition_start,
	.dev_acquisition_stop = dev_acquisition_stop,
	.context = NULL,
};
SR_REGISTER_DEV_DRIVER(atk_dl16_driver_info);
