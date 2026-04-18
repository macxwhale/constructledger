--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.9

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = off;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET escape_string_warning = off;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA "public";


--
-- Name: SCHEMA "public"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA "public" IS 'standard public schema';


--
-- Name: app_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE "public"."app_role" AS ENUM (
    'manager',
    'viewer'
);


--
-- Name: cost_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE "public"."cost_type" AS ENUM (
    'materials',
    'labor',
    'equipment',
    'subcontractors'
);


--
-- Name: accept_invitation("uuid"); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION "public"."accept_invitation"("_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  _invitation RECORD;
  _user_id UUID;
  _existing_profile UUID;
BEGIN
  _user_id := auth.uid();
  
  IF _user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Get the invitation
  SELECT * INTO _invitation
  FROM public.invitations
  WHERE token = _token
    AND accepted_at IS NULL
    AND expires_at > now();
    
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired invitation');
  END IF;

  -- Check if user already has a profile
  SELECT id INTO _existing_profile FROM public.profiles WHERE user_id = _user_id;
  
  IF _existing_profile IS NOT NULL THEN
    -- Update existing profile to new company
    UPDATE public.profiles SET company_id = _invitation.company_id WHERE user_id = _user_id;
  ELSE
    -- Create new profile
    INSERT INTO public.profiles (user_id, company_id, full_name)
    VALUES (_user_id, _invitation.company_id, COALESCE((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = _user_id), ''));
  END IF;

  -- Delete any existing roles for this user
  DELETE FROM public.user_roles WHERE user_id = _user_id;
  
  -- Create user role in new company
  INSERT INTO public.user_roles (user_id, company_id, role)
  VALUES (_user_id, _invitation.company_id, _invitation.role);

  -- Mark invitation as accepted
  UPDATE public.invitations
  SET accepted_at = now()
  WHERE token = _token;

  RETURN jsonb_build_object('success', true, 'company_id', _invitation.company_id);
END;
$$;


--
-- Name: get_invitation_details("uuid"); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION "public"."get_invitation_details"("_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  _invitation RECORD;
  _company_name text;
BEGIN
  -- Get the invitation if valid (not accepted, not expired)
  SELECT * INTO _invitation
  FROM public.invitations
  WHERE token = _token
    AND accepted_at IS NULL
    AND expires_at > now();
    
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired invitation');
  END IF;

  -- Get company name
  SELECT name INTO _company_name
  FROM public.companies
  WHERE id = _invitation.company_id;

  RETURN jsonb_build_object(
    'success', true,
    'email', _invitation.email,
    'role', _invitation.role,
    'company_id', _invitation.company_id,
    'company_name', _company_name
  );
END;
$$;


--
-- Name: get_user_company_id("uuid"); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION "public"."get_user_company_id"("_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT company_id FROM public.profiles WHERE user_id = _user_id LIMIT 1
$$;


--
-- Name: handle_new_user_signup("text", "text"); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION "public"."handle_new_user_signup"("_company_name" "text", "_full_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  _company_id uuid;
BEGIN
  -- Create the company
  INSERT INTO public.companies (name)
  VALUES (_company_name)
  RETURNING id INTO _company_id;
  
  -- Create the profile
  INSERT INTO public.profiles (user_id, company_id, full_name)
  VALUES (auth.uid(), _company_id, _full_name);
  
  -- Assign manager role
  INSERT INTO public.user_roles (user_id, company_id, role)
  VALUES (auth.uid(), _company_id, 'manager');
  
  RETURN _company_id;
END;
$$;


--
-- Name: has_role("uuid", "uuid", "public"."app_role"); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION "public"."has_role"("_user_id" "uuid", "_company_id" "uuid", "_role" "public"."app_role") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND company_id = _company_id
      AND role = _role
  )
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


SET default_table_access_method = "heap";

--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."companies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


--
-- Name: costs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."costs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "cost_type" "public"."cost_type" NOT NULL,
    "amount" numeric(12,2) NOT NULL,
    "description" "text" NOT NULL,
    "date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "supplier" "text",
    "quantity" numeric(10,2),
    "unit_cost" numeric(12,2),
    "worker_name" "text",
    "hours" numeric(6,2),
    "hourly_rate" numeric(10,2),
    "equipment_name" "text",
    "rental_days" integer,
    "daily_rate" numeric(10,2),
    "contractor_name" "text",
    "invoice_reference" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "transport_cost" numeric(12,2) DEFAULT 0,
    "labor_cost" numeric(12,2) DEFAULT 0
);


--
-- Name: COLUMN "costs"."transport_cost"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN "public"."costs"."transport_cost" IS 'Extra transport cost specifically tied to a material entry';


--
-- Name: COLUMN "costs"."labor_cost"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN "public"."costs"."labor_cost" IS 'Extra labor/handling cost specifically tied to a material entry';


--
-- Name: income; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."income" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "amount" numeric(12,2) NOT NULL,
    "description" "text",
    "invoice_reference" "text",
    "date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "role" "public"."app_role" DEFAULT 'viewer'::"public"."app_role" NOT NULL,
    "invited_by" "uuid" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval) NOT NULL,
    "accepted_at" timestamp with time zone
);


--
-- Name: materials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."materials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "unit" "text",
    "default_unit_cost" numeric,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


--
-- Name: password_reset_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."password_reset_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '01:00:00'::interval) NOT NULL,
    "used_at" timestamp with time zone
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "full_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "client_name" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "projects_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'completed'::"text", 'on_hold'::"text"])))
);


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE "public"."user_roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "role" "public"."app_role" DEFAULT 'viewer'::"public"."app_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


--
-- Data for Name: companies; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."companies" ("id", "name", "created_at", "updated_at") VALUES ('7617de06-6520-4d58-9a41-11455c7a70a1', 'Buni Systems', '2026-01-05 09:44:08.387039+00', '2026-01-05 09:44:08.387039+00');
INSERT INTO "public"."companies" ("id", "name", "created_at", "updated_at") VALUES ('4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'Buni Systems LLC', '2026-01-05 11:01:35.458927+00', '2026-01-05 11:01:35.458927+00');
INSERT INTO "public"."companies" ("id", "name", "created_at", "updated_at") VALUES ('dbd078a3-2437-435d-88be-b32c2ebf0d13', 'Sabalink Technologies ', '2026-01-05 17:06:09.117512+00', '2026-01-05 17:06:09.117512+00');
INSERT INTO "public"."companies" ("id", "name", "created_at", "updated_at") VALUES ('006e73e3-eb6e-4eb0-8ba6-156bcc2847cd', 'Sabalink Technologies ', '2026-01-06 13:23:51.25187+00', '2026-01-06 13:23:51.25187+00');
INSERT INTO "public"."companies" ("id", "name", "created_at", "updated_at") VALUES ('e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Starhotech', '2026-04-08 12:18:18.551559+00', '2026-04-08 14:49:29.024673+00');
INSERT INTO "public"."companies" ("id", "name", "created_at", "updated_at") VALUES ('198c8f08-a450-46af-9dc0-5e9cfa8e5db9', 'Test Corp', '2026-04-17 20:32:18.304327+00', '2026-04-17 20:32:18.304327+00');


--
-- Data for Name: costs; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('f1ea081d-9250-4f58-a8a8-df8f8452e820', '0bd48400-244f-40c8-8e5c-0637a91144c7', 'materials', 5000.00, 'Building', '2026-01-05', 'ME', 1.00, 5000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '387c4ab8-c63d-4b24-920d-bf50ede0cdc6', '2026-01-05 09:49:22.668367+00', '2026-01-05 09:49:22.668367+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('85bd722a-282a-45cc-82ef-0ea97b7abfc4', '0bd48400-244f-40c8-8e5c-0637a91144c7', 'labor', 500.00, 'Workers', '2026-01-05', NULL, NULL, NULL, 'Kioko', 1.00, 500.00, NULL, NULL, NULL, NULL, NULL, '387c4ab8-c63d-4b24-920d-bf50ede0cdc6', '2026-01-05 09:49:47.060267+00', '2026-01-05 09:49:47.060267+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('7fb3d790-ee08-4e09-ab01-3ed1a3415989', '0bd48400-244f-40c8-8e5c-0637a91144c7', 'equipment', 522.00, 'Desc', '2026-01-05', NULL, NULL, NULL, NULL, NULL, NULL, 'Excavator', 1, 522.00, NULL, NULL, '387c4ab8-c63d-4b24-920d-bf50ede0cdc6', '2026-01-05 09:50:05.920454+00', '2026-01-05 09:50:05.920454+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('604f1362-9842-44c2-aad3-6cfe18ac1bb6', '0bd48400-244f-40c8-8e5c-0637a91144c7', 'subcontractors', 1000.00, 'Esc', '2026-01-05', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '4554', 'INV55', '387c4ab8-c63d-4b24-920d-bf50ede0cdc6', '2026-01-05 09:50:22.123431+00', '2026-01-05 09:50:22.123431+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('a460e5fc-1415-42d0-92a4-889ffa98b4ba', 'b0062077-0e20-4d61-960e-3aae0013877d', 'materials', 75000.00, 'Unpaid', '2026-01-06', 'Telwise', 3.00, 25000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b68e8adb-3331-4602-b017-4cbb88a70388', '2026-01-06 11:02:25.457729+00', '2026-01-06 11:02:25.457729+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('db09ff70-516f-4ac0-97a3-151944dafdcf', 'b25fa983-7e07-4f97-839e-0e22a420b9fe', 'materials', 9000.00, 'Beds and Backings', '2026-04-08', NULL, 18.00, 500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2c49c094-ca6b-4f04-a2d5-6aca33b08a02', '2026-04-08 12:46:13.711394+00', '2026-04-08 12:46:13.711394+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('982640af-4459-405e-baae-d19c0ced4db4', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 120000.00, 'Gypsum Board 12mm', '2026-04-09', 'Linnaxx Enterprises', 100.00, 1200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:39:54.235044+00', '2026-04-13 11:39:54.235044+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('33f0c641-b293-4c25-8f35-caaf201fce3a', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 28500.00, 'Gypsum Board 9mm', '2026-04-09', 'Linnaxx Enterprises', 30.00, 950.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:40:53.764537+00', '2026-04-13 11:40:53.764537+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('d97dcdc8-d203-4786-bbdb-b939fdbb14c0', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 48000.00, 'Channels', '2026-04-09', 'Linnaxx Enterprises', 30.00, 1600.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:41:41.417514+00', '2026-04-13 11:41:41.417514+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('275d243e-b0b2-4002-b367-19b974ab95d7', 'e696b079-6689-45f9-9f70-bdf186d557d0', 'materials', 2000.00, '30mm thick cement and sand backing', '2026-04-08', 'starhotech', 4.00, 500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '2026-04-08 13:54:59.202116+00', '2026-04-08 13:54:59.202116+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('fc189f7c-93be-4e66-8b65-b65d6195a80e', 'e696b079-6689-45f9-9f70-bdf186d557d0', 'materials', 1000.00, '30mm thick cement and sand backing', '2026-04-08', 'starhotech', 2.00, 500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '2026-04-08 13:55:08.260484+00', '2026-04-08 13:55:35.324531+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('0f29a0bb-f37b-4812-a328-baf6e093ac34', 'e696b079-6689-45f9-9f70-bdf186d557d0', 'labor', 1500.00, 'Labour', '2026-04-08', NULL, NULL, NULL, 'casuals', 8.00, 187.50, NULL, NULL, NULL, NULL, NULL, 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '2026-04-08 14:14:34.795259+00', '2026-04-08 14:14:34.795259+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('68b6ae49-d55a-42ba-8e2e-d03298eb1242', 'e696b079-6689-45f9-9f70-bdf186d557d0', 'materials', 42000.00, '1045x350 mm long counter top', '2026-04-08', 'starhotech', 4.00, 10500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '2026-04-08 14:26:43.519722+00', '2026-04-08 14:28:00.581175+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('1bd8bddd-af52-4603-9520-43c6a954c988', 'e696b079-6689-45f9-9f70-bdf186d557d0', 'materials', 52500.00, '1045x350 mm long counter top', '2026-04-08', 'starhotech', 5.00, 10500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '2026-04-08 14:29:00.020883+00', '2026-04-08 14:29:00.020883+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('8cd6bd73-2895-466f-95ba-c1591e85269f', 'e696b079-6689-45f9-9f70-bdf186d557d0', 'subcontractors', 40000.00, 'carpet reception', '2026-04-08', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'carpets', 'INV-2026', 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '2026-04-08 14:34:42.563375+00', '2026-04-08 14:34:42.563375+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('f2b4517c-7b34-4e43-8ae9-725d4edb2da3', 'b25fa983-7e07-4f97-839e-0e22a420b9fe', 'materials', 100.00, 'D', '2026-04-08', 'M', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2c49c094-ca6b-4f04-a2d5-6aca33b08a02', '2026-04-08 14:41:02.402095+00', '2026-04-08 14:41:22.994849+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('964b7c63-7a54-4a67-938b-8b242883dc21', 'b25fa983-7e07-4f97-839e-0e22a420b9fe', 'materials', 1200.00, 'Cement', '2026-04-10', 'rre', 1.00, 1200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2c49c094-ca6b-4f04-a2d5-6aca33b08a02', '2026-04-10 15:25:47.459029+00', '2026-04-10 15:25:47.459029+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('08e85fbd-5d4a-4587-859f-3b3e27336ee0', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 24900.00, '9 gypsum workers-1500*3=13,500
12 Labourers-700*12=8,400
2Thomas -500*2=3,000', '2026-04-10', NULL, NULL, NULL, 'Gypsum', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 07:27:35.850828+00', '2026-04-13 07:30:38.41971+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('08f2d813-2dd0-403a-92c6-e445cf34920d', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 21500.00, 'painter 3*1500=4,500
gypsum 6*1500=9,000
labourer 7*700=4,900
Electrician=1500
Thomas=1500', '2026-04-11', NULL, NULL, NULL, 'day shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 07:49:07.987796+00', '2026-04-13 07:49:07.987796+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('199f2e2b-738c-49fb-b164-0332783e7f44', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 24500.00, 'Painter 3*1500=4,500
Gypsum 9*1500=13,500
Labourer 5*700=3,500
Electrician=1,500
Thomas=1,500', '2026-04-11', NULL, NULL, NULL, 'night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 07:55:58.078936+00', '2026-04-13 07:55:58.078936+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('590a9eb6-07b2-4c13-a079-50aabd776e01', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 31100.00, 'Painter 5*1500=7,500
Gypsum 9*1500=13,500
Elactrician 2*1500=3000
Labourer 8*700=5,600
Thomas=1,500', '2026-04-12', NULL, NULL, NULL, 'day shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:00:02.707522+00', '2026-04-13 08:00:02.707522+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('908b8587-881f-4588-b931-170d4d7914b0', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 32800.00, 'Painter 6*1,500=9000
Gypsum 12*1,500=18,000
Labourer 4*700=2,800
Electric=1,500
Thomas=1,500', '2026-04-12', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:05:27.551103+00', '2026-04-13 08:05:27.551103+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('ed1816fe-5a31-4a19-904c-c24b90dc5ee7', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 8000.00, '2 x2 Timber', '2026-04-11', 'Headquarter Timber & Hardware', 200.00, 40.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:33:47.076946+00', '2026-04-13 08:34:37.735677+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('ab227e97-06ee-47fb-b736-25c618fe8307', 'b25fa983-7e07-4f97-839e-0e22a420b9fe', 'labor', 44.00, 'kkk', '2026-04-13', NULL, NULL, NULL, 'Kioko', 1.00, NULL, NULL, NULL, NULL, NULL, NULL, '2c49c094-ca6b-4f04-a2d5-6aca33b08a02', '2026-04-13 08:38:32.178925+00', '2026-04-13 08:38:32.178925+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('13d3ab4c-5803-4f8a-9c25-7826942c8e60', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2000.00, '2x2 timber transport', '2026-04-11', 'Headquarter Timber & Hardware', 200.00, 10.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:41:25.114329+00', '2026-04-13 08:41:53.681384+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('dd396c63-4f71-4847-a9ef-833b7fb71d4b', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 16000.00, '2x2 timber', '2026-04-12', 'Headquarter Timber & Hardware', 400.00, 40.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:43:02.735177+00', '2026-04-13 08:43:02.735177+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('d3d70bc7-5a15-4f17-85ba-4cc3c8fe4058', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2000.00, '2x2 timber transport', '2026-04-12', 'Headquarter Timber & Hardware', 200.00, 10.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:43:38.416713+00', '2026-04-13 08:43:56.740519+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('655667e3-04d3-47d8-a2d3-388d7c6776ac', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 20000.00, '2x2 timber', '2026-04-10', 'Headquarter Timber & Hardware', 500.00, 40.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:50:08.213051+00', '2026-04-13 08:50:08.213051+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('33dc873c-f9e0-4bef-8dad-fd57d3b1a5cb', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2000.00, '2x2 timber transport', '2026-04-10', 'Headquarter Timber & Hardware', 200.00, 10.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:50:40.694442+00', '2026-04-13 08:50:40.694442+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('9bf83dcb-ed7e-47c3-91f0-a434b22fd2f1', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 45000.00, 'Styro Foam', '2026-04-11', 'Headquarter Timber & Hardware', 30.00, 1500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:54:51.642323+00', '2026-04-13 08:54:51.642323+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('11ed21b2-f778-4f55-8b64-4235240345c1', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 3000.00, 'Styro Foam Transport', '2026-04-11', 'Headquarter Timber & Hardware', 30.00, 100.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 08:55:27.837471+00', '2026-04-13 08:55:27.837471+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('78dd06fc-73dc-4c5b-b772-4fd75f48b79f', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 25000.00, '1.5 Electric Cable', '2026-04-11', 'Jojo Electricals and Hardware Materials', 2.00, 12500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 09:04:21.334213+00', '2026-04-13 09:04:21.334213+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('cb4eedad-a1c2-42c3-8bef-f4bf0f86d792', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 35000.00, '2.5 Electric Cable', '2026-04-11', 'Jojo Electricals and Hardware Materials', 2.00, 17500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 09:04:56.708623+00', '2026-04-13 09:04:56.708623+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('784f4897-8b0b-4acf-88d5-53ac0b73a7bc', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 1500.00, 'Tape', '2026-04-11', 'Jojo Electricals and Hardware Materials', 10.00, 150.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 09:05:21.06855+00', '2026-04-13 09:05:21.06855+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('def7c8e1-aa83-49f8-98c9-4b043ee174c2', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 200.00, 'delivery cost', '2026-04-11', 'Jojo Electricals and Hardware Materials', 10.00, 20.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 09:08:00.5356+00', '2026-04-13 09:08:00.5356+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('b2949fac-d011-4603-acdf-5af86903b8a8', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 42000.00, 'Gyproc', '2026-04-09', 'Linnaxx Enterprises', 20.00, 2100.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:45:25.935641+00', '2026-04-13 11:45:25.935641+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('c55f8d96-3a41-49d1-9da5-046d2db6cb72', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 3000.00, 'Delivery Cost', '2026-04-09', 'Linnaxx Enterprises', 10.00, 300.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:45:58.220234+00', '2026-04-13 11:45:58.220234+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('8c0fa514-d24a-4b27-bd47-9302587923a9', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2000.00, 'Wall Plug', '2026-04-09', 'Linnaxx Enterprises', 10.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:43:11.710682+00', '2026-04-13 11:46:37.011776+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('2dea6753-3df7-4181-906b-ac8e1399785a', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 20000.00, 'Gypsum Scraps', '2026-04-09', 'Linnaxx Enterprises', 20.00, 1000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:42:43.263459+00', '2026-04-13 11:46:49.737516+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('77ca3e7e-ef1b-4f7b-b400-fbae239af33c', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 900.00, 'Steel Nails', '2026-04-09', 'Linnaxx Enterprises', 3.00, 300.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:44:49.92364+00', '2026-04-13 11:47:08.541265+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('0db9ba98-6ff5-4f0c-a3a7-7d18945f53de', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 56000.00, 'Stads', '2026-04-09', 'Linnaxx Enterprises', 35.00, 1600.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:42:12.003574+00', '2026-04-13 11:47:17.030232+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('ee16d10c-cfb2-4506-abca-1bbb0472c8a0', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 10000.00, 'Fibre Tape', '2026-04-09', 'Linnaxx Enterprises', 20.00, 500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:44:08.253495+00', '2026-04-13 11:47:57.32642+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('8187e48d-30d6-4714-a7f6-da5f6fb65cfd', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 15000.00, 'Wall Corner tape', '2026-04-09', 'Linnaxx Enterprises', 10.00, 1500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-13 11:43:42.037682+00', '2026-04-13 11:47:46.675691+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('fc31250d-5f1c-44ff-9c09-7c608124a259', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 187500.00, 'Gypsum Board 12mm', '2026-04-13', 'Linnaxx Enterprises', 150.00, 1250.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 06:56:26.229199+00', '2026-04-14 06:56:26.229199+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('6e1a3288-2a5c-430b-9237-4272852df95b', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 38000.00, 'Gypsum Board 9mm', '2026-04-13', 'Linnaxx Enterprises', 40.00, 950.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 06:57:05.977799+00', '2026-04-14 06:57:05.977799+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('d4f57df7-1b90-43ae-aeab-70d6363f338b', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 104000.00, 'Stads', '2026-04-13', 'Linnaxx Enterprises', 65.00, 1600.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 06:58:43.196898+00', '2026-04-14 06:58:43.196898+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('c53f6b09-5a55-4260-84be-6da40c5b4470', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 10000.00, 'Fiber Tape', '2026-04-13', 'Linnaxx Enterprises', 20.00, 500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 06:59:28.358859+00', '2026-04-14 06:59:28.358859+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('b4b20e23-92ce-4969-a0fa-16ed902da0bc', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 22500.00, 'Wall Corner Tape', '2026-04-13', NULL, 15.00, 1500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:00:05.038272+00', '2026-04-14 07:00:05.038272+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('25266e3b-bf6f-47ff-8c45-0b6ac553bb6e', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2000.00, 'Wall Plug 6mm', '2026-04-13', 'Linnaxx Enterprises', 10.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:00:53.708865+00', '2026-04-14 07:00:53.708865+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('bb458014-a9e9-429e-8b7a-b0a3ce9e8621', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 1800.00, 'Steel Nails', '2026-04-13', 'Linnaxx Enterprises', 6.00, 300.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:01:26.926873+00', '2026-04-14 07:01:26.926873+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('4ce00df5-3cc1-4e44-b12a-7a1f571da8cc', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 4000.00, 'Delivery Cost', '2026-04-13', 'Linnaxx Enterprises', 20.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:02:10.517204+00', '2026-04-14 07:02:10.517204+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('36b15db1-43dd-4f8c-aab2-44d6535819a8', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 80000.00, 'Channels', '2026-04-13', 'Linnaxx Enterprises', 50.00, 1600.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 06:58:05.230867+00', '2026-04-14 07:02:29.778642+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('7bf53fc2-f9f5-4b20-9fe8-a807837c8585', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 42000.00, 'Filler', '2026-04-13', 'Linnaxx Enterprises', 20.00, 2100.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:05:04.472843+00', '2026-04-14 07:05:04.472843+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('f3f16568-9235-42b6-824f-206ec2e460e8', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 20000.00, 'Gypsum Screw 1''''', '2026-04-13', 'Linnaxx Enterprises', 20.00, 1000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:05:39.040057+00', '2026-04-14 07:05:39.040057+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('e16a3df2-22d7-439c-bf7c-594084ffffc9', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 10000.00, 'Gypsum Screw 2''''', '2026-04-13', 'Linnaxx Enterprises', 10.00, 1000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:06:06.33898+00', '2026-04-14 07:06:06.33898+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('f700e62c-f599-44d1-bcd9-c1bbf3be2d96', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 12500.00, '1.5 Electric Cable', '2026-04-13', 'Jojo Electricals and Hardware Materials', 1.00, 12500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:16:09.054952+00', '2026-04-14 07:16:09.054952+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('9cd386db-81d1-448a-ae05-5510bb729c26', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 35000.00, '2.5 Electric Cable', '2026-04-13', 'Jojo Electricals and Hardware Materials', 2.00, 17500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:16:40.272239+00', '2026-04-14 07:16:40.272239+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('215d6c55-b732-496c-b279-8949eecb2c8c', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 1500.00, 'Hilt Bit 6'''' Mason', '2026-04-13', 'Jojo Electricals and Hardware Materials', 10.00, 150.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:42:41.889018+00', '2026-04-14 07:42:41.889018+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('3d8d2fc9-51b6-46bd-acbd-6724591fed04', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2000.00, 'Hilt bit 8'''' Mason', '2026-04-13', 'Jojo Electricals and Hardware Materials', 10.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:43:23.687702+00', '2026-04-14 07:43:23.687702+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('0c61dbca-5f87-4a8e-990f-1e86a5d18a13', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 200.00, 'Electrical Delivery cost', '2026-04-13', 'Jojo Electricals and Hardware Materials', 1.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:46:01.185767+00', '2026-04-14 07:46:01.185767+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('c3068047-802c-44a1-b1b5-411e3b78d405', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 16000.00, '2x2 timber', '2026-04-13', 'Headquarter Timber & Hardware', 400.00, 40.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:47:02.235888+00', '2026-04-14 07:47:02.235888+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('f61362fa-b6cc-406e-9758-429dfc5a6e5e', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2000.00, 'Timber Delivery cost', '2026-04-13', 'Headquarter Timber & Hardware', 400.00, 5.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 07:48:21.140485+00', '2026-04-14 07:48:21.140485+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('8c51a850-ba4e-4851-9fa1-6ea20e885001', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 4200.00, 'A2 Site Drawing Lamination', '2026-04-13', 'Citi place LTD', 12.00, 350.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 08:07:14.119771+00', '2026-04-14 08:07:14.119771+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('d73430ca-15c4-41e2-bfd7-2ec532af1c38', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 25200.00, 'workers dayshift', '2026-04-13', NULL, NULL, NULL, 'day shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 08:54:01.328671+00', '2026-04-14 08:54:01.328671+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('8bbcb1be-2a4c-48f7-a72d-9d6aa5662252', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 40200.00, 'workers nightshift', '2026-04-13', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 08:54:37.045812+00', '2026-04-14 08:54:37.045812+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('3f232a7d-2766-4ae4-8628-dcfbc3a4ad08', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2700.00, 'A2 Color drawings', '2026-04-13', 'Citi place LTD', 18.00, 150.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 09:01:30.130924+00', '2026-04-14 09:01:30.130924+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('59c6d4a4-46e9-4cda-928a-5389eba04202', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 2350.00, 'Workers Supper', '2026-04-13', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 09:04:01.145614+00', '2026-04-14 09:04:24.174795+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('1396b7c6-d52f-4cf5-9c71-116ecd4c9d2e', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 200.00, 'Passports', '2026-04-13', 'Citi place LTD', 1.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 09:05:43.845869+00', '2026-04-14 09:05:43.845869+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('7dfbf609-f30f-401c-8532-88c4b8f826f4', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2100.00, 'A2 Laminations', '2026-04-13', 'Citi place LTD', 6.00, 350.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 09:08:08.521239+00', '2026-04-14 09:08:08.521239+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('1e9f38b6-0c3f-47b8-91b4-c50e7fb51a12', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 2000.00, 'workers supper', '2026-04-11', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 09:13:24.094892+00', '2026-04-14 09:13:24.094892+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('be03f781-13be-46d2-8929-af806dbcd03f', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 1900.00, 'workers supper', '2026-04-10', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-14 09:14:33.226608+00', '2026-04-14 09:14:33.226608+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('1303c293-ca21-47e6-ad3d-da92aaaa3623', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 40000.00, 'Channels', '2026-04-12', 'Linnaxx Enterprises', 25.00, 1600.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:31:14.064491+00', '2026-04-15 08:31:14.064491+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('e2c2428c-9eee-4e3d-ba07-fced98bfe293', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 72000.00, 'Stands', '2026-04-12', 'Linnaxx Enterprises', 45.00, 1600.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:31:41.400702+00', '2026-04-15 08:31:41.400702+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('7762294b-7e40-478b-8cdd-5e53bd8f4493', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 3000.00, 'Linnax Delivery cost', '2026-04-12', 'Linnaxx Enterprises', 10.00, 300.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:32:33.941057+00', '2026-04-15 08:32:33.941057+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('bc80567d-7886-4dc1-86cc-392929af31af', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 33000.00, 'Filler', '2026-04-12', 'Linnaxx Enterprises', 15.00, 2200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:33:27.583858+00', '2026-04-15 08:33:27.583858+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('2ae23ba2-f075-49c3-bc6a-1171f3ee0c87', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 5000.00, 'Fibre Tape', '2026-04-12', 'Linnaxx Enterprises', 10.00, 500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:34:01.103812+00', '2026-04-15 08:34:01.103812+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('bec9a686-e2a6-4637-a1ab-dc11491eb22f', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 112500.00, 'Gypsum Board', '2026-04-12', 'Linnaxx Enterprises', 90.00, 1250.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:36:02.631845+00', '2026-04-15 08:36:02.631845+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('32271345-19a8-4375-90d1-c89549025dd3', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 10000.00, 'Screws 1''''', '2026-04-12', 'Linnaxx Enterprises', 10.00, 1000.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:39:15.013845+00', '2026-04-15 08:39:15.013845+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('d77556b9-ee50-4a1f-8505-12de1acb2fd0', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 1200.00, 'workers supper', '2026-04-14', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:44:54.179535+00', '2026-04-15 08:44:54.179535+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('79d4e9c2-0a37-4557-8a5c-3ebaa346d52c', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 29000.00, 'Workers Night Shift', '2026-04-14', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:44:24.081209+00', '2026-04-15 08:45:17.117305+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('b88a8f18-0f19-4d9a-a693-3319699a9fab', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 23700.00, 'Workers Day Shift', '2026-04-14', NULL, NULL, NULL, 'day shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-15 08:43:08.250877+00', '2026-04-15 08:45:32.038607+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('ff1fbe75-eb16-4170-b39f-65cda5c50b0e', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 25900.00, 'Workers Dayshift', '2026-04-15', NULL, NULL, NULL, 'day shift ', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-16 08:32:02.822131+00', '2026-04-16 08:32:02.822131+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('3bf5fdaf-2f00-43f3-92d5-380d3f0792b0', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 41100.00, 'Workers Nightshift', '2026-04-16', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-16 08:32:30.744641+00', '2026-04-16 08:32:30.744641+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('9714204e-e344-41d3-bc61-723f1d25f82d', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 25000.00, '1.5 Electric cable', '2026-04-17', 'Jojo Electricals and Hardware Materials', 2.00, 12500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 12:52:29.032861+00', '2026-04-17 12:52:29.032861+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('6e8faadf-cfa2-4ab9-894b-c6a7df3d98b4', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 17500.00, '2.5 Electric Cable', '2026-04-17', 'Jojo Electricals and Hardware Materials', 1.00, 17500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 12:55:30.511852+00', '2026-04-17 12:55:30.511852+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('27c6369b-537f-49d1-b719-8325273d57c8', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 2500.00, 'Steel bit 1/2', '2026-04-17', 'Jojo Electricals and Hardware Materials', 10.00, 250.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 12:58:09.218782+00', '2026-04-17 12:58:09.218782+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('745db1b8-48a3-4e2f-8c88-2b7058c47d0f', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 25000.00, '1.5 Electric Cable', '2026-04-15', 'Jojo Electricals and Hardware Materials', 2.00, 12500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 13:01:00.688933+00', '2026-04-17 13:01:00.688933+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('ed6342e2-ecb0-460c-80b8-adaac6177143', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 1500.00, 'Tape', '2026-04-15', 'Jojo Electricals and Hardware Materials', 10.00, 150.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 13:02:09.066901+00', '2026-04-17 13:02:09.066901+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('ef703fc5-78b9-42cb-afac-65e608fe3d94', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 1500.00, 'Lock Small', '2026-04-11', 'Jojo Electricals and Hardware Materials', 1.00, 1500.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 13:04:46.945626+00', '2026-04-17 13:04:46.945626+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('15c76a7a-7ad6-4b71-9fa4-e07f902ea54a', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 31200.00, 'workers dayshift', '2026-04-16', NULL, NULL, NULL, 'day shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 13:06:36.181461+00', '2026-04-17 13:06:36.181461+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('e3b4a78a-26bc-4d54-8370-90479997f7e8', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'labor', 45800.00, 'workers nightshift', '2026-04-16', NULL, NULL, NULL, 'Night shift', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 13:07:07.476333+00', '2026-04-17 13:07:07.476333+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('94014e0f-c89d-4cc3-98a4-45abd6c58d7f', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 200.00, 'Delivery cost', '2026-04-15', 'Jojo Electricals and Hardware Materials', 1.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 13:08:00.852203+00', '2026-04-17 13:08:15.282042+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('cec0a3fb-5693-4edd-af1f-2d8ffa4915df', '203fda33-eb8b-47c4-bd4c-4694c75925d1', 'materials', 200.00, 'Delivery cost', '2026-04-11', 'Jojo Electricals and Hardware Materials', 1.00, 200.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '2026-04-17 13:08:39.920035+00', '2026-04-17 13:08:39.920035+00', 0.00, 0.00);
INSERT INTO "public"."costs" ("id", "project_id", "cost_type", "amount", "description", "date", "supplier", "quantity", "unit_cost", "worker_name", "hours", "hourly_rate", "equipment_name", "rental_days", "daily_rate", "contractor_name", "invoice_reference", "created_by", "created_at", "updated_at", "transport_cost", "labor_cost") VALUES ('a4f9c8b2-ed26-469f-95b7-2e80cf170223', '10715825-7c35-4b34-afbc-7d15a5917714', 'materials', 8008700.00, 'Test material add', '2026-04-17', NULL, 10.00, 800800.00, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '75ce6a56-cea2-4211-be36-e7862831cdaf', '2026-04-17 20:41:36.45632+00', '2026-04-17 20:41:36.45632+00', 200.00, 500.00);


--
-- Data for Name: income; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."income" ("id", "project_id", "amount", "description", "invoice_reference", "date", "created_by", "created_at", "updated_at") VALUES ('8a903c63-6bba-4c4b-b802-87dcb3543e8c', '0bd48400-244f-40c8-8e5c-0637a91144c7', 40.00, 'First Home', '#BK', '2026-01-05', '387c4ab8-c63d-4b24-920d-bf50ede0cdc6', '2026-01-05 09:45:16.925444+00', '2026-01-05 09:45:16.925444+00');
INSERT INTO "public"."income" ("id", "project_id", "amount", "description", "invoice_reference", "date", "created_by", "created_at", "updated_at") VALUES ('ea358033-c4ab-436a-bd0a-95adb5a2752c', 'e696b079-6689-45f9-9f70-bdf186d557d0', 50000.00, '1045x350 mm long counter top', 'INV-2026', '2026-04-08', 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '2026-04-08 14:00:43.949148+00', '2026-04-08 14:32:50.351693+00');


--
-- Data for Name: invitations; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."invitations" ("id", "company_id", "email", "role", "invited_by", "token", "created_at", "expires_at", "accepted_at") VALUES ('8a1cce51-11ea-47ec-a6dd-a9bd433b12af', '4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'macxwhale@gmail.com', 'viewer', 'c6604217-32d5-4537-ab27-db72367c1999', '7bbea228-91fb-442f-8fa5-bbbbff69c11f', '2026-01-05 11:06:54.95571+00', '2026-01-12 11:06:54.95571+00', '2026-01-05 11:08:35.013865+00');
INSERT INTO "public"."invitations" ("id", "company_id", "email", "role", "invited_by", "token", "created_at", "expires_at", "accepted_at") VALUES ('0f460c4a-4eb0-482a-b427-ef6e410704ee', '006e73e3-eb6e-4eb0-8ba6-156bcc2847cd', 'suzziewangechi6@gmail.com', 'manager', 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '78cf0d21-bd34-4fd1-bacd-e052ce0dfdcd', '2026-04-08 14:40:45.746555+00', '2026-04-15 14:40:45.746555+00', NULL);
INSERT INTO "public"."invitations" ("id", "company_id", "email", "role", "invited_by", "token", "created_at", "expires_at", "accepted_at") VALUES ('30c6cf85-b84c-410b-a786-70b75f874647', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'acronixbusinessolutions@gmail.com', 'manager', 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', '93461cab-d9d8-4b10-946c-4f3a28a91234', '2026-04-08 14:46:41.145829+00', '2026-04-15 14:46:41.145829+00', '2026-04-08 14:48:45.860863+00');


--
-- Data for Name: materials; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('0974748e-9152-400e-8d3c-e1d8f22e489f', '4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'Cement', 'peices', 1200, '2026-04-10 15:25:27.955144+00', '2026-04-10 15:25:27.955144+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('65645ef7-1940-40ca-a549-e1db1845db7a', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', '2x2 timber', '200ft', 40, '2026-04-13 08:32:38.0658+00', '2026-04-13 08:32:38.0658+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('10a85abe-c148-4b1d-b709-ae6c1cac9064', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', '2x2 timber transport', '200ft', 10, '2026-04-13 08:40:45.016264+00', '2026-04-13 08:40:45.016264+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('8250577e-a20b-4f5e-ab66-dd86eb518e12', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Styro Foam', '30 pcs', 1500, '2026-04-13 08:51:48.501077+00', '2026-04-13 08:51:48.501077+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('27b1a214-4fa7-48e7-86df-50d7f8907046', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Styro Foam transport', '30 pcs', 100, '2026-04-13 08:53:29.681861+00', '2026-04-13 08:53:29.681861+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('08863f30-a635-4d59-9c0e-a549e9bf4ca9', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Tape', '10 pcs', 150, '2026-04-13 09:00:49.989458+00', '2026-04-13 09:00:49.989458+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('cd5dba66-a623-4ce6-bfa5-b63c05e088f8', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', '1.5 Electric cable', '2R', 12500, '2026-04-13 09:02:05.880952+00', '2026-04-13 09:02:05.880952+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('c2419138-819d-4519-9a52-ac8f0107ee8b', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', '2.5 Electric Cable', '2R', 17500, '2026-04-13 09:03:01.011977+00', '2026-04-13 09:03:01.011977+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('19745ce8-364a-4c49-80aa-144e8325260b', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Delivery Cost', NULL, NULL, '2026-04-13 09:07:02.120331+00', '2026-04-13 09:07:02.120331+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('1850dc57-d964-4b81-8c63-ee80bc7b32dd', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Gypsum Board 12mm', '100', 1200, '2026-04-13 11:28:45.887239+00', '2026-04-13 11:28:45.887239+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('e8a30d23-c468-40f1-93d9-1a0b31947aa9', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Gypsum Board 9mm', '30 pcs', 950, '2026-04-13 11:29:40.236705+00', '2026-04-13 11:29:40.236705+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('4abeb00e-8914-4569-b7a9-2323b2cc306b', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Gypsum Scraps', '20 pkts', 1000, '2026-04-13 11:30:28.778682+00', '2026-04-13 11:30:28.778682+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('43c82db1-9d4c-45fd-8efe-15d6fcea401f', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'delivery cost', '10', 3000, '2026-04-13 11:31:12.52361+00', '2026-04-13 11:31:12.52361+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('ae64c599-49e6-4d6c-b965-6c6633b45120', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'steel Nails', '3pkts', 300, '2026-04-13 11:31:44.148541+00', '2026-04-13 11:31:44.148541+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('b8adb908-60ec-4f48-a1bc-f75cff3e3e5b', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Fiber Tape', '20 rolls', 500, '2026-04-13 11:32:31.199012+00', '2026-04-13 11:32:31.199012+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('972b92dc-540a-419c-b93b-3ddde84fd9ab', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Channels', '30 bundles', 1600, '2026-04-13 11:33:33.07867+00', '2026-04-13 11:33:33.07867+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('5cb3935c-2fe1-48d0-b125-443daca0f063', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Stads', '35 bundles', 1600, '2026-04-13 11:34:44.359232+00', '2026-04-13 11:34:44.359232+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('ae793b99-2cc3-483c-99c2-f0554d28644b', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'wall plug', '10 pkts', 200, '2026-04-13 11:35:25.99378+00', '2026-04-13 11:35:25.99378+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('9be99ff6-8663-4d63-a5e1-f6a57b79c0a4', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'wall corner tape', '10 pkts', 1500, '2026-04-13 11:35:51.672642+00', '2026-04-13 11:35:51.672642+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('4461a42a-fc5f-46a6-bad8-685df08eb32a', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Gyproc', '20', 2100, '2026-04-13 11:38:38.44814+00', '2026-04-13 11:38:38.44814+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('2849a0ba-42b6-4d65-b220-e962befe5da3', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Filler', '20 bags', 2100, '2026-04-14 07:03:15.827502+00', '2026-04-14 07:03:15.827502+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('e747189b-f6c5-491a-8b5f-8176171438f6', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Gypsum Screw 1''''', '20pkt', 1000, '2026-04-14 07:03:48.161693+00', '2026-04-14 07:03:48.161693+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('e84053d3-e546-4178-87b0-6879214e7bc6', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Gypsum Screw 2''''', '10pkt', 1000, '2026-04-14 07:04:25.010852+00', '2026-04-14 07:04:25.010852+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('fccda913-6136-40e1-9dfb-05d4d84a5abe', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Hilt bit 8'''' Mason', '10pcs', 200, '2026-04-14 07:41:11.521757+00', '2026-04-14 07:41:11.521757+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('16923e41-39f8-4ab2-84a2-83ec5bd176d8', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Hilt bit 6'''' Mason', '10pcs', 150, '2026-04-14 07:41:51.5483+00', '2026-04-14 07:41:51.5483+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('39560a4a-de58-4e7d-9dec-7b3894f6cbaf', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'passports', '1', 200, '2026-04-14 07:54:59.066848+00', '2026-04-14 07:54:59.066848+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('f93c4dd9-5de1-45ff-9229-2922c15650ea', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'A2 color drawings', '18', 150, '2026-04-14 07:55:49.759245+00', '2026-04-14 07:55:49.759245+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('56b51d7e-8243-4692-beef-eb6353b0f3d1', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'A2 Lamination', '1', 350, '2026-04-14 09:09:26.117242+00', '2026-04-14 09:09:26.117242+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('7ecc0b8f-a085-48a0-84fe-27ad6f265163', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Gypsum Board', '90sheets', 1250, '2026-04-15 08:34:55.487306+00', '2026-04-15 08:34:55.487306+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('4b9462d6-1c3e-4970-8bde-8b62dbbbca5d', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Screws 1''''', '10', 1000, '2026-04-15 08:35:28.036914+00', '2026-04-15 08:35:28.036914+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('bbb6bc6b-fa32-4b2b-9754-36ca9795f1d9', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Steel bit 1/2', '10', 2500, '2026-04-17 12:57:35.932983+00', '2026-04-17 12:57:35.932983+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('35a08301-964d-4d7f-ace9-ec89ad1dad64', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Lock Small', '1', 1500, '2026-04-17 13:03:53.799404+00', '2026-04-17 13:03:53.799404+00');
INSERT INTO "public"."materials" ("id", "company_id", "name", "unit", "default_unit_cost", "created_at", "updated_at") VALUES ('7f8acffa-33ef-40a8-8b92-7b21e10193f5', '198c8f08-a450-46af-9dc0-5e9cfa8e5db9', 'Cement', '50kg bag', 800, '2026-04-17 20:34:51.328184+00', '2026-04-17 20:34:51.328184+00');


--
-- Data for Name: password_reset_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."password_reset_tokens" ("id", "email", "token", "created_at", "expires_at", "used_at") VALUES ('711a2510-72fd-4ad5-8be4-45dd0da127f0', 'info1@bunisytems.com', '09a0d526-8432-42fb-9812-7503897210a4', '2026-01-19 15:13:10.909597+00', '2026-01-19 16:13:10.909597+00', NULL);
INSERT INTO "public"."password_reset_tokens" ("id", "email", "token", "created_at", "expires_at", "used_at") VALUES ('16e21a4e-afe9-4501-a092-3ea9c1ae7853', 'macxwhale@gmail.com', 'af876293-1058-4c18-a5d6-1acdb4f6bf5f', '2026-04-08 12:14:35.437904+00', '2026-04-08 13:14:35.437904+00', '2026-04-08 12:15:42.017+00');
INSERT INTO "public"."password_reset_tokens" ("id", "email", "token", "created_at", "expires_at", "used_at") VALUES ('5c2a9996-9428-4cfc-9a73-320cc3887027', 'cngash11@gmail.com', 'a6ef3257-26db-4418-a7b0-99bb9a403e21', '2026-04-08 13:39:57.125275+00', '2026-04-08 14:39:57.125275+00', '2026-04-08 13:41:48.218+00');
INSERT INTO "public"."password_reset_tokens" ("id", "email", "token", "created_at", "expires_at", "used_at") VALUES ('68dbeadb-6f8d-4b1e-b902-11354d3bef75', 'macxwhale@gmail.com', '082b0b1e-5f29-4c8f-a0bb-b9c5f35f6fdd', '2026-04-10 10:10:19.729307+00', '2026-04-10 11:10:19.729307+00', '2026-04-10 10:13:38.606+00');


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('8bf9db3f-3db9-4ad8-a275-ad0a34e12c1b', '387c4ab8-c63d-4b24-920d-bf50ede0cdc6', '7617de06-6520-4d58-9a41-11455c7a70a1', 'oxymoron', '2026-01-05 09:44:08.387039+00', '2026-01-05 09:44:08.387039+00');
INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('2fba2648-487d-4394-8d78-997b5ce4ea69', 'c6604217-32d5-4537-ab27-db72367c1999', '4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'bunisystems', '2026-01-05 11:01:35.458927+00', '2026-01-05 11:01:35.458927+00');
INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('cc867ef9-b1fb-4b4a-9763-12572c8c6a78', '2c49c094-ca6b-4f04-a2d5-6aca33b08a02', '4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'Buni Systems78', '2026-01-05 11:08:35.013865+00', '2026-01-05 11:08:35.013865+00');
INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('bd675cd8-f066-4da7-868f-cfc07c1b5651', 'b68e8adb-3331-4602-b017-4cbb88a70388', 'dbd078a3-2437-435d-88be-b32c2ebf0d13', 'Charles Njuguna ', '2026-01-05 17:06:09.117512+00', '2026-01-05 17:06:09.117512+00');
INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('583a2ef7-225d-406c-bdf9-70f62bc88ad9', 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '006e73e3-eb6e-4eb0-8ba6-156bcc2847cd', 'Charles', '2026-01-06 13:23:51.25187+00', '2026-01-06 13:23:51.25187+00');
INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('c9a8558d-e1b4-4456-87cd-6ee09e9b33d8', 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Susan Wangechi', '2026-04-08 12:18:18.551559+00', '2026-04-08 12:18:18.551559+00');
INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('bca99dd7-bb71-4716-9df2-a3c7cfc76eb1', '548ce515-67fc-4773-b89a-9b85fe4f8a14', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'Charles Njuguna', '2026-04-08 14:48:45.860863+00', '2026-04-08 14:49:28.690719+00');
INSERT INTO "public"."profiles" ("id", "user_id", "company_id", "full_name", "created_at", "updated_at") VALUES ('3e39c79f-82d6-4aac-a4e1-60d25a8024f5', '75ce6a56-cea2-4211-be36-e7862831cdaf', '198c8f08-a450-46af-9dc0-5e9cfa8e5db9', 'Test User', '2026-04-17 20:32:18.304327+00', '2026-04-17 20:32:18.304327+00');


--
-- Data for Name: projects; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('0bd48400-244f-40c8-8e5c-0637a91144c7', '7617de06-6520-4d58-9a41-11455c7a70a1', 'Buni Sysems HQ', 'Home land', 'Buni Systems', 'active', '2026-01-05 09:44:38.36507+00', '2026-01-05 09:44:38.36507+00');
INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('b0062077-0e20-4d61-960e-3aae0013877d', 'dbd078a3-2437-435d-88be-b32c2ebf0d13', 'Gpo', 'Renovation', 'Ps office', 'active', '2026-01-05 17:06:34.212464+00', '2026-01-05 17:06:34.212464+00');
INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('b25fa983-7e07-4f97-839e-0e22a420b9fe', '4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'HAZINA TRADE CENTRE', 'PROPOSED OFFICE PARTITIONING AND REFURBISHMENT WORKS TO 6TH AND 7TH FLOORS AT HAZINA TRADE CENTRE FOR EAST AFRICAN COMMUNITY', 'EAST AFRICAN COMMUNITY', 'active', '2026-04-08 12:45:22.382306+00', '2026-04-08 12:45:22.382306+00');
INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('e696b079-6689-45f9-9f70-bdf186d557d0', '006e73e3-eb6e-4eb0-8ba6-156bcc2847cd', 'Gpo', 'Renovation', 'Ps office', 'active', '2026-01-06 13:24:21.158602+00', '2026-04-08 13:48:48.938163+00');
INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('e12c4b64-6983-49f5-9312-b351d117c1d5', '006e73e3-eb6e-4eb0-8ba6-156bcc2847cd', 'Hazina 1', 'construction', 'Hazina Towers', 'active', '2026-04-08 13:57:56.287175+00', '2026-04-08 13:57:56.287175+00');
INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('62dfb0d2-e3ef-4a3e-80f6-548f7577b20a', '006e73e3-eb6e-4eb0-8ba6-156bcc2847cd', 'HAZINA TRADE CENTER', 'SITE RENOVATION', 'EAST AFRICAN COMMUNITY', 'active', '2026-04-08 14:39:02.440654+00', '2026-04-08 14:39:02.440654+00');
INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('203fda33-eb8b-47c4-bd4c-4694c75925d1', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'HAZINA TRADE CENTER', 'OFFICE RENOVATION', 'East African Community', 'active', '2026-04-08 12:26:09.431496+00', '2026-04-13 07:25:10.886923+00');
INSERT INTO "public"."projects" ("id", "company_id", "name", "description", "client_name", "status", "created_at", "updated_at") VALUES ('10715825-7c35-4b34-afbc-7d15a5917714', '198c8f08-a450-46af-9dc0-5e9cfa8e5db9', 'Test Project', NULL, NULL, 'active', '2026-04-17 20:32:55.30742+00', '2026-04-17 20:32:55.30742+00');


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('9b3d04ef-daf7-420e-a842-9fe7f4a816a8', '387c4ab8-c63d-4b24-920d-bf50ede0cdc6', '7617de06-6520-4d58-9a41-11455c7a70a1', 'manager', '2026-01-05 09:44:08.387039+00');
INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('4a38f953-c24d-4fcd-94c7-a0995932fa2a', 'c6604217-32d5-4537-ab27-db72367c1999', '4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'manager', '2026-01-05 11:01:35.458927+00');
INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('24ae3937-ed5f-4f29-9303-c5400bea783f', 'b68e8adb-3331-4602-b017-4cbb88a70388', 'dbd078a3-2437-435d-88be-b32c2ebf0d13', 'manager', '2026-01-05 17:06:09.117512+00');
INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('f575289e-aad5-493d-b70e-a6af91ac9883', 'd1c535ee-bc1d-4cec-b38b-2d5ceaf10c22', '006e73e3-eb6e-4eb0-8ba6-156bcc2847cd', 'manager', '2026-01-06 13:23:51.25187+00');
INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('6887bb71-635f-4814-913b-4d9d11168172', 'b4d9fa7c-21d2-40f0-ba51-5afd711a0988', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'manager', '2026-04-08 12:18:18.551559+00');
INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('df296938-2226-4eed-a3ef-65e2901d4c02', '2c49c094-ca6b-4f04-a2d5-6aca33b08a02', '4f7cd44a-f066-4aca-8bf2-baa455f5e65b', 'manager', '2026-01-05 11:08:35.013865+00');
INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('126f413f-7f1c-4a96-81dc-5dee9414e625', '548ce515-67fc-4773-b89a-9b85fe4f8a14', 'e4c10d92-0bc8-40e7-8e37-8319cc832f04', 'manager', '2026-04-08 14:48:45.860863+00');
INSERT INTO "public"."user_roles" ("id", "user_id", "company_id", "role", "created_at") VALUES ('4f56d456-119b-43a9-9ca4-3a8abc5b572b', '75ce6a56-cea2-4211-be36-e7862831cdaf', '198c8f08-a450-46af-9dc0-5e9cfa8e5db9', 'manager', '2026-04-17 20:32:18.304327+00');


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");


--
-- Name: costs costs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."costs"
    ADD CONSTRAINT "costs_pkey" PRIMARY KEY ("id");


--
-- Name: income income_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."income"
    ADD CONSTRAINT "income_pkey" PRIMARY KEY ("id");


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");


--
-- Name: invitations invitations_token_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_token_unique" UNIQUE ("token");


--
-- Name: materials materials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."materials"
    ADD CONSTRAINT "materials_pkey" PRIMARY KEY ("id");


--
-- Name: password_reset_tokens password_reset_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."password_reset_tokens"
    ADD CONSTRAINT "password_reset_tokens_pkey" PRIMARY KEY ("id");


--
-- Name: password_reset_tokens password_reset_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."password_reset_tokens"
    ADD CONSTRAINT "password_reset_tokens_token_key" UNIQUE ("token");


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");


--
-- Name: profiles profiles_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_key" UNIQUE ("user_id");


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");


--
-- Name: user_roles user_roles_user_id_company_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_company_id_key" UNIQUE ("user_id", "company_id");


--
-- Name: idx_costs_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_costs_project_id" ON "public"."costs" USING "btree" ("project_id");


--
-- Name: idx_costs_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_costs_type" ON "public"."costs" USING "btree" ("cost_type");


--
-- Name: idx_income_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_income_project_id" ON "public"."income" USING "btree" ("project_id");


--
-- Name: idx_invitations_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_invitations_company_id" ON "public"."invitations" USING "btree" ("company_id");


--
-- Name: idx_invitations_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_invitations_email" ON "public"."invitations" USING "btree" ("email");


--
-- Name: idx_invitations_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_invitations_expires_at" ON "public"."invitations" USING "btree" ("expires_at");


--
-- Name: idx_invitations_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_invitations_token" ON "public"."invitations" USING "btree" ("token");


--
-- Name: idx_password_reset_tokens_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_password_reset_tokens_expires" ON "public"."password_reset_tokens" USING "btree" ("expires_at");


--
-- Name: idx_password_reset_tokens_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_password_reset_tokens_token" ON "public"."password_reset_tokens" USING "btree" ("token");


--
-- Name: idx_profiles_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_profiles_company_id" ON "public"."profiles" USING "btree" ("company_id");


--
-- Name: idx_profiles_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_profiles_user_id" ON "public"."profiles" USING "btree" ("user_id");


--
-- Name: idx_projects_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_projects_company_id" ON "public"."projects" USING "btree" ("company_id");


--
-- Name: idx_user_roles_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_user_roles_company_id" ON "public"."user_roles" USING "btree" ("company_id");


--
-- Name: idx_user_roles_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "idx_user_roles_user_id" ON "public"."user_roles" USING "btree" ("user_id");


--
-- Name: companies update_companies_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER "update_companies_updated_at" BEFORE UPDATE ON "public"."companies" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- Name: costs update_costs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER "update_costs_updated_at" BEFORE UPDATE ON "public"."costs" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- Name: income update_income_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER "update_income_updated_at" BEFORE UPDATE ON "public"."income" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- Name: materials update_materials_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER "update_materials_updated_at" BEFORE UPDATE ON "public"."materials" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- Name: profiles update_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER "update_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- Name: projects update_projects_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER "update_projects_updated_at" BEFORE UPDATE ON "public"."projects" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


--
-- Name: costs costs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."costs"
    ADD CONSTRAINT "costs_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");


--
-- Name: costs costs_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."costs"
    ADD CONSTRAINT "costs_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;


--
-- Name: income income_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."income"
    ADD CONSTRAINT "income_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");


--
-- Name: income income_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."income"
    ADD CONSTRAINT "income_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;


--
-- Name: invitations invitations_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;


--
-- Name: materials materials_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."materials"
    ADD CONSTRAINT "materials_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;


--
-- Name: profiles profiles_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;


--
-- Name: profiles profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: projects projects_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;


--
-- Name: user_roles user_roles_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: companies Authenticated users can create companies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can create companies" ON "public"."companies" FOR INSERT TO "authenticated" WITH CHECK (true);


--
-- Name: invitations Managers can create invitations in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can create invitations in their company" ON "public"."invitations" FOR INSERT WITH CHECK ((("company_id" = "public"."get_user_company_id"("auth"."uid"())) AND "public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role")));


--
-- Name: costs Managers can delete costs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can delete costs" ON "public"."costs" FOR DELETE USING (("project_id" IN ( SELECT "p"."id"
   FROM "public"."projects" "p"
  WHERE "public"."has_role"("auth"."uid"(), "p"."company_id", 'manager'::"public"."app_role"))));


--
-- Name: income Managers can delete income; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can delete income" ON "public"."income" FOR DELETE USING (("project_id" IN ( SELECT "p"."id"
   FROM "public"."projects" "p"
  WHERE "public"."has_role"("auth"."uid"(), "p"."company_id", 'manager'::"public"."app_role"))));


--
-- Name: invitations Managers can delete invitations in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can delete invitations in their company" ON "public"."invitations" FOR DELETE USING ("public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role"));


--
-- Name: materials Managers can delete materials; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can delete materials" ON "public"."materials" FOR DELETE USING ("public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role"));


--
-- Name: projects Managers can delete projects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can delete projects" ON "public"."projects" FOR DELETE USING ("public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role"));


--
-- Name: costs Managers can insert costs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can insert costs" ON "public"."costs" FOR INSERT WITH CHECK ((("project_id" IN ( SELECT "p"."id"
   FROM "public"."projects" "p"
  WHERE ("p"."company_id" = "public"."get_user_company_id"("auth"."uid"())))) AND "public"."has_role"("auth"."uid"(), "public"."get_user_company_id"("auth"."uid"()), 'manager'::"public"."app_role")));


--
-- Name: income Managers can insert income; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can insert income" ON "public"."income" FOR INSERT WITH CHECK ((("project_id" IN ( SELECT "p"."id"
   FROM "public"."projects" "p"
  WHERE ("p"."company_id" = "public"."get_user_company_id"("auth"."uid"())))) AND "public"."has_role"("auth"."uid"(), "public"."get_user_company_id"("auth"."uid"()), 'manager'::"public"."app_role")));


--
-- Name: materials Managers can insert materials; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can insert materials" ON "public"."materials" FOR INSERT WITH CHECK ((("company_id" = "public"."get_user_company_id"("auth"."uid"())) AND "public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role")));


--
-- Name: profiles Managers can insert profiles in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can insert profiles in their company" ON "public"."profiles" FOR INSERT WITH CHECK ((("company_id" = "public"."get_user_company_id"("auth"."uid"())) AND "public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role")));


--
-- Name: projects Managers can insert projects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can insert projects" ON "public"."projects" FOR INSERT WITH CHECK ((("company_id" = "public"."get_user_company_id"("auth"."uid"())) AND "public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role")));


--
-- Name: user_roles Managers can manage roles in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can manage roles in their company" ON "public"."user_roles" USING ("public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role"));


--
-- Name: costs Managers can update costs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can update costs" ON "public"."costs" FOR UPDATE USING (("project_id" IN ( SELECT "p"."id"
   FROM "public"."projects" "p"
  WHERE "public"."has_role"("auth"."uid"(), "p"."company_id", 'manager'::"public"."app_role"))));


--
-- Name: income Managers can update income; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can update income" ON "public"."income" FOR UPDATE USING (("project_id" IN ( SELECT "p"."id"
   FROM "public"."projects" "p"
  WHERE "public"."has_role"("auth"."uid"(), "p"."company_id", 'manager'::"public"."app_role"))));


--
-- Name: materials Managers can update materials; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can update materials" ON "public"."materials" FOR UPDATE USING ("public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role"));


--
-- Name: projects Managers can update projects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can update projects" ON "public"."projects" FOR UPDATE USING ("public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role"));


--
-- Name: companies Managers can update their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can update their company" ON "public"."companies" FOR UPDATE USING ("public"."has_role"("auth"."uid"(), "id", 'manager'::"public"."app_role"));


--
-- Name: invitations Managers can view invitations in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can view invitations in their company" ON "public"."invitations" FOR SELECT USING ("public"."has_role"("auth"."uid"(), "company_id", 'manager'::"public"."app_role"));


--
-- Name: profiles Users can update their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("user_id" = "auth"."uid"()));


--
-- Name: costs Users can view costs in their projects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view costs in their projects" ON "public"."costs" FOR SELECT USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."company_id" = "public"."get_user_company_id"("auth"."uid"())))));


--
-- Name: income Users can view income in their projects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view income in their projects" ON "public"."income" FOR SELECT USING (("project_id" IN ( SELECT "projects"."id"
   FROM "public"."projects"
  WHERE ("projects"."company_id" = "public"."get_user_company_id"("auth"."uid"())))));


--
-- Name: materials Users can view materials in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view materials in their company" ON "public"."materials" FOR SELECT USING (("company_id" = "public"."get_user_company_id"("auth"."uid"())));


--
-- Name: profiles Users can view profiles in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view profiles in their company" ON "public"."profiles" FOR SELECT USING (("company_id" = "public"."get_user_company_id"("auth"."uid"())));


--
-- Name: projects Users can view projects in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view projects in their company" ON "public"."projects" FOR SELECT USING (("company_id" = "public"."get_user_company_id"("auth"."uid"())));


--
-- Name: user_roles Users can view roles in their company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view roles in their company" ON "public"."user_roles" FOR SELECT USING (("company_id" = "public"."get_user_company_id"("auth"."uid"())));


--
-- Name: companies Users can view their own company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their own company" ON "public"."companies" FOR SELECT USING (("id" = "public"."get_user_company_id"("auth"."uid"())));


--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."companies" ENABLE ROW LEVEL SECURITY;

--
-- Name: costs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."costs" ENABLE ROW LEVEL SECURITY;

--
-- Name: income; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."income" ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."invitations" ENABLE ROW LEVEL SECURITY;

--
-- Name: materials; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."materials" ENABLE ROW LEVEL SECURITY;

--
-- Name: password_reset_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."password_reset_tokens" ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;

--
-- Name: projects; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--


