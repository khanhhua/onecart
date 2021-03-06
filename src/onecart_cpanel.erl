%%%-------------------------------------------------------------------
%%% @author khanhhua
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Feb 2018 9:15 PM
%%%-------------------------------------------------------------------
-module(onecart_cpanel).
-author("khanhhua").

-behavior(cowboy_handler).
-include("records.hrl").
%% API
-export([init/2, terminate/3]).
init(Req0, State = #{resource := apps, skey := _SKey, grecaptcha_secret := _GRecaptchaSecret }) ->
  resource_apps(Req0, State);
init(Req0, State = #{resource := 'public-enc-key'}) ->
  resource_public_enc_key(Req0, State);
init(Req0, State = #{resource := Resource, skey := SKey }) ->
  Authorization = cowboy_req:header(<<"authorization">>, Req0),
  io:format("Authorization: ~p~n",[Authorization]),
  <<"Bearer ", JwtToken/binary>> = Authorization,
  {ok, Claims} = jwt:decode(JwtToken, SKey),
  AppID = maps:get(<<"sub">>, Claims),
  io:format("AppID: ~p~n",[AppID]),
%% Guard against invalid App IDs
  {ok, Req, _State} = case onecart_db:app_exists(AppID) of
    true -> case Resource of
              product -> resource_product(Req0, State#{appid => AppID});
              products -> resource_products(Req0, State#{appid => AppID});
              orders -> resource_orders(Req0, State#{appid => AppID})
            end;
    false -> {ok, cowboy_req:reply(403, Req0), State}
  end,

  {ok, Req, State};
init(Req0, State = #{action := login}) ->
  action_login(Req0, State).

terminate(_Reason, _Req, _State) ->
  ok.

resource_apps(Req0=#{method := <<"POST">>}, State = #{skey := SKey, salt := Salt, grecaptcha_secret := GRecaptchaSecret}) ->
  Headers = #{<<"content-type">> => <<"application/json">>},
  {ok, Body, _} = cowboy_req:read_body(Req0),
  Data = jsx:decode(Body, [return_maps]),

  OwnerID = maps:get(<<"ownerid">>, Data),
  Recaptcha = maps:get(<<"recaptcha">>, Data),

  case verify_captcha(GRecaptchaSecret, Recaptcha) of
    false ->
      {ok, cowboy_req:reply(400,
        Headers,
        jsx:encode(#{<<"error">> => <<"Invalid captcha">>}),
        Req0), State};
    true ->
      App = #app{
        ownerid = OwnerID,
        paypal_merchant_id = maps:get(<<"paypal_merchant_id">>, Data, undefined)
      },
      io:format("Credentials (base64.enc): ~p~n", [Data]),
      EncPassword = base64:decode(maps:get(<<"password">>, Data)),
      io:format("Credentials (decoded enc): ~p~n", [EncPassword]),
      Password = decrypt(EncPassword, SKey),
      io:format("Credentials (decrypted pwd): ~p~n", [Password]),

      io:format("Salt: ~p~n", [Salt]),
      HashedPass = hash(Password, list_to_binary(Salt)), % persisted password :: sha256(sha1(raw), salt)
      io:format("Hashed pwd: ~p~n", [HashedPass]),

      case onecart_db:find_app([{ownerid, OwnerID}]) of
        {ok, []} -> case onecart_db:create_app(App, HashedPass) of
                      {ok, AppID} ->
                        io:format("Generated AppID: ~p~n", [AppID]),
                        sendmail(OwnerID, AppID),
                        {ok, cowboy_req:reply(201,
                          Headers,
                          jsx:encode(<<"ok">>),
                          Req0), State};
                      {error, Reason} ->
                        {ok, cowboy_req:reply(500,
                          Headers,
                          jsx:encode(#{<<"error">> => Reason}),
                          Req0), State}
                    end;
        {ok, Apps} when length(Apps) > 0 ->
          {ok, cowboy_req:reply(400,
            Headers,
            jsx:encode(#{<<"error">> => <<"App quota per account reached">>}),
            Req0), State};
        {error, Reason} ->
          {ok, cowboy_req:reply(500,
            Headers,
            jsx:encode(#{<<"error">> => Reason}),
            Req0), State}
      end
  end.

resource_public_enc_key(Req0 = #{method := <<"GET">>}, State = #{pkeyraw := PKeyRaw}) ->
  io:format("Retrieving PKey (public key)~n"),
  {ok, cowboy_req:reply(200, #{}, PKeyRaw, Req0), State}.

action_login(Req0 = #{method := <<"POST">>}, State = #{skey := SKey, salt := Salt}) ->
  {ok, Body, _Req0} = cowboy_req:read_body(Req0),
  Data = jsx:decode(Body, [return_maps]),
  AppID = maps:get(<<"appid">>, Data),

  io:format("Credentials (base64.enc): ~p~n", [Data]),
  EncPassword = base64:decode(maps:get(<<"password">>, Data)),
  io:format("Credentials (decoded enc): ~p~n", [EncPassword]),
  Password = decrypt(EncPassword, SKey),
  io:format("Credentials (decrypted pwd): ~p~n", [Password]),

  io:format("Salt: ~p~n", [Salt]),
  HashedPass = hash(Password, list_to_binary(Salt)), % persisted password :: sha256(sha1(raw), salt)
  io:format("Hashed pwd: ~p~n", [HashedPass]),

  Authed = case onecart_db:app_authorize(AppID, HashedPass) of
    {ok, owner} -> true;
    {error, permission} -> false
  end,

  if
    Authed =:= true ->
      ExpiryInSeconds = 3600,
      Claims = [
        {iss, <<"onecart">>},
        {aud, AppID},
        {sub, AppID},
        {iat, (os:system_time() div 1000000)}
      ],
      {ok, Token} = jwt:encode(<<"RS256">>, Claims, ExpiryInSeconds, SKey),
      erlang:display(Token),

      {ok, cowboy_req:reply(200, #{<<"Content-Type">> => <<"application/json">>}, jsx:encode(#{jwt => Token}), Req0), State};
    true ->
      {ok, cowboy_req:reply(403, Req0), State}
  end.

resource_product(Req0 = #{method := <<"GET">>}, State = #{appid := AppID}) ->
  Headers = #{<<"content-type">> => <<"application/json">>},

  ID = cowboy_req:binding(productid, Req0),
  ProductID = ?TO_APPID_ID(AppID, ID),
  {ok,Product} = onecart_db:get_product(ProductID),
  Req = cowboy_req:reply(200, Headers,
    jsx:encode(#{product => #{
      id => ?TO_ID(Product#product.appid_id),
      name => Product#product.name,
      price => Product#product.price
    }}), Req0),
  {ok, Req, State};
resource_product(Req0 = #{method := <<"PUT">>}, State = #{appid := AppID}) ->
  Headers = #{<<"content-type">> => <<"application/json">>},
  ID = cowboy_req:binding(productid, Req0),
  {ok, Body, _} = cowboy_req:read_body(Req0),
  JSON = jsx:decode(Body, [return_maps]),
  Data = maps:get(<<"product">>, JSON),
  ProductID = ?TO_APPID_ID(AppID, ID),
  Product = #product{
    appid_id = ProductID,
    name = maps:get(<<"name">>, Data),
    price = maps:get(<<"price">>, Data)
  },
  {ok, Updated} = onecart_db:update_product(Product),

  Req = cowboy_req:reply(200, Headers,
    jsx:encode(#{product => #{
      id => ?TO_ID(Updated#product.appid_id),
      name => Updated#product.name,
      price => Updated#product.price
    }}), Req0),
  {ok, Req, State}.

resource_products(Req0 = #{method := <<"POST">>}, State = #{appid := AppID}) ->
  Headers = #{<<"content-type">> => <<"application/json">>},
  {ok, Body, _} = cowboy_req:read_body(Req0),
  JSON = jsx:decode(Body, [return_maps]),
  Data = maps:get(<<"product">>, JSON),

  ProductID = ?TO_APPID_ID(AppID, maps:get(<<"id">>, Data)),
  Product = #product{
    appid_id = ProductID,
    name = maps:get(<<"name">>, Data),
    price = maps:get(<<"price">>, Data)
  },
  {ok, Product} = onecart_db:create_product(Product),

  Req = cowboy_req:reply(200, Headers,
    jsx:encode(#{product => #{
      id => ?TO_ID(Product#product.appid_id),
      name => Product#product.name,
      price => Product#product.price
    }}), Req0),
  {ok, Req, State};
resource_products(Req0, State = #{appid := AppID}) ->
  {ok, Products} = onecart_db:get_products(AppID, #{}),
  io:format("Products: ~p~n", [Products]),
  Req = cowboy_req:reply(200, #{
    <<"content-type">> => <<"application/json">>
  }, jsx:encode(#{products => lists:map(
    fun (It) ->
      #{
        id => ?TO_ID(It#product.appid_id),
        name => It#product.name,
        price => It#product.price
      }
    end, Products)
  }), Req0),
  {ok, Req, State}.

resource_orders(Req0 = #{method := <<"POST">>},
    State = #{
      appid := AppID,
      hashids_ctx := HashidsContext,
      pkey := PKey
    }) ->
  {ok, Body, _} = cowboy_req:read_body(Req0),
  Data = jsx:decode(Body, [return_maps]),
  Id = maps:get(<<"id">>, Data),

  case onecart_db:get_order(AppID, Id) of
    {ok, Order} ->
      TxID = list_to_binary(hashids:encode(HashidsContext, erlang:system_time())),
      {ok, RefNo} = onecart_db:next_ref_no(AppID),
      FormattedRefNo = iolist_to_binary(io_lib:format("~B~2..0B~6..0B", tuple_to_list(RefNo))),
      {ok, OrderUpdated} = onecart_db:update_order(AppID,
        Order#order{
          transactionid = TxID,
          refno = FormattedRefNo,
          status = pending
        }),
      io:format("Order transaction ID: ~p~n", [TxID]),

      {ok, CardID} = onecart_db:create_cart(AppID),
      EncCardID = encrypt(CardID, PKey),
      Req = cowboy_req:reply(200, #{
        <<"content-type">> => <<"application/json">>
      }, jsx:encode(
        #{
          <<"order">> => #{
            <<"id">> => ?TO_ID(Order#order.appid_id),
            <<"refno">> => OrderUpdated#order.refno
          },
          <<"next_cid">> => base64:encode(EncCardID)
        }), Req0),
      {ok, Req, State};
    {error, Reason} ->
      Req = cowboy_req:reply(400, #{
        <<"content-type">> => <<"application/json">>
      }, jsx:encode(list_to_binary(Reason)), Req0),
      {ok, Req, State}
  end;
resource_orders(Req0, State = #{appid := AppID}) ->
  {ok, Orders} = onecart_db:get_orders(AppID, #{}),

  Req = cowboy_req:reply(200, #{
    <<"content-type">> => <<"application/json">>
  }, jsx:encode(lists:map(
    fun (It) -> #{id => ?TO_ID(It#order.appid_id)} end,
    Orders)), Req0),
  {ok, Req, State}.
%%
%%
encrypt(Input, PKey) when is_integer(Input) ->
  public_key:encrypt_public(integer_to_binary(Input), PKey).

decrypt(Encrypted, SKey) ->
  public_key:decrypt_private(Encrypted, SKey).

hash(Input, Salt) ->
  <<X:256/big-unsigned-integer>> = crypto:hash(sha256, io_lib:format("~s:~s", [Salt, Input])),
  integer_to_list(X, 32).

verify_captcha(GRecaptchaSecret, Recaptcha) ->
  VerificationPayload = {form, [
    {secret, list_to_binary(GRecaptchaSecret)},
    {response, Recaptcha}
  ]},

  {ok, 200, _RespHeaders, ClientRef} = hackney:post(
    <<"https://www.google.com/recaptcha/api/siteverify">>,
    [{<<"Content-Type">>, <<"application/x-www-form-urlencoded">>}],
    VerificationPayload,
    [{ssl_options, [{versions, ['tlsv1']}]}]),

  {ok, Verification} = hackney:body(ClientRef),
  io:format("Verication: ~p~n", [Verification]),
  maps:get(<<"success">>, jsx:decode(Verification, [return_maps])).

sendmail(Email, AppID) ->
  {ok, APIKey} = application:get_env(onecart, sendgrid_apikey),
  {ok, Endpoint} = application:get_env(onecart, sendgrid_endpoint),

  Text = list_to_binary(io_lib:format("AppID: ~s", [AppID])),
  Payload = jsx:encode(#{
    personalizations => [
      #{to => [#{email => Email}]}
    ],
    from => #{email => <<"noreply@onecart.sg">>},
    subject => <<"Welcome to OneCart">>,
    content => [#{type => <<"text/plain">>, value => Text}]
  }),
  {ok, Status, _ResHeaders, _ClientRef} = hackney:post(
    Endpoint,
    [
      {<<"Content-Type">>, <<"application/json">>},
      {<<"Authorization">>, list_to_binary(io_lib:format("Bearer ~s", [APIKey]))}
    ],
    Payload, [{ssl_options, [{versions, ['tlsv1']}]}]),

  if
    Status =:= 202 -> ok;
    true -> error
  end.
