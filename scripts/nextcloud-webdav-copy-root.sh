#!/usr/bin/env bash
set -euo pipefail

if [[ -f "${HOME}/.bash_profile" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bash_profile" >/dev/null 2>&1
fi

KUBE_CONTEXT="${KUBE_CONTEXT:-admin@staging}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-nextcloud}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-nextcloud-migration-clean}"

SOURCE_SERVICE_URL="${SOURCE_SERVICE_URL:-http://nextcloud.default.svc.cluster.local}"
TARGET_SERVICE_URL="${TARGET_SERVICE_URL:-http://127.0.0.1}"

SOURCE_USER="${SOURCE_USER:-}"
TARGET_USER="${TARGET_USER:-${SOURCE_USER}}"
COPY_ROOT="${COPY_ROOT:-}"
ALLOW_ENTIRE_HOME="${ALLOW_ENTIRE_HOME:-false}"
APPLY="${APPLY:-false}"
MAX_FILES="${MAX_FILES:-1000}"
VERIFY_AFTER_COPY="${VERIFY_AFTER_COPY:-true}"
VERIFY_RAW_ENCRYPTION="${VERIFY_RAW_ENCRYPTION:-true}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/nextcloud-webdav-copy-root-$(date +%Y%m%d-%H%M%S)}"

SOURCE_PASSWORD="${SOURCE_PASSWORD:-}"
TARGET_PASSWORD="${TARGET_PASSWORD:-}"

if [[ -z "${SOURCE_USER}" ]]; then
  echo "SOURCE_USER is required" >&2
  exit 2
fi

if [[ -z "${TARGET_USER}" ]]; then
  echo "TARGET_USER is required" >&2
  exit 2
fi

if [[ -z "${COPY_ROOT}" || "${COPY_ROOT}" == "/" ]]; then
  if [[ "${ALLOW_ENTIRE_HOME}" != "true" ]]; then
    echo "COPY_ROOT is required. Set ALLOW_ENTIRE_HOME=true to operate on an entire user home." >&2
    exit 2
  fi
  COPY_ROOT=""
elif [[ "${COPY_ROOT}" == /* || "${COPY_ROOT}" == *".."* ]]; then
  echo "COPY_ROOT must be a relative path without '..'" >&2
  exit 2
fi

if [[ -z "${SOURCE_PASSWORD}" ]]; then
  echo "SOURCE_PASSWORD is required; use an app password or a temporary migration credential" >&2
  exit 2
fi

if [[ -z "${TARGET_PASSWORD}" ]]; then
  echo "TARGET_PASSWORD is required; use an app password or a temporary migration credential" >&2
  exit 2
fi

mkdir -p "${OUTPUT_DIR}"

report_file="${OUTPUT_DIR}/webdav-copy-root-report.json"

kubectl --context "${KUBE_CONTEXT}" -n "${TARGET_NAMESPACE}" exec -i "deploy/${TARGET_DEPLOYMENT}" -c nextcloud -- \
  env \
    SOURCE_SERVICE_URL="${SOURCE_SERVICE_URL}" \
    TARGET_SERVICE_URL="${TARGET_SERVICE_URL}" \
    SOURCE_USER="${SOURCE_USER}" \
    TARGET_USER="${TARGET_USER}" \
    SOURCE_PASSWORD="${SOURCE_PASSWORD}" \
    TARGET_PASSWORD="${TARGET_PASSWORD}" \
    COPY_ROOT="${COPY_ROOT}" \
    ALLOW_ENTIRE_HOME="${ALLOW_ENTIRE_HOME}" \
    APPLY="${APPLY}" \
    MAX_FILES="${MAX_FILES}" \
    VERIFY_AFTER_COPY="${VERIFY_AFTER_COPY}" \
    VERIFY_RAW_ENCRYPTION="${VERIFY_RAW_ENCRYPTION}" \
    php <<'PHP' >"${report_file}"
<?php
declare(strict_types=1);

function env_value(string $name): string {
    $value = getenv($name);
    if ($value === false) {
        return '';
    }
    return $value;
}

function bool_env(string $name): bool {
    return in_array(strtolower(env_value($name)), ['1', 'true', 'yes', 'on'], true);
}

function encode_path(string $path): string {
    $path = trim($path, '/');
    if ($path === '') {
        return '';
    }
    return implode('/', array_map('rawurlencode', explode('/', $path)));
}

function webdav_base(string $service_url, string $user): string {
    return rtrim($service_url, '/') . '/remote.php/dav/files/' . rawurlencode($user);
}

function webdav_url(string $base, string $path): string {
    $encoded = encode_path($path);
    if ($encoded === '') {
        return $base . '/';
    }
    return $base . '/' . $encoded;
}

function request(string $method, string $url, string $user, string $password, array $headers = [], ?string $body = null): array {
    $header_lines = array_merge([
        'Authorization: Basic ' . base64_encode($user . ':' . $password),
        'User-Agent: nextcloud-webdav-copy-root/1.0',
    ], $headers);

    $context = stream_context_create([
        'http' => [
            'method' => $method,
            'header' => implode("\r\n", $header_lines),
            'content' => $body ?? '',
            'ignore_errors' => true,
            'timeout' => 120,
        ],
    ]);

    $response = @file_get_contents($url, false, $context);
    $response_headers = $http_response_header ?? [];
    $status = 0;
    foreach ($response_headers as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d+)/', $header, $matches)) {
            $status = (int) $matches[1];
        }
    }

    return [
        'status' => $status,
        'body' => $response === false ? '' : $response,
        'headers' => $response_headers,
    ];
}

function curl_status_or_fail($curl, string $label): array {
    $ok = curl_exec($curl);
    $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);

    if ($ok === false) {
        fwrite(STDERR, $label . ' curl_error=' . $error . "\n");
        exit(1);
    }

    return ['status' => $status, 'body' => '', 'headers' => []];
}

function curl_download_to_file(string $url, string $user, string $password, string $path): array {
    $handle = fopen($path, 'wb');
    if ($handle === false) {
        fwrite(STDERR, 'Unable to open temporary download path ' . $path . "\n");
        exit(1);
    }

    $curl = curl_init($url);
    curl_setopt_array($curl, [
        CURLOPT_CUSTOMREQUEST => 'GET',
        CURLOPT_USERPWD => $user . ':' . $password,
        CURLOPT_HTTPAUTH => CURLAUTH_BASIC,
        CURLOPT_USERAGENT => 'nextcloud-webdav-copy-root/1.0',
        CURLOPT_FILE => $handle,
        CURLOPT_FOLLOWLOCATION => false,
        CURLOPT_FAILONERROR => false,
        CURLOPT_CONNECTTIMEOUT => 30,
        CURLOPT_TIMEOUT => 0,
    ]);

    $result = curl_status_or_fail($curl, 'GET ' . $url);
    fclose($handle);
    return $result;
}

function curl_upload_file(string $url, string $user, string $password, string $path): array {
    $handle = fopen($path, 'rb');
    if ($handle === false) {
        fwrite(STDERR, 'Unable to open temporary upload path ' . $path . "\n");
        exit(1);
    }

    $curl = curl_init($url);
    curl_setopt_array($curl, [
        CURLOPT_UPLOAD => true,
        CURLOPT_CUSTOMREQUEST => 'PUT',
        CURLOPT_USERPWD => $user . ':' . $password,
        CURLOPT_HTTPAUTH => CURLAUTH_BASIC,
        CURLOPT_USERAGENT => 'nextcloud-webdav-copy-root/1.0',
        CURLOPT_INFILE => $handle,
        CURLOPT_INFILESIZE => filesize($path),
        CURLOPT_HTTPHEADER => ['Content-Type: application/octet-stream'],
        CURLOPT_FOLLOWLOCATION => false,
        CURLOPT_FAILONERROR => false,
        CURLOPT_CONNECTTIMEOUT => 30,
        CURLOPT_TIMEOUT => 0,
    ]);

    $result = curl_status_or_fail($curl, 'PUT ' . $url);
    fclose($handle);
    return $result;
}

function require_status(array $response, array $allowed, string $label): void {
    if (!in_array($response['status'], $allowed, true)) {
        fwrite(STDERR, $label . ' unexpected_status=' . $response['status'] . "\n");
        exit(1);
    }
}

function propfind_children(string $base, string $user, string $password, string $path): array {
    $body = '<?xml version="1.0" encoding="utf-8" ?>'
        . '<d:propfind xmlns:d="DAV:"><d:prop>'
        . '<d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
        . '</d:prop></d:propfind>';

    $response = request(
        'PROPFIND',
        webdav_url($base, $path),
        $user,
        $password,
        ['Depth: 1', 'Content-Type: application/xml; charset=utf-8'],
        $body
    );
    require_status($response, [207], 'PROPFIND ' . $path);

    $dom = new DOMDocument();
    $previous = libxml_use_internal_errors(true);
    $loaded = $dom->loadXML($response['body']);
    libxml_use_internal_errors($previous);
    if (!$loaded) {
        fwrite(STDERR, 'Unable to parse WebDAV PROPFIND response for ' . $path . "\n");
        exit(1);
    }

    $xpath = new DOMXPath($dom);
    $xpath->registerNamespace('d', 'DAV:');
    $children = [];
    $prefix = '/remote.php/dav/files/' . $user . '/';
    $current = trim($path, '/');

    foreach ($xpath->query('//d:response') as $response_node) {
        $href = $xpath->evaluate('string(d:href)', $response_node);
        $href_path = rawurldecode(parse_url($href, PHP_URL_PATH) ?? '');
        $prefix_pos = strpos($href_path, $prefix);
        if ($prefix_pos === false) {
            continue;
        }

        $relative = trim(substr($href_path, $prefix_pos + strlen($prefix)), '/');
        if ($relative === $current) {
            continue;
        }

        $is_collection = $xpath->evaluate('count(d:propstat/d:prop/d:resourcetype/d:collection)', $response_node) > 0;
        $size_value = $xpath->evaluate('string(d:propstat/d:prop/d:getcontentlength)', $response_node);
        $modified = $xpath->evaluate('string(d:propstat/d:prop/d:getlastmodified)', $response_node);
        $children[] = [
            'path' => $relative,
            'type' => $is_collection ? 'directory' : 'file',
            'size' => $size_value === '' ? null : (int) $size_value,
            'last_modified' => $modified === '' ? null : $modified,
        ];
    }

    return $children;
}

function ensure_collection(string $base, string $user, string $password, string $path): void {
    $parts = explode('/', trim($path, '/'));
    $current = '';
    foreach ($parts as $part) {
        if ($part === '') {
            continue;
        }
        $current = $current === '' ? $part : $current . '/' . $part;
        $response = request('MKCOL', webdav_url($base, $current), $user, $password);
        require_status($response, [201, 405], 'MKCOL ' . $current);
    }
}

function sha256_bytes(string $bytes): string {
    return hash('sha256', $bytes);
}

function copy_file(array $ctx, string $path): array {
    $tmp_source = tempnam(sys_get_temp_dir(), 'nextcloud-source-');
    $tmp_target = tempnam(sys_get_temp_dir(), 'nextcloud-target-');
    if ($tmp_source === false || $tmp_target === false) {
        fwrite(STDERR, "Unable to create temporary copy files\n");
        exit(1);
    }

    $source = curl_download_to_file(
        webdav_url($ctx['source_base'], $path),
        $ctx['source_user'],
        $ctx['source_password'],
        $tmp_source
    );
    require_status($source, [200], 'GET source ' . $path);
    $source_sha = hash_file('sha256', $tmp_source);
    $bytes = filesize($tmp_source);

    $parent = dirname($path);
    if ($parent !== '.' && $parent !== '') {
        ensure_collection($ctx['target_base'], $ctx['target_user'], $ctx['target_password'], $parent);
    }

    $put = curl_upload_file(
        webdav_url($ctx['target_base'], $path),
        $ctx['target_user'],
        $ctx['target_password'],
        $tmp_source
    );
    require_status($put, [200, 201, 204], 'PUT target ' . $path);

    $target_sha = null;
    if ($ctx['verify_after_copy']) {
        $target = curl_download_to_file(
            webdav_url($ctx['target_base'], $path),
            $ctx['target_user'],
            $ctx['target_password'],
            $tmp_target
        );
        require_status($target, [200], 'GET target ' . $path);
        $target_sha = hash_file('sha256', $tmp_target);
        if ($source_sha !== $target_sha) {
            fwrite(STDERR, 'checksum_mismatch path=' . $path . "\n");
            exit(1);
        }
    }

    $raw_encrypted = null;
    if ($ctx['verify_raw_encryption'] && $bytes > 0) {
        $raw_encrypted = raw_target_file_is_encrypted($ctx['target_user'], $path);
        if (!$raw_encrypted) {
            fwrite(STDERR, 'target_file_not_nextcloud_encrypted path=' . $path . "\n");
            exit(1);
        }
    }

    @unlink($tmp_source);
    @unlink($tmp_target);

    return [
        'path' => $path,
        'bytes' => $bytes,
        'sha256' => $source_sha,
        'target_sha256' => $target_sha,
        'raw_target_file_encrypted' => $raw_encrypted,
    ];
}

function raw_target_file_is_encrypted(string $target_user, string $path): bool {
    if (str_contains($path, "\0") || str_contains($target_user, "\0")) {
        return false;
    }

    foreach (explode('/', $path) as $segment) {
        if ($segment === '..') {
            return false;
        }
    }

    $raw_path = '/var/www/html/data/' . $target_user . '/files/' . $path;
    if (!is_file($raw_path)) {
        return false;
    }

    $handle = fopen($raw_path, 'rb');
    if ($handle === false) {
        return false;
    }
    $header = fread($handle, 96);
    fclose($handle);

    return is_string($header)
        && str_contains($header, 'HBEGIN:oc_encryption_module:OC_DEFAULT_MODULE');
}

$source_user = env_value('SOURCE_USER');
$target_user = env_value('TARGET_USER');
$copy_root = trim(env_value('COPY_ROOT'), '/');
$copy_root_display = $copy_root === '' ? '/' : $copy_root;
$apply = bool_env('APPLY');
$allow_entire_home = bool_env('ALLOW_ENTIRE_HOME');
$verify_after_copy = bool_env('VERIFY_AFTER_COPY');
$verify_raw_encryption = bool_env('VERIFY_RAW_ENCRYPTION');
$max_files = (int) env_value('MAX_FILES');

$ctx = [
    'source_user' => $source_user,
    'source_password' => env_value('SOURCE_PASSWORD'),
    'target_user' => $target_user,
    'target_password' => env_value('TARGET_PASSWORD'),
    'source_base' => webdav_base(env_value('SOURCE_SERVICE_URL'), $source_user),
    'target_base' => webdav_base(env_value('TARGET_SERVICE_URL'), $target_user),
    'verify_after_copy' => $verify_after_copy,
    'verify_raw_encryption' => $verify_raw_encryption,
];

$seen = [];
$directories = [];
$files = [];
$stack = [$copy_root];

while ($stack !== []) {
    $dir = array_pop($stack);
    if (isset($seen[$dir])) {
        continue;
    }
    $seen[$dir] = true;
    $directories[] = $dir;
    foreach (propfind_children($ctx['source_base'], $source_user, $ctx['source_password'], $dir) as $child) {
        if ($child['type'] === 'directory') {
            $stack[] = $child['path'];
        } else {
            $files[] = $child;
        }
    }
}

usort($directories, static fn($a, $b) => strcmp($a, $b));
usort($files, static fn($a, $b) => strcmp($a['path'], $b['path']));

$total_bytes = array_sum(array_map(static fn($file) => $file['size'] ?? 0, $files));
$copied = [];

if ($apply && count($files) > $max_files) {
    fwrite(STDERR, 'Refusing to copy ' . count($files) . ' files because MAX_FILES=' . $max_files . "\n");
    exit(1);
}

if ($apply) {
    foreach ($directories as $directory) {
        ensure_collection($ctx['target_base'], $target_user, $ctx['target_password'], $directory);
    }
    foreach ($files as $file) {
        $copied[] = copy_file($ctx, $file['path']);
    }
}

$report = [
    'generated_at' => gmdate('c'),
    'source_user' => $source_user,
    'target_user' => $target_user,
    'copy_root' => $copy_root_display,
    'allow_entire_home' => $allow_entire_home,
    'apply' => $apply,
    'max_files' => $max_files,
    'verify_after_copy' => $verify_after_copy,
    'verify_raw_encryption' => $verify_raw_encryption,
    'safety_boundary' => [
        'uses_webdav_only' => true,
        'does_not_read_raw_s3_objects' => true,
        'does_not_modify_nextcloud_config' => true,
        'does_not_delete_source_data' => true,
    ],
    'planned' => [
        'directory_count' => count($directories),
        'file_count' => count($files),
        'total_bytes' => $total_bytes,
        'directories' => $directories,
        'files' => $files,
    ],
    'copied' => [
        'file_count' => count($copied),
        'total_bytes' => array_sum(array_map(static fn($file) => $file['bytes'], $copied)),
        'files' => $copied,
    ],
];

echo json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
PHP

jq -r '
  "webdav_copy_root_report=" + input_filename,
  "source_user=" + .source_user,
  "target_user=" + .target_user,
  "copy_root=" + .copy_root,
  "allow_entire_home=" + (.allow_entire_home | tostring),
  "apply=" + (.apply | tostring),
  "verify_raw_encryption=" + (.verify_raw_encryption | tostring),
  "planned_directories=" + (.planned.directory_count | tostring),
  "planned_files=" + (.planned.file_count | tostring),
  "planned_bytes=" + (.planned.total_bytes | tostring),
  "copied_files=" + (.copied.file_count | tostring),
  "copied_bytes=" + (.copied.total_bytes | tostring),
  "uses_webdav_only=" + (.safety_boundary.uses_webdav_only | tostring)
' "${report_file}"

cat <<EOF

Wrote WebDAV copy report to:
${report_file}

Default mode is dry-run. Set APPLY=true only for a reviewed COPY_ROOT, or with
ALLOW_ENTIRE_HOME=true after the whole-home dry-run report has been reviewed.
EOF
