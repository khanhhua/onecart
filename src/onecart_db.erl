%%%-------------------------------------------------------------------
%%% @author khanhhua
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Feb 2018 10:10 PM
%%%-------------------------------------------------------------------
-module(onecart_db).
-author("khanhhua").

-behaviour(gen_server).
-include("records.hrl").
%% API
-export([start_link/0]).
-export([
  create_app/2,
  app_exists/1,
  get_app/1,
  find_app/1,
  app_authorize/2,
  create_product/1,
  get_product/1,
  get_products/2,
  update_product/1,
  get_order/1,
  get_order/2,
  get_orders/2,
  create_cart/1,
  get_cart/1,
  update_cart/2,
  remove_cart_item/3,
  create_order/2,
  update_order/2,
  next_ref_no/1]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(CART_TABLE, 'tbl_cart').

-record(state, {hashids_ctx}).

%%%===================================================================
%%% API
%%%===================================================================

create_app(OwnerID, HashedPass) ->
  gen_server:call(?SERVER, {create_app, OwnerID, HashedPass}).
get_app(AppID) ->
  gen_server:call(?SERVER, {get_app, AppID}).
app_exists(AppID) ->
  gen_server:call(?SERVER, {app_exists, AppID}).
find_app([{ownerid, OwnerID}]) ->
  gen_server:call(?SERVER, {find_app, [{ownerid, OwnerID}]}).
app_authorize(AppID, HashedPass) ->
  gen_server:call(?SERVER, {app_authorize, AppID, HashedPass}).

create_product(Product) ->
  gen_server:call(?SERVER, {create_product, Product}).

get_product(ProductID) ->
  gen_server:call(?SERVER, {get_product, ProductID}).

update_product(Product) ->
  gen_server:call(?SERVER, {update_product, Product}).

get_products(AppID, Params) ->
  gen_server:call(?SERVER, {get_products, AppID, Params}).

get_order(AppID, {transactionid, TxID}) ->
  gen_server:call(?SERVER, {get_order, AppID, {transactionid, TxID}}).

get_order(OrderID) ->
  gen_server:call(?SERVER, {get_order, OrderID}).

get_orders(AppID, Params) -> {ok, []}.

%%--------------------------------------------------------------------
%% @doc
%% Create a new cart
%%
%% @end
%%--------------------------------------------------------------------
-spec(create_cart(AppID :: term()) ->
  {ok, CartID :: term()} | {error, Reason :: term()}).
create_cart(AppID) ->
  gen_server:call(?SERVER, {create_cart, AppID}).

get_cart(CartID) ->
  gen_server:call(?SERVER, {get_cart, CartID}).

remove_cart_item(AppID, CartID, ProductID) ->
  gen_server:call(?SERVER, {remove_cart_item, AppID, CartID, ProductID}).

update_cart(CartID, ItemsToUpdate) ->
  gen_server:call(?SERVER, {update_cart, CartID, ItemsToUpdate}).

create_order(AppID, Items) ->
  gen_server:call(?SERVER, {create_order, AppID, Items}).

update_order(AppID, OrderID) ->
  gen_server:call(?SERVER, {update_order, AppID, OrderID}).

next_ref_no(AppID) ->
  gen_server:call(?SERVER, {next_ref_no, AppID}).
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  io:format("Initializing onecart_db...~n"),

  {ok, DataDir} = application:get_env(onecart, data_dir),

  {ok, app} = dets:open_file(app, [
    {keypos, #app.id},
    {file, filename:join(DataDir, "apps.dat")}
  ]),
  {ok, app_stats} = dets:open_file(app_stats, [
    {keypos, #app_stats.id},
    {file, filename:join(DataDir, "app_stats.dat")}
  ]),
  {ok, app_auth} = dets:open_file(app_auth, [
    {keypos, #app_auth.id},
    {file, filename:join(DataDir, "app_auth.dat")}
  ]),
  {ok, cart} = dets:open_file(cart, [
    {keypos, #cart.appid_id},
    {file, filename:join(DataDir, "cart.dat")}
  ]),
  {ok, order} = dets:open_file(order, [
    {keypos, #order.appid_id},
    {file, filename:join(DataDir, "orders.dat")}
  ]),
  {ok, product} = dets:open_file(product, [
    {keypos, #product.appid_id},
    {file, filename:join(DataDir, "products.dat")}
  ]),

  {ok, HashidsSalt} = application:get_env(onecart, hashids_salt),
  HashidsContext = hashids:new([{salt, HashidsSalt},
                                {min_hash_length, 8},
                                {default_alphabet, "abcdefghijklmnopqrstuvwxxyz0123456789"}]),

  quickrand:seed(),

  {ok, #state{hashids_ctx = HashidsContext}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call({create_app, App, HashedPass}, _From, State) ->
  HashidsContext = State#state.hashids_ctx,
  AppID = list_to_binary(hashids:encode(HashidsContext, erlang:system_time())),

  case dets:insert_new(app, App#app{id = AppID}) of
    true ->
      dets:insert(app_auth, #app_auth{id = AppID, passwd = HashedPass}),
      case dets:insert_new(app_stats, #app_stats{id = AppID}) of
        true -> {reply, {ok, AppID}, State};
        {error, Reason} -> {reply, {error, Reason}, State}
      end;
    {error, Reason} -> {reply, {error, Reason}, State}
  end;
handle_call({get_app, AppID}, _From, State) ->
  case dets:lookup(app, AppID) of
    [App] -> {reply, {ok, App}, State};
    Anything ->
      io:format("Anything: ~p", [Anything]),
      {reply, {error, "Could not find app"}, State}
  end;
handle_call({app_exists, AppID}, _From, State) ->
  io:format("Looking up AppID: ~p...~n=>~p~n", [AppID, dets:lookup(app, AppID)]),
  case dets:lookup(app, AppID) of
    [_] -> {reply, true, State};
    _ -> {reply, false, State}
  end;
handle_call({find_app, [{ownerid, OwnerID}]}, _From, State) ->
  case dets:match_object(app, #app{id = '$1', paypal_merchant_id = '$2', ownerid = OwnerID}) of
    Apps -> {reply, {ok, Apps}, State}
  end;
handle_call({app_authorize, AppID, HashedPass}, _From, State) ->
  io:format("Authorize as owner of AppID: ~p, hashed pass: ~p...~n", [AppID, HashedPass]),
  case dets:lookup(app_auth, AppID) of
    [App] -> case App#app_auth.passwd of
               HashedPass -> {reply, {ok, owner}, State};
               _ -> {reply, {error, permission}, State}
             end;
    _ -> {reply, {error, permission}, State}
  end;

handle_call({create_cart, AppID}, _From, State) ->
  CartID = rand:uniform(1000000),

  case dets:insert_new(cart, #cart{appid_id = ?TO_APPID_ID(AppID, CartID), items = []}) of
    true -> {reply, {ok, CartID}, State};
    {error, Reason} -> {reply, {error, Reason}, State}
  end;
handle_call({get_cart, CartID}, _From, State) ->
  case dets:lookup(cart, CartID) of
    [Cart] -> {reply, {ok, Cart}, State};
    Anything ->
      io:format("Anything: ~p", [Anything]),
      {reply, {error, "Could not find cart"}, State}
  end;
handle_call({update_cart, CartID, ItemsToUpdate}, _From, State) ->
  AppID = ?TO_APPID(CartID),
  case dets:lookup(cart, CartID) of
    [Cart] ->
      ItemsToUpdateWithName = lists:map(
        fun (It) ->
          [#product{name = ProductName, price = ProductPrice}] = dets:lookup(product, ?TO_APPID_ID(AppID, It#order_item.productid)),
          It#order_item{productname = ProductName, price = ProductPrice}
        end, ItemsToUpdate),

      UpdatedCart = Cart#cart{items = lists:ukeymerge(#order_item.productid, ItemsToUpdateWithName, Cart#cart.items)},
      case dets:insert(cart, UpdatedCart) of
        ok -> {reply, {ok, UpdatedCart}, State};
        {error, Reason} -> {reply, {error, Reason}, State}
      end;
    Anything ->
      io:format("Error: ~p", [Anything]),
      {reply, {error, "Could not find cart"}, State}
  end;
handle_call({remove_cart_item, AppID, CartID, ProductID}, _From, State) ->
  case dets:lookup(cart, ?TO_APPID_ID(AppID, CartID)) of
    [Cart] ->
      ItemsToUpdateWithName = lists:filter(
        fun (It) -> It#order_item.productid =/= ProductID
        end, Cart#cart.items),

      UpdatedCart = Cart#cart{items = ItemsToUpdateWithName},
      case dets:insert(cart, UpdatedCart) of
        ok -> {reply, {ok, UpdatedCart}, State};
        {error, Reason} -> {reply, {error, Reason}, State}
      end;
    Anything ->
      io:format("Error: ~p", [Anything]),
      {reply, {error, "Could not find cart"}, State}
  end;
handle_call({create_product, Product}, _From, State) when is_record(Product, product) ->
  case dets:insert_new(product, Product) of
    true -> {reply, {ok, Product}, State};
    {error, Reason} -> {reply, {error, Reason}, State}
  end;
handle_call({get_product, ProductID}, _From, State) ->
  case dets:lookup(product, ProductID) of
    [Product] -> {reply, {ok, Product}, State};
    Anything ->
      io:format("Error: ~p", [Anything]),
      {reply, {error, "Could not find product"}, State}
  end;
handle_call({get_products, AppID, Params}, _From, State) ->
  case dets:match_object(product, #product{appid_id = ?TO_APPID_ID(AppID, '_'), name = '$2', price = '$3'}) of
    {error, Reason} ->
      io:format("Error: ~p", [Reason]),
      {reply, {error, "Could not find product"}, State};
    Products -> {reply, {ok, Products}, State}
  end;
handle_call({update_product, UpdatedProduct = #product{appid_id = ProductID}}, _From, State) ->
  case dets:lookup(product, ProductID) of
    {error, Reason} ->
      io:format("Error: ~p", [Reason]),
      {reply, {error, "Could not find product"}, State};
    [Product] when Product#product.appid_id =:= ProductID ->
      %% Merge
      Updated = ?MERGE_RECORD(product, Product, UpdatedProduct),

      case dets:insert(product, Updated) of
        ok -> {reply, {ok, Updated}, State};
        Anything ->
          io:format("Error: ~p", [Anything]),
          {reply, {error, "Could not update product"}, State}
      end;
    Anything ->
      io:format("Error: ~p", [Anything]),
      {reply, {error, "Could not find product"}, State}
  end;
handle_call({create_order, AppID, Items}, _From, State) ->
  OrderID = list_to_binary(uuid:uuid_to_string(uuid:get_v4())),
  Total = lists:foldl(
    fun (Item, Acc) ->
      io:format("Qty: ~p x Price: ~p", [Item#order_item.qty, Item#order_item.price]),
      Acc + Item#order_item.qty * Item#order_item.price end,
    0.0, Items),
  Order = #order{appid_id = ?TO_APPID_ID(AppID, OrderID), items = Items, total = Total},
  case dets:insert_new(order, Order) of
    true -> {reply, {ok, Order}, State};
    {error, Reason} -> {reply, {error, Reason}, State}
  end;
handle_call({update_order, AppID, UpdatedOrder = #order{appid_id = OrderID}}, _From, State) ->
  case dets:lookup(order, OrderID) of
    [#order{appid_id = OrderID}] ->
      case dets:insert(order, UpdatedOrder) of
        ok -> {reply, {ok, UpdatedOrder}, State};
        {error, Reason} -> {reply, {error, Reason}, State}
      end;
    Anything ->
      io:format("Error: ~p", [Anything]),
      {reply, {error, "Could not find order"}, State}
  end;
handle_call({get_order, AppID, {transactionid, TxID}}, _From, State) ->
  case dets:match_object(order,
    #order{
      transactionid = TxID,
      appid_id = ?TO_APPID_ID(AppID, '_'),
      refno = '$2',
      status = '$3',
      total = '$4',
      items = '$5'
    }) of
    [Order] -> {reply, {ok, Order}, State};
    {error, Reason} -> {reply, {error, Reason}, State}
  end;
handle_call({get_order, OrderID}, _From, State) ->
  case dets:lookup(order, OrderID) of
    [Order] -> {reply, {ok, Order}, State};
    {error, Reason} -> {reply, {error, Reason}, State}
  end;
handle_call({next_ref_no, AppID}, _From, State) ->
  %% Note: next vs last depends on how you see it
  %% "last" from db's point of view
  %% "next" from manager's point of view
  case dets:lookup(app_stats, AppID) of
    [AppStats] ->
      NextRefNo = if
        AppStats#app_stats.last_order_no =:= undefined -> generate_next_ref_no();
        true -> generate_next_ref_no(AppStats#app_stats.last_order_no)
      end,

      ok = dets:insert(app_stats, AppStats#app_stats{last_order_no = NextRefNo}),
      {reply, {ok, NextRefNo}, State};
    {error, Reason} -> {reply, {error, Reason}, State}
  end;
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  dets:close(app),
  dets:close(app_stats),
  dets:close(cart),
  dets:close(product),
  dets:close(orders),
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

generate_next_ref_no() ->
  {{Y,M,_}, _} = calendar:local_time(),
  {Y,M,1}.
generate_next_ref_no(RefNo) ->
  {Y0,M0,Current} = RefNo,
  {{Y,M,_}, _} = calendar:local_time(),

  if
    (Y0 =:= Y) and (M0 =:= M) -> {Y,M,Current + 1};
    true -> {Y,M,1}
  end.
