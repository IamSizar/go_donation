-- 126 — Marketplace stock never moved on a purchase (client report,
-- 2026-09-22: "stock is 30, 12 are bought, stock stays 30 — it should
-- update automatically with every purchase").
--
-- WHY
-- CreateOrder (internal/marketplace/marketplace.go) checks stock_quantity
-- before inserting an order, but nothing anywhere ever wrote it back down —
-- grep the whole backend for an UPDATE of stock_quantity and there was none.
-- The check at purchase time was therefore reading a number that never
-- reflected what had actually sold, so it could not really prevent overselling
-- either.
--
-- WHY A TRIGGER AND NOT A GO-SIDE UPDATE IN ONE HANDLER
-- An order's status is writable from TWO places today:
--   * AdminStatusHandler.MarketplaceOrder (POST .../status), the dedicated
--     status-transition action;
--   * AdminEditHandler.MarketplaceOrder (PATCH .../marketplace_orders/:id),
--     the generic field editor, which can also set `status` directly.
-- Putting the stock adjustment in only one of those leaves the other a way to
-- move an order to 'completed' with no stock effect at all. A trigger on the
-- table itself fires no matter which code path — or a future one — changes
-- the row, and runs in the same transaction as the UPDATE that changed it.
--
-- THE RULE
-- Decrement stock_quantity by the order's quantity the moment status first
-- becomes 'completed' (delivered) from something else — not on every write
-- that merely re-saves 'completed', which is what a naive `NEW.status =
-- 'completed'` check would do on every unrelated PATCH to a completed order.
-- Symmetrically, put the quantity back if a 'completed' order is later moved
-- away from that status (a cancellation after delivery was recorded in
-- error). Every other transition is inventory-neutral. Untracked stock
-- (stock_quantity IS NULL, "don't count this product") is left alone in both
-- directions, matching the existing NULL = unlimited convention CreateOrder
-- already uses for the pre-purchase check.
CREATE OR REPLACE FUNCTION marketplace_order_stock_adjust() RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    UPDATE marketplace_products
       SET stock_quantity = stock_quantity - NEW.quantity
     WHERE id = NEW.product_id AND stock_quantity IS NOT NULL;
  ELSIF OLD.status = 'completed' AND NEW.status IS DISTINCT FROM 'completed' THEN
    UPDATE marketplace_products
       SET stock_quantity = stock_quantity + NEW.quantity
     WHERE id = NEW.product_id AND stock_quantity IS NOT NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_marketplace_order_stock_adjust
  AFTER UPDATE OF status ON marketplace_orders
  FOR EACH ROW
  WHEN (NEW.status IS DISTINCT FROM OLD.status)
  EXECUTE FUNCTION marketplace_order_stock_adjust();
