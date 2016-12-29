//
//  LEFTCPUUsage.m
//  FullTextSearch
//
//  Created by leo on 2016/12/29.
//  Copyright © 2016年 leo. All rights reserved.
//

#import "LEFTCPUUsage.h"

#include <sys/sysctl.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>

processor_info_array_t cpuInfo, prevCpuInfo;
mach_msg_type_number_t numCpuInfo, numPrevCpuInfo;
unsigned numCPUs;
NSTimer *updateTimer;
NSLock *CPUUsageLock;

static kern_return_t current_usage(float *in_use, float *out_total)
{
    natural_t numCPUsU = 0U;
    kern_return_t err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo);
    if(err == KERN_SUCCESS) {
        [CPUUsageLock lock];
        
        for(unsigned i = 0U; i < numCPUs; ++i) {
            float inUse, total;
            if(prevCpuInfo) {
                inUse = (
                         (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE])
                         );
                total = inUse + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE]);
            } else {
                inUse = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
                total = inUse + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
            }
            
            in_use[i] = inUse;
            out_total[i] = total;
        }
        [CPUUsageLock unlock];
        
        if(prevCpuInfo) {
            size_t prevCpuInfoSize = sizeof(integer_t) * numPrevCpuInfo;
            vm_deallocate(mach_task_self(), (vm_address_t)prevCpuInfo, prevCpuInfoSize);
        }
        
        prevCpuInfo = cpuInfo;
        numPrevCpuInfo = numCpuInfo;
        
        cpuInfo = NULL;
        numCpuInfo = 0U;
        return err;
    } else {
        return err;
    }
}

static LEFTCPUUsage *cpuUsage;

@implementation LEFTCPUUsage

+ (void)load
{
    int mib[2U] = { CTL_HW, HW_NCPU };
    size_t sizeOfNumCPUs = sizeof(numCPUs);
    int status = sysctl(mib, 2U, &numCPUs, &sizeOfNumCPUs, NULL, 0U);
    if(status)
        numCPUs = 1;
    
    CPUUsageLock = [[NSLock alloc] init];
}

+ (instancetype)defaultInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cpuUsage = [[LEFTCPUUsage alloc] init];
    });
    return cpuUsage;
}

- (NSUInteger)cpuNumber
{
    return numCPUs;
}

- (CGFloat)totalUsage
{
    NSUInteger cpu_num = [self cpuNumber];
    float *in_use = calloc(sizeof(float), cpu_num);
    float *total = calloc(sizeof(float), cpu_num);
    current_usage(in_use, total);
    float total_in_use = 0.0;
    float total_total = 0.0;
    for (int i = 0 ; i < cpu_num; i++) {
        total_in_use += in_use[i];
        total_total += total[i];
    }
    return total_total != 0.0 ? total_in_use/total_total : 0.0;
}

- (CGFloat)usageWithCoreNumber:(NSUInteger)coreNumber
{
    NSUInteger cpu_num = [self cpuNumber];
    float *in_use = calloc(sizeof(float), cpu_num);
    float *total = calloc(sizeof(float), cpu_num);
    current_usage(in_use, total);

    if (coreNumber >= cpu_num) {
        return 0.0;
    } else {
        return total[coreNumber] != 0.0 ? in_use[coreNumber]/total[coreNumber] : 0.0;
    }
}

@end
