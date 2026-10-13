from pathlib import Path
p=Path(__file__).resolve().parent.parent/'vendor/whisper/examples/server/server.cpp'
s=p.read_text()
needle='    std::atomic<server_state> state{SERVER_STATE_LOADING_MODEL};'
patch='''
    // Folio: protect the local speech engine from other applications and websites.
    const char * folio_env = std::getenv("FOLIO_ENGINE_TOKEN");
    const std::string folio_token = folio_env ? folio_env : "";
    if (!folio_token.empty()) {
        svr->set_pre_routing_handler([folio_token](const httplib::Request & req, httplib::Response & res) {
            if (req.get_header_value("Authorization") != "Bearer " + folio_token) {
                res.status = 401;
                res.set_content("Unauthorized", "text/plain");
                return httplib::Server::HandlerResponse::Handled;
            }
            if (req.path != "/" && req.path != "/inference") {
                res.status = 404;
                return httplib::Server::HandlerResponse::Handled;
            }
            return httplib::Server::HandlerResponse::Unhandled;
        });
    }
'''
if 'FOLIO_ENGINE_TOKEN' not in s:
 s=s.replace(needle,needle+'\n'+patch)
 p.write_text(s)

# Preserve explicit authentication failures in the upstream error handler.
s=p.read_text()
if 'if (res.status == 401) { res.set_content' not in s:
 s=s.replace('if (res.status == 400) {', 'if (res.status == 401) { res.set_content("Unauthorized", "text/plain"); } else if (res.status == 400) {')
p.write_text(s)
