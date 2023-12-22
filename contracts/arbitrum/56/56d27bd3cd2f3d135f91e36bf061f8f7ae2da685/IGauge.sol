// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

struct SupplyCheckpoint {
    uint timestamp;
    uint supply;
}

struct Checkpoint {
    uint timestamp;
    uint balanceOf;
}

interface IGauge {
    function getReward(address account, address[] memory tokens) external;
    function claimFees() external returns (uint claimed0, uint claimed1);
    function left(address token) external view returns (uint);
    function deposit(uint amount, uint tokenId) external;
    function withdrawAll() external;
    function withdraw(uint amount) external;
    function totalSupply() external view returns (uint);
    function earned(address token, address account) external view returns (uint);
    function getPriorBalanceIndex(address account, uint timestamp) external view returns (uint);
    function getPriorSupplyIndex(uint timestamp) external view returns (uint);
    function getPriorRewardPerToken(address token, uint timestamp) external view returns (uint, uint);
    function batchRewardPerToken(address token, uint maxRuns) external;
    function notifyRewardAmount(address token, uint amount) external;
    function supplyNumCheckpoints() external view returns (uint);
    function supplyCheckpoints(uint i) external view returns (SupplyCheckpoint memory);
    function checkpoints(address account, uint index) external view returns (Checkpoint memory);
    function numCheckpoints(address account) external view returns (uint);
    function swapOutReward(uint i, address oldToken, address newToken) external;


}
