%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Basho Technologies Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(rms_node).

-behaviour(gen_server).

-export([start_link/2]).

-export([get_cluster_key/1,
         get_hostname/1,
         get_agent_id_value/1,
         get_persistence_id/1,
         set_reservation/4,
         needs_to_be_reconciled/1,
         can_be_scheduled/1,
         has_reservation/1,
         set_unreserve/1,
         delete/1]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(node, {key :: key(),
               status = requested :: status(),
               cluster_key :: rms_cluster:key(),
               node_name = "" :: string(),
               hostname = "" :: string(),
               http_port :: pos_integer(),
               pb_port :: pos_integer(),
               disterl_port :: pos_integer(),
               agent_id_value = "" :: string(),
               container_path = "" :: string(),
               persistence_id = "" :: string()}).

-type key() :: string().
-export_type([key/0]).

-type status() :: undefined | %% Possible status for waiting reconciliation.
                  requested |
                  reserved |
                  starting |
                  started |
                  shutting_down |
                  shutdown |
                  failed |
                  restarting.
-export_type([status/0]).

-type node_state() :: #node{}.
-export_type([node_state/0]).

%% External functions.

-spec start_link(key(), rms_cluster:key()) ->
    {ok, pid()} | {error, term()}.
start_link(Key, ClusterKey) ->
    gen_server:start_link(?MODULE, {Key, ClusterKey}, []).

-spec get_cluster_key(key()) -> {ok, rms_cluster:key()} | {error, term()}.
get_cluster_key(Key) ->
    case get_node(Key) of
        {ok, #node{cluster_key = ClusterKey}} ->
            {ok, ClusterKey};
        {error, Reason} ->
            {error, Reason}
    end.

-spec get_hostname(key()) -> {ok, string()} | {error, term()}.
get_hostname(Key) ->
    case get_node(Key) of
        {ok, #node{hostname = Hostname}} ->
            {ok, Hostname};
        {error, Reason} ->
            {error, Reason}
    end.

-spec get_agent_id_value(key()) -> {ok, string()} | {error, term()}.
get_agent_id_value(Key) ->
    case get_node(Key) of
        {ok, #node{agent_id_value = AgentIdValue}} ->
            {ok, AgentIdValue};
        {error, Reason} ->
            {error, Reason}
    end.

-spec needs_to_be_reconciled(key()) -> {ok, boolean()} | {error, term()}.
needs_to_be_reconciled(Key) ->
    case get_node(Key) of
        {ok, #node{status = Status}} ->
            %% Basic simple solution.
            %% TODO: implement "needs to be reconciled" logic here.
            NeedsReconciliation = Status =:= undefined,
            {ok, NeedsReconciliation};
        {error, Reason} ->
            {error, Reason}
    end.

-spec can_be_scheduled(key()) -> {ok, boolean()} | {error, term()}.
can_be_scheduled(Key) ->
    case get_node(Key) of
        {ok, #node{status = Status}} ->
            %% Basic simple solution.
            %% TODO: implement "can be scheduled" logic here.
            CanBeScheduled = Status =:= requested,
            {ok, CanBeScheduled};
        {error, Reason} ->
            {error, Reason}
    end.

-spec has_reservation(key()) -> {ok, boolean()} | {error, term()}.
has_reservation(Key) ->
    case get_node(Key) of
        {ok, #node{persistence_id = PersistenceId}} ->
            HasReservation = PersistenceId =/= "",
            {ok, HasReservation};
        {error, Reason} ->
            {error, Reason}
    end.

-spec get_persistence_id(key()) -> {ok, string()} | {error, term()}.
get_persistence_id(Key) ->
    case get_node(Key) of
        {ok, #node{persistence_id = PersistenceId}} ->
            {ok, PersistenceId};
        {error, Reason} ->
            {stop, Reason}
    end.

-spec set_reservation(pid(), string(), string(), string()) ->
    ok | {error, term()}.
set_reservation(Pid, Hostname, AgentIdValue, PersistenceId) ->
    gen_server:call(Pid, {set_reservation, Hostname, AgentIdValue,
                          PersistenceId}).

-spec set_unreserve(pid()) -> ok | {error, term()}.
set_unreserve(_Pid) ->
    %% TODO: implement unreserve here via sync call to the node process.
    ok.

-spec delete(pid()) -> ok | {error, term()}.
delete(Pid) ->
    gen_server:call(Pid, delete).

%% gen_server callback functions.

init({Key, ClusterKey}) ->
    case get_node(Key) of
        {ok, Node} ->
            {ok, Node};
        {error, not_found} ->
            Node = #node{key = Key,
                         cluster_key = ClusterKey},
            case add_node(Node) of
                ok ->
                    {ok, Node};
                {error, Reason} ->
                    {stop, Reason}
            end
    end.

handle_call({set_reservation, Hostname, AgentIdValue, PersistenceId}, _From,
            Node) ->
    Node1 = Node#node{status = reserved,
                      hostname = Hostname,
                      agent_id_value = AgentIdValue,
                      persistence_id = PersistenceId},
    update_node_state(Node, Node1);
handle_call(delete, _From, Node) ->
    Node1 = Node#node{status = shutting_down},
    update_node_state(Node, Node1);
handle_call(_Request, _From, State) ->
    {noreply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Request, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.

%% Internal functions.

-spec get_node(key()) -> {ok, node_state()} | {error, term()}.
get_node(Key) ->
    case rms_metadata:get_node(Key) of
        {ok, Node} ->
            {ok, from_list(Node)};
        {error, Reason} ->
            {error, Reason}
    end.

-spec add_node(node_state()) -> ok | {error, term()}.
add_node(Node) ->
    rms_metadata:add_node(to_list(Node)).

-spec update_node_state(node_state(), node_state()) ->
    {reply, ok | {error, term()}, node_state()}.
update_node_state(#node{key = Key} = Node, NewNode) ->
    case update_node(Key, NewNode) of
        ok ->
            {reply, ok, NewNode};
        {error, Reason} ->
            {reply, {error, Reason}, Node}
    end.

-spec update_node(key(), node_state()) -> ok | {error, term()}.
update_node(Key, Node) ->
    rms_metadata:update_node(Key, to_list(Node)).

-spec from_list(rms_metadata:node_state()) -> node_state().
from_list(NodeList) ->
    #node{key = proplists:get_value(key, NodeList),
          status = proplists:get_value(status, NodeList),
          cluster_key = proplists:get_value(cluster_key, NodeList),
          node_name = proplists:get_value(node_name, NodeList),
          hostname = proplists:get_value(hostname, NodeList),
          http_port = proplists:get_value(http_port, NodeList),
          pb_port = proplists:get_value(pb_port, NodeList),
          disterl_port = proplists:get_value(disterl_port, NodeList),
          agent_id_value = proplists:get_value(agent_id_value, NodeList),
          container_path = proplists:get_value(container_path, NodeList),
          persistence_id = proplists:get_value(persistence_id, NodeList)}.

-spec to_list(node_state()) -> rms_metadata:node_state().
to_list(#node{key = Key,
              status = Status,
              cluster_key = ClusterKey,
              node_name = NodeName,
              hostname = Hostname,
              http_port = HttpPort,
              pb_port = PbPort,
              disterl_port = DisterlPort,
              agent_id_value = AgentIdValue,
              container_path = ContainerPath,
              persistence_id = PersistenceId}) ->
    [{key, Key},
     {status, Status},
     {cluster_key, ClusterKey},
     {node_name, NodeName},
     {hostname, Hostname},
     {http_port, HttpPort},
     {pb_port, PbPort},
     {disterl_port, DisterlPort},
     {agent_id_value, AgentIdValue},
     {container_path, ContainerPath},
     {persistence_id, PersistenceId}].
