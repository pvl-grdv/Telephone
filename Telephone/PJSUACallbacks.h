//
//  PJSUACallbacks.h
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import <pjsua-lib/pjsua.h>

void PJSUAOnIncomingCall(pjsua_acc_id accountID, pjsua_call_id callID, pjsip_rx_data *invite);
void PJSUAOnCallState(pjsua_call_id callID, pjsip_event *event);
void PJSUAOnCallMediaState(pjsua_call_id callID);
void PJSUAOnCallTransferStatus(pjsua_call_id callID,
                               int statusCode,
                               const pj_str_t *statusText,
                               pj_bool_t isFinal,
                               pj_bool_t *wantsFurtherNotifications);
void PJSUAOnCallReplaced(pjsua_call_id oldCallID, pjsua_call_id newCallID);
void PJSUAOnAccountRegistrationState(pjsua_acc_id accountID);
void PJSUAOnNATDetect(const pj_stun_nat_detect_result *result);
void PJSUAOnAccountFindForIncoming(const pjsip_rx_data *rdata, pjsua_acc_id *acc_id);

static inline pj_status_t TelephonePJSIPFailedCredentialError(void) {
    return PJSIP_EFAILEDCREDENTIAL;
}


static inline pj_status_t TelephonePJSIPRegisterCurrentThread(void) {
    if (pj_thread_is_registered()) {
        return PJ_SUCCESS;
    }

    static _Thread_local pj_thread_desc descriptor;
    pj_thread_t *thread = NULL;
    return pj_thread_register(
        "Telephone-swift",
        descriptor,
        &thread
    );
}

static inline void TelephonePJSUASetNameServer(
    pjsua_config *config,
    unsigned index,
    pj_str_t value
) {
    config->nameserver[index] = value;
}

static inline void TelephonePJSUASetOutboundProxy(
    pjsua_config *config,
    pj_str_t value
) {
    config->outbound_proxy[0] = value;
}

static inline void TelephonePJSUASetSTUNServer(
    pjsua_config *config,
    pj_str_t value
) {
    config->stun_srv[0] = value;
}

static inline void TelephonePJSUAConfigureCredential(
    pjsua_acc_config *config,
    pj_str_t realm,
    pj_str_t username,
    pj_str_t password
) {
    config->cred_count = 1;
    config->cred_info[0].realm = realm;
    config->cred_info[0].scheme = pj_str("digest");
    config->cred_info[0].username = username;
    config->cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    config->cred_info[0].data = password;
}

static inline void TelephonePJSUASetAccountProxy(
    pjsua_acc_config *config,
    pj_str_t value
) {
    config->proxy_cnt = 1;
    config->proxy[0] = value;
}

static inline pjsip_sip_uri *TelephonePJSIPIncomingToURI(
    const pjsip_rx_data *data
) {
    if (data == NULL || data->msg_info.to == NULL) {
        return NULL;
    }
    return (pjsip_sip_uri *)pjsip_uri_get_uri(data->msg_info.to->uri);
}

static inline pjsip_sip_uri *TelephonePJSIPIncomingRequestURI(
    const pjsip_rx_data *data
) {
    if (data == NULL || data->msg_info.msg == NULL) {
        return NULL;
    }
    return (pjsip_sip_uri *)pjsip_uri_get_uri(
        data->msg_info.msg->line.req.uri
    );
}

static inline void TelephonePJSUAOnIPChangeProgress(
    pjsua_ip_change_op operation,
    pj_status_t status,
    const pjsua_ip_change_op_info *info
) {
    (void)info;
    PJ_LOG(
        3,
        (
            "Telephone",
            "SIP_IP_CHANGE op=%d status=%d",
            (int)operation,
            status
        )
    );
}

static inline void TelephonePJSUAConfigureCallbacks(
    pjsua_config *config
) {
    config->cb.on_incoming_call = &PJSUAOnIncomingCall;
    config->cb.on_call_state = &PJSUAOnCallState;
    config->cb.on_call_media_state = &PJSUAOnCallMediaState;
    config->cb.on_call_transfer_status = &PJSUAOnCallTransferStatus;
    config->cb.on_call_replaced = &PJSUAOnCallReplaced;
    config->cb.on_reg_state = &PJSUAOnAccountRegistrationState;
    config->cb.on_nat_detect = &PJSUAOnNATDetect;
    config->cb.on_acc_find_for_incoming = &PJSUAOnAccountFindForIncoming;
    config->cb.on_ip_change_progress = &TelephonePJSUAOnIPChangeProgress;
}
