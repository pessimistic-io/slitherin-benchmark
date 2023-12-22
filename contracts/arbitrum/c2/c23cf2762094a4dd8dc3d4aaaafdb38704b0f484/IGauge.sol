// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGauge {
    function deposit(uint amount) external;

    function withdraw(uint amount) external;

    function claim_rewards() external;

    function claimable_reward_write(address _addr, address _token) external returns (uint);

    function claimable_reward(address _user, address _reward_token) external view returns (uint);

    function claimed_reward(address _addr, address _token) external view returns (uint);
    
    function balanceOf(address account) external view returns (uint);

    function claimable_tokens(address addr) external returns (uint);
}

