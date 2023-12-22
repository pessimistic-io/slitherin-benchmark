// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IVester {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Claim(address receiver, uint256 amount);
    event Deposit(address account, uint256 amount);
    event PairTransfer(address indexed from, address indexed to, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Withdraw(address account, uint256 claimedAmount, uint256 balance);

    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function balanceOf(address _account) external view returns (uint256);
    function balances(address) external view returns (uint256);
    function bonusRewards(address) external view returns (uint256);
    function claim() external returns (uint256);
    function claimForAccount(address _account, address _receiver) external returns (uint256);
    function claimable(address _account) external view returns (uint256);
    function claimableToken() external view returns (address);
    function claimedAmounts(address) external view returns (uint256);
    function cumulativeClaimAmounts(address) external view returns (uint256);
    function cumulativeRewardDeductions(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function deposit(uint256 _amount) external;
    function depositForAccount(address _account, uint256 _amount) external;
    function esToken() external view returns (address);
    function getCombinedAverageStakedAmount(address _account) external view returns (uint256);
    function getMaxVestableAmount(address _account) external view returns (uint256);
    function getPairAmount(address _account, uint256 _esAmount) external view returns (uint256);
    function getTotalVested(address _account) external view returns (uint256);
    function getVestedAmount(address _account) external view returns (uint256);
    function gov() external view returns (address);
    function hasMaxVestableAmount() external view returns (bool);
    function hasPairToken() external view returns (bool);
    function hasRewardTracker() external view returns (bool);
    function isHandler(address) external view returns (bool);
    function lastVestingTimes(address) external view returns (uint256);
    function name() external view returns (string memory);
    function pairAmounts(address) external view returns (uint256);
    function pairSupply() external view returns (uint256);
    function pairToken() external view returns (address);
    function rewardTracker() external view returns (address);
    function setBonusRewards(address _account, uint256 _amount) external;
    function setCumulativeRewardDeductions(address _account, uint256 _amount) external;
    function setGov(address _gov) external;
    function setHandler(address _handler, bool _isActive) external;
    function setHasMaxVestableAmount(bool _hasMaxVestableAmount) external;
    function setTransferredAverageStakedAmounts(address _account, uint256 _amount) external;
    function setTransferredCumulativeRewards(address _account, uint256 _amount) external;
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function transferStakeValues(address _sender, address _receiver) external;
    function transferredAverageStakedAmounts(address) external view returns (uint256);
    function transferredCumulativeRewards(address) external view returns (uint256);
    function vestingDuration() external view returns (uint256);
    function withdraw() external;
    function withdrawToken(address _token, address _account, uint256 _amount) external;
}

