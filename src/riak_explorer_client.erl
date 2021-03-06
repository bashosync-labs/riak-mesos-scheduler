
-module(riak_explorer_client).

-export([node_key_from_cluster/1,
         node_name_to_key/1,
         get_node_info/1,
         apply_command/2,
         apply_command/3]).

-export([clusters/1,
         aae_status/2,
         status/2,
         ringready/2,
         transfers/2,
         bucket_types/2,
         bucket_type/3,
         create_bucket_type/4,
         join/3,
         leave/3
        ]).

%%% Utility

-spec node_key_from_cluster(string()) -> {error, not_found} | string().
node_key_from_cluster(ClusterKey) ->
    case rms_node_manager:get_running_node_keys(ClusterKey) of
        [N|_] ->
            N;
        _ ->
            {error, not_found}
    end.

-spec node_name_to_key(string()) -> {error, not_found} | string().
node_name_to_key(NodeName) ->
    case string:tokens(NodeName, "@") of
        [N|_] ->
            N;
        _ ->
            {error, not_found}
    end.

-spec get_node_info(string()) -> {error, not_found} | [binary()].
get_node_info(NodeKey) ->
    case {rms_node_manager:get_node_http_url(NodeKey),
          rms_node_manager:get_node_name(NodeKey)} of
        {{ok,U},{ok,N}} when
              is_list(U) and is_list(N) ->
            [list_to_binary(U), list_to_binary(N)];
        _ ->
            {error, not_found}
    end.

-spec apply_command(string(), atom()) -> {error, not_found} | [binary()].
apply_command(NodeKey, Command) ->
    apply_command(NodeKey, Command, []).

-spec apply_command(string(), atom(), [term()]) -> {error, not_found} | [binary()].
apply_command(NodeKey, Command, Args) ->
    case get_node_info(NodeKey) of
        {error, not_found} ->
            {error, not_found};
        [H, N] ->
            erlang:apply(?MODULE, Command, [H, N | Args])
    end.

%%% Client functions

%% @doc Gets cluster / node info from Explorer.
-spec clusters(binary()) ->
    {ok, binary()} | {error, term()}.
clusters(Host) ->
    ReqUri = <<"explore/clusters">>,
    do_get(Host, ReqUri).

%% @doc Gets AAE status for a node from Explorer.
-spec aae_status(binary(), binary()) ->
    {ok, binary()} | {error, term()}.
aae_status(Host, Node) ->
    ReqUri = <<"control/nodes/", Node/binary, "/aae-status">>,
    do_get(Host, ReqUri).

%% @doc Gets status for a node from Explorer.
-spec status(binary(), binary()) ->
    {ok, binary()} | {error, term()}.
status(Host, Node) ->
    ReqUri = <<"control/nodes/", Node/binary, "/status">>,
    do_get(Host, ReqUri).

%% @doc Gets status for a node from Explorer.
-spec ringready(binary(), binary()) ->
    {ok, binary()} | {error, term()}.
ringready(Host, Node) ->
    ReqUri = <<"control/nodes/", Node/binary, "/ringready">>,
    do_get(Host, ReqUri).

%% @doc Gets status for a node from Explorer.
-spec transfers(binary(), binary()) ->
    {ok, binary()} | {error, term()}.
transfers(Host, Node) ->
    ReqUri = <<"control/nodes/", Node/binary, "/transfers">>,
    do_get(Host, ReqUri).

%% @doc Gets status for a node from Explorer.
-spec bucket_types(binary(), binary()) ->
    {ok, binary()} | {error, term()}.
bucket_types(Host, Node) ->
    ReqUri = <<"explore/nodes/", Node/binary, "/bucket_types">>,
    do_get(Host, ReqUri).

%% @doc Get a bucket type from Explorer.
-spec bucket_type(binary(), binary(), binary()) ->
    {ok, binary()} | {error, term()}.
bucket_type(Host, Node, Type) ->
    ReqUri = <<"explore/nodes/", Node/binary, "/bucket_type/", Type/binary>>,
    do_get(Host, ReqUri).

%% @doc Gets status for a node from Explorer.
-spec create_bucket_type(binary(), binary(), binary(), binary()) ->
    {ok, binary()} | {error, term()}.
create_bucket_type(Host, Node, Type, Props) ->
    ReqUri = <<"explore/nodes/", Node/binary, "/bucket_types/", Type/binary>>,
    do_put(Host, ReqUri, Props).

%% @doc Gets status for a node from Explorer.
-spec join(binary(), binary(), binary()) ->
    {ok, binary()} | {error, term()}.
join(Host, FromNode, ToNode) ->
    ReqUri = <<"control/nodes/", FromNode/binary, "/join/", ToNode/binary>>,
    do_get(Host, ReqUri).

%% @doc Gets status for a node from Explorer.
-spec leave(binary(), binary(), binary()) ->
    {ok, binary()} | {error, term()}.
leave(Host, StayingNode, LeavingNode) ->
    ReqUri = <<"control/nodes/", StayingNode/binary, "/leave/", LeavingNode/binary>>,
    do_get(Host, ReqUri).

%% @doc Returns request options.
%% @private
-spec request_options() -> [{atom(), term()}].
request_options() ->
    [{connect_timeout,30000},{recv_timeout,30000}].

%% @doc Returns request url.
%% @private
-spec request_url(binary(), binary()) -> binary().
request_url(Host, Uri) ->
    <<"http://", Host/binary, "/admin/", Uri/binary>>.

%% @doc Returns request headers.
%% @private
-spec request_headers(binary()) -> erl_mesos_http:headers().
request_headers(ContentType) ->
    [{<<"Content-Type">>, ContentType},
     {<<"Accept">>, ContentType},
     {<<"Connection">>, <<"close">>}].

%% @doc Sends http request.
-spec request(atom(), binary(), [{binary(), binary()}], binary(), [{atom(), term()}]) ->
    {ok, hackney:client_ref()} | {ok, non_neg_integer(), [{binary(), binary()}], hackney:client_ref()} |
    {error, term()}.
request(Method, Url, Headers, Body, Options) ->
    hackney:request(Method, Url, Headers, Body, Options).

%% @doc Perform get and return body.
%% @private
-spec do_get(binary(), binary()) ->
    {ok, binary()} | {error, term()}.
do_get(Host, Uri) ->
    ReqUrl = request_url(Host, Uri),
    ReqHeaders = request_headers(<<"application/json">>),
    ReqBody = <<>>,
    ReqOptions = request_options(),
    lager:info("Riak Explorer GET: ~p", [ReqUrl]),
    Response = case request(get, ReqUrl, ReqHeaders, ReqBody, ReqOptions) of
        {ok, Ref} ->
            body(Ref);
        {ok, _Code, _Headers, Ref} ->
            body(Ref);
        {error, Reason} ->
            {error, Reason}
    end,
    lager:info("Riak Explorer GET Response: ~p", [Response]),
    case Response of
        {ok, Bin} ->
            try_decode_json(Bin);
        {error, Reason1} ->
            {error, Reason1}
    end.

%% @doc Perform get and return body.
%% @private
-spec do_put(binary(), binary(), binary()) ->
    {ok, binary()} | {error, term()}.
do_put(Host, Uri, Data) ->
    ReqUrl = request_url(Host, Uri),
    ReqHeaders = request_headers(<<"application/json">>),
    ReqOptions = request_options(),
    lager:info("Riak Explorer PUT: ~p, Data: ~p", [ReqUrl, Data]),
    Response = case request(put, ReqUrl, ReqHeaders, Data, ReqOptions) of
        {ok, Ref} ->
            body(Ref);
        {ok, _Code, _Headers, Ref} ->
            body(Ref);
        {error, _}=Error ->
            Error
    end,
    lager:info("Riak Explorer PUT Response: ~p", [Response]),
    case Response of
        {ok, Bin} ->
            try_decode_json(Bin);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Receives http request body.
%% @private
-spec body(hackney:client_ref()) -> {ok, binary()} | {error, term()}.
body(Ref) ->
    hackney:body(Ref).

-spec try_decode_json(binary()) -> {ok, binary()} | {ok, [{binary(), term()}]}.
try_decode_json(Bin) ->
    try
        {ok, mochijson2:decode(Bin, [{format, proplist}])}
    catch
        _Exception:_Reason ->
            {ok, Bin}
    end.
