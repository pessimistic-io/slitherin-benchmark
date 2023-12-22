// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ILevel.sol";
import "./LevelBase.sol";
import "./IPeekABoo.sol";
import "./IStakeManager.sol";

contract Level is
    ILevel,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    LevelBase
{
    function initialize(IPeekABoo _peekaboo) public initializer {
        __Ownable_init();
        __Pausable_init();
        peekaboo = _peekaboo;

        difficultyToEXP[0] = 1;
        difficultyToEXP[1] = 2;
        difficultyToEXP[2] = 4;

        BASE_EXP = 10;
        EXP_GROWTH_RATE1 = 11;
        EXP_GROWTH_RATE2 = 10;
    }

    modifier onlyService() {
        require(
            stakeManager.isService(_msgSender()),
            "Must be a service, don't cheat"
        );
        _;
    }

    function updateExp(
        uint256 tokenId,
        bool won,
        uint256 difficulty
    ) external onlyService {
        uint256 tokenExp = tokenIdToEXP[tokenId];
        uint256 _expRequired = expRequired(tokenId);
        uint256 expGained;
        if (won) {
            expGained = (difficultyToEXP[difficulty] * 4);
        } else {
            expGained = difficultyToEXP[difficulty];
        }
        IPeekABoo peekabooRef = peekaboo;

        if (tokenExp + expGained >= _expRequired) {
            /* Leveled Up */
            emit LevelUp(tokenId);
            tokenIdToEXP[tokenId] = (tokenExp + expGained) - _expRequired;
            peekabooRef.incrementLevel(tokenId);
            unlockTrait(tokenId, peekabooRef.getTokenTraits(tokenId).level);
        } else {
            tokenIdToEXP[tokenId] += expGained;
        }
    }

    function expAmount(uint256 tokenId) external view returns (uint256) {
        return tokenIdToEXP[tokenId];
    }

    function expRequired(uint256 tokenId) public returns (uint256) {
        IPeekABoo peekabooRef = peekaboo;
        uint256 levelRequirement = peekabooRef.getTokenTraits(tokenId).level;
        return
            (BASE_EXP * growthRate(levelRequirement)) /
            growthRate2(levelRequirement);
    }

    function growthRate(uint256 level) internal returns (uint256) {
        return uint256(EXP_GROWTH_RATE1)**uint256(level - 1);
    }

    function growthRate2(uint256 level) internal returns (uint256) {
        return uint256(EXP_GROWTH_RATE2)**uint256(level - 1);
    }

    function unlockTrait(uint256 tokenId, uint64 level) internal {
        bool _isGhost = peekaboo.getTokenTraits(tokenId).isGhost;
        if (level == 2) {
            unlockedTraits[tokenId][0] = 10;
        } else if (_isGhost) {
            if (level == 3) unlockedTraits[tokenId][1] = 10;
            else if (level == 4) unlockedTraits[tokenId][2] = 10;
            else if (level == 5) unlockedTraits[tokenId][3] = 16;
            else if (level == 6) unlockedTraits[tokenId][4] = 14;
            else if (level == 7) unlockedTraits[tokenId][5] = 8;
            else if (level == 8) unlockedTraits[tokenId][6] = 10;
            else if (level == 9) unlockedTraits[tokenId][1] = 12;
            else if (level == 10) unlockedTraits[tokenId][2] = 13;
            else if (level == 11) unlockedTraits[tokenId][3] = 20;
            else if (level == 12) unlockedTraits[tokenId][4] = 17;
            else if (level == 13) unlockedTraits[tokenId][5] = 10;
            else if (level == 14) unlockedTraits[tokenId][6] = 13;
            else if (level == 15) unlockedTraits[tokenId][1] = 13;
            else if (level == 16) unlockedTraits[tokenId][3] = 22;
            else if (level == 17) unlockedTraits[tokenId][4] = 19;
            else if (level == 18) unlockedTraits[tokenId][5] = 14;
            else if (level == 19) unlockedTraits[tokenId][6] = 14;
            else if (level == 20) unlockedTraits[tokenId][4] = 24;
            else if (level == 21) unlockedTraits[tokenId][4] = 28;
            else if (level == 22) unlockedTraits[tokenId][4] = 30;
            else if (level == 23) unlockedTraits[tokenId][0] = 12;
            else if (level == 24) unlockedTraits[tokenId][1] = 16;
            else if (level == 25) unlockedTraits[tokenId][2] = 16;
            else if (level == 26) unlockedTraits[tokenId][3] = 25;
            else if (level == 27) unlockedTraits[tokenId][4] = 34;
            else if (level == 28) unlockedTraits[tokenId][5] = 17;
            else if (level == 29) unlockedTraits[tokenId][6] = 19;
            else if (level == 30) unlockedTraits[tokenId][0] = 14;
            else if (level == 31) unlockedTraits[tokenId][1] = 18;
            else if (level == 32) unlockedTraits[tokenId][3] = 28;
            else if (level == 33) unlockedTraits[tokenId][4] = 39;
            else if (level == 34) unlockedTraits[tokenId][5] = 19;
            else if (level == 35) unlockedTraits[tokenId][0] = 15;
            else if (level == 36) unlockedTraits[tokenId][5] = 21;
            else if (level == 37) unlockedTraits[tokenId][6] = 23;
            else if (level == 38) unlockedTraits[tokenId][0] = 16;
            else if (level == 39) unlockedTraits[tokenId][1] = 21;
            else if (level == 40) unlockedTraits[tokenId][2] = 18;
            else if (level == 41) unlockedTraits[tokenId][3] = 30;
            else if (level == 42) unlockedTraits[tokenId][4] = 41;
            else if (level == 43) unlockedTraits[tokenId][5] = 23;
            else if (level == 44) unlockedTraits[tokenId][6] = 27;
            else if (level == 45) unlockedTraits[tokenId][0] = 17;
            else if (level == 46) unlockedTraits[tokenId][1] = 31;
            else if (level == 47) unlockedTraits[tokenId][0] = 18;
            else if (level == 48) unlockedTraits[tokenId][4] = 44;
            else if (level == 49) unlockedTraits[tokenId][6] = 28;
            else if (level == 50) unlockedTraits[tokenId][0] = 20;
        } else {
            if (level == 3) unlockedTraits[tokenId][1] = 7;
            else if (level == 4) unlockedTraits[tokenId][2] = 13;
            else if (level == 5) unlockedTraits[tokenId][3] = 10;
            else if (level == 6) unlockedTraits[tokenId][4] = 4;
            else if (level == 7) unlockedTraits[tokenId][5] = 4;
            else if (level == 8) unlockedTraits[tokenId][1] = 10;
            else if (level == 9) unlockedTraits[tokenId][2] = 14;
            else if (level == 10) unlockedTraits[tokenId][3] = 13;
            else if (level == 11) unlockedTraits[tokenId][4] = 5;
            else if (level == 12) unlockedTraits[tokenId][2] = 15;
            else if (level == 13) unlockedTraits[tokenId][3] = 17;
            else if (level == 14) unlockedTraits[tokenId][4] = 6;
            else if (level == 15) unlockedTraits[tokenId][3] = 19;
            else if (level == 16) unlockedTraits[tokenId][0] = 12;
            else if (level == 17) unlockedTraits[tokenId][1] = 11;
            else if (level == 18) unlockedTraits[tokenId][2] = 18;
            else if (level == 19) unlockedTraits[tokenId][3] = 22;
            else if (level == 20) unlockedTraits[tokenId][4] = 7;
            else if (level == 21) unlockedTraits[tokenId][5] = 5;
            else if (level == 22) unlockedTraits[tokenId][0] = 14;
            else if (level == 23) unlockedTraits[tokenId][1] = 12;
            else if (level == 24) unlockedTraits[tokenId][3] = 24;
            else if (level == 25) unlockedTraits[tokenId][4] = 8;
            else if (level == 26) unlockedTraits[tokenId][5] = 7;
            else if (level == 27) unlockedTraits[tokenId][0] = 15;
            else if (level == 28) unlockedTraits[tokenId][1] = 13;
            else if (level == 29) unlockedTraits[tokenId][4] = 9;
            else if (level == 30) unlockedTraits[tokenId][2] = 20;
            else if (level == 31) unlockedTraits[tokenId][0] = 16;
            else if (level == 32) unlockedTraits[tokenId][1] = 14;
            else if (level == 33) unlockedTraits[tokenId][2] = 21;
            else if (level == 34) unlockedTraits[tokenId][3] = 25;
            else if (level == 35) unlockedTraits[tokenId][4] = 10;
            else if (level == 36) unlockedTraits[tokenId][5] = 8;
            else if (level == 37) unlockedTraits[tokenId][0] = 17;
            else if (level == 38) unlockedTraits[tokenId][1] = 15;
            else if (level == 39) unlockedTraits[tokenId][2] = 23;
            else if (level == 40) unlockedTraits[tokenId][3] = 26;
            else if (level == 41) unlockedTraits[tokenId][4] = 11;
            else if (level == 42) unlockedTraits[tokenId][5] = 42;
            else if (level == 43) unlockedTraits[tokenId][0] = 18;
            else if (level == 44) unlockedTraits[tokenId][1] = 16;
            else if (level == 45) unlockedTraits[tokenId][2] = 24;
            else if (level == 46) unlockedTraits[tokenId][3] = 27;
            else if (level == 47) unlockedTraits[tokenId][4] = 12;
            else if (level == 48) unlockedTraits[tokenId][0] = 20;
            else if (level == 49) unlockedTraits[tokenId][2] = 25;
            else if (level == 50) unlockedTraits[tokenId][3] = 28;
        }
    }

    function isUnlocked(
        uint256 tokenId,
        uint256 traitType,
        uint256 traitId
    ) external returns (bool) {
        if (peekaboo.getTokenTraits(tokenId).isGhost) {
            if (
                (traitType == 0 && traitId <= 6) ||
                (traitType == 1 && traitId <= 8) ||
                (traitType == 2 && traitId <= 7) ||
                (traitType == 3 && traitId <= 13) ||
                (traitType == 4 && traitId <= 12) ||
                (traitType == 5 && traitId <= 6) ||
                (traitType == 6 && traitId <= 6)
            ) {
                return true;
            }
        } else {
            if (
                (traitType == 0 && traitId <= 6) ||
                (traitType == 1 && traitId <= 4) ||
                (traitType == 2 && traitId <= 11) ||
                (traitType == 3 && traitId <= 9) ||
                (traitType == 4 && traitId <= 3) ||
                (traitType == 5 && traitId <= 1)
            ) {
                return true;
            }
        }
        return (traitId <= unlockedTraits[tokenId][traitType]);
    }

    function setGrowthRate(uint256 rate) external onlyOwner {
        require(rate > 10, "No declining rate.");
        EXP_GROWTH_RATE1 = rate;
    }

    function setEXPDifficulty(
        uint256 easy,
        uint256 medium,
        uint256 hard
    ) external onlyOwner {
        difficultyToEXP[0] = easy;
        difficultyToEXP[1] = medium;
        difficultyToEXP[2] = hard;
    }

    function setStakeManager(address _stakeManager) external onlyOwner {
        stakeManager = IStakeManager(_stakeManager);
    }

    function setPeekABoo(address _peekaboo) external onlyOwner {
        peekaboo = IPeekABoo(_peekaboo);
    }

    function getUnlockedTraits(uint256 tokenId, uint256 traitType)
        external
        returns (uint256)
    {
        return unlockedTraits[tokenId][traitType];
    }
}

