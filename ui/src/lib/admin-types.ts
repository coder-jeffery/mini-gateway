export type AdminAction =
  | "upsert_apikey"
  | "del_apikey"
  | "whitelist_add"
  | "whitelist_del"
  | "whitelist_list"
  | "admin_whitelist_add"
  | "admin_whitelist_del"
  | "admin_whitelist_list";

export type AdminOkResponse = {
  ok: true;
  msg?: string;
  whitelist?: string[];
  admin_whitelist?: string[];
};

export type AdminErrResponse = {
  ok: false;
  msg: string;
};

export type AdminResponse = AdminOkResponse | AdminErrResponse;
