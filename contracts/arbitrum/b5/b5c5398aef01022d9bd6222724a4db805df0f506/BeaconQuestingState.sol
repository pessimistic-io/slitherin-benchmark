//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./AdminableUpgradeable.sol";
import "./IRandomizer.sol";
import "./IBeacon.sol";
import "./IMasterOfInflation.sol";
import "./IPoolConfigProvider.sol";
import "./IBeaconQuesting.sol";

abstract contract BeaconQuestingState is Initializable, IBeaconQuesting, IPoolConfigProvider, ERC1155HolderUpgradeable, AdminableUpgradeable {

    event QuestLengthUpdated(uint128 _questLength);
    event PoolIdUpdated(uint64 poolId);
    event TotalQuestingCharactersUpdated(uint64 totalQuestingCharacters);
    event QuestEnded(address indexed user, uint64 questsEnded, uint64 nullStonesMinted);

    uint256 public constant NULL_STONE_ID = 10_000;
    uint64 public constant NULL_STONE_AMOUNT = 20;
    // Founding character.
    //
    uint256 constant REQUIRED_CHARACTER_TYPE = 1;

    IRandomizer public randomizer;
    IMasterOfInflation public masterOfInflation;
    IBeacon public beacon;

    mapping(address => UserInfo) addressToInfo;
    mapping(uint256 => TokenInfo) public tokenIdToInfo;

    QuestInfo public questInfo;

    function __BeaconQuestingState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        questInfo.questLength = 12 hours;
        emit QuestLengthUpdated(questInfo.questLength);
    }
}

struct UserInfo {
    EnumerableSetUpgradeable.UintSet stakedTokens;
}

struct TokenInfo {
    uint128 startTime;
    uint64 requestId;
}

struct QuestInfo {
    uint128 questLength;
    uint64 poolId;
    uint64 totalQuestingCharacters;
}
