// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

import {IL2MetaCubeRule} from "./IL2MetaCubeRule.sol";

contract L2MetaCubeRule is IL2MetaCubeRule, Ownable {

    uint256 public modNumber;

    constructor() {
        modNumber = 10000000;
    }

    function setModNumber() external onlyOwner {
        modNumber = modNumber;
    }

    function getTokenIdRuleNone() public pure returns (TokenIdRule memory) {
        return TokenIdRule(0, 0, 0, 0, 0);
    }

    /**
    * @param level_ Meta Cube Level
    */
    function getTokenIdRuleByLevel(uint8 level_) public pure returns (TokenIdRule memory) {
        //level,startTokenId,endTokenId,tokenIdTotalSupply,awardAmount
        if (level_ == 0) {
            return TokenIdRule(0, 1000000000, 3999999999, 3000000000, 0);
        } else if (level_ == 1) {
            return TokenIdRule(1, 100000000, 399999999, 300000000, 100);
        } else if (level_ == 2) {
            return TokenIdRule(2, 10000000, 39999999, 30000000, 1000);
        } else if (level_ == 3) {
            return TokenIdRule(3, 1000000, 3999999, 3000000, 10000);
        } else if (level_ == 4) {
            return TokenIdRule(4, 100000, 399999, 300000, 100000);
        } else if (level_ == 5) {
            return TokenIdRule(5, 10000, 39999, 30000, 1000000);
        } else if (level_ == 6) {
            return TokenIdRule(6, 1000, 3999, 3000, 10000000);
        } else {
            return getTokenIdRuleNone();
        }
    }

    /**
    * @param tokenId_ TokenId
    */
    function getTokenIdRuleByTokenId(uint256 tokenId_) external pure returns (TokenIdRule memory) {
        for (uint8 level_ = 0; level_ <= 9;) {
            TokenIdRule memory tokenIdRule = getTokenIdRuleByLevel(level_);
            if (tokenId_ >= tokenIdRule.startTokenId && tokenId_ <= tokenIdRule.endTokenId) {
                return tokenIdRule;
            }
            unchecked{++level_;}
        }
        return getTokenIdRuleNone();
    }

    /**
    * @param unicornLevel_ Unicorn Level
    * @param randomNum_ Random number
    */
    function getTokenIdRuleByUnicornLevelRandomNum(uint8 unicornLevel_, uint256 randomNum_) public pure returns (TokenIdRule memory) {
        for (uint8 level_ = 0; level_ <= 6;) {
            MergeRule memory mergeRule = getMergeRuleByUnicornLevelLevel(unicornLevel_, level_);
            if (randomNum_ >= mergeRule.startRandomNum && randomNum_ <= mergeRule.endRandomNum) {
                return getTokenIdRuleByLevel(mergeRule.level);
            }
            unchecked{++level_;}
        }
        return getTokenIdRuleNone();
    }

    /**
    * @param unicornLevel_ Unicorn Level
    * @param level_ Meta Cube Level
    */
    function getMergeRuleByUnicornLevelLevel(uint8 unicornLevel_, uint8 level_) public pure returns (MergeRule memory) {
        if (unicornLevel_ == 1) {
            if (level_ == 0) {
                return MergeRule(0, 0, 8375888);
            } else if (level_ == 1) {
                return MergeRule(1, 8375889, 9375888);
            } else if (level_ == 2) {
                return MergeRule(2, 9375889, 9975888);
            } else if (level_ == 3) {
                return MergeRule(3, 9975889, 9999888);
            } else if (level_ == 4) {
                return MergeRule(4, 9999889, 9999988);
            } else if (level_ == 5) {
                return MergeRule(5, 9999989, 9999998);
            } else if (level_ == 6) {
                return MergeRule(6, 9999999, 9999999);
            }
        } else if (unicornLevel_ == 2) {
            if (level_ == 0) {
                return MergeRule(0, 0, 6149888);
            } else if (level_ == 1) {
                return MergeRule(1, 6149889, 7149888);
            } else if (level_ == 2) {
                return MergeRule(2, 7149889, 9899888);
            } else if (level_ == 3) {
                return MergeRule(3, 9899889, 9999888);
            } else if (level_ == 4) {
                return MergeRule(4, 9999889, 9999988);
            } else if (level_ == 5) {
                return MergeRule(5, 9999989, 9999998);
            } else if (level_ == 6) {
                return MergeRule(6, 9999999, 9999999);
            }
        } else if (unicornLevel_ == 3) {
            if (level_ == 0) {
                return MergeRule(0, 0, 7193988);
            } else if (level_ == 1) {
                return MergeRule(1, 7193989, 8193988);
            } else if (level_ == 2) {
                return MergeRule(2, 8193989, 9193988);
            } else if (level_ == 3) {
                return MergeRule(3, 9193989, 9993988);
            } else if (level_ == 4) {
                return MergeRule(4, 9993989, 9999988);
            } else if (level_ == 5) {
                return MergeRule(5, 9999989, 9999998);
            } else if (level_ == 6) {
                return MergeRule(6, 9999999, 9999999);
            }
        } else if (unicornLevel_ == 4) {
            if (level_ == 0) {
                return MergeRule(0, 0, 6376988);
            } else if (level_ == 1) {
                return MergeRule(1, 6376989, 7376988);
            } else if (level_ == 2) {
                return MergeRule(2, 7376989, 8376988);
            } else if (level_ == 3) {
                return MergeRule(3, 8376989, 9976988);
            } else if (level_ == 4) {
                return MergeRule(4, 9976989, 9999988);
            } else if (level_ == 5) {
                return MergeRule(5, 9999989, 9999998);
            } else if (level_ == 6) {
                return MergeRule(6, 9999999, 9999999);
            }
        } else if (unicornLevel_ == 5) {
            if (level_ == 0) {
                return MergeRule(0, 0, 6193998);
            } else if (level_ == 1) {
                return MergeRule(1, 6193999, 7193998);
            } else if (level_ == 2) {
                return MergeRule(2, 7193999, 8193998);
            } else if (level_ == 3) {
                return MergeRule(3, 8193999, 9193998);
            } else if (level_ == 4) {
                return MergeRule(4, 9193999, 9993998);
            } else if (level_ == 5) {
                return MergeRule(5, 9993999, 9999998);
            } else if (level_ == 6) {
                return MergeRule(6, 9999999, 9999999);
            }
        } else if (unicornLevel_ == 6) {
            if (level_ == 0) {
                return MergeRule(0, 0, 5469998);
            } else if (level_ == 1) {
                return MergeRule(1, 5469999, 6469998);
            } else if (level_ == 2) {
                return MergeRule(2, 6469999, 7469998);
            } else if (level_ == 3) {
                return MergeRule(3, 7469999, 8469998);
            } else if (level_ == 4) {
                return MergeRule(4, 8469999, 9969998);
            } else if (level_ == 5) {
                return MergeRule(5, 9969999, 9999998);
            } else if (level_ == 6) {
                return MergeRule(6, 9999999, 9999999);
            }
        }
        return MergeRule(0, 0, 0);
    }

    /**
    * @param unicornLevel_ Unicorn Level
    */
    /*function getMergeRuleByUnicornLevel(uint8 unicornLevel_) public pure returns (MergeRule[] memory mergeRules) {
        if (unicornLevel_ >= 1 && unicornLevel_ <= 6) {
            mergeRules = new MergeRule[](6);
            if (unicornLevel_ == 1) {
                mergeRules[0] = MergeRule(0, 0, 8375888);
                mergeRules[1] = MergeRule(1, 8375889, 9375888);
                mergeRules[2] = MergeRule(2, 9375889, 9975888);
                mergeRules[3] = MergeRule(3, 9975889, 9999888);
                mergeRules[4] = MergeRule(4, 9999889, 9999988);
                mergeRules[5] = MergeRule(5, 9999989, 9999998);
                mergeRules[6] = MergeRule(6, 9999999, 9999999);
            } else if (unicornLevel_ == 2) {
                mergeRules[0] = MergeRule(0, 0, 6149888);
                mergeRules[1] = MergeRule(1, 6149889, 7149888);
                mergeRules[2] = MergeRule(2, 7149889, 9899888);
                mergeRules[3] = MergeRule(3, 9899889, 9999888);
                mergeRules[4] = MergeRule(4, 9999889, 9999988);
                mergeRules[5] = MergeRule(5, 9999989, 9999998);
                mergeRules[6] = MergeRule(6, 9999999, 9999999);
            } else if (unicornLevel_ == 3) {
                mergeRules[0] = MergeRule(0, 0, 7193988);
                mergeRules[1] = MergeRule(1, 7193989, 8193988);
                mergeRules[2] = MergeRule(2, 8193989, 9193988);
                mergeRules[3] = MergeRule(3, 9193989, 9993988);
                mergeRules[4] = MergeRule(4, 9993989, 9999988);
                mergeRules[5] = MergeRule(5, 9999989, 9999998);
                mergeRules[6] = MergeRule(6, 9999999, 9999999);
            } else if (unicornLevel_ == 4) {
                mergeRules[0] = MergeRule(0, 0, 6376988);
                mergeRules[1] = MergeRule(1, 6376989, 7376988);
                mergeRules[2] = MergeRule(2, 7376989, 8376988);
                mergeRules[3] = MergeRule(3, 8376989, 9976988);
                mergeRules[4] = MergeRule(4, 9976989, 9999988);
                mergeRules[5] = MergeRule(5, 9999989, 9999998);
                mergeRules[6] = MergeRule(6, 9999999, 9999999);
            } else if (unicornLevel_ == 5) {
                mergeRules[0] = MergeRule(0, 0, 6193998);
                mergeRules[1] = MergeRule(1, 6193999, 7193998);
                mergeRules[2] = MergeRule(2, 7193999, 8193998);
                mergeRules[3] = MergeRule(3, 8193999, 9193998);
                mergeRules[4] = MergeRule(4, 9193999, 9993998);
                mergeRules[5] = MergeRule(5, 9993999, 9999998);
                mergeRules[6] = MergeRule(6, 9999999, 9999999);
            } else if (unicornLevel_ == 6) {
                mergeRules[0] = MergeRule(0, 0, 5469998);
                mergeRules[1] = MergeRule(1, 5469999, 6469998);
                mergeRules[2] = MergeRule(2, 6469999, 7469998);
                mergeRules[3] = MergeRule(3, 7469999, 8469998);
                mergeRules[4] = MergeRule(4, 8469999, 9969998);
                mergeRules[5] = MergeRule(5, 9969999, 9999998);
                mergeRules[6] = MergeRule(6, 9999999, 9999999);
            }
        } else {
            mergeRules = new MergeRule[](0);
        }
        return mergeRules;
    }*/

}

