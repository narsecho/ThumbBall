#ifndef TB_RIME_BRIDGE_H
#define TB_RIME_BRIDGE_H
int tb_rime_start(const char *shared, const char *user, int deploy);
void tb_rime_stop(void);
int tb_rime_key(int code);
void tb_rime_clear(void);
int tb_rime_select(int index);
int tb_rime_page(int backward);
int tb_rime_count(void);
const char *tb_rime_candidate(int index);
const char *tb_rime_preedit(void);
const char *tb_rime_commit(void);
#endif
