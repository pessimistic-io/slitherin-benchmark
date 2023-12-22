// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";

import {IL2Unicorn} from "./IL2Unicorn.sol";
import {IL2UnicornRule} from "./IL2UnicornRule.sol";
import {IL2MetaCube} from "./IL2MetaCube.sol";
import {IL2MetaCubeRule} from "./IL2MetaCubeRule.sol";

import {BaseL2Unicorn} from "./BaseL2Unicorn.sol";
import {BaseL2UnicornRule} from "./BaseL2UnicornRule.sol";
import {BaseL2MetaCube} from "./BaseL2MetaCube.sol";
import {BaseL2MetaCubeRule} from "./BaseL2MetaCubeRule.sol";
import {RewardsManager} from "./RewardsManager.sol";

contract L2NonFungibleTokenResolver is BaseL2Unicorn, BaseL2UnicornRule, BaseL2MetaCube, BaseL2MetaCubeRule, RewardsManager {

    event Resolve (
        address indexed user,
        address collection,
        uint8 level,
        uint256 tokenId,
        uint256 awardAmount
    );

    constructor(address l2Unicorn_, address l2UnicornRule_, address l2MetaCube_, address l2MetaCubeRule_, address rewardsToken_)
        BaseL2Unicorn(l2Unicorn_)
        BaseL2UnicornRule(l2UnicornRule_)
        BaseL2MetaCube(l2MetaCube_)
        BaseL2MetaCubeRule(l2MetaCubeRule_)
        RewardsManager(rewardsToken_, 0) {}

    function resolveL2Unicorn(uint256[] calldata tokenIdArr) external {
        uint256 length = tokenIdArr.length;
        uint256 totalAwardAmount;
        for (uint256 i_ = 0; i_ < length;) {
            uint256 tokenId_ = tokenIdArr[i_];
            require(_msgSender() == IERC721(l2Unicorn).ownerOf(tokenId_), "L2NonFungibleTokenResolver: incorrect owner");
            IL2UnicornRule.HatchRule memory hatchRule = IL2UnicornRule(l2UnicornRule).getHatchRuleByTokenId(tokenId_);
            uint256 awardAmount_ = hatchRule.awardAmount;
            require(awardAmount_ > 0, "L2NonFungibleTokenResolver: award amount is zero");
            totalAwardAmount += awardAmount_;
            emit Resolve(_msgSender(), l2Unicorn, hatchRule.level, tokenId_, awardAmount_);
            unchecked{++i_;}
        }
        IL2Unicorn(l2Unicorn).batchBurn(tokenIdArr);
        if (totalAwardAmount > 0) {
            IERC20(rewardsToken).transfer(_msgSender(), totalAwardAmount * 1e18);
        }
    }

    function resolveL2MetaCube(uint256[] calldata tokenIdArr) external {
        uint256 length = tokenIdArr.length;
        uint256 totalAwardAmount;
        for (uint256 i_ = 0; i_ < length;) {
            uint256 tokenId_ = tokenIdArr[i_];
            require(_msgSender() == IERC721(l2MetaCube).ownerOf(tokenId_), "L2NonFungibleTokenResolver: incorrect owner");
            IL2MetaCubeRule.TokenIdRule memory tokenIdRule = IL2MetaCubeRule(l2MetaCubeRule).getTokenIdRuleByTokenId(tokenId_);
            uint256 awardAmount_ = tokenIdRule.awardAmount;
            require(awardAmount_ > 0, "L2NonFungibleTokenResolver: award amount is zero");
            totalAwardAmount += awardAmount_;
            emit Resolve(_msgSender(), l2MetaCube, tokenIdRule.level, tokenId_, awardAmount_);
            unchecked{++i_;}
        }
        IL2MetaCube(l2MetaCube).batchBurn(tokenIdArr);
        if (totalAwardAmount > 0) {
            IERC20(rewardsToken).transfer(_msgSender(), totalAwardAmount * 1e18);
        }
    }

}

