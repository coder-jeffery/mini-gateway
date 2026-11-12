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
  | "service_create"
  | "service_update"
  | "service_delete"
  | "service_get"
  | "service_list";

export type ApiKeyRecord = {
  api_key: string;
  limit: number;
  window: number;
};

export type ServiceRecord = {
  id: string;
  name: string;
  path_prefix: string;
  upstream_url: string;
  cors_enabled: boolean;
  cors_allow_origins: string;
  cors_allow_methods: string;
  cors_allow_headers: string;
  cors_expose_headers: string;
  cors_max_age: number;
  cors_allow_credentials: boolean;
};

export type ApiKeyListResponse = {
  ok: true;
  apikeys: ApiKeyRecord[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
};

export type ServiceListResponse = {
  ok: true;
  services: ServiceRecord[];
};

export type AdminOkResponse = {
  ok: true;
  msg?: string;
  whitelist?: string[];
  admin_whitelist?: string[];
  apikey?: ApiKeyRecord;
  apikeys?: ApiKeyRecord[];
  service?: ServiceRecord;
  services?: ServiceRecord[];
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
