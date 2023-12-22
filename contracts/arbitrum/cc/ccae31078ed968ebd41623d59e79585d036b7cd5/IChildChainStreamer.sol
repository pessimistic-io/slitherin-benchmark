// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IChildChainStreamer {
    struct RewardToken {
        address distributor;
        uint256 period_finish;
        uint256 rate;
        uint256 duration;
        uint256 received;
        uint256 paid;
    }

    function get_reward() external;
    function notify_reward_amount(address _token) external;
    function reward_data(address _token) external returns (RewardToken memory);
    function set_reward_distributor(address _token, address _distributor) external;
}

