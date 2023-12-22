pragma solidity =0.8.8;

interface IStableJoeStaking {
    event ClaimReward(address indexed user, address indexed rewardToken, uint256 amount);
    event Deposit(address indexed user, uint256 amount, uint256 fee);
    event DepositFeeChanged(uint256 newFee, uint256 oldFee);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RewardTokenAdded(address token);
    event RewardTokenRemoved(address token);
    event Withdraw(address indexed user, uint256 amount);

    function deposit(uint256 _amount) external;

    function emergencyWithdraw() external;

    function withdraw(uint256 _amount) external;

    function ACC_REWARD_PER_SHARE_PRECISION() external view returns (uint256);

    function DEPOSIT_FEE_PERCENT_PRECISION() external view returns (uint256);

    function accRewardPerShare(address) external view returns (uint256);

    function addRewardToken(address _rewardToken) external;

    function depositFeePercent() external view returns (uint256);

    function feeCollector() external view returns (address);

    function getUserInfo(address _user, address _rewardToken) external view returns (uint256, uint256);

    function initialize(address _rewardToken, address _joe, address _feeCollector, uint256 _depositFeePercent)
        external;

    function internalJoeBalance() external view returns (uint256);

    function isRewardToken(address) external view returns (bool);

    function joe() external view returns (address);

    function lastRewardBalance(address) external view returns (uint256);

    function owner() external view returns (address);

    function pendingReward(address _user, address _token) external view returns (uint256);

    function removeRewardToken(address _rewardToken) external;

    function renounceOwnership() external;

    function rewardTokens(uint256) external view returns (address);

    function rewardTokensLength() external view returns (uint256);

    function setDepositFeePercent(uint256 _depositFeePercent) external;

    function transferOwnership(address newOwner) external;

    function updateReward(address _token) external;
}

