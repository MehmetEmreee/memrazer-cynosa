// SPDX-License-Identifier: GPL-2.0-or-later
#include "cusb.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdlib.h>

struct cusb_device {
    IOUSBDeviceInterface **intf;
};

cusb_device *cusb_open(uint16_t vid, uint16_t pid, IOReturn *err) {
    *err = kIOReturnNotFound;
    CFMutableDictionaryRef match = IOServiceMatching(kIOUSBDeviceClassName);
    if (!match) return NULL;
    int v = vid, p = pid;
    CFNumberRef nv = CFNumberCreate(NULL, kCFNumberIntType, &v);
    CFNumberRef np = CFNumberCreate(NULL, kCFNumberIntType, &p);
    CFDictionarySetValue(match, CFSTR(kUSBVendorID), nv);
    CFDictionarySetValue(match, CFSTR(kUSBProductID), np);
    CFRelease(nv);
    CFRelease(np);

    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS) return NULL;

    cusb_device *result = NULL;
    io_service_t svc;
    while (!result && (svc = IOIteratorNext(it))) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score;
        *err = IOCreatePlugInInterfaceForService(svc, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
        IOObjectRelease(svc);
        if (*err != kIOReturnSuccess || !plugin) continue;

        IOUSBDeviceInterface **intf = NULL;
        HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&intf);
        IODestroyPlugInInterface(plugin);
        if (hr != S_OK || !intf) { *err = kIOReturnError; continue; }

        result = calloc(1, sizeof *result);
        result->intf = intf;
        *err = kIOReturnSuccess;
    }
    IOObjectRelease(it);
    return result;
}

void cusb_close(cusb_device *dev) {
    if (!dev) return;
    (*dev->intf)->Release(dev->intf);
    free(dev);
}

static IOReturn request(cusb_device *dev, uint8_t type, uint8_t req, uint16_t interface,
                        void *data, uint16_t length, uint32_t *transferred) {
    IOUSBDevRequestTO r = {
        .bmRequestType = type,
        .bRequest = req,
        .wValue = 0x0300,
        .wIndex = interface,
        .wLength = length,
        .pData = data,
        .noDataTimeout = 1000,
        .completionTimeout = 1000,
    };
    IOReturn ret = (*dev->intf)->DeviceRequestTO(dev->intf, &r);
    if (transferred) *transferred = r.wLenDone;
    return ret;
}

IOReturn cusb_set_feature(cusb_device *dev, uint16_t interface, const uint8_t *data, uint16_t length) {
    return request(dev, 0x21, 0x09, interface, (void *)data, length, NULL);
}

IOReturn cusb_get_feature(cusb_device *dev, uint16_t interface, uint8_t *data, uint16_t length, uint32_t *transferred) {
    return request(dev, 0xA1, 0x01, interface, data, length, transferred);
}
