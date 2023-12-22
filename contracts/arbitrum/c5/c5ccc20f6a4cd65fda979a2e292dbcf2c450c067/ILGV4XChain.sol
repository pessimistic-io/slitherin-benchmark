// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILGV4XChain {
    function deposit(uint256) external;

    function deposit(uint256, address) external;

    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256) external;

    function withdraw(uint256, address, bool) external;

    function reward_tokens(uint256) external view returns(address);

    function claim_rewards() external;

    function claim_rewards(address) external;

    function claim_rewards_for(address, address) external;

    function deposit_reward_token(address, uint256) external;

    function lp_token() external returns(address);

    function initialize(address, address, address, address, address, address) external;

    function set_claimer(address) external;

    function transfer_ownership(address) external; 

    function add_reward(address, address) external;

    function reward_count() external returns(uint256);

    function admin() external returns(address);

    function rewards_receiver(address) external returns(address);
}
