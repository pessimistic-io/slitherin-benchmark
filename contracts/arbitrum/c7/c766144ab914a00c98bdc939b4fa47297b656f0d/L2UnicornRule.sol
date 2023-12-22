// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "./Ownable.sol";

import {IL2UnicornRule} from "./IL2UnicornRule.sol";

contract L2UnicornRule is IL2UnicornRule, Ownable {

    uint256 public modNumber;

    constructor() {
        modNumber = 1000000;
    }

    function setModNumber() external onlyOwner {
        modNumber = modNumber;
    }

    function getHatchRuleNone() public pure returns (HatchRule memory) {
        return HatchRule(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    /**
    * @param level_ Level
    */
    function getHatchRuleByLevel(uint8 level_) public pure returns (HatchRule memory) {
        //startRandomNumE0,endRandomNumE0,startRandomNumE1,endRandomNumE1,startTokenId,endTokenId,tokenIdTotalSupply,awardAmount
        if (level_ == 0) {
            return HatchRule(0, 0, 615668, 0, 578668, 0, 728988, 1000000000000, 1299999999999, 300000000000, 0);
        } else if (level_ == 1) {
            return HatchRule(1, 615669, 965668, 578669, 778668, 0, 0, 100000000000, 129999999999, 30000000000, 50);
        } else if (level_ == 2) {
            return HatchRule(2, 965669, 995668, 778669, 978668, 0, 0, 10000000000, 19999999999, 10000000000, 200);
        } else if (level_ == 3) {
            return HatchRule(3, 995669, 998668, 978669, 998668, 0, 0, 1000000000, 3999999999, 3000000000, 500);
        } else if (level_ == 4) {
            return HatchRule(4, 998669, 999668, 998669, 999668, 728989, 928988, 100000000, 399999999, 300000000, 1000);
        } else if (level_ == 5) {
            return HatchRule(5, 999669, 999868, 999669, 999868, 928989, 988988, 10000000, 39999999, 30000000, 5000);
        } else if (level_ == 6) {
            return HatchRule(6, 999869, 999968, 999869, 999968, 988989, 998988, 1000000, 3999999, 3000000, 10000);
        } else if (level_ == 7) {
            return HatchRule(7, 999969, 999988, 999969, 999988, 998989, 999988, 100000, 399999, 300000, 50000);
        } else if (level_ == 8) {
            return HatchRule(8, 999989, 999998, 999989, 999998, 999989, 999998, 10000, 39999, 30000, 100000);
        } else if (level_ == 9) {
            return HatchRule(9, 999999, 999999, 999999, 999999, 999999, 999999, 1000, 3999, 3000, 1000000);
        } else {
            return getHatchRuleNone();
        }
    }

    /**
    * @param randomNum_ Random number
    * @param eSeries_ E series
    */
    function getHatchRuleByESeriesRandomNum(uint8 eSeries_, uint256 randomNum_) external pure returns (HatchRule memory) {
        for (uint8 level_ = 0; level_ <= 9;) {
            HatchRule memory hatchRule = getHatchRuleByLevel(level_);
            if (randomNum_ >= hatchRule.startRandomNumE0 && randomNum_ <= hatchRule.endRandomNumE0 && eSeries_ == 0) {
                return hatchRule;
            } else if (randomNum_ >= hatchRule.startRandomNumE1 && randomNum_ <= hatchRule.endRandomNumE1 && eSeries_ == 1) {
                return hatchRule;
            } else if (randomNum_ >= hatchRule.startRandomNumE2 && randomNum_ <= hatchRule.endRandomNumE2 && eSeries_ == 2) {
                return hatchRule;
            }
            unchecked{++level_;}
        }
        return getHatchRuleNone();
    }

    /**
    * @param tokenId_ TokenId
    */
    function getHatchRuleByTokenId(uint256 tokenId_) external pure returns (HatchRule memory) {
        for (uint8 level_ = 0; level_ <= 9;) {
            HatchRule memory hatchRule = getHatchRuleByLevel(level_);
            if (tokenId_ >= hatchRule.startTokenId && tokenId_ <= hatchRule.endTokenId) {
                return hatchRule;
            }
            unchecked{++level_;}
        }
        return getHatchRuleNone();
    }

    /**
    * @param evolveTokenIdLevel_ Evolve tokenId level
    * @param randomNum_ Random number
    */
    function getHatchRuleByEvolveTokenIdLevelRandomNum(uint8 evolveTokenIdLevel_, uint256 randomNum_) public pure returns (HatchRule memory) {
        for (uint8 nextLevelIndex_ = 0; nextLevelIndex_ <= 9;) {
            EvolveRule memory evolveRule = getEvolveRuleByEvolveTokenIdLevelNextLevelIndex(evolveTokenIdLevel_, nextLevelIndex_);
            if (randomNum_ >= evolveRule.startRandomNum && randomNum_ <= evolveRule.endRandomNum) {
                return getHatchRuleByLevel(evolveRule.level);
            }
            unchecked{++nextLevelIndex_;}
        }
        return getHatchRuleNone();
    }

    /**
    * @param evolveTokenIdLevel_ Evolve tokenId level
    * @param nextLevelIndex_ Next level index
    */
    function getEvolveRuleByEvolveTokenIdLevelNextLevelIndex(uint8 evolveTokenIdLevel_, uint8 nextLevelIndex_) public pure returns (EvolveRule memory) {
        if (evolveTokenIdLevel_ == 1) {
            if (nextLevelIndex_ == 0) {
                return EvolveRule(0, 0, 808668);
            } else if (nextLevelIndex_ == 1) {
                return EvolveRule(1, 808669, 908668);
            } else if (nextLevelIndex_ == 2) {
                return EvolveRule(2, 908669, 988668);
            } else if (nextLevelIndex_ == 3) {
                return EvolveRule(3, 988669, 998668);
            } else if (nextLevelIndex_ == 4) {
                return EvolveRule(4, 998669, 999668);
            } else if (nextLevelIndex_ == 5) {
                return EvolveRule(5, 999669, 999868);
            } else if (nextLevelIndex_ == 6) {
                return EvolveRule(6, 999869, 999968);
            } else if (nextLevelIndex_ == 7) {
                return EvolveRule(7, 999969, 999988);
            } else if (nextLevelIndex_ == 8) {
                return EvolveRule(8, 999989, 999998);
            } else if (nextLevelIndex_ == 9) {
                return EvolveRule(9, 999999, 999999);
            }
        } else if (evolveTokenIdLevel_ == 2) {
            if (nextLevelIndex_ == 0) {
                return EvolveRule(0, 0, 619668);
            } else if (nextLevelIndex_ == 1) {
                return EvolveRule(1, 619669, 719668);
            } else if (nextLevelIndex_ == 2) {
                return EvolveRule(2, 719669, 819668);
            } else if (nextLevelIndex_ == 3) {
                return EvolveRule(3, 819669, 979668);
            } else if (nextLevelIndex_ == 4) {
                return EvolveRule(4, 979669, 999668);
            } else if (nextLevelIndex_ == 5) {
                return EvolveRule(5, 999669, 999868);
            } else if (nextLevelIndex_ == 6) {
                return EvolveRule(6, 999869, 999968);
            } else if (nextLevelIndex_ == 7) {
                return EvolveRule(7, 999969, 999988);
            } else if (nextLevelIndex_ == 8) {
                return EvolveRule(8, 999989, 999998);
            } else if (nextLevelIndex_ == 9) {
                return EvolveRule(9, 999999, 999999);
            }
        } else if (evolveTokenIdLevel_ == 3) {
            if (nextLevelIndex_ == 0) {
                return EvolveRule(0, 0, 490868);
            } else if (nextLevelIndex_ == 1) {
                return EvolveRule(1, 490869, 590868);
            } else if (nextLevelIndex_ == 2) {
                return EvolveRule(2, 590869, 690868);
            } else if (nextLevelIndex_ == 3) {
                return EvolveRule(3, 690869, 790868);
            } else if (nextLevelIndex_ == 4) {
                return EvolveRule(4, 790869, 990868);
            } else if (nextLevelIndex_ == 5) {
                return EvolveRule(5, 990869, 999868);
            } else if (nextLevelIndex_ == 6) {
                return EvolveRule(6, 999869, 999968);
            } else if (nextLevelIndex_ == 7) {
                return EvolveRule(7, 999969, 999988);
            } else if (nextLevelIndex_ == 8) {
                return EvolveRule(8, 999989, 999998);
            } else if (nextLevelIndex_ == 9) {
                return EvolveRule(9, 999999, 999999);
            }
        } else if (evolveTokenIdLevel_ == 4) {
            if (nextLevelIndex_ == 0) {
                return EvolveRule(0, 0, 512968);
            } else if (nextLevelIndex_ == 1) {
                return EvolveRule(1, 512969, 612968);
            } else if (nextLevelIndex_ == 2) {
                return EvolveRule(2, 612969, 712968);
            } else if (nextLevelIndex_ == 3) {
                return EvolveRule(3, 712969, 812968);
            } else if (nextLevelIndex_ == 4) {
                return EvolveRule(4, 812969, 912968);
            } else if (nextLevelIndex_ == 5) {
                return EvolveRule(5, 912969, 992968);
            } else if (nextLevelIndex_ == 6) {
                return EvolveRule(6, 992969, 999968);
            } else if (nextLevelIndex_ == 7) {
                return EvolveRule(7, 999969, 999988);
            } else if (nextLevelIndex_ == 8) {
                return EvolveRule(8, 999989, 999998);
            } else if (nextLevelIndex_ == 9) {
                return EvolveRule(9, 999999, 999999);
            }
        } else if (evolveTokenIdLevel_ == 5) {
            if (nextLevelIndex_ == 0) {
                return EvolveRule(0, 0, 288988);
            } else if (nextLevelIndex_ == 1) {
                return EvolveRule(1, 288989, 388988);
            } else if (nextLevelIndex_ == 2) {
                return EvolveRule(2, 388989, 488988);
            } else if (nextLevelIndex_ == 3) {
                return EvolveRule(3, 488989, 588988);
            } else if (nextLevelIndex_ == 4) {
                return EvolveRule(4, 588989, 688988);
            } else if (nextLevelIndex_ == 5) {
                return EvolveRule(5, 688989, 788988);
            } else if (nextLevelIndex_ == 6) {
                return EvolveRule(6, 788989, 988988);
            } else if (nextLevelIndex_ == 7) {
                return EvolveRule(7, 988989, 999988);
            } else if (nextLevelIndex_ == 8) {
                return EvolveRule(8, 999989, 999998);
            } else if (nextLevelIndex_ == 9) {
                return EvolveRule(9, 999999, 999999);
            }
        } else if (evolveTokenIdLevel_ == 6) {
            if (nextLevelIndex_ == 0) {
                return EvolveRule(0, 0, 313998);
            } else if (nextLevelIndex_ == 1) {
                return EvolveRule(1, 313999, 413998);
            } else if (nextLevelIndex_ == 2) {
                return EvolveRule(2, 413999, 513998);
            } else if (nextLevelIndex_ == 3) {
                return EvolveRule(3, 513999, 613998);
            } else if (nextLevelIndex_ == 4) {
                return EvolveRule(4, 613999, 713998);
            } else if (nextLevelIndex_ == 5) {
                return EvolveRule(5, 713999, 813998);
            } else if (nextLevelIndex_ == 6) {
                return EvolveRule(6, 813999, 913998);
            } else if (nextLevelIndex_ == 7) {
                return EvolveRule(7, 913999, 989998);
            } else if (nextLevelIndex_ == 8) {
                return EvolveRule(8, 989999, 999998);
            } else if (nextLevelIndex_ == 9) {
                return EvolveRule(9, 999999, 999999);
            }
        }
        return EvolveRule(0, 0, 0);
    }

}

