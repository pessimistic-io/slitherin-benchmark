// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Contract imports
import { ERC721BaseInternal } from "./ERC721BaseInternal.sol";
import { ERC721EnumerableInternal } from "./ERC721EnumerableInternal.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

// Storage imports
import { WithModifiers } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";
import "./Constants.sol";

// Library imports
import { LibMagicRewardsUtils } from "./LibMagicRewardsUtils.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";

contract WLMagicRewardsFacet is WithModifiers, ERC721BaseInternal, ERC721EnumerableInternal, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event MagicRewardsToppedUp(address indexed account, uint256 amount);
    event MagicRewardsClaimed(address indexed account, uint256 indexed landId, uint256 claimable);

    /**
     * @dev Topup Magic rewards which will be divided over all Wastelands
     */
    function topupMagicRewards(uint256 amount) external {
        IERC20(ws().magic).safeTransferFrom(msg.sender, address(this), amount);
        ws().magicRewardsPerLand += amount / MAX_CAP_LAND;
        emit MagicRewardsToppedUp(msg.sender, amount);
    }

    /**
     * @dev Claim outstanding Magic rewards for a Wasteland
     */
    function claimMagicReward(uint256 landId) external notPaused nonReentrant {
        if (_ownerOf(landId) != msg.sender) revert Errors.NotOwnerOfLand();
        uint256 claimableReward = LibMagicRewardsUtils.claimableMagicReward(landId);
        if (claimableReward > 0) {
            ws().rewardsWithdrawnPerLand[landId] += claimableReward;
            IERC20(ws().magic).safeTransfer(msg.sender, claimableReward);
            emit MagicRewardsClaimed(msg.sender, landId, claimableReward);
        }
    }

    /**
     * @dev Claim all outstanding Magic rewards of the caller.
     */
    function claimAllMagicRewards() external notPaused nonReentrant {
        uint256 balance = _balanceOf(msg.sender);
        uint256 claimableReward;
        for (uint256 i = 0; i < balance; i++) {
            uint256 landId = _tokenOfOwnerByIndex(msg.sender, i);
            uint256 claimableForLand = LibMagicRewardsUtils.claimableMagicReward(landId);
            ws().rewardsWithdrawnPerLand[landId] += claimableForLand;
            claimableReward += claimableForLand;
            if (claimableForLand > 0) {
                emit MagicRewardsClaimed(msg.sender, landId, claimableForLand);
            }
        }
        if (claimableReward > 0) {
            IERC20(ws().magic).safeTransfer(msg.sender, claimableReward);
        }
    }

    /**
     * @dev Get the total claimable Magic rewards of the provided account
     */
    function totalClaimable(address account) external view returns(uint256 claimableReward) {
        uint256 balance = _balanceOf(account);
        for (uint256 i = 0; i < balance; i++) {
            uint256 landId = _tokenOfOwnerByIndex(account, i);
            uint256 claimableForLand = LibMagicRewardsUtils.claimableMagicReward(landId);
            claimableReward += claimableForLand;
        }
    }

    /**
     * @dev Get the claimable Magic rewards of the provided Wasteland
     */
    function claimable(uint256 landId) external view returns(uint256) {
        return LibMagicRewardsUtils.claimableMagicReward(landId);
    }

    /**
     * @dev Get the amount of claimed Magic for the provided Wasteland
     */
    function claimed(uint256 landId) external view returns(uint256) {
        return ws().rewardsWithdrawnPerLand[landId];
    }
}

