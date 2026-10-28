#include "RimeBridge.h"
#include "rime_api.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
static RimeApi *api;
static RimeSessionId session;
static RimeContext context;
static int has_context;
static char committed[16384];
static char *shared_path, *user_path;
static void refresh(void) {
  if (has_context) api->free_context(&context);
  memset(&context, 0, sizeof(context));
  RIME_STRUCT_INIT(RimeContext, context);
  has_context = session && api->get_context(session, &context);
}
int tb_rime_start(const char *shared, const char *user, int deploy) {
  if (session) return 1;
  api = rime_get_api();
  shared_path = strdup(shared); user_path = strdup(user);
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared_path; traits.user_data_dir = user_path;
  traits.distribution_name = "ThumbBall"; traits.distribution_code_name = "thumbball";
  traits.distribution_version = "1.5"; traits.app_name = "rime.thumbball";
  traits.min_log_level = 2; traits.log_dir = user_path;
  api->setup(&traits); api->initialize(&traits);
  if (deploy) { api->start_maintenance(1); api->join_maintenance_thread(); }
  session = api->create_session();
  if (!session || !api->select_schema(session, "thumbball_t9")) { tb_rime_stop(); return 0; }
  api->set_option(session, "ascii_mode", 0);
  refresh(); return 1;
}
void tb_rime_stop(void) {
  if (!api) return;
  if (has_context) { api->free_context(&context); has_context = 0; }
  if (session) { api->destroy_session(session); session = 0; }
  api->finalize(); api = NULL;
  free(shared_path); free(user_path); shared_path = user_path = NULL;
}
int tb_rime_key(int code) { if (!session) return 0; int ok = api->process_key(session, code, 0); refresh(); return ok; }
void tb_rime_clear(void) { if (session) { api->clear_composition(session); (void)tb_rime_commit(); refresh(); } }
int tb_rime_select(int index) { if (!session || index < 0 || index >= tb_rime_count()) return 0; int ok = api->select_candidate_on_current_page(session, (size_t)index); refresh(); return ok; }
int tb_rime_page(int backward) {
  if (!session || !has_context || (backward && context.menu.page_no == 0) || (!backward && context.menu.is_last_page)) return 0;
  int before = context.menu.page_no;
  int ok = api->change_page(session, backward); refresh();
  return ok && has_context && context.menu.num_candidates > 0 && context.menu.page_no != before;
}
int tb_rime_count(void) { return has_context ? context.menu.num_candidates : 0; }
const char *tb_rime_candidate(int index) { return has_context && index >= 0 && index < context.menu.num_candidates ? context.menu.candidates[index].text : ""; }
const char *tb_rime_preedit(void) { return has_context && context.composition.preedit ? context.composition.preedit : ""; }
const char *tb_rime_commit(void) {
  committed[0] = 0;
  if (session) { RIME_STRUCT(RimeCommit, c); if (api->get_commit(session, &c)) { if(c.text) snprintf(committed, sizeof(committed), "%s", c.text); api->free_commit(&c); } }
  return committed;
}
