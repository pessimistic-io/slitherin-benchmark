// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IL2MetaCubeRule {

    struct TokenIdRule {
        uint8 level;
        uint256 startTokenId;
        uint256 endTokenId;
        uint256 tokenIdTotalSupply;
        uint256 awardAmount;
    }

    struct MergeRule {
        uint8 level;
        uint256 startRandomNum;
        uint256 endRandomNum;
    }

    function modNumber() external view returns (uint256);

    function getTokenIdRuleByLevel(uint8 level_) external pure returns (TokenIdRule memory);

    function getTokenIdRuleByTokenId(uint256 tokenId_) external pure returns (TokenIdRule memory);

    function getTokenIdRuleByUnicornLevelRandomNum(uint8 unicornLevel_, uint256 randomNum_) external pure returns (TokenIdRule memory);

    function getMergeRuleByUnicornLevelLevel(uint8 unicornLevel_, uint8 level_) external pure returns (MergeRule memory);

}

