// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ERC1155Holder } from "./ERC1155Holder.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Multicall } from "./Multicall.sol";
import { IERC1155Supply } from "./IERC1155Supply.sol";
import { GlobalConstants } from "./Constants.sol";

interface IToggleGovernance {
    function hasEnoughOpenGovernToggles(uint256 requiredStake) external view returns (bool);
}

error InsufficientStakeAmount();

contract ToggleGovernance is ERC1155Holder, IToggleGovernance, ReentrancyGuard, Multicall {
    IERC1155Supply public immutable governanceToken;
    uint256 public immutable governanceTokenId;

    mapping(address => uint256) public stakers;
    uint256 public stakedAmount;

    event Stake(address indexed staker, uint256 indexed amount);
    event Unstake(address indexed staker, uint256 indexed amount);

    constructor(IERC1155Supply _governanceToken, uint256 _governanceTokenId) {
        governanceToken = _governanceToken;
        governanceTokenId = _governanceTokenId;
    }

    function stake(uint256 amount) external nonReentrant {
        stakers[msg.sender] += amount;
        stakedAmount += amount;
        governanceToken.safeTransferFrom(msg.sender, address(this), governanceTokenId, amount, "");
        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (stakers[msg.sender] < amount) revert InsufficientStakeAmount();
        stakers[msg.sender] -= amount;
        stakedAmount -= amount;
        governanceToken.safeTransferFrom(address(this), msg.sender, governanceTokenId, amount, "");
        emit Unstake(msg.sender, amount);
    }

    function hasEnoughOpenGovernToggles(uint256 requiredOpenToggles) external view override returns (bool) {
        // staked   = "closed" toggles
        // unstaked = "open" toggles
        // inital   = all of "open" toggles
        return GlobalConstants.MAX_CHAPTER_COUNT - stakedAmount >= requiredOpenToggles;
    }
}

