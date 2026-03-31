--
-- PostgreSQL database dump
--

\restrict dRGFCMs3dX3ktoMU0AA8mOCLtBciYFeQ5Zuf13gzcc4zcqQQNr75vKcWODreXCs

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg13+2)
-- Dumped by pg_dump version 18.1 (Debian 18.1-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

ALTER TABLE IF EXISTS ONLY public.oauth2_refresh_token_session DROP CONSTRAINT IF EXISTS oauth2_refresh_token_session_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_refresh_token_session DROP CONSTRAINT IF EXISTS oauth2_refresh_token_session_challenge_id_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_pkce_request_session DROP CONSTRAINT IF EXISTS oauth2_pkce_request_session_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_pkce_request_session DROP CONSTRAINT IF EXISTS oauth2_pkce_request_session_challenge_id_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_openid_connect_session DROP CONSTRAINT IF EXISTS oauth2_openid_connect_session_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_openid_connect_session DROP CONSTRAINT IF EXISTS oauth2_openid_connect_session_challenge_id_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_device_code_session DROP CONSTRAINT IF EXISTS oauth2_device_code_session_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_device_code_session DROP CONSTRAINT IF EXISTS oauth2_device_code_session_challenge_id_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_consent_session DROP CONSTRAINT IF EXISTS oauth2_consent_session_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_consent_session DROP CONSTRAINT IF EXISTS oauth2_consent_session_preconfiguration_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_consent_preconfiguration DROP CONSTRAINT IF EXISTS oauth2_consent_preconfiguration_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_authorization_code_session DROP CONSTRAINT IF EXISTS oauth2_authorization_code_session_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_authorization_code_session DROP CONSTRAINT IF EXISTS oauth2_authorization_code_session_challenge_id_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_access_token_session DROP CONSTRAINT IF EXISTS oauth2_access_token_session_subject_fkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_access_token_session DROP CONSTRAINT IF EXISTS oauth2_access_token_session_challenge_id_fkey;
DROP INDEX IF EXISTS public.webauthn_users_lookup_key;
DROP INDEX IF EXISTS public.webauthn_credentials_lookup_key;
DROP INDEX IF EXISTS public.webauthn_credentials_kid_key;
DROP INDEX IF EXISTS public.user_preferences_username_key;
DROP INDEX IF EXISTS public.user_opaque_identifier_service_sector_id_username_key;
DROP INDEX IF EXISTS public.user_opaque_identifier_identifier_key;
DROP INDEX IF EXISTS public.totp_history_lookup_key;
DROP INDEX IF EXISTS public.totp_configurations_username_key;
DROP INDEX IF EXISTS public.one_time_code_lookup_key;
DROP INDEX IF EXISTS public.oauth2_refresh_token_session_request_id_idx;
DROP INDEX IF EXISTS public.oauth2_refresh_token_session_client_id_subject_idx;
DROP INDEX IF EXISTS public.oauth2_refresh_token_session_client_id_idx;
DROP INDEX IF EXISTS public.oauth2_pkce_request_session_request_id_idx;
DROP INDEX IF EXISTS public.oauth2_pkce_request_session_client_id_subject_idx;
DROP INDEX IF EXISTS public.oauth2_pkce_request_session_client_id_idx;
DROP INDEX IF EXISTS public.oauth2_par_context_signature_key;
DROP INDEX IF EXISTS public.oauth2_openid_connect_session_request_id_idx;
DROP INDEX IF EXISTS public.oauth2_openid_connect_session_client_id_subject_idx;
DROP INDEX IF EXISTS public.oauth2_openid_connect_session_client_id_idx;
DROP INDEX IF EXISTS public.oauth2_device_code_session_request_id_idx;
DROP INDEX IF EXISTS public.oauth2_device_code_session_client_id_subject_idx;
DROP INDEX IF EXISTS public.oauth2_device_code_session_client_id_idx;
DROP INDEX IF EXISTS public.oauth2_consent_session_challenge_id_key;
DROP INDEX IF EXISTS public.oauth2_blacklisted_jti_signature_key;
DROP INDEX IF EXISTS public.oauth2_authorization_code_session_request_id_idx;
DROP INDEX IF EXISTS public.oauth2_authorization_code_session_client_id_subject_idx;
DROP INDEX IF EXISTS public.oauth2_authorization_code_session_client_id_idx;
DROP INDEX IF EXISTS public.oauth2_access_token_session_request_id_idx;
DROP INDEX IF EXISTS public.oauth2_access_token_session_client_id_subject_idx;
DROP INDEX IF EXISTS public.oauth2_access_token_session_client_id_idx;
DROP INDEX IF EXISTS public.identity_verification_jti_key;
DROP INDEX IF EXISTS public.encryption_name_key;
DROP INDEX IF EXISTS public.duo_devices_username_key;
DROP INDEX IF EXISTS public.cached_data_name_key;
DROP INDEX IF EXISTS public.banned_user_username_idx;
DROP INDEX IF EXISTS public.banned_user_lookup_idx;
DROP INDEX IF EXISTS public.banned_user_list_idx;
DROP INDEX IF EXISTS public.banned_ip_lookup_idx;
DROP INDEX IF EXISTS public.banned_ip_list_idx;
DROP INDEX IF EXISTS public.banned_ip_ip_idx;
DROP INDEX IF EXISTS public.authentication_logs_username_idx;
DROP INDEX IF EXISTS public.authentication_logs_remote_ip_idx;
ALTER TABLE IF EXISTS ONLY public.webauthn_users DROP CONSTRAINT IF EXISTS webauthn_users_pkey;
ALTER TABLE IF EXISTS ONLY public.webauthn_credentials DROP CONSTRAINT IF EXISTS webauthn_credentials_pkey;
ALTER TABLE IF EXISTS ONLY public.user_preferences DROP CONSTRAINT IF EXISTS user_preferences_pkey;
ALTER TABLE IF EXISTS ONLY public.user_opaque_identifier DROP CONSTRAINT IF EXISTS user_opaque_identifier_pkey;
ALTER TABLE IF EXISTS ONLY public.totp_history DROP CONSTRAINT IF EXISTS totp_history_pkey;
ALTER TABLE IF EXISTS ONLY public.one_time_code DROP CONSTRAINT IF EXISTS one_time_code_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_refresh_token_session DROP CONSTRAINT IF EXISTS oauth2_refresh_token_session_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_pkce_request_session DROP CONSTRAINT IF EXISTS oauth2_pkce_request_session_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_par_context DROP CONSTRAINT IF EXISTS oauth2_par_context_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_openid_connect_session DROP CONSTRAINT IF EXISTS oauth2_openid_connect_session_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_device_code_session DROP CONSTRAINT IF EXISTS oauth2_device_code_session_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_consent_session DROP CONSTRAINT IF EXISTS oauth2_consent_session_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_consent_preconfiguration DROP CONSTRAINT IF EXISTS oauth2_consent_preconfiguration_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_blacklisted_jti DROP CONSTRAINT IF EXISTS oauth2_blacklisted_jti_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_authorization_code_session DROP CONSTRAINT IF EXISTS oauth2_authorization_code_session_pkey;
ALTER TABLE IF EXISTS ONLY public.oauth2_access_token_session DROP CONSTRAINT IF EXISTS oauth2_access_token_session_pkey;
ALTER TABLE IF EXISTS ONLY public.migrations DROP CONSTRAINT IF EXISTS migrations_pkey;
ALTER TABLE IF EXISTS ONLY public.identity_verification DROP CONSTRAINT IF EXISTS identity_verification_pkey;
ALTER TABLE IF EXISTS ONLY public.encryption DROP CONSTRAINT IF EXISTS encryption_pkey;
ALTER TABLE IF EXISTS ONLY public.duo_devices DROP CONSTRAINT IF EXISTS duo_devices_pkey;
ALTER TABLE IF EXISTS ONLY public.cached_data DROP CONSTRAINT IF EXISTS cached_data_pkey;
ALTER TABLE IF EXISTS ONLY public.banned_user DROP CONSTRAINT IF EXISTS banned_user_pkey;
ALTER TABLE IF EXISTS ONLY public.banned_ip DROP CONSTRAINT IF EXISTS banned_ip_pkey;
ALTER TABLE IF EXISTS ONLY public.authentication_logs DROP CONSTRAINT IF EXISTS authentication_logs_pkey;
ALTER TABLE IF EXISTS public.webauthn_users ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.webauthn_credentials ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.user_preferences ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.user_opaque_identifier ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.totp_history ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.totp_configurations ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.one_time_code ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_refresh_token_session ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_pkce_request_session ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_par_context ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_openid_connect_session ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_device_code_session ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_consent_session ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_consent_preconfiguration ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_blacklisted_jti ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_authorization_code_session ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.oauth2_access_token_session ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.migrations ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.identity_verification ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.encryption ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.duo_devices ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.cached_data ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.banned_user ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.banned_ip ALTER COLUMN id DROP DEFAULT;
ALTER TABLE IF EXISTS public.authentication_logs ALTER COLUMN id DROP DEFAULT;
DROP SEQUENCE IF EXISTS public.webauthn_users_id_seq;
DROP TABLE IF EXISTS public.webauthn_users;
DROP SEQUENCE IF EXISTS public.webauthn_credentials_id_seq;
DROP TABLE IF EXISTS public.webauthn_credentials;
DROP SEQUENCE IF EXISTS public.user_preferences_id_seq;
DROP TABLE IF EXISTS public.user_preferences;
DROP SEQUENCE IF EXISTS public.user_opaque_identifier_id_seq;
DROP TABLE IF EXISTS public.user_opaque_identifier;
DROP SEQUENCE IF EXISTS public.totp_history_id_seq;
DROP TABLE IF EXISTS public.totp_history;
DROP SEQUENCE IF EXISTS public.totp_configurations_id_seq1;
DROP TABLE IF EXISTS public.totp_configurations;
DROP SEQUENCE IF EXISTS public.one_time_code_id_seq;
DROP TABLE IF EXISTS public.one_time_code;
DROP SEQUENCE IF EXISTS public.oauth2_refresh_token_session_id_seq;
DROP TABLE IF EXISTS public.oauth2_refresh_token_session;
DROP SEQUENCE IF EXISTS public.oauth2_pkce_request_session_id_seq;
DROP TABLE IF EXISTS public.oauth2_pkce_request_session;
DROP SEQUENCE IF EXISTS public.oauth2_par_context_id_seq;
DROP TABLE IF EXISTS public.oauth2_par_context;
DROP SEQUENCE IF EXISTS public.oauth2_openid_connect_session_id_seq;
DROP TABLE IF EXISTS public.oauth2_openid_connect_session;
DROP SEQUENCE IF EXISTS public.oauth2_device_code_session_id_seq;
DROP TABLE IF EXISTS public.oauth2_device_code_session;
DROP SEQUENCE IF EXISTS public.oauth2_consent_session_id_seq;
DROP TABLE IF EXISTS public.oauth2_consent_session;
DROP SEQUENCE IF EXISTS public.oauth2_consent_preconfiguration_id_seq;
DROP TABLE IF EXISTS public.oauth2_consent_preconfiguration;
DROP SEQUENCE IF EXISTS public.oauth2_blacklisted_jti_id_seq;
DROP TABLE IF EXISTS public.oauth2_blacklisted_jti;
DROP SEQUENCE IF EXISTS public.oauth2_authorization_code_session_id_seq;
DROP TABLE IF EXISTS public.oauth2_authorization_code_session;
DROP SEQUENCE IF EXISTS public.oauth2_access_token_session_id_seq;
DROP TABLE IF EXISTS public.oauth2_access_token_session;
DROP SEQUENCE IF EXISTS public.migrations_id_seq;
DROP TABLE IF EXISTS public.migrations;
DROP SEQUENCE IF EXISTS public.identity_verification_id_seq;
DROP TABLE IF EXISTS public.identity_verification;
DROP SEQUENCE IF EXISTS public.encryption_id_seq;
DROP TABLE IF EXISTS public.encryption;
DROP SEQUENCE IF EXISTS public.duo_devices_id_seq;
DROP TABLE IF EXISTS public.duo_devices;
DROP SEQUENCE IF EXISTS public.cached_data_id_seq;
DROP TABLE IF EXISTS public.cached_data;
DROP SEQUENCE IF EXISTS public.banned_user_id_seq;
DROP TABLE IF EXISTS public.banned_user;
DROP SEQUENCE IF EXISTS public.banned_ip_id_seq;
DROP TABLE IF EXISTS public.banned_ip;
DROP SEQUENCE IF EXISTS public.authentication_logs_id_seq;
DROP TABLE IF EXISTS public.authentication_logs;
SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: authentication_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.authentication_logs (
    id integer NOT NULL,
    "time" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    successful boolean NOT NULL,
    banned boolean DEFAULT false NOT NULL,
    username character varying(100) NOT NULL,
    auth_type character varying(8) DEFAULT '1FA'::character varying NOT NULL,
    remote_ip character varying(39) DEFAULT NULL::character varying,
    request_uri text,
    request_method character varying(8) DEFAULT ''::character varying NOT NULL
);


--
-- Name: authentication_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.authentication_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: authentication_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.authentication_logs_id_seq OWNED BY public.authentication_logs.id;


--
-- Name: banned_ip; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banned_ip (
    id integer NOT NULL,
    "time" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires timestamp with time zone,
    expired timestamp with time zone,
    revoked boolean DEFAULT false NOT NULL,
    ip character varying(39) NOT NULL,
    source character varying(10) NOT NULL,
    reason character varying(100) DEFAULT NULL::character varying
);


--
-- Name: banned_ip_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.banned_ip_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: banned_ip_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.banned_ip_id_seq OWNED BY public.banned_ip.id;


--
-- Name: banned_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banned_user (
    id integer NOT NULL,
    "time" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires timestamp with time zone,
    expired timestamp with time zone,
    revoked boolean DEFAULT false NOT NULL,
    username character varying(100) NOT NULL,
    source character varying(10) NOT NULL,
    reason character varying(100) DEFAULT NULL::character varying
);


--
-- Name: banned_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.banned_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: banned_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.banned_user_id_seq OWNED BY public.banned_user.id;


--
-- Name: cached_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cached_data (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    name character varying(20) NOT NULL,
    encrypted boolean DEFAULT false NOT NULL,
    value bytea NOT NULL
);


--
-- Name: cached_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cached_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cached_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cached_data_id_seq OWNED BY public.cached_data.id;


--
-- Name: duo_devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.duo_devices (
    id integer NOT NULL,
    username character varying(100) NOT NULL,
    device character varying(32) NOT NULL,
    method character varying(16) NOT NULL
);


--
-- Name: duo_devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.duo_devices_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: duo_devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.duo_devices_id_seq OWNED BY public.duo_devices.id;


--
-- Name: encryption; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.encryption (
    id integer NOT NULL,
    name character varying(100),
    value bytea NOT NULL
);


--
-- Name: encryption_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.encryption_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: encryption_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.encryption_id_seq OWNED BY public.encryption.id;


--
-- Name: identity_verification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_verification (
    id integer NOT NULL,
    jti character(36),
    iat timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    issued_ip character varying(39) NOT NULL,
    exp timestamp with time zone NOT NULL,
    username character varying(100) NOT NULL,
    action character varying(50) NOT NULL,
    consumed timestamp with time zone,
    consumed_ip character varying(39) DEFAULT NULL::character varying,
    revoked timestamp with time zone,
    revoked_ip character varying(39) DEFAULT NULL::character varying
);


--
-- Name: identity_verification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identity_verification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_verification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identity_verification_id_seq OWNED BY public.identity_verification.id;


--
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    applied timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version_before integer,
    version_after integer NOT NULL,
    application_version character varying(128) NOT NULL
);


--
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- Name: oauth2_access_token_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_access_token_session (
    id integer NOT NULL,
    challenge_id character(36) DEFAULT NULL::bpchar,
    request_id character varying(40) NOT NULL,
    client_id character varying(255) NOT NULL,
    signature character varying(768) NOT NULL,
    subject character(36) DEFAULT NULL::bpchar,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    requested_scopes text NOT NULL,
    granted_scopes text NOT NULL,
    requested_audience text DEFAULT ''::text,
    granted_audience text DEFAULT ''::text,
    active boolean DEFAULT false NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    form_data text NOT NULL,
    session_data bytea NOT NULL
);


--
-- Name: oauth2_access_token_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_access_token_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_access_token_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_access_token_session_id_seq OWNED BY public.oauth2_access_token_session.id;


--
-- Name: oauth2_authorization_code_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_authorization_code_session (
    id integer NOT NULL,
    challenge_id character(36) NOT NULL,
    request_id character varying(40) NOT NULL,
    client_id character varying(255) NOT NULL,
    signature character varying(255) NOT NULL,
    subject character(36) NOT NULL,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    requested_scopes text NOT NULL,
    granted_scopes text NOT NULL,
    requested_audience text DEFAULT ''::text,
    granted_audience text DEFAULT ''::text,
    active boolean DEFAULT false NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    form_data text NOT NULL,
    session_data bytea NOT NULL
);


--
-- Name: oauth2_authorization_code_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_authorization_code_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_authorization_code_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_authorization_code_session_id_seq OWNED BY public.oauth2_authorization_code_session.id;


--
-- Name: oauth2_blacklisted_jti; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_blacklisted_jti (
    id integer NOT NULL,
    signature character varying(64) NOT NULL,
    expires_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: oauth2_blacklisted_jti_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_blacklisted_jti_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_blacklisted_jti_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_blacklisted_jti_id_seq OWNED BY public.oauth2_blacklisted_jti.id;


--
-- Name: oauth2_consent_preconfiguration; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_consent_preconfiguration (
    id integer NOT NULL,
    client_id character varying(255) NOT NULL,
    subject character(36) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at timestamp with time zone,
    revoked boolean DEFAULT false NOT NULL,
    scopes text NOT NULL,
    audience text,
    requested_claims text,
    signature_claims character(64),
    granted_claims text DEFAULT ''::text
);


--
-- Name: oauth2_consent_preconfiguration_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_consent_preconfiguration_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_consent_preconfiguration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_consent_preconfiguration_id_seq OWNED BY public.oauth2_consent_preconfiguration.id;


--
-- Name: oauth2_consent_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_consent_session (
    id integer NOT NULL,
    challenge_id character(36) NOT NULL,
    client_id character varying(255) NOT NULL,
    subject character(36) DEFAULT NULL::bpchar,
    authorized boolean DEFAULT false NOT NULL,
    granted boolean DEFAULT false NOT NULL,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    responded_at timestamp with time zone,
    form_data text NOT NULL,
    requested_scopes text NOT NULL,
    granted_scopes text NOT NULL,
    requested_audience text,
    granted_audience text,
    preconfiguration integer,
    granted_claims text,
    expires_at timestamp with time zone DEFAULT '2000-01-01 00:00:00+00'::timestamp with time zone NOT NULL
);


--
-- Name: oauth2_consent_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_consent_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_consent_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_consent_session_id_seq OWNED BY public.oauth2_consent_session.id;


--
-- Name: oauth2_device_code_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_device_code_session (
    id integer NOT NULL,
    challenge_id character(36) DEFAULT NULL::bpchar,
    request_id character varying(40) NOT NULL,
    client_id character varying(255) NOT NULL,
    signature character varying(255) NOT NULL,
    user_code_signature character varying(255) NOT NULL,
    status integer NOT NULL,
    subject character(36) DEFAULT NULL::bpchar,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    checked_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    requested_scopes text NOT NULL,
    granted_scopes text NOT NULL,
    requested_audience text DEFAULT ''::text,
    granted_audience text DEFAULT ''::text,
    active boolean DEFAULT false NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    form_data text NOT NULL,
    session_data bytea NOT NULL
);


--
-- Name: oauth2_device_code_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_device_code_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_device_code_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_device_code_session_id_seq OWNED BY public.oauth2_device_code_session.id;


--
-- Name: oauth2_openid_connect_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_openid_connect_session (
    id integer NOT NULL,
    challenge_id character(36) NOT NULL,
    request_id character varying(40) NOT NULL,
    client_id character varying(255) NOT NULL,
    signature character varying(255) NOT NULL,
    subject character(36) NOT NULL,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    requested_scopes text NOT NULL,
    granted_scopes text NOT NULL,
    requested_audience text DEFAULT ''::text,
    granted_audience text DEFAULT ''::text,
    active boolean DEFAULT false NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    form_data text NOT NULL,
    session_data bytea NOT NULL
);


--
-- Name: oauth2_openid_connect_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_openid_connect_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_openid_connect_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_openid_connect_session_id_seq OWNED BY public.oauth2_openid_connect_session.id;


--
-- Name: oauth2_par_context; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_par_context (
    id integer NOT NULL,
    request_id character varying(40) NOT NULL,
    client_id character varying(255) NOT NULL,
    signature character varying(255) NOT NULL,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    scopes text NOT NULL,
    audience text DEFAULT ''::text,
    handled_response_types text DEFAULT ''::text NOT NULL,
    response_mode text DEFAULT ''::text NOT NULL,
    response_mode_default text DEFAULT ''::text NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    form_data text NOT NULL,
    session_data bytea NOT NULL
);


--
-- Name: oauth2_par_context_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_par_context_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_par_context_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_par_context_id_seq OWNED BY public.oauth2_par_context.id;


--
-- Name: oauth2_pkce_request_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_pkce_request_session (
    id integer NOT NULL,
    challenge_id character(36) NOT NULL,
    request_id character varying(40) NOT NULL,
    client_id character varying(255) NOT NULL,
    signature character varying(255) NOT NULL,
    subject character(36) NOT NULL,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    requested_scopes text NOT NULL,
    granted_scopes text NOT NULL,
    requested_audience text DEFAULT ''::text,
    granted_audience text DEFAULT ''::text,
    active boolean DEFAULT false NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    form_data text NOT NULL,
    session_data bytea NOT NULL
);


--
-- Name: oauth2_pkce_request_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_pkce_request_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_pkce_request_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_pkce_request_session_id_seq OWNED BY public.oauth2_pkce_request_session.id;


--
-- Name: oauth2_refresh_token_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth2_refresh_token_session (
    id integer NOT NULL,
    challenge_id character(36) NOT NULL,
    request_id character varying(40) NOT NULL,
    client_id character varying(255) NOT NULL,
    signature character varying(255) NOT NULL,
    subject character(36) NOT NULL,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    requested_scopes text NOT NULL,
    granted_scopes text NOT NULL,
    requested_audience text DEFAULT ''::text,
    granted_audience text DEFAULT ''::text,
    active boolean DEFAULT false NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    form_data text NOT NULL,
    session_data bytea NOT NULL
);


--
-- Name: oauth2_refresh_token_session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth2_refresh_token_session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth2_refresh_token_session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth2_refresh_token_session_id_seq OWNED BY public.oauth2_refresh_token_session.id;


--
-- Name: one_time_code; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.one_time_code (
    id integer NOT NULL,
    public_id character(36) NOT NULL,
    signature character varying(128) NOT NULL,
    issued timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    issued_ip character varying(39) NOT NULL,
    expires timestamp with time zone NOT NULL,
    username character varying(100) NOT NULL,
    intent character varying(100) NOT NULL,
    consumed timestamp with time zone,
    consumed_ip character varying(39) DEFAULT NULL::character varying,
    revoked timestamp with time zone,
    revoked_ip character varying(39) DEFAULT NULL::character varying,
    code bytea NOT NULL
);


--
-- Name: one_time_code_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.one_time_code_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: one_time_code_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.one_time_code_id_seq OWNED BY public.one_time_code.id;


--
-- Name: totp_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.totp_configurations (
    id integer CONSTRAINT totp_configurations_id_not_null1 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_used_at timestamp with time zone,
    username character varying(100) CONSTRAINT totp_configurations_username_not_null1 NOT NULL,
    issuer character varying(100),
    algorithm character varying(6) DEFAULT 'SHA1'::character varying CONSTRAINT totp_configurations_algorithm_not_null1 NOT NULL,
    digits integer DEFAULT 6 CONSTRAINT totp_configurations_digits_not_null1 NOT NULL,
    period integer DEFAULT 30 CONSTRAINT totp_configurations_period_not_null1 NOT NULL,
    secret bytea CONSTRAINT totp_configurations_secret_not_null1 NOT NULL
);


--
-- Name: totp_configurations_id_seq1; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.totp_configurations_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: totp_configurations_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.totp_configurations_id_seq1 OWNED BY public.totp_configurations.id;


--
-- Name: totp_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.totp_history (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    username character varying(100) NOT NULL,
    step character(64) NOT NULL
);


--
-- Name: totp_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.totp_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: totp_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.totp_history_id_seq OWNED BY public.totp_history.id;


--
-- Name: user_opaque_identifier; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_opaque_identifier (
    id integer NOT NULL,
    service character varying(20) NOT NULL,
    sector_id character varying(255) NOT NULL,
    username character varying(100) NOT NULL,
    identifier character(36) NOT NULL
);


--
-- Name: user_opaque_identifier_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_opaque_identifier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_opaque_identifier_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_opaque_identifier_id_seq OWNED BY public.user_opaque_identifier.id;


--
-- Name: user_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_preferences (
    id integer NOT NULL,
    username character varying(100) NOT NULL,
    second_factor_method character varying(11) NOT NULL
);


--
-- Name: user_preferences_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_preferences_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_preferences_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_preferences_id_seq OWNED BY public.user_preferences.id;


--
-- Name: webauthn_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webauthn_credentials (
    id integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_used_at timestamp with time zone,
    rpid character varying(512) NOT NULL,
    username character varying(100) NOT NULL,
    description character varying(64) NOT NULL,
    kid character varying(512) NOT NULL,
    aaguid character(36),
    attestation_type character varying(32),
    attachment character varying(64) NOT NULL,
    transport character varying(64) DEFAULT ''::character varying,
    sign_count integer DEFAULT 0,
    clone_warning boolean DEFAULT false NOT NULL,
    legacy boolean DEFAULT false NOT NULL,
    discoverable boolean NOT NULL,
    present boolean DEFAULT false NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    backup_eligible boolean DEFAULT false NOT NULL,
    backup_state boolean DEFAULT false NOT NULL,
    public_key bytea NOT NULL,
    attestation bytea
);


--
-- Name: webauthn_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webauthn_credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webauthn_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webauthn_credentials_id_seq OWNED BY public.webauthn_credentials.id;


--
-- Name: webauthn_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webauthn_users (
    id integer NOT NULL,
    rpid character varying(512) NOT NULL,
    username character varying(100) NOT NULL,
    userid character(64) NOT NULL
);


--
-- Name: webauthn_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webauthn_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webauthn_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webauthn_users_id_seq OWNED BY public.webauthn_users.id;


--
-- Name: authentication_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authentication_logs ALTER COLUMN id SET DEFAULT nextval('public.authentication_logs_id_seq'::regclass);


--
-- Name: banned_ip id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banned_ip ALTER COLUMN id SET DEFAULT nextval('public.banned_ip_id_seq'::regclass);


--
-- Name: banned_user id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banned_user ALTER COLUMN id SET DEFAULT nextval('public.banned_user_id_seq'::regclass);


--
-- Name: cached_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cached_data ALTER COLUMN id SET DEFAULT nextval('public.cached_data_id_seq'::regclass);


--
-- Name: duo_devices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duo_devices ALTER COLUMN id SET DEFAULT nextval('public.duo_devices_id_seq'::regclass);


--
-- Name: encryption id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.encryption ALTER COLUMN id SET DEFAULT nextval('public.encryption_id_seq'::regclass);


--
-- Name: identity_verification id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_verification ALTER COLUMN id SET DEFAULT nextval('public.identity_verification_id_seq'::regclass);


--
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- Name: oauth2_access_token_session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_access_token_session ALTER COLUMN id SET DEFAULT nextval('public.oauth2_access_token_session_id_seq'::regclass);


--
-- Name: oauth2_authorization_code_session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_authorization_code_session ALTER COLUMN id SET DEFAULT nextval('public.oauth2_authorization_code_session_id_seq'::regclass);


--
-- Name: oauth2_blacklisted_jti id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_blacklisted_jti ALTER COLUMN id SET DEFAULT nextval('public.oauth2_blacklisted_jti_id_seq'::regclass);


--
-- Name: oauth2_consent_preconfiguration id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_consent_preconfiguration ALTER COLUMN id SET DEFAULT nextval('public.oauth2_consent_preconfiguration_id_seq'::regclass);


--
-- Name: oauth2_consent_session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_consent_session ALTER COLUMN id SET DEFAULT nextval('public.oauth2_consent_session_id_seq'::regclass);


--
-- Name: oauth2_device_code_session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_device_code_session ALTER COLUMN id SET DEFAULT nextval('public.oauth2_device_code_session_id_seq'::regclass);


--
-- Name: oauth2_openid_connect_session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_openid_connect_session ALTER COLUMN id SET DEFAULT nextval('public.oauth2_openid_connect_session_id_seq'::regclass);


--
-- Name: oauth2_par_context id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_par_context ALTER COLUMN id SET DEFAULT nextval('public.oauth2_par_context_id_seq'::regclass);


--
-- Name: oauth2_pkce_request_session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_pkce_request_session ALTER COLUMN id SET DEFAULT nextval('public.oauth2_pkce_request_session_id_seq'::regclass);


--
-- Name: oauth2_refresh_token_session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_refresh_token_session ALTER COLUMN id SET DEFAULT nextval('public.oauth2_refresh_token_session_id_seq'::regclass);


--
-- Name: one_time_code id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.one_time_code ALTER COLUMN id SET DEFAULT nextval('public.one_time_code_id_seq'::regclass);


--
-- Name: totp_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.totp_configurations ALTER COLUMN id SET DEFAULT nextval('public.totp_configurations_id_seq1'::regclass);


--
-- Name: totp_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.totp_history ALTER COLUMN id SET DEFAULT nextval('public.totp_history_id_seq'::regclass);


--
-- Name: user_opaque_identifier id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_opaque_identifier ALTER COLUMN id SET DEFAULT nextval('public.user_opaque_identifier_id_seq'::regclass);


--
-- Name: user_preferences id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences ALTER COLUMN id SET DEFAULT nextval('public.user_preferences_id_seq'::regclass);


--
-- Name: webauthn_credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webauthn_credentials ALTER COLUMN id SET DEFAULT nextval('public.webauthn_credentials_id_seq'::regclass);


--
-- Name: webauthn_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webauthn_users ALTER COLUMN id SET DEFAULT nextval('public.webauthn_users_id_seq'::regclass);


--
-- Data for Name: authentication_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.authentication_logs (id, "time", successful, banned, username, auth_type, remote_ip, request_uri, request_method) FROM stdin;
1	2026-03-27 20:29:57.971938+00	t	f	rich	1FA	50.47.197.121		
2	2026-03-27 23:10:33.809958+00	t	f	rich	1FA	50.47.197.121		
3	2026-03-27 23:47:04.837565+00	t	f	rich	1FA	50.47.197.121	https://radarr.myrobertson.com/	GET
4	2026-03-28 00:13:34.811204+00	t	f	rich	1FA	2600:100f:b076:65bc:0:2d:a311:2801	https://radarr.myrobertson.com/	GET
5	2026-03-28 00:27:04.041985+00	t	f	rich	1FA	2600:100f:b076:65bc:0:2d:a311:2801	https://radarr.myrobertson.com/	GET
6	2026-03-28 01:03:44.517289+00	t	f	rich	1FA	50.47.197.121	https://radarr.myrobertson.com/	GET
7	2026-03-28 05:11:44.422902+00	t	f	rich	1FA	50.47.197.121	https://radarr.myrobertson.com/	GET
8	2026-03-28 14:31:33.950783+00	t	f	rich	1FA	50.47.197.121	https://radarr.myrobertson.com/	GET
9	2026-03-28 22:18:40.180535+00	t	f	rich	1FA	50.47.197.121	https://sonarr.myrobertson.com/add/new	GET
10	2026-03-30 01:29:14.845892+00	t	f	rich	1FA	50.47.197.121	https://sonarr.myrobertson.com/	GET
\.


--
-- Data for Name: banned_ip; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.banned_ip (id, "time", expires, expired, revoked, ip, source, reason) FROM stdin;
\.


--
-- Data for Name: banned_user; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.banned_user (id, "time", expires, expired, revoked, username, source, reason) FROM stdin;
\.


--
-- Data for Name: cached_data; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cached_data (id, created_at, updated_at, name, encrypted, value) FROM stdin;
\.


--
-- Data for Name: duo_devices; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.duo_devices (id, username, device, method) FROM stdin;
\.


--
-- Data for Name: encryption; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.encryption (id, name, value) FROM stdin;
1	check	\\x55687e73fbadbd03e5e3824ef8f3d25d0c8ecb9ad5286c1322e4d96ffa46d795093e6e797524c1232856a50a386e17b96523f6e87f3f97a04b029175c5925804
2	hmac_key_otc	\\x83326cbba67939f04aaefa80307306490e793b34abf5761893d562e3e024012d209fba3e76bd0b78618097c65d02a8250978e906cbfc1f7490ebddb50ac215b238d1bbc6f2bfebdd559451a2a12dee1079c4ec238a2bd8b1b0db4ae6469566604b8e8ed0af7d0200f1e496c9e19ab3fe7a5b97ac0392516cc454892311a9208f437a01a1762eb110b050d818e385aaa8dc89594104e84f1134d288d1
3	hmac_key_otp	\\xb82f1be0e21e48bd60e04663a9b59aef0f07879dbf3c82ce5d47cc5a120f730d265dc34846b220b5cec6cee04786f6ecbb85f5d92af4bdd5595f8adfc0c598cf895b3ed1a35ca4517c8a125e05fce57bc4c4da26d6fc5f2ca783234b
\.


--
-- Data for Name: identity_verification; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.identity_verification (id, jti, iat, issued_ip, exp, username, action, consumed, consumed_ip, revoked, revoked_ip) FROM stdin;
\.


--
-- Data for Name: migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.migrations (id, applied, version_before, version_after, application_version) FROM stdin;
1	2026-03-27 19:53:45.029748+00	0	1	v4.39.13
2	2026-03-27 19:53:45.055978+00	1	2	v4.39.13
3	2026-03-27 19:53:45.058734+00	2	3	v4.39.13
4	2026-03-27 19:53:45.088704+00	3	4	v4.39.13
5	2026-03-27 19:53:45.089804+00	4	5	v4.39.13
6	2026-03-27 19:53:45.108003+00	5	6	v4.39.13
7	2026-03-27 19:53:45.11636+00	6	7	v4.39.13
8	2026-03-27 19:53:45.11792+00	7	8	v4.39.13
9	2026-03-27 19:53:45.118446+00	8	9	v4.39.13
10	2026-03-27 19:53:45.119237+00	9	10	v4.39.13
11	2026-03-27 19:53:45.119757+00	10	11	v4.39.13
12	2026-03-27 19:53:45.123481+00	11	12	v4.39.13
13	2026-03-27 19:53:45.125094+00	12	13	v4.39.13
14	2026-03-27 19:53:45.125743+00	13	14	v4.39.13
15	2026-03-27 19:53:45.126918+00	14	15	v4.39.13
16	2026-03-27 19:53:45.127544+00	15	16	v4.39.13
17	2026-03-27 19:53:45.128312+00	16	17	v4.39.13
18	2026-03-27 19:53:45.130959+00	17	18	v4.39.13
19	2026-03-27 19:53:45.132472+00	18	19	v4.39.13
20	2026-03-27 19:53:45.135716+00	19	20	v4.39.13
21	2026-03-27 19:53:45.135927+00	20	21	v4.39.13
22	2026-03-27 19:53:45.136456+00	21	22	v4.39.13
23	2026-03-27 19:53:45.137289+00	22	23	v4.39.13
\.


--
-- Data for Name: oauth2_access_token_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_access_token_session (id, challenge_id, request_id, client_id, signature, subject, requested_at, requested_scopes, granted_scopes, requested_audience, granted_audience, active, revoked, form_data, session_data) FROM stdin;
\.


--
-- Data for Name: oauth2_authorization_code_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_authorization_code_session (id, challenge_id, request_id, client_id, signature, subject, requested_at, requested_scopes, granted_scopes, requested_audience, granted_audience, active, revoked, form_data, session_data) FROM stdin;
\.


--
-- Data for Name: oauth2_blacklisted_jti; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_blacklisted_jti (id, signature, expires_at) FROM stdin;
\.


--
-- Data for Name: oauth2_consent_preconfiguration; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_consent_preconfiguration (id, client_id, subject, created_at, expires_at, revoked, scopes, audience, requested_claims, signature_claims, granted_claims) FROM stdin;
\.


--
-- Data for Name: oauth2_consent_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_consent_session (id, challenge_id, client_id, subject, authorized, granted, requested_at, responded_at, form_data, requested_scopes, granted_scopes, requested_audience, granted_audience, preconfiguration, granted_claims, expires_at) FROM stdin;
\.


--
-- Data for Name: oauth2_device_code_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_device_code_session (id, challenge_id, request_id, client_id, signature, user_code_signature, status, subject, requested_at, checked_at, requested_scopes, granted_scopes, requested_audience, granted_audience, active, revoked, form_data, session_data) FROM stdin;
\.


--
-- Data for Name: oauth2_openid_connect_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_openid_connect_session (id, challenge_id, request_id, client_id, signature, subject, requested_at, requested_scopes, granted_scopes, requested_audience, granted_audience, active, revoked, form_data, session_data) FROM stdin;
\.


--
-- Data for Name: oauth2_par_context; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_par_context (id, request_id, client_id, signature, requested_at, scopes, audience, handled_response_types, response_mode, response_mode_default, revoked, form_data, session_data) FROM stdin;
\.


--
-- Data for Name: oauth2_pkce_request_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_pkce_request_session (id, challenge_id, request_id, client_id, signature, subject, requested_at, requested_scopes, granted_scopes, requested_audience, granted_audience, active, revoked, form_data, session_data) FROM stdin;
\.


--
-- Data for Name: oauth2_refresh_token_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.oauth2_refresh_token_session (id, challenge_id, request_id, client_id, signature, subject, requested_at, requested_scopes, granted_scopes, requested_audience, granted_audience, active, revoked, form_data, session_data) FROM stdin;
\.


--
-- Data for Name: one_time_code; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.one_time_code (id, public_id, signature, issued, issued_ip, expires, username, intent, consumed, consumed_ip, revoked, revoked_ip, code) FROM stdin;
\.


--
-- Data for Name: totp_configurations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.totp_configurations (id, created_at, last_used_at, username, issuer, algorithm, digits, period, secret) FROM stdin;
\.


--
-- Data for Name: totp_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.totp_history (id, created_at, username, step) FROM stdin;
\.


--
-- Data for Name: user_opaque_identifier; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_opaque_identifier (id, service, sector_id, username, identifier) FROM stdin;
\.


--
-- Data for Name: user_preferences; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_preferences (id, username, second_factor_method) FROM stdin;
1	rich	totp
\.


--
-- Data for Name: webauthn_credentials; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.webauthn_credentials (id, created_at, last_used_at, rpid, username, description, kid, aaguid, attestation_type, attachment, transport, sign_count, clone_warning, legacy, discoverable, present, verified, backup_eligible, backup_state, public_key, attestation) FROM stdin;
\.


--
-- Data for Name: webauthn_users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.webauthn_users (id, rpid, username, userid) FROM stdin;
\.


--
-- Name: authentication_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.authentication_logs_id_seq', 10, true);


--
-- Name: banned_ip_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.banned_ip_id_seq', 1, false);


--
-- Name: banned_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.banned_user_id_seq', 1, false);


--
-- Name: cached_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cached_data_id_seq', 1, false);


--
-- Name: duo_devices_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.duo_devices_id_seq', 1, false);


--
-- Name: encryption_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.encryption_id_seq', 3, true);


--
-- Name: identity_verification_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.identity_verification_id_seq', 1, false);


--
-- Name: migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.migrations_id_seq', 23, true);


--
-- Name: oauth2_access_token_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_access_token_session_id_seq', 1, false);


--
-- Name: oauth2_authorization_code_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_authorization_code_session_id_seq', 1, false);


--
-- Name: oauth2_blacklisted_jti_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_blacklisted_jti_id_seq', 1, false);


--
-- Name: oauth2_consent_preconfiguration_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_consent_preconfiguration_id_seq', 1, false);


--
-- Name: oauth2_consent_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_consent_session_id_seq', 1, false);


--
-- Name: oauth2_device_code_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_device_code_session_id_seq', 1, false);


--
-- Name: oauth2_openid_connect_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_openid_connect_session_id_seq', 1, false);


--
-- Name: oauth2_par_context_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_par_context_id_seq', 1, false);


--
-- Name: oauth2_pkce_request_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_pkce_request_session_id_seq', 1, false);


--
-- Name: oauth2_refresh_token_session_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.oauth2_refresh_token_session_id_seq', 1, false);


--
-- Name: one_time_code_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.one_time_code_id_seq', 1, false);


--
-- Name: totp_configurations_id_seq1; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.totp_configurations_id_seq1', 1, false);


--
-- Name: totp_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.totp_history_id_seq', 1, false);


--
-- Name: user_opaque_identifier_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_opaque_identifier_id_seq', 1, false);


--
-- Name: user_preferences_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_preferences_id_seq', 2, true);


--
-- Name: webauthn_credentials_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.webauthn_credentials_id_seq', 1, false);


--
-- Name: webauthn_users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.webauthn_users_id_seq', 1, false);


--
-- Name: authentication_logs authentication_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authentication_logs
    ADD CONSTRAINT authentication_logs_pkey PRIMARY KEY (id);


--
-- Name: banned_ip banned_ip_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banned_ip
    ADD CONSTRAINT banned_ip_pkey PRIMARY KEY (id);


--
-- Name: banned_user banned_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banned_user
    ADD CONSTRAINT banned_user_pkey PRIMARY KEY (id);


--
-- Name: cached_data cached_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cached_data
    ADD CONSTRAINT cached_data_pkey PRIMARY KEY (id);


--
-- Name: duo_devices duo_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duo_devices
    ADD CONSTRAINT duo_devices_pkey PRIMARY KEY (id);


--
-- Name: encryption encryption_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.encryption
    ADD CONSTRAINT encryption_pkey PRIMARY KEY (id);


--
-- Name: identity_verification identity_verification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_verification
    ADD CONSTRAINT identity_verification_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: oauth2_access_token_session oauth2_access_token_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_access_token_session
    ADD CONSTRAINT oauth2_access_token_session_pkey PRIMARY KEY (id);


--
-- Name: oauth2_authorization_code_session oauth2_authorization_code_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_authorization_code_session
    ADD CONSTRAINT oauth2_authorization_code_session_pkey PRIMARY KEY (id);


--
-- Name: oauth2_blacklisted_jti oauth2_blacklisted_jti_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_blacklisted_jti
    ADD CONSTRAINT oauth2_blacklisted_jti_pkey PRIMARY KEY (id);


--
-- Name: oauth2_consent_preconfiguration oauth2_consent_preconfiguration_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_consent_preconfiguration
    ADD CONSTRAINT oauth2_consent_preconfiguration_pkey PRIMARY KEY (id);


--
-- Name: oauth2_consent_session oauth2_consent_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_consent_session
    ADD CONSTRAINT oauth2_consent_session_pkey PRIMARY KEY (id);


--
-- Name: oauth2_device_code_session oauth2_device_code_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_device_code_session
    ADD CONSTRAINT oauth2_device_code_session_pkey PRIMARY KEY (id);


--
-- Name: oauth2_openid_connect_session oauth2_openid_connect_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_openid_connect_session
    ADD CONSTRAINT oauth2_openid_connect_session_pkey PRIMARY KEY (id);


--
-- Name: oauth2_par_context oauth2_par_context_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_par_context
    ADD CONSTRAINT oauth2_par_context_pkey PRIMARY KEY (id);


--
-- Name: oauth2_pkce_request_session oauth2_pkce_request_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_pkce_request_session
    ADD CONSTRAINT oauth2_pkce_request_session_pkey PRIMARY KEY (id);


--
-- Name: oauth2_refresh_token_session oauth2_refresh_token_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_refresh_token_session
    ADD CONSTRAINT oauth2_refresh_token_session_pkey PRIMARY KEY (id);


--
-- Name: one_time_code one_time_code_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.one_time_code
    ADD CONSTRAINT one_time_code_pkey PRIMARY KEY (id);


--
-- Name: totp_history totp_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.totp_history
    ADD CONSTRAINT totp_history_pkey PRIMARY KEY (id);


--
-- Name: user_opaque_identifier user_opaque_identifier_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_opaque_identifier
    ADD CONSTRAINT user_opaque_identifier_pkey PRIMARY KEY (id);


--
-- Name: user_preferences user_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences
    ADD CONSTRAINT user_preferences_pkey PRIMARY KEY (id);


--
-- Name: webauthn_credentials webauthn_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_pkey PRIMARY KEY (id);


--
-- Name: webauthn_users webauthn_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webauthn_users
    ADD CONSTRAINT webauthn_users_pkey PRIMARY KEY (id);


--
-- Name: authentication_logs_remote_ip_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX authentication_logs_remote_ip_idx ON public.authentication_logs USING btree ("time", remote_ip, auth_type);


--
-- Name: authentication_logs_username_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX authentication_logs_username_idx ON public.authentication_logs USING btree ("time", username, auth_type);


--
-- Name: banned_ip_ip_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX banned_ip_ip_idx ON public.banned_ip USING btree (ip);


--
-- Name: banned_ip_list_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX banned_ip_list_idx ON public.banned_ip USING btree (revoked, expires, expired);


--
-- Name: banned_ip_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX banned_ip_lookup_idx ON public.banned_ip USING btree (ip, revoked, expires, expired);


--
-- Name: banned_user_list_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX banned_user_list_idx ON public.banned_user USING btree (revoked, expires, expired);


--
-- Name: banned_user_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX banned_user_lookup_idx ON public.banned_user USING btree (username, revoked, expires, expired);


--
-- Name: banned_user_username_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX banned_user_username_idx ON public.banned_user USING btree (username);


--
-- Name: cached_data_name_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cached_data_name_key ON public.cached_data USING btree (name);


--
-- Name: duo_devices_username_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX duo_devices_username_key ON public.duo_devices USING btree (username);


--
-- Name: encryption_name_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX encryption_name_key ON public.encryption USING btree (name);


--
-- Name: identity_verification_jti_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX identity_verification_jti_key ON public.identity_verification USING btree (jti);


--
-- Name: oauth2_access_token_session_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_access_token_session_client_id_idx ON public.oauth2_access_token_session USING btree (client_id);


--
-- Name: oauth2_access_token_session_client_id_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_access_token_session_client_id_subject_idx ON public.oauth2_access_token_session USING btree (client_id, subject);


--
-- Name: oauth2_access_token_session_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_access_token_session_request_id_idx ON public.oauth2_access_token_session USING btree (request_id);


--
-- Name: oauth2_authorization_code_session_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_authorization_code_session_client_id_idx ON public.oauth2_authorization_code_session USING btree (client_id);


--
-- Name: oauth2_authorization_code_session_client_id_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_authorization_code_session_client_id_subject_idx ON public.oauth2_authorization_code_session USING btree (client_id, subject);


--
-- Name: oauth2_authorization_code_session_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_authorization_code_session_request_id_idx ON public.oauth2_authorization_code_session USING btree (request_id);


--
-- Name: oauth2_blacklisted_jti_signature_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX oauth2_blacklisted_jti_signature_key ON public.oauth2_blacklisted_jti USING btree (signature);


--
-- Name: oauth2_consent_session_challenge_id_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX oauth2_consent_session_challenge_id_key ON public.oauth2_consent_session USING btree (challenge_id);


--
-- Name: oauth2_device_code_session_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_device_code_session_client_id_idx ON public.oauth2_device_code_session USING btree (client_id);


--
-- Name: oauth2_device_code_session_client_id_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_device_code_session_client_id_subject_idx ON public.oauth2_device_code_session USING btree (client_id, subject);


--
-- Name: oauth2_device_code_session_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_device_code_session_request_id_idx ON public.oauth2_device_code_session USING btree (request_id);


--
-- Name: oauth2_openid_connect_session_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_openid_connect_session_client_id_idx ON public.oauth2_openid_connect_session USING btree (client_id);


--
-- Name: oauth2_openid_connect_session_client_id_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_openid_connect_session_client_id_subject_idx ON public.oauth2_openid_connect_session USING btree (client_id, subject);


--
-- Name: oauth2_openid_connect_session_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_openid_connect_session_request_id_idx ON public.oauth2_openid_connect_session USING btree (request_id);


--
-- Name: oauth2_par_context_signature_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX oauth2_par_context_signature_key ON public.oauth2_par_context USING btree (signature);


--
-- Name: oauth2_pkce_request_session_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_pkce_request_session_client_id_idx ON public.oauth2_pkce_request_session USING btree (client_id);


--
-- Name: oauth2_pkce_request_session_client_id_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_pkce_request_session_client_id_subject_idx ON public.oauth2_pkce_request_session USING btree (client_id, subject);


--
-- Name: oauth2_pkce_request_session_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_pkce_request_session_request_id_idx ON public.oauth2_pkce_request_session USING btree (request_id);


--
-- Name: oauth2_refresh_token_session_client_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_refresh_token_session_client_id_idx ON public.oauth2_refresh_token_session USING btree (client_id);


--
-- Name: oauth2_refresh_token_session_client_id_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_refresh_token_session_client_id_subject_idx ON public.oauth2_refresh_token_session USING btree (client_id, subject);


--
-- Name: oauth2_refresh_token_session_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oauth2_refresh_token_session_request_id_idx ON public.oauth2_refresh_token_session USING btree (request_id);


--
-- Name: one_time_code_lookup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_time_code_lookup_key ON public.one_time_code USING btree (signature, username);


--
-- Name: totp_configurations_username_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX totp_configurations_username_key ON public.totp_configurations USING btree (username);


--
-- Name: totp_history_lookup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX totp_history_lookup_key ON public.totp_history USING btree (username, step);


--
-- Name: user_opaque_identifier_identifier_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_opaque_identifier_identifier_key ON public.user_opaque_identifier USING btree (identifier);


--
-- Name: user_opaque_identifier_service_sector_id_username_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_opaque_identifier_service_sector_id_username_key ON public.user_opaque_identifier USING btree (service, sector_id, username);


--
-- Name: user_preferences_username_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_preferences_username_key ON public.user_preferences USING btree (username);


--
-- Name: webauthn_credentials_kid_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX webauthn_credentials_kid_key ON public.webauthn_credentials USING btree (kid);


--
-- Name: webauthn_credentials_lookup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX webauthn_credentials_lookup_key ON public.webauthn_credentials USING btree (rpid, username, description);


--
-- Name: webauthn_users_lookup_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX webauthn_users_lookup_key ON public.webauthn_users USING btree (rpid, username);


--
-- Name: oauth2_access_token_session oauth2_access_token_session_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_access_token_session
    ADD CONSTRAINT oauth2_access_token_session_challenge_id_fkey FOREIGN KEY (challenge_id) REFERENCES public.oauth2_consent_session(challenge_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: oauth2_access_token_session oauth2_access_token_session_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_access_token_session
    ADD CONSTRAINT oauth2_access_token_session_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: oauth2_authorization_code_session oauth2_authorization_code_session_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_authorization_code_session
    ADD CONSTRAINT oauth2_authorization_code_session_challenge_id_fkey FOREIGN KEY (challenge_id) REFERENCES public.oauth2_consent_session(challenge_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: oauth2_authorization_code_session oauth2_authorization_code_session_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_authorization_code_session
    ADD CONSTRAINT oauth2_authorization_code_session_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: oauth2_consent_preconfiguration oauth2_consent_preconfiguration_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_consent_preconfiguration
    ADD CONSTRAINT oauth2_consent_preconfiguration_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: oauth2_consent_session oauth2_consent_session_preconfiguration_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_consent_session
    ADD CONSTRAINT oauth2_consent_session_preconfiguration_fkey FOREIGN KEY (preconfiguration) REFERENCES public.oauth2_consent_preconfiguration(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: oauth2_consent_session oauth2_consent_session_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_consent_session
    ADD CONSTRAINT oauth2_consent_session_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: oauth2_device_code_session oauth2_device_code_session_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_device_code_session
    ADD CONSTRAINT oauth2_device_code_session_challenge_id_fkey FOREIGN KEY (challenge_id) REFERENCES public.oauth2_consent_session(challenge_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: oauth2_device_code_session oauth2_device_code_session_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_device_code_session
    ADD CONSTRAINT oauth2_device_code_session_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: oauth2_openid_connect_session oauth2_openid_connect_session_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_openid_connect_session
    ADD CONSTRAINT oauth2_openid_connect_session_challenge_id_fkey FOREIGN KEY (challenge_id) REFERENCES public.oauth2_consent_session(challenge_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: oauth2_openid_connect_session oauth2_openid_connect_session_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_openid_connect_session
    ADD CONSTRAINT oauth2_openid_connect_session_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: oauth2_pkce_request_session oauth2_pkce_request_session_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_pkce_request_session
    ADD CONSTRAINT oauth2_pkce_request_session_challenge_id_fkey FOREIGN KEY (challenge_id) REFERENCES public.oauth2_consent_session(challenge_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: oauth2_pkce_request_session oauth2_pkce_request_session_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_pkce_request_session
    ADD CONSTRAINT oauth2_pkce_request_session_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: oauth2_refresh_token_session oauth2_refresh_token_session_challenge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_refresh_token_session
    ADD CONSTRAINT oauth2_refresh_token_session_challenge_id_fkey FOREIGN KEY (challenge_id) REFERENCES public.oauth2_consent_session(challenge_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: oauth2_refresh_token_session oauth2_refresh_token_session_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth2_refresh_token_session
    ADD CONSTRAINT oauth2_refresh_token_session_subject_fkey FOREIGN KEY (subject) REFERENCES public.user_opaque_identifier(identifier) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict dRGFCMs3dX3ktoMU0AA8mOCLtBciYFeQ5Zuf13gzcc4zcqQQNr75vKcWODreXCs

