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
 * Hantek DSO-3062L: mixed-signal acquisition.
 *
 * Sixteen logic channels and two analog. All ride one sample stream of
 * four-byte groups: slots 2 and 3 are logic D0-D7 and D8-D15, and slots 0
 * and 1 are either CH1's two interleaved ADC cores or, when the enable word
 * says so, CH1 and CH2.
 *
 * Triggering is edge-only on an analog source, with auto-trigger behaviour:
 * the configured condition is armed, and a capture is forced if nothing fires
 * within a second.
 */

#include <config.h>
#include <libusb.h>
#include "protocol.h"

static const uint32_t scanopts[] = {
	SR_CONF_CONN,
};

static const uint32_t drvopts[] = {
	SR_CONF_OSCILLOSCOPE,
	SR_CONF_LOGIC_ANALYZER,
};

static const uint32_t devopts[] = {
	SR_CONF_CONN | SR_CONF_GET,
	SR_CONF_SAMPLERATE | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_LIMIT_SAMPLES | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	/*
	 * The threshold is offered under two keys on purpose.
	 *
	 * VOLTAGE_THRESHOLD is the one PulseView renders. Its device-options
	 * binding (pv/binding/device.cpp) is an explicit switch over config
	 * keys ending in `default: break;`, so a key it does not name is
	 * silently ignored - LOGIC_THRESHOLD_CUSTOM among them. Offering only
	 * that one leaves the control that decides what counts as high or low
	 * unreachable from the GUI, with no error to explain why.
	 *
	 * LOGIC_THRESHOLD_CUSTOM stays for sigrok-cli, where an arbitrary
	 * float is more useful than a menu. The hardware DAC is continuous
	 * over roughly -11 V to +11 V; the list below is only a convenience.
	 */
	SR_CONF_VOLTAGE_THRESHOLD | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_LOGIC_THRESHOLD_CUSTOM | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_TRIGGER_SLOPE | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_TRIGGER_LEVEL | SR_CONF_GET | SR_CONF_SET,
	SR_CONF_TRIGGER_SOURCE | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_CAPTURE_RATIO | SR_CONF_GET | SR_CONF_SET,
	/* The 20 MHz trigger-path HF-reject filter. */
	SR_CONF_FILTER | SR_CONF_GET | SR_CONF_SET,
	/* Continuous (roll) acquisition: stream the live ring until stopped,
	 * instead of one triggered 16 M record. Best at rates up to ~1 MHz. */
	SR_CONF_CONTINUOUS | SR_CONF_GET | SR_CONF_SET,
	/* Software logic pattern trigger, matched host-side in the captured
	 * record - PulseView renders per-channel trigger conditions. */
	SR_CONF_TRIGGER_MATCH | SR_CONF_LIST,
};

/* Logic-channel trigger conditions PulseView may set. Matched in software
 * over the full-rate captured record (see protocol.c). */
static const int32_t trigger_matches[] = {
	SR_TRIGGER_ZERO,
	SR_TRIGGER_ONE,
	SR_TRIGGER_RISING,
	SR_TRIGGER_FALLING,
	SR_TRIGGER_EDGE,
};

/* Enable-word trigger-source field: bits 14-15 (11 = CH1, 00 = CH2) plus
 * bit 13 for EXT. The logic channels are not wired up yet. */
static const char *trigger_sources[] = { "CH1", "CH2", "EXT" };

/* Per-channel-group options: the full nine-range 1-2-5 ladder and all
 * three couplings, on both channels. */
static const uint32_t devopts_cg_ch1[] = {
	SR_CONF_VDIV | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
	SR_CONF_COUPLING | SR_CONF_GET | SR_CONF_SET | SR_CONF_LIST,
};

/* GND is the PGA's disconnect state (11), not a relay. Order matches
 * enum dso3062l_coupling. */
static const char *coupling_options[] = { "DC", "AC", "GND" };

/* PulseView renders TRIGGER_SLOPE as a dropdown from this list. */
static const char *trigger_slopes[] = { "r", "f" };

/*
 * Selectable thresholds, as low/high pairs. This device has a single
 * comparator level rather than a hysteresis band, so both entries of each
 * pair are the same value - that is the honest encoding, not a placeholder.
 */
static const double threshold_ranges[][2] = {
	{ 0.4, 0.4 },
	{ 0.6, 0.6 },
	{ 0.9, 0.9 },
	{ 1.2, 1.2 },
	{ 1.4, 1.4 },
	{ 1.65, 1.65 },
	{ 2.0, 2.0 },
	{ 2.5, 2.5 },
	{ 3.0, 3.0 },
};

static const char *channel_names_analog[] = {
	"CH1", "CH2",
};

/*
 * Logic sample rates, derived from 100 MHz / (ticks + 1) with the vendor's
 * 1-2-5 tick sequence. Only the dividing rates are offered: the top of the
 * range has not been tested against a real signal, and advertising a rate the
 * instrument cannot actually sustain is worse than offering fewer.
 */
static const uint64_t samplerates[] = {
	SR_KHZ(100),
	SR_KHZ(200),
	SR_KHZ(500),
	SR_MHZ(1),
	SR_MHZ(2),
	SR_MHZ(5),
	SR_MHZ(10),
	SR_MHZ(20),
	SR_MHZ(50),
};

#define DSO3062L_DEFAULT_SAMPLERATE	SR_KHZ(200)
#define DSO3062L_DEFAULT_LIMIT_SAMPLES	10240
#define DSO3062L_DEFAULT_THRESHOLD	1.4
/* Mid-swing on the instrument's own 1 kHz 2 Vpp compensation output, so a
 * capture triggers out of the box on the signal most likely to be attached. */
#define DSO3062L_DEFAULT_TRIGGER_LEVEL	1.0

static struct sr_dev_driver hantek_dso3062l_driver_info;

static GSList *scan(struct sr_dev_driver *di, GSList *options)
{
	struct drv_context *drvc;
	struct dev_context *devc;
	struct sr_dev_inst *sdi;
	struct sr_config *src;
	struct sr_usb_dev_inst *usb;
	struct sr_channel *ch;
	struct sr_channel_group *cg;
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

	if (conn)
		conn_devices = sr_usb_find(drvc->sr_ctx->libusb_ctx, conn);
	else
		conn_devices = NULL;

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

		if (des.idVendor != DSO3062L_VID
		    || des.idProduct != DSO3062L_PID)
			continue;

		if (usb_get_port_path(devlist[i], connection_id,
				sizeof(connection_id)) < 0)
			continue;

		sdi = g_malloc0(sizeof(struct sr_dev_inst));
		sdi->status = SR_ST_INITIALIZING;
		sdi->vendor = g_strdup("Hantek");
		sdi->model = g_strdup("DSO-3062L");
		sdi->connection_id = g_strdup(connection_id);
		sdi->inst_type = SR_INST_USB;
		sdi->conn = sr_usb_dev_inst_new(
			libusb_get_bus_number(devlist[i]),
			libusb_get_device_address(devlist[i]), NULL);

		/*
		 * Channels are declared from the instrument's fixed layout
		 * rather than probed. The logic pod is 16 channels in two
		 * banks of eight, D0-D7 and D8-D15, which is how the 0x41
		 * threshold command addresses them too.
		 *
		 * Both types are numbered from zero, and they deliberately
		 * overlap. A logic channel's index is not an identifier: it is
		 * the bit position that channel occupies in the packed logic
		 * data, so D0 must be index 0 or the whole set is displaced.
		 * Numbering logic from 2 to leave room for the analog channels
		 * shifted every trace by two and pushed D14 and D15 past the
		 * end of the two-byte unit, where they were interpreted as
		 * analog. Mixed-signal drivers disambiguate by index *and*
		 * type, which is what send_analog() does.
		 */
		for (j = 0; j < DSO3062L_NUM_ANALOG_CHANNELS; j++) {
			ch = sr_channel_new(sdi, j, SR_CHANNEL_ANALOG, TRUE,
				channel_names_analog[j]);
			/* One group per analog channel, so frontends have
			 * somewhere to hang the volts/div and coupling
			 * controls. */
			cg = sr_channel_group_new(sdi,
				channel_names_analog[j], NULL);
			cg->channels = g_slist_append(cg->channels, ch);
		}
		for (j = 0; j < DSO3062L_NUM_LOGIC_CHANNELS; j++) {
			g_snprintf(channel_name, sizeof(channel_name), "D%d", j);
			sr_channel_new(sdi, j, SR_CHANNEL_LOGIC, TRUE,
				channel_name);
		}

		devc = g_malloc0(sizeof(struct dev_context));
		devc->samplerate = DSO3062L_DEFAULT_SAMPLERATE;
		devc->limit_samples = DSO3062L_DEFAULT_LIMIT_SAMPLES;
		devc->logic_threshold = DSO3062L_DEFAULT_THRESHOLD;
		devc->vdiv_index = DSO3062L_RANGE_DEFAULT;
		devc->ch2_vdiv_index = DSO3062L_RANGE_DEFAULT;
		devc->ch1_coupling = DSO3062L_COUPLING_DC;
		devc->ch2_coupling = DSO3062L_COUPLING_DC;
		devc->trigger_slope = DSO3062L_SLOPE_RISING;
		devc->trigger_level = DSO3062L_DEFAULT_TRIGGER_LEVEL;
		devc->capture_ratio = 50;
		sdi->priv = devc;

		devices = g_slist_append(devices, sdi);
	}
	libusb_free_device_list(devlist, 1);
	g_slist_free_full(conn_devices, (GDestroyNotify)sr_usb_dev_inst_free);

	return std_scan_complete(di, devices);
}

static int dev_open(struct sr_dev_inst *sdi)
{
	struct sr_dev_driver *di;
	struct dev_context *devc;
	struct drv_context *drvc;
	struct sr_usb_dev_inst *usb;
	uint8_t speed;
	int ret;

	di = sdi->driver;
	drvc = di->context;
	devc = sdi->priv;
	usb = sdi->conn;

	ret = sr_usb_open(drvc->sr_ctx->libusb_ctx, usb);
	if (ret != SR_OK)
		return ret;

	/*
	 * Claiming can fail because another driver owns the device. On
	 * Windows that is the ordinary state of affairs until the interface
	 * is bound to WinUSB, so say which one it is rather than reporting a
	 * bare error code.
	 */
	ret = libusb_claim_interface(usb->devhdl, DSO3062L_USB_INTERFACE);
	if (ret < 0) {
		sr_err("Failed to claim interface %d: %s.",
			DSO3062L_USB_INTERFACE, libusb_error_name(ret));
		if (ret == LIBUSB_ERROR_ACCESS || ret == LIBUSB_ERROR_BUSY) {
			sr_err("The device is claimed by another driver. "
				"On Windows bind it to WinUSB; on Linux check "
				"the udev rules.");
		}
		sr_usb_close(usb);
		return SR_ERR;
	}

	/*
	 * Confirm the instrument actually answers before declaring it open.
	 * A VID/PID match only proves something is plugged in.
	 */
	ret = hantek_dso3062l_get_speed(sdi, &speed);
	if (ret != SR_OK) {
		libusb_release_interface(usb->devhdl, DSO3062L_USB_INTERFACE);
		sr_usb_close(usb);
		return ret;
	}

	if (speed != DSO3062L_SPEED_HIGH) {
		/* Not fatal - but a full-speed link cannot sustain capture,
		 * and silently running slowly is worse than being told. */
		sr_warn("Device reports USB speed 0x%02x, expected high speed "
			"(0x%02x). Check the cable and port.",
			speed, DSO3062L_SPEED_HIGH);
	} else {
		sr_info("Device open, high speed.");
	}
	devc->speed_verified = TRUE;

	/* Load the instrument's own offset calibration; non-fatal. */
	hantek_dso3062l_read_calibration(sdi);

	return SR_OK;
}

static int dev_close(struct sr_dev_inst *sdi)
{
	struct sr_usb_dev_inst *usb;

	usb = sdi->conn;
	if (!usb || !usb->devhdl)
		return SR_ERR_BUG;

	libusb_release_interface(usb->devhdl, DSO3062L_USB_INTERFACE);
	sr_usb_close(usb);

	return SR_OK;
}

/* The analog index behind a channel group, or -1 for anything else. */
static int cg_analog_index(const struct sr_channel_group *cg)
{
	struct sr_channel *ch;

	if (!cg || !cg->channels)
		return -1;
	ch = cg->channels->data;
	if (ch->type != SR_CHANNEL_ANALOG)
		return -1;

	return ch->index;
}

static int config_get(uint32_t key, GVariant **data,
	const struct sr_dev_inst *sdi, const struct sr_channel_group *cg)
{
	struct dev_context *devc;
	struct sr_usb_dev_inst *usb;
	const struct dso3062l_range *step;

	if (!sdi)
		return SR_ERR_ARG;
	devc = sdi->priv;

	/*
	 * Only the two vertical keys belong to a channel group. Anything else
	 * falls through to the global handling below even when a group is
	 * named, because sigrok-cli routes every --config through the group
	 * once --channel-group is given.
	 */
	switch (key) {
	case SR_CONF_VDIV:
		switch (cg_analog_index(cg)) {
		case 0:
			step = &dso3062l_ranges_ch1[devc->vdiv_index];
			*data = g_variant_new("(tt)", step->p, step->q);
			return SR_OK;
		case 1:
			step = &dso3062l_ranges_ch2[devc->ch2_vdiv_index];
			*data = g_variant_new("(tt)", step->p, step->q);
			return SR_OK;
		default:
			return SR_ERR_NA;
		}
	case SR_CONF_COUPLING:
		switch (cg_analog_index(cg)) {
		case 0:
			*data = g_variant_new_string(
				coupling_options[devc->ch1_coupling]);
			return SR_OK;
		case 1:
			*data = g_variant_new_string(
				coupling_options[devc->ch2_coupling]);
			return SR_OK;
		default:
			return SR_ERR_NA;
		}
	default:
		break;
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
	case SR_CONF_LOGIC_THRESHOLD_CUSTOM:
		*data = g_variant_new_double(devc->logic_threshold);
		break;
	case SR_CONF_TRIGGER_SLOPE:
		*data = g_variant_new_string(trigger_slopes[devc->trigger_slope]);
		break;
	case SR_CONF_TRIGGER_LEVEL:
		*data = g_variant_new_double(devc->trigger_level);
		break;
	case SR_CONF_TRIGGER_SOURCE:
		*data = g_variant_new_string(
			trigger_sources[devc->trigger_source % 3]);
		break;
	case SR_CONF_CAPTURE_RATIO:
		*data = g_variant_new_uint64(devc->capture_ratio);
		break;
	case SR_CONF_FILTER:
		*data = g_variant_new_boolean(devc->trigger_hf_reject);
		break;
	case SR_CONF_CONTINUOUS:
		*data = g_variant_new_boolean(devc->continuous);
		break;
	case SR_CONF_VOLTAGE_THRESHOLD:
		*data = std_gvar_tuple_double(devc->logic_threshold,
			devc->logic_threshold);
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
	uint64_t rate, p, q;
	int idx, i;

	if (!sdi)
		return SR_ERR_ARG;
	devc = sdi->priv;

	/* Group keys first; everything else is global even with a group
	 * named, matching config_get. */
	switch (key) {
	case SR_CONF_VDIV:
		switch (cg_analog_index(cg)) {
		case 0:
			g_variant_get(data, "(tt)", &p, &q);
			/* Cross-multiplied so 18/1000 and 9/500 match. */
			for (i = 0; i < DSO3062L_NUM_RANGES; i++) {
				if (p * dso3062l_ranges_ch1[i].q
				    == q * dso3062l_ranges_ch1[i].p) {
					devc->vdiv_index = i;
					return SR_OK;
				}
			}
			return SR_ERR_ARG;
		case 1:
			g_variant_get(data, "(tt)", &p, &q);
			for (i = 0; i < DSO3062L_NUM_RANGES; i++) {
				if (p * dso3062l_ranges_ch2[i].q
				    == q * dso3062l_ranges_ch2[i].p) {
					devc->ch2_vdiv_index = i;
					return SR_OK;
				}
			}
			return SR_ERR_ARG;
		default:
			return SR_ERR_NA;
		}
	case SR_CONF_COUPLING:
		idx = std_str_idx(data, ARRAY_AND_SIZE(coupling_options));
		if (idx < 0)
			return SR_ERR_ARG;
		switch (cg_analog_index(cg)) {
		case 0:
			devc->ch1_coupling = idx;
			return SR_OK;
		case 1:
			devc->ch2_coupling = idx;
			return SR_OK;
		default:
			return SR_ERR_NA;
		}
	default:
		break;
	}

	switch (key) {
	case SR_CONF_SAMPLERATE:
		rate = g_variant_get_uint64(data);
		/*
		 * Reject rather than silently round. The divider is integral,
		 * so an unrepresentable rate would otherwise be accepted and
		 * then quietly captured at a different one - and every
		 * timing the frontend displays would be wrong.
		 */
		if (hantek_dso3062l_ticks_for_rate(rate) == 0
		    && rate != DSO3062L_LOGIC_BASE_CLOCK_HZ) {
			sr_err("Unsupported sample rate %" PRIu64 " Hz.", rate);
			return SR_ERR_ARG;
		}
		devc->samplerate = rate;
		break;
	case SR_CONF_LIMIT_SAMPLES:
		rate = g_variant_get_uint64(data);
		if (rate < DSO3062L_MIN_SAMPLES
		    || rate > DSO3062L_MAX_SAMPLES) {
			sr_err("Sample count %" PRIu64 " outside the "
				"supported %d..%d range.", rate,
				DSO3062L_MIN_SAMPLES, DSO3062L_MAX_SAMPLES);
			return SR_ERR_ARG;
		}
		devc->limit_samples = rate;
		break;
	case SR_CONF_LOGIC_THRESHOLD_CUSTOM:
		devc->logic_threshold = g_variant_get_double(data);
		break;
	case SR_CONF_TRIGGER_SLOPE:
		idx = std_str_idx(data, ARRAY_AND_SIZE(trigger_slopes));
		if (idx < 0)
			return SR_ERR_ARG;
		devc->trigger_slope = idx;
		break;
	case SR_CONF_TRIGGER_LEVEL:
		devc->trigger_level = g_variant_get_double(data);
		break;
	case SR_CONF_TRIGGER_SOURCE:
		idx = std_str_idx(data, ARRAY_AND_SIZE(trigger_sources));
		if (idx < 0)
			return SR_ERR_ARG;
		devc->trigger_source = idx;
		break;
	case SR_CONF_CAPTURE_RATIO:
		rate = g_variant_get_uint64(data);
		if (rate > 100)
			return SR_ERR_ARG;
		devc->capture_ratio = rate;
		break;
	case SR_CONF_FILTER:
		devc->trigger_hf_reject = g_variant_get_boolean(data);
		break;
	case SR_CONF_CONTINUOUS:
		devc->continuous = g_variant_get_boolean(data);
		break;
	case SR_CONF_VOLTAGE_THRESHOLD:
		idx = std_double_tuple_idx(data, ARRAY_AND_SIZE(threshold_ranges));
		if (idx < 0)
			return SR_ERR_ARG;
		devc->logic_threshold = threshold_ranges[idx][0];
		break;
	default:
		return SR_ERR_NA;
	}

	return SR_OK;
}

static int config_list(uint32_t key, GVariant **data,
	const struct sr_dev_inst *sdi, const struct sr_channel_group *cg)
{
	GVariantBuilder gvb;
	int i;

	if (cg && key == SR_CONF_DEVICE_OPTIONS) {
		if (cg_analog_index(cg) >= 0)
			*data = std_gvar_array_u32(
				ARRAY_AND_SIZE(devopts_cg_ch1));
		else
			*data = std_gvar_array_u32(NULL, 0);
		return SR_OK;
	}

	switch (key) {
	case SR_CONF_VDIV:
		switch (cg_analog_index(cg)) {
		case 0:
			g_variant_builder_init(&gvb, G_VARIANT_TYPE_ARRAY);
			for (i = 0; i < DSO3062L_NUM_RANGES; i++) {
				g_variant_builder_add(&gvb, "(tt)",
					dso3062l_ranges_ch1[i].p,
					dso3062l_ranges_ch1[i].q);
			}
			*data = g_variant_builder_end(&gvb);
			return SR_OK;
		case 1:
			g_variant_builder_init(&gvb, G_VARIANT_TYPE_ARRAY);
			for (i = 0; i < DSO3062L_NUM_RANGES; i++) {
				g_variant_builder_add(&gvb, "(tt)",
					dso3062l_ranges_ch2[i].p,
					dso3062l_ranges_ch2[i].q);
			}
			*data = g_variant_builder_end(&gvb);
			return SR_OK;
		default:
			return SR_ERR_NA;
		}
	case SR_CONF_COUPLING:
		if (cg_analog_index(cg) < 0)
			return SR_ERR_NA;
		*data = g_variant_new_strv(ARRAY_AND_SIZE(coupling_options));
		return SR_OK;
	default:
		break;
	}

	switch (key) {
	case SR_CONF_SAMPLERATE:
		*data = std_gvar_samplerates(ARRAY_AND_SIZE(samplerates));
		break;
	case SR_CONF_LIMIT_SAMPLES:
		*data = std_gvar_tuple_u64(DSO3062L_MIN_SAMPLES,
			DSO3062L_MAX_SAMPLES);
		break;
	case SR_CONF_VOLTAGE_THRESHOLD:
		*data = std_gvar_thresholds(ARRAY_AND_SIZE(threshold_ranges));
		break;
	case SR_CONF_TRIGGER_SLOPE:
		*data = g_variant_new_strv(ARRAY_AND_SIZE(trigger_slopes));
		break;
	case SR_CONF_TRIGGER_SOURCE:
		*data = g_variant_new_strv(ARRAY_AND_SIZE(trigger_sources));
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
	struct dev_context *devc;
	int ret;

	devc = sdi->priv;

	/*
	 * The triggered path needs the rate/depth pair to fit the ring;
	 * refuse impossible ones here, where the frontend reports it,
	 * rather than in a timer callback where it looks like a silent
	 * no-op. Continuous (roll) mode has no fixed record, so it skips
	 * this check.
	 */
	if (!devc->continuous && !hantek_dso3062l_depth_feasible(devc)) {
		sr_err("%" PRIu64 " samples at %" PRIu64 " Hz cannot be "
			"captured: the trigger window is too narrow at this "
			"rate. Reduce the sample count or the sample rate.",
			devc->limit_samples, devc->samplerate);
		return SR_ERR_ARG;
	}

	if (devc->continuous && devc->samplerate > SR_MHZ(1)) {
		sr_warn("Continuous mode streams over USB at about 1 M "
			"points/s; %" PRIu64 " Hz will overrun and drop "
			"data. Use %s or lower for gap-free capture.",
			devc->samplerate, "1 MHz");
	}

	/* Parse any logic pattern trigger; matched host-side in read. */
	hantek_dso3062l_parse_trigger(sdi);
	if (devc->continuous && devc->sw_trig) {
		sr_warn("Software pattern trigger is ignored in continuous "
			"mode; use a bounded capture to trigger on a pattern.");
		devc->sw_trig = FALSE;
	}

	if (devc->continuous) {
		ret = hantek_dso3062l_roll_mode(sdi, TRUE);
		if (ret != SR_OK) {
			sr_err("Failed to enter roll mode.");
			return ret;
		}
	}

	ret = hantek_dso3062l_configure(sdi);
	if (ret != SR_OK) {
		sr_err("Failed to configure the device for acquisition.");
		if (devc->continuous)
			hantek_dso3062l_roll_mode(sdi, FALSE);
		return ret;
	}

	devc->settle_ticks = 0;
	devc->poll_ticks = 0;
	devc->collect_us = 0;
	devc->retries = 0;
	devc->roll_forwarded = 0;

	if (devc->continuous) {
		/* Start the free-running writer; the state machine sends
		 * 0x04 and seeds the read cursor from ROLL_ARM. */
		uint8_t cmd[2] = { DSO3062L_CMD_START_COLLECT, 0x00 };
		ret = hantek_dso3062l_send_cmd(sdi, cmd, sizeof(cmd));
		if (ret != SR_OK) {
			hantek_dso3062l_roll_mode(sdi, FALSE);
			return ret;
		}
		devc->state = DSO3062L_ACQ_ROLL_ARM;
		devc->settle_ticks = 4;
	} else {
		devc->state = DSO3062L_ACQ_START_COLLECT;
	}

	std_session_send_df_header(sdi);

	/*
	 * A timer source rather than a USB file descriptor: the capture is
	 * driven by polling the instrument's state, not by asynchronous
	 * transfer completion. 50 ms is fine granularity for a sequence whose
	 * own settling times are measured in hundreds of milliseconds.
	 */
	sr_session_source_add(sdi->session, -1, 0, 50,
		hantek_dso3062l_receive_data, (void *)sdi);

	return SR_OK;
}

static int dev_acquisition_stop(struct sr_dev_inst *sdi)
{
	struct dev_context *devc;

	devc = sdi->priv;
	devc->state = DSO3062L_ACQ_IDLE;

	sr_session_source_remove(sdi->session, -1);

	/* Leave roll mode so the next capture starts clean. */
	if (devc->continuous)
		hantek_dso3062l_roll_mode(sdi, FALSE);

	std_session_send_df_end(sdi);

	return SR_OK;
}

static struct sr_dev_driver hantek_dso3062l_driver_info = {
	.name = "hantek-dso3062l",
	.longname = "Hantek DSO-3062L",
	.api_version = 1,
	.init = std_init,
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
SR_REGISTER_DEV_DRIVER(hantek_dso3062l_driver_info);
