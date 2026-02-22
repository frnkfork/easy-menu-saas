-- ========================================================
-- 🚀 SMARTSTOCK PRO & EASYMENU: MASTER ARCHITECTURE (SaaS)
-- ========================================================
-- Este script consolida toda la base de datos para la plataforma SaaS,
-- incluyendo perfiles, configuración de negocio, inventario y pedidos.
-- Implementa Aislamiento Multi-usuario (RLS) en todos los niveles.

-- 1. EXTENSIÓN PARA GENERAR UUIDS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. TABLA: PROFILES (Información básica del administrador)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE NOT NULL PRIMARY KEY,
    full_name TEXT,
    company_name TEXT,
    email TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. TABLA: BUSINESS_PROFILE (Personalización SaaS por empresa)
CREATE TABLE IF NOT EXISTS public.business_profile (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    business_name TEXT NOT NULL DEFAULT 'Nuevo Negocio',
    currency_symbol TEXT NOT NULL DEFAULT 'S/',
    email TEXT,
    critical_threshold FLOAT NOT NULL DEFAULT 0.4,
    low_threshold FLOAT NOT NULL DEFAULT 1.0,
    logo_initials TEXT DEFAULT 'SP',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. TABLA: PRODUCTS (Maestro de Inventario con IA Predictiva)
CREATE TABLE IF NOT EXISTS public.products (
    id TEXT NOT NULL,
    user_id UUID REFERENCES auth.users NOT NULL,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    stock INTEGER NOT NULL DEFAULT 0,
    price NUMERIC(10,2) NOT NULL,
    min_stock INTEGER NOT NULL DEFAULT 20,
    target_stock INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    PRIMARY KEY (id, user_id)
);

-- 5. TABLA: ORDERS (Gestión de Comandas en Tiempo Real)
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users NOT NULL, -- Importante para multi-tenancy
    table_number TEXT NOT NULL,
    items JSONB NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'preparing', 'delivered', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. TABLA: AUDIT_LOG (Historial para el Motor de Pronósticos)
CREATE TABLE IF NOT EXISTS public.audit_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users NOT NULL,
    product_id TEXT NOT NULL,
    product_name TEXT NOT NULL,
    action TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('critical', 'warning', 'info', 'order_generated', 'ignored')),
    message TEXT NOT NULL,
    stock_level INTEGER,
    is_archived BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- 7. SEGURIDAD: HABILITAR RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- 8. POLÍTICAS DE AISLAMIENTO (Multi-Usuario)
-- Solo el dueño de la cuenta puede ver/editar sus datos

-- Business & Profiles
CREATE POLICY "RLS_Profiles_Own" ON public.profiles FOR ALL USING (auth.uid() = id);
CREATE POLICY "RLS_Business_Own" ON public.business_profile FOR ALL USING (auth.uid() = user_id);

-- Inventory (Products)
CREATE POLICY "RLS_Products_Own" ON public.products FOR ALL USING (auth.uid() = user_id);

-- Orders
CREATE POLICY "RLS_Orders_Own" ON public.orders FOR ALL USING (auth.uid() = user_id);

-- Logs
CREATE POLICY "RLS_Audit_Own" ON public.audit_log FOR ALL USING (auth.uid() = user_id);

-- 9. AUTOMATIZACIÓN: REGISTRO DE USUARIO (La Magia SaaS)
-- Crea automáticamente el perfil y negocio al registrarse en Auth de Supabase
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Perfil de Usuario
    INSERT INTO public.profiles (id, full_name, company_name, email)
    VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'company_name', NEW.email);

    -- Configuración SaaS de Negocio
    INSERT INTO public.business_profile (user_id, business_name, currency_symbol, email)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'company_name', 'Nuevo Negocio'), 'S/', NEW.email);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created_master ON auth.users;
CREATE TRIGGER on_auth_user_created_master
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 10. REALTIME CONFIGURATION
ALTER PUBLICATION supabase_realtime ADD TABLE orders;
ALTER PUBLICATION supabase_realtime ADD TABLE products;
ALTER PUBLICATION supabase_realtime ADD TABLE business_profile;
