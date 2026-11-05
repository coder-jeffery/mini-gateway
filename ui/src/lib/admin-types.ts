export type AdminAction =
  | "upsert_apikey"
  | "del_apikey"
  | "get_apikey"
  | "apikey_list"
  | "whitelist_add"
  | "whitelist_del"
  | "whitelist_list"
  | "admin_whitelist_add"
  | "admin_whitelist_del"
  | "admin_whitelist_list";

export type ApiKeyRecord = {
  api_key: string;
  limit: number;
  window: number;
};

export type ApiKeyListResponse = {
  ok: true;
  apikeys: ApiKeyRecord[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
};

export type AdminOkResponse = {
  ok: true;
  msg?: string;
  whitelist?: string[];
  admin_whitelist?: string[];
  apikey?: ApiKeyRecord;
  apikeys?: ApiKeyRecord[];
  total?: number;
  page?: number;
  page_size?: number;
  total_pages?: number;
};

export type AdminErrResponse = {
  ok: false;
  msg: string;
};

export type AdminResponse = AdminOkResponse | AdminErrResponse;
