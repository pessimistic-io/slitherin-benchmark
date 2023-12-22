// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC721} from "./IERC721.sol";
import {IERC20} from "./IERC20.sol";

import {IRecipient} from "./IRecipient.sol";

import {RewardsManager} from "./RewardsManager.sol";

import {ILiquidityStakingRewards} from "./ILiquidityStakingRewards.sol";
import {LiquidityStakingRewards} from "./LiquidityStakingRewards.sol";

contract LiquidityStakingRewardsManager is RewardsManager {

    struct LiquidityStakingRewardsInfo {
        uint256 tokenId;
        address liquidityStakingRewards;
    }

    address public immutable positionManagerAddress;

    address public immutable WETH9;

    uint256[] private _allLiquidityTokenIds;

    mapping(uint256 => address) private _liquidityStakingRewardsMapping;

    constructor(address positionManagerAddress_, address WETH9_, address rewardsToken_) RewardsManager(rewardsToken_, 100e18) {
        positionManagerAddress = positionManagerAddress_;
        WETH9 = WETH9_;
    }

    function viewLiquidityStakingRewardsInfos(uint8 startIndex_, uint8 endIndex_) external view returns (LiquidityStakingRewardsInfo[] memory liquidityStakingRewardsInfos){
        if (startIndex_ >= 0 && endIndex_ >= startIndex_) {
            uint8 len = endIndex_ + 1 - startIndex_;
            uint256 total = _allLiquidityTokenIds.length;
            uint256 arrayLen = len > total ? total : len;
            liquidityStakingRewardsInfos = new LiquidityStakingRewardsInfo[](arrayLen);
            uint arrayIndex_ = 0;
            for (uint8 i_ = startIndex_; i_ < ((endIndex_ > total) ? total : endIndex_);) {
                uint256 tokenId_ = _allLiquidityTokenIds[i_];
                liquidityStakingRewardsInfos[arrayIndex_] = LiquidityStakingRewardsInfo({
                    tokenId : tokenId_,
                    liquidityStakingRewards : _liquidityStakingRewardsMapping[tokenId_]
                });
                unchecked{++i_; ++arrayIndex_;}
            }
        }
        return liquidityStakingRewardsInfos;
    }

    function createLiquidityStakingRewards(uint256 liquidityTokenId_, address recipient_) external onlyOwner {
        LiquidityStakingRewards liquidityStakingRewards = new LiquidityStakingRewards(positionManagerAddress, rewardsToken, WETH9, liquidityTokenId_, recipient_);
        IERC721(positionManagerAddress).safeTransferFrom(_msgSender(), address(liquidityStakingRewards), liquidityTokenId_);
        _liquidityStakingRewardsMapping[liquidityTokenId_] = address(liquidityStakingRewards);
        _allLiquidityTokenIds.push(liquidityTokenId_);
    }

    function distributionRewards(uint256 liquidityTokenId_, uint256 amount_, uint256 rewardsDuration_) external onlyOwner {
        address liquidityStakingRewards = _liquidityStakingRewardsMapping[liquidityTokenId_];
        require(liquidityStakingRewards != address(0), "LiquidityStakingRewardsManager: LiquidityStakingRewards is zero address");
        require(amount_ > 0, "LiquidityStakingRewardsManager: amount is zero");
        IERC20(rewardsToken).transfer(liquidityStakingRewards, amount_);
        ILiquidityStakingRewards(liquidityStakingRewards).notifyRewardAmount(amount_, rewardsDuration_);
    }

    function setRecipient(address liquidityStakingRewardsAddress_, address recipient_) external onlyOwner {
        IRecipient(liquidityStakingRewardsAddress_).setRecipient(recipient_);
    }

}

