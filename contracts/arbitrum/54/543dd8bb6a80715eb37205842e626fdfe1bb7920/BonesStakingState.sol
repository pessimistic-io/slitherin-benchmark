//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC721Upgradeable.sol";

abstract contract BonesStakingState {
    event BonesStaked(
        address indexed _owner,
        uint256 indexed _amount,
        uint256 indexed _stakeTime
    );
    event BonesUnstaked(address indexed _owner, uint256 indexed _amount);
    event RewardClaimed(
        address indexed _owner,
        uint256 indexed _rewardAmount,
        uint256 indexed _tokenId
    );
    event RewardBoosted(address indexed _owner, uint256 indexed _tokenId);

    IERC721Upgradeable public neanderSmols;
    address public bones;
    address public neanderStaking;
    address public treasury;

    uint256 public minStakeAmount;
    uint256 public reward;

    uint256 public boostPayment;
    uint256 public boostAmount;

    struct StakeDetails {
        uint256 amountStaked;
        uint256 startTime;
        uint256 lastRewardTime;
        uint256 tokenId;
    }

    mapping(address => StakeDetails[]) internal userToStakeDetails;

    bool public boostActive;

    modifier whenBoostActive() {
        require(boostActive, "Boost is not active");
        _;
    }

    modifier contractsAreSet() {
        require(
            address(neanderSmols) != address(0) &&
                bones != address(0) &&
                neanderStaking != address(0) &&
                treasury != address(0),
            "Contracts aren't set"
        );
        _;
    }
}

interface IBones {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface INeanderSmol {
    function updateCommonSense(uint256 _tokenId, uint256 amount) external;
}

interface INeanderStaking {
    function getUserFromToken(uint256 _tokenId) external view returns (address);
}

