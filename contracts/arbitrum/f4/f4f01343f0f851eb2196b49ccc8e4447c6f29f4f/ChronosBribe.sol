pragma solidity ^0.8.10;

interface Bribe {
    event Recovered(address token, uint256 amount);
    event RewardAdded(address rewardToken, uint256 reward, uint256 startTimestamp);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);
    event Staked(uint256 indexed tokenId, uint256 amount);
    event Withdrawn(uint256 indexed tokenId, uint256 amount);

    function TYPE() external view returns (string memory);
    function WEEK() external view returns (uint256);
    function _deposit(uint256 amount, uint256 tokenId) external;
    function _totalSupply(uint256) external view returns (uint256);
    function _withdraw(uint256 amount, uint256 tokenId) external;
    function addReward(address _rewardsToken) external;
    function addRewardToken(address _token) external;
    function balanceOf(uint256 tokenId) external view returns (uint256);
    function balanceOfAt(uint256 tokenId, uint256 _timestamp) external view returns (uint256);
    function bribeFactory() external view returns (address);
    function earned(uint256 tokenId, address _rewardToken) external view returns (uint256);
    function firstBribeTimestamp() external view returns (uint256);
    function getEpochStart() external view returns (uint256);
    function getNextEpochStart() external view returns (uint256);
    function getReward(uint256 tokenId, address[] memory tokens) external;
    function getRewardForOwner(uint256 tokenId, address[] memory tokens) external;
    function isRewardToken(address) external view returns (bool);
    function minter() external view returns (address);
    function notifyRewardAmount(address _rewardsToken, uint256 reward) external;
    function owner() external view returns (address);
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;
    function rewardData(address, uint256)
        external
        view
        returns (uint256 periodFinish, uint256 rewardsPerEpoch, uint256 lastUpdateTime);
    function rewardPerToken(address _rewardsToken, uint256 _timestmap) external view returns (uint256);
    function rewardTokens(uint256) external view returns (address);
    function rewardsListLength() external view returns (uint256);
    function setMinter(address _minter) external;
    function setOwner(address _owner) external;
    function setVoter(address _Voter) external;
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256 _timestamp) external view returns (uint256);
    function userRewardPerTokenPaid(uint256, address) external view returns (uint256);
    function userTimestamp(uint256, address) external view returns (uint256);
    function ve() external view returns (address);
    function voter() external view returns (address);
}

