-- Seed data for products table (runs on first container startup)
-- The table is auto-created by Hibernate, but this INSERT uses IF NOT EXISTS logic

-- Wait for Hibernate to create the table on first app boot, so we use a simpler approach:
-- We create the table here as well so seed data is available immediately.

CREATE TABLE IF NOT EXISTS products (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    original_price DOUBLE PRECISION NOT NULL,
    sale_price DOUBLE PRECISION NOT NULL,
    stock_quantity INT NOT NULL,
    category VARCHAR(100),
    is_flash_sale BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO products (name, description, original_price, sale_price, stock_quantity, category, is_flash_sale) VALUES
('iPhone 15 Pro', '256GB, Natural Titanium', 1199.99, 899.99, 50, 'Electronics', true),
('Sony WH-1000XM5', 'Wireless Noise Cancelling Headphones', 399.99, 249.99, 200, 'Electronics', true),
('Nike Air Max 90', 'Classic running shoe, White/Black', 130.00, 79.99, 500, 'Footwear', true),
('Samsung 65" OLED TV', '4K Smart TV with Alexa Built-in', 1799.99, 1199.99, 30, 'Electronics', true),
('Dyson V15 Detect', 'Cordless Vacuum Cleaner', 749.99, 499.99, 100, 'Home Appliances', true),
('Instant Pot Duo 7-in-1', 'Electric Pressure Cooker 6 Qt', 89.99, 49.99, 300, 'Kitchen', false),
('Apple Watch Series 9', 'GPS 45mm, Midnight Aluminum', 429.99, 329.99, 150, 'Wearables', true),
('Levi''s 501 Original Jeans', 'Men''s Classic Fit, Dark Wash', 69.50, 39.99, 400, 'Clothing', false),
('Kindle Paperwhite', '16GB, 6.8" display, adjustable warm light', 139.99, 94.99, 250, 'Electronics', true),
('Lodge Cast Iron Skillet', '12-inch Pre-Seasoned', 44.99, 24.99, 600, 'Kitchen', false);

-- Create the external_order_log table for external workflow results
CREATE TABLE IF NOT EXISTS external_order_log (
    id BIGSERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    requested_quantity INT NOT NULL,
    unit_price DOUBLE PRECISION NOT NULL,
    total_price DOUBLE PRECISION NOT NULL,
    status VARCHAR(50) NOT NULL,
    processed_at TIMESTAMP DEFAULT NOW()
);
