// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

interface ICurveGaugeManagerProxy
{
    function deploy_gauge(address _pool) external returns (address);
    function add_reward(address _gauge, address _reward_token, address _distributor) external;
    function set_reward_distributor(address _gauge, address _reward_token, address _distributor) external;
    function gauge_manager(address gauge) external view returns (address);
}
