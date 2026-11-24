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
  | "admin_whitelist_list"
  | "audit_list"
  | "admin_role_get"
  | "admin_role_set"
  | "uri_block_add"
  | "uri_block_del"
  | "uri_block_list"
  | "route_quota_set";

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

export type GatewayStorageBackend = "memory" | "redis" | "sqlite";

export type AdminOkResponse = {
  ok: true;
  msg?: string;
  storage?: GatewayStorageBackend;
  whitelist?: string[];
  admin_whitelist?: string[];
  apikey?: ApiKeyRecord;
  apikeys?: ApiKeyRecord[];
  total?: number;
  page?: number;
  page_size?: number;
  total_pages?: number;
};

export type AdminProbeResponse = AdminOkResponse & {
  msg: "hmac verified";
  storage: GatewayStorageBackend;
};

export type AdminErrResponse = {
  ok: false;
  msg: string;
};

export type AdminResponse = AdminOkResponse | AdminErrResponse;
