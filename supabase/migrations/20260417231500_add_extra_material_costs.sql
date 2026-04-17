
ALTER TABLE public.costs 
ADD COLUMN transport_cost DECIMAL(12,2) DEFAULT 0,
ADD COLUMN labor_cost DECIMAL(12,2) DEFAULT 0;

COMMENT ON COLUMN public.costs.transport_cost IS 'Extra transport cost specifically tied to a material entry';
COMMENT ON COLUMN public.costs.labor_cost IS 'Extra labor/handling cost specifically tied to a material entry';
