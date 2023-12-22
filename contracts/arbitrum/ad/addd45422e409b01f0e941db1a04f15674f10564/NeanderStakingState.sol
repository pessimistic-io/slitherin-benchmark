//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC721Holder.sol";
import "./IERC721.sol";
import "./EnumerableSetUpgradeable.sol";

abstract contract NeanderStakingState is ERC721Holder {
    event NeanderStaked(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _lockTime,
        uint256 _stakeTime
    );
    event NeanderUnstaked(
        address indexed _owner,
        address indexed _neanderAddress,
        uint256 indexed _tokenId
    );
    event RewardClaimed(
        address indexed _owner,
        uint256 indexed _tokenId,
        uint256 indexed _rewardAmount
    );

    IERC721 public neanderSmols;
    address public bones;
    address public soul50;
    address public soul100;

    mapping(address => EnumerableSetUpgradeable.UintSet)
        internal userToTokensStaked;
    mapping(uint256 => address) public tokenIdToUser;

    mapping(uint256 => uint256) public tokenIdToStakeStartTime;
    mapping(uint256 => uint256) public tokenIdToLockDuration;
    mapping(uint256 => uint256) public tokenIdToLastRewardTime;

    mapping(uint256 => uint256) public daysLockedToReward;
    mapping(uint256 => bool) internal lockTimesAvailable;

    struct userInfo {
        uint256 tokenId;
        uint256 endTime;
        uint256 reward;
    }

    address public bonesStaking;

    modifier contractsAreSet() {
        require(
            address(neanderSmols) != address(0) &&
                bones != address(0) &&
                bonesStaking != address(0) &&
                soul50 != address(0) &&
                soul100 != address(0),
            "Contracts aren't set"
        );
        _;
    }
}

interface IBonesStaking {
    struct StakeDetails {
        uint256 amountStaked;
        uint256 startTime;
        uint256 lastRewardTime;
        uint256 tokenId;
    }

    function getStakes(
        address _user
    ) external view returns (StakeDetails[] memory);
}

interface IErc20 {
    function mint(address to, uint256 amount) external;
}

