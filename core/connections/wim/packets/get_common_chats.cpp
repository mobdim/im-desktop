#include "stdafx.h"
#include "get_common_chats.h"

#include "../../../http_request.h"
#include "../../urls_cache.h"

using namespace core;
using namespace wim;


get_common_chats::get_common_chats(wim_packet_params _params, const std::string& _sn)
    :    robusto_packet(std::move(_params))
    ,   sn_(_sn)
{
}


get_common_chats::~get_common_chats()
{

}

int32_t get_common_chats::init_request(std::shared_ptr<core::http_request_simple> _request)
{
    constexpr char method[] = "getCommonChats";

    _request->set_url(urls::get_url(urls::url_type::rapi_host));
    _request->set_normalized_url(method);
    _request->set_keep_alive();

    rapidjson::Document doc(rapidjson::Type::kObjectType);
    auto& a = doc.GetAllocator();

    doc.AddMember("method", method, a);
    doc.AddMember("reqId", get_req_id(), a);

    rapidjson::Value node_params(rapidjson::Type::kObjectType);
    node_params.AddMember("sn", sn_, a);
    doc.AddMember("params", std::move(node_params), a);

    sign_packet(doc, a, _request);

    if (!params_.full_log_)
    {
        log_replace_functor f;
        f.add_marker("a");
        f.add_json_marker("aimsid", aimsid_range_evaluator());
        _request->set_replace_log_function(f);
    }

    return 0;
}

int32_t get_common_chats::parse_results(const rapidjson::Value& _node_results)
{
    const auto iter_chats = _node_results.FindMember("chats");
    if (iter_chats != _node_results.MemberEnd() && iter_chats->value.IsArray())
    {
        for (const auto &node : iter_chats->value.GetArray())
        {
            common_chat_info info;
            info.unserialize(node);
            result_.push_back(std::move(info));
        }
    }

    return 0;
}
