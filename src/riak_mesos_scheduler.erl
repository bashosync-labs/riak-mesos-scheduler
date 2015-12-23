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

-module(riak_mesos_scheduler).

-behaviour(erl_mesos_scheduler).

-include_lib("erl_mesos/include/erl_mesos.hrl").

-export([init/1,
         registered/3,
         reregistered/2,
         disconnected/2,
         resource_offers/3,
         offer_rescinded/3,
         status_update/3,
         slave_lost/3,
         executor_lost/3,
         error/3,
         handle_info/3,
         terminate/3]).

-record(state, {offer_mode = accept :: accept | reconcile | decline}).

%%%===================================================================
%%% Callbacks
%%%===================================================================

init(Options) ->
    FrameworkInfo = framework_info(),
    lager:info("Options: ~p", [Options]),
    lager:info("FrameworkInfo: ~p", [FrameworkInfo]),
    %% We should always start up in reconcile mode to ensure that
    %% we have the latest update information before acting on offers.
    {ok, FrameworkInfo, true, #state{offer_mode = reconcile}}.

registered(_SchedulerInfo, #event_subscribed{} = EventSubscribed, State) ->
    lager:info("Registered: ~p", [EventSubscribed]),
    {ok, State}.

reregistered(SchedulerInfo, State) ->
    lager:info("Reregistered: ~p", [SchedulerInfo]),
    {ok, State}.

disconnected(SchedulerInfo, State) ->
    lager:warning("Disconnected: ~p", [SchedulerInfo]),
    {ok, State}.

resource_offers(SchedulerInfo, #event_offers{offers = Offers},
                State=#state{offer_mode=reconcile}) ->
    lager:info("Resource Offers: Offer mode: ~p", [State#state.offer_mode]),
    %% Reconcile
    TaskId = #task_id{value = <<"3">>},
    CallReconcileTask = #call_reconcile_task{task_id = TaskId},
    CallReconcile = #call_reconcile{tasks = [CallReconcileTask]},
    ok = erl_mesos_scheduler:reconcile(SchedulerInfo, CallReconcile),
    %% Decline this offer
    OfferIds = lists:map(fun(#offer{id = OfferId}) -> OfferId end, Offers),
    CallAccept = #call_accept{offer_ids = OfferIds, operations = []},
    ok = erl_mesos_scheduler:accept(SchedulerInfo, CallAccept),
    {ok, State#state{offer_mode = accept}};
resource_offers(SchedulerInfo, #event_offers{offers = Offers} = EventOffers,
                State=#state{offer_mode=accept}) ->
    lager:info("Resource Offers: ~p", [EventOffers]),
    lager:info("Offer mode: ~p", [State#state.offer_mode]),

    HandleOfferFun = fun(#offer{id = OfferId, agent_id = AgentId}, {OfferIds, Operations, OfferNum}) ->
        TaskIdValue = list_to_binary(binary_to_list(AgentId#agent_id.value) ++ "-" ++ integer_to_list(OfferNum)),
        TaskId = #task_id{value = TaskIdValue},

        CommandValue = <<"while true; do echo 'Test task is running...'; sleep 1; done">>,
        CommandInfo = #command_info{shell = true,
                                    value = CommandValue},
        CpuScalarValue = #value_scalar{value = 0.1},
        ResourceCpu = #resource{name = <<"cpus">>,
                                type = <<"SCALAR">>,
                                scalar = CpuScalarValue},
        TaskInfo = #task_info{name = <<"test_task">>,
                              task_id = TaskId,
                              agent_id = AgentId,
                              command = CommandInfo,
                              resources = [ResourceCpu]},
        Launch = #offer_operation_launch{task_infos = [TaskInfo]},
        OfferOperation = #offer_operation{type = <<"LAUNCH">>,
                                          launch = Launch},
        {[OfferId|OfferIds], [OfferOperation|Operations], OfferNum + 1}
    end,

    {OfferIds, Operations, _} = lists:foldl(HandleOfferFun, {[],[], 1}, Offers),
    CallAccept = #call_accept{offer_ids = OfferIds,
                              operations = Operations},

    lager:info("Call Accept: ~p", [CallAccept]),

    ok = erl_mesos_scheduler:accept(SchedulerInfo, CallAccept),
    %% TODO: Manually returing to decline mode for now, but needs to be based on
    %% whether or not we have nodes to launch eventually.
    {ok, State#state{offer_mode = decline}};
resource_offers(SchedulerInfo, #event_offers{offers = Offers},
                State=#state{offer_mode=decline}) ->
    lager:info("Resource Offers: Offer mode: ~p", [State#state.offer_mode]),
    OfferIds = lists:map(fun(#offer{id = OfferId}) -> OfferId end, Offers),
    CallAccept = #call_accept{offer_ids = OfferIds, operations = []},
    ok = erl_mesos_scheduler:accept(SchedulerInfo, CallAccept),
    {ok, State}.

offer_rescinded(_SchedulerInfo, #event_rescind{} = EventRescind, State) ->
    lager:info("Offer Rescinded: ~p", [EventRescind]),
    {ok, State}.

status_update(_SchedulerInfo, #event_update{} = EventUpdate, State) ->
    lager:info("Status Update: ~p", [EventUpdate]),
    {ok, State}.

slave_lost(_SchedulerInfo, #event_failure{} = EventFailure, State) ->
    lager:info("Slave Lost: ~p", [EventFailure]),
    {ok, State}.

executor_lost(_SchedulerInfo, #event_failure{} = EventFailure, State) ->
    lager:info("Executor Lost: ~p", [EventFailure]),
    {ok, State}.

error(_SchedulerInfo, #event_error{} = EventError, State) ->
    lager:info("Error: ~p", [EventError]),
    {stop, State}.

handle_info(SchedulerInfo, stop, State) ->
    lager:info("Handle Info: Stop: ~p", [SchedulerInfo]),
    {stop, State};
handle_info(_SchedulerInfo, Info, State) ->
    lager:info("Handle Info: Undefined: ~p", [Info]),
    {ok, State}.

terminate(_SchedulerInfo, Reason, _State) ->
    lager:warning("Terminate: ~p", [Reason]),
    ok.

%% ====================================================================
%% Private
%% ====================================================================

framework_info() ->
    User = riak_mesos_scheduler_config:get_value(user, <<"root">>, binary),
    Name = riak_mesos_scheduler_config:get_value(name, <<"riak">>, binary),
    Role = riak_mesos_scheduler_config:get_value(role, <<"riak">>, binary),
    Hostname = riak_mesos_scheduler_config:get_value(hostname, undefined, binary),
    Principal = riak_mesos_scheduler_config:get_value(principal, <<"riak">>, binary),

    #framework_info{user = User,
                    name = Name,
                    role = Role,
                    hostname = Hostname,
                    principal = Principal,
                    checkpoint = undefined, %% TODO: We will want to enable checkpointing
                    id = undefined, %% TODO: Will need to check ZK for this for reregistration
                    webui_url = undefined, %% TODO: Get this from webmachine helper probably
                    failover_timeout = undefined, %% TODO: Add this to configurable options
                    capabilities = undefined,
                    labels = undefined}.
