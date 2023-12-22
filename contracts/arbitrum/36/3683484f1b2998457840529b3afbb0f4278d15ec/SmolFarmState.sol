//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./IERC721.sol";

import "./AdminableUpgradeable.sol";
import "./IRandomizer.sol";
import "./ISmolTreasures.sol";

abstract contract SmolFarmState is
    Initializable,
    AdminableUpgradeable,
    ERC721HolderUpgradeable
{
    event SmolStaked(
        address indexed _owner,
        address indexed _smolAddress,
        uint256 indexed _tokenId,
        uint256 _stakeTime
    );
    event SmolUnstaked(address indexed _owner, address indexed _smolAddress, uint256 indexed _tokenId);

    event StartClaiming(
        address indexed _owner,
        address indexed _smolAddress,
        uint256 indexed _tokenId,
        uint256 _requestId,
        uint256 _numberRewards
    );
    event RewardClaimed(
        address indexed _owner,
        address indexed _smolAddress,
        uint256 indexed _tokenId,
        uint256 _claimedRewardId,
        uint256 _amount
    );

    ISmolTreasures public treasures;
    IRandomizer public randomizer;
    IERC721 public smolBrains;
    IERC721 public smolBodies;
    IERC721 public smolLand;

    // collection address -> user address -> tokens staked for collection
    mapping(address => mapping(address => EnumerableSetUpgradeable.UintSet)) internal userToTokensStaked;

    // collection address -> tokenId -> info
    mapping(address => mapping(uint256 => uint256)) public tokenIdToStakeStartTime;
    mapping(address => mapping(uint256 => uint256)) public tokenIdToRewardsClaimed;
    mapping(address => mapping(uint256 => uint256)) public tokenIdToRequestId;
    mapping(address => mapping(uint256 => uint256)) public tokenIdToRewardsInProgress;

    uint256[] public rewardOptions;
    // Odds out of 100,000
    mapping(uint256 => uint32) public rewardIdToOdds;

    uint256 public _timeForReward;

    uint256 public _endEmissionTime;

    function __SmolFarmState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();

        _timeForReward = 1 days;
    }
}

