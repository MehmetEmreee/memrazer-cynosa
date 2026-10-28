// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <stdint.h>
#include <IOKit/IOReturn.h>

typedef struct cusb_device cusb_device;

/// Opens the first USB device matching vid/pid. Returns NULL and sets *err on failure.
cusb_device *cusb_open(uint16_t vid, uint16_t pid, IOReturn *err);
void cusb_close(cusb_device *dev);

/// HID class SET_REPORT / GET_REPORT (feature, report ID 0) on the given interface.
IOReturn cusb_set_feature(cusb_device *dev, uint16_t interface, const uint8_t *data, uint16_t length);
IOReturn cusb_get_feature(cusb_device *dev, uint16_t interface, uint8_t *data, uint16_t length, uint32_t *transferred);
