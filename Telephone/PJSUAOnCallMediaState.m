//
//  PJSUAOnCallMediaState.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//  Modifications © 2026 Pavel Gordeev
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

#import "PJSUACallbacks.h"

#import "AKSIPCall.h"
#import "AKSIPUserAgent.h"

#define THIS_FILE "PJSUAOnCallMediaState.m"

static void LogCallMedia(const pjsua_call_info *callInfo);
static void LogAudioStream(pjsua_call_id callID, unsigned mediaIndex);
static void LogSoundPath(void);
static void LogSoundDevice(const char *role, int deviceID);
static void LogConferenceBridge(void);
static void CallMediaStateChanged(pjsua_call_id identifier, pjsua_call_media_status status, pjsua_conf_port_id port);
static const char *MediaStatusTextWithStatus(pjsua_call_media_status status);
static void ConnectCallToSoundDevice(AKSIPCall *call, pjsua_call_media_status status, pjsua_conf_port_id port);
static void PostMediaStateChangeNotification(AKSIPCall *call, pjsua_call_media_status status);

void PJSUAOnCallMediaState(pjsua_call_id callID) {
    pjsua_call_info info;
    pj_status_t infoStatus = pjsua_call_get_info(callID, &info);
    if (infoStatus != PJ_SUCCESS) {
        PJ_PERROR(3, (THIS_FILE, infoStatus, "Could not get call media info for call %d", callID));
        return;
    }

    LogCallMedia(&info);

    NSInteger audioIndex = -1;
    for (unsigned i = 0; i < info.media_cnt; i++) {
        if (info.media[i].type == PJMEDIA_TYPE_AUDIO) {
            audioIndex = (NSInteger)i;
            break;
        }
    }

    if (audioIndex < 0) {
        PJ_LOG(3, (THIS_FILE, "Call %d has no audio media", callID));
        return;
    }

    pjsua_call_media_status status = info.media[audioIndex].status;
    pjsua_conf_port_id port = info.media[audioIndex].stream.aud.conf_slot;

    if (status == PJSUA_CALL_MEDIA_ACTIVE || status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        LogSoundPath();
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        CallMediaStateChanged(info.id, status, port);
    });
}

static void LogCallMedia(const pjsua_call_info *callInfo) {
    PJ_LOG(4, (THIS_FILE, "Call %d media count: %u", callInfo->id, callInfo->media_cnt));

    for (unsigned i = 0; i < callInfo->media_cnt; i++) {
        PJ_LOG(4, (THIS_FILE, "Call %d media %u [type=%s], status=%s",
                   callInfo->id,
                   i,
                   pjmedia_type_name(callInfo->media[i].type),
                   MediaStatusTextWithStatus(callInfo->media[i].status)));

        if (callInfo->media[i].type == PJMEDIA_TYPE_AUDIO) {
            LogAudioStream(callInfo->id, i);
        }
    }
}

static void LogAudioStream(pjsua_call_id callID, unsigned mediaIndex) {
    pjsua_stream_info streamInfo;
    pj_status_t status = pjsua_call_get_stream_info(callID, mediaIndex, &streamInfo);
    if (status != PJ_SUCCESS) {
        PJ_PERROR(3, (THIS_FILE, status, "Could not get audio stream info for call %d media %u",
                      callID, mediaIndex));
        return;
    }

    if (streamInfo.type != PJMEDIA_TYPE_AUDIO) {
        return;
    }

    const pjmedia_stream_info *audio = &streamInfo.info.aud;
    const char *codecName = audio->fmt.encoding_name.ptr ?: "";
    int codecNameLength = (int)audio->fmt.encoding_name.slen;

    PJ_LOG(3, (THIS_FILE,
               "AUDIO_DIAG call=%d media=%u codec=%.*s clock=%uHz channels=%u tx_pt=%u rx_pt=%u dir=%d",
               callID,
               mediaIndex,
               codecNameLength,
               codecName,
               audio->fmt.clock_rate,
               audio->fmt.channel_cnt,
               audio->tx_pt,
               audio->rx_pt,
               audio->dir));

    if (audio->param != NULL) {
        unsigned encodePtime = audio->param->info.enc_ptime != 0
            ? audio->param->info.enc_ptime
            : audio->param->info.frm_ptime;

        PJ_LOG(3, (THIS_FILE,
                   "AUDIO_DIAG codec_pcm clock=%uHz channels=%u bits=%u frame_ptime=%ums encode_ptime=%ums avg_bps=%u max_bps=%u",
                   audio->param->info.clock_rate,
                   audio->param->info.channel_cnt,
                   audio->param->info.pcm_bits_per_sample,
                   audio->param->info.frm_ptime,
                   encodePtime,
                   audio->param->info.avg_bps,
                   audio->param->info.max_bps));
    }

    PJ_LOG(4, (THIS_FILE,
               "AUDIO_DIAG jitter init=%dms min_prefetch=%dms max_prefetch=%dms max=%dms",
               audio->jb_init,
               audio->jb_min_pre,
               audio->jb_max_pre,
               audio->jb_max));
}

static void LogSoundPath(void) {
    pjsua_snd_dev_param soundParameters;
    pjsua_snd_dev_param_default(&soundParameters);

    pj_status_t status = pjsua_get_snd_dev2(&soundParameters);
    if (status != PJ_SUCCESS) {
        PJ_PERROR(3, (THIS_FILE, status, "Could not get current sound device parameters"));
        return;
    }

    PJ_LOG(3, (THIS_FILE,
               "AUDIO_DIAG sound capture_id=%d playback_id=%d mode=0x%x default_settings=%d",
               soundParameters.capture_dev,
               soundParameters.playback_dev,
               soundParameters.mode,
               soundParameters.use_default_settings));

    LogSoundDevice("capture", soundParameters.capture_dev);
    if (soundParameters.playback_dev != soundParameters.capture_dev) {
        LogSoundDevice("playback", soundParameters.playback_dev);
    } else {
        LogSoundDevice("capture+playback", soundParameters.playback_dev);
    }
    LogConferenceBridge();
}

static void LogSoundDevice(const char *role, int deviceID) {
    if (deviceID < 0) {
        PJ_LOG(3, (THIS_FILE, "AUDIO_DIAG device role=%s id=%d", role, deviceID));
        return;
    }

    pjmedia_aud_dev_info info;
    pj_status_t status = pjmedia_aud_dev_get_info(deviceID, &info);
    if (status != PJ_SUCCESS) {
        PJ_PERROR(3, (THIS_FILE, status, "Could not get %s audio device info for id %d", role, deviceID));
        return;
    }

    PJ_LOG(3, (THIS_FILE,
               "AUDIO_DIAG device role=%s id=%d name=%s driver=%s rate=%uHz inputs=%u outputs=%u caps=0x%x",
               role,
               deviceID,
               info.name,
               info.driver,
               info.default_samples_per_sec,
               info.input_count,
               info.output_count,
               info.caps));
}

static void LogConferenceBridge(void) {
    pjsua_conf_port_info info;
    pj_status_t status = pjsua_conf_get_port_info(0, &info);
    if (status != PJ_SUCCESS) {
        PJ_PERROR(3, (THIS_FILE, status, "Could not get conference bridge sound-port info"));
        return;
    }

    PJ_LOG(3, (THIS_FILE,
               "AUDIO_DIAG conference clock=%uHz channels=%u samples_per_frame=%u bits=%u",
               info.clock_rate,
               info.channel_count,
               info.samples_per_frame,
               info.bits_per_sample));
}

static void CallMediaStateChanged(pjsua_call_id identifier, pjsua_call_media_status status, pjsua_conf_port_id port) {
    AKSIPUserAgent *userAgent = [AKSIPUserAgent sharedUserAgent];
    AKSIPCall *call = [userAgent callWithIdentifier:identifier];
    if (call == nil) {
        PJ_LOG(3, (THIS_FILE, "Could not find AKSIPCall for call %d during media state change", identifier));
        return;
    }
    ConnectCallToSoundDevice(call, status, port);
    [userAgent stopRingbackForCall:call];
    PostMediaStateChangeNotification(call, status);
}

static const char *MediaStatusTextWithStatus(pjsua_call_media_status status) {
    switch (status) {
        case PJSUA_CALL_MEDIA_NONE:
            return "None";
        case PJSUA_CALL_MEDIA_ACTIVE:
            return "Active";
        case PJSUA_CALL_MEDIA_LOCAL_HOLD:
            return "Local hold";
        case PJSUA_CALL_MEDIA_REMOTE_HOLD:
            return "Remote hold";
        case PJSUA_CALL_MEDIA_ERROR:
            return "Error";
        default:
            return "Unknown";
    }
}

static void ConnectCallToSoundDevice(AKSIPCall *call, pjsua_call_media_status status, pjsua_conf_port_id port) {
    if (status == PJSUA_CALL_MEDIA_ACTIVE || status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        pjsua_conf_connect(port, 0);
        if (!call.isMicrophoneMuted) {
            pjsua_conf_connect(0, port);
        }
    }
}

static void PostMediaStateChangeNotification(AKSIPCall *call, pjsua_call_media_status status) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSString *notificationName = nil;
    switch (status) {
        case PJSUA_CALL_MEDIA_ACTIVE:
            notificationName = AKSIPCallMediaDidBecomeActiveNotification;
            break;
        case PJSUA_CALL_MEDIA_LOCAL_HOLD:
            notificationName = AKSIPCallDidLocalHoldNotification;
            break;
        case PJSUA_CALL_MEDIA_REMOTE_HOLD:
            notificationName = AKSIPCallDidRemoteHoldNotification;
            break;
        default:
            break;
    }

    if (notificationName != nil) {
        [nc postNotificationName:notificationName object:call];
    }
}
