%%%-------------------------------------------------------------------
%%% @author khanhhua
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Feb 2018 10:23 PM
%%%-------------------------------------------------------------------
-author("khanhhua").

-record(app, {id, ownerid, paypal_merchant_id}).
-record(product, {id, name, price}).
-record(cart, {id, appid, items = []}).
-record(order, {id, transactionid, items = [], total}).
-record(order_item, {productid, productname, qty, price}).
-record(payment, {paykey, status}).