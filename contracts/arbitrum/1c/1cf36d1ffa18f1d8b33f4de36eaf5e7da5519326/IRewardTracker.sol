// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IRewardTracker {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Claim(address receiver, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function BASIS_POINTS_DIVISOR() external view returns (uint256);
    function PRECISION() external view returns (uint256);
    function allowance(address _owner, address _spender) external view returns (uint256);
    function allowances(address, address) external view returns (uint256);
    function approve(address _spender, uint256 _amount) external returns (bool);
    function averageStakedAmounts(address) external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function balances(address) external view returns (uint256);
    function claim(address _receiver) external returns (uint256);
    function claimForAccount(address _account, address _receiver) external returns (uint256);
    function claimable(address _account) external view returns (uint256);
    function claimableReward(address) external view returns (uint256);
    function cumulativeRewardPerToken() external view returns (uint256);
    function cumulativeRewards(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function depositBalances(address, address) external view returns (uint256);
    function distributor() external view returns (address);
    function gov() external view returns (address);
    function inPrivateClaimingMode() external view returns (bool);
    function inPrivateStakingMode() external view returns (bool);
    function inPrivateTransferMode() external view returns (bool);
    function initialize(address[] memory _depositTokens, address _distributor) external;
    function isDepositToken(address) external view returns (bool);
    function isHandler(address) external view returns (bool);
    function isInitialized() external view returns (bool);
    function name() external view returns (string memory);
    function previousCumulatedRewardPerToken(address) external view returns (uint256);
    function rewardToken() external view returns (address);
    function setDepositToken(address _depositToken, bool _isDepositToken) external;
    function setGov(address _gov) external;
    function setHandler(address _handler, bool _isActive) external;
    function setInPrivateClaimingMode(bool _inPrivateClaimingMode) external;
    function setInPrivateStakingMode(bool _inPrivateStakingMode) external;
    function setInPrivateTransferMode(bool _inPrivateTransferMode) external;
    function stake(address _depositToken, uint256 _amount) external;
    function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint256 _amount) external;
    function stakedAmounts(address) external view returns (uint256);
    function symbol() external view returns (string memory);
    function tokensPerInterval() external view returns (uint256);
    function totalDepositSupply(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);
    function unstake(address _depositToken, uint256 _amount) external;
    function unstakeForAccount(address _account, address _depositToken, uint256 _amount, address _receiver) external;
    function updateRewards() external;
    function withdrawToken(address _token, address _account, uint256 _amount) external;
}

