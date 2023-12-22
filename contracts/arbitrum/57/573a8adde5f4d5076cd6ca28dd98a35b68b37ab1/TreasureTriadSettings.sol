//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasureTriadContracts.sol";

abstract contract TreasureTriadSettings is Initializable, TreasureTriadContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __TreasureTriadSettings_init() internal initializer {
        TreasureTriadContracts.__TreasureTriadContracts_init();
    }

    function addTreasureCardInfo(
        uint256[] calldata _treasureIds,
        CardInfo[] calldata _cardInfo)
    external
    onlyAdminOrOwner
    {
        require(_treasureIds.length > 0 && _treasureIds.length == _cardInfo.length,
            "TreasureTriad: Bad array lengths");

        for(uint256 i = 0; i < _treasureIds.length; i++) {
            require(_cardInfo[i].north > 0
                && _cardInfo[i].east > 0
                && _cardInfo[i].south > 0
                && _cardInfo[i].west > 0,
                "TreasureTriad: Cards must have a value on each side");

            treasureIds.add(_treasureIds[i]);

            treasureIdToCardInfo[_treasureIds[i]] = _cardInfo[i];

            emit TreasureCardInfoSet(_treasureIds[i], _cardInfo[i]);
        }
    }

    function affinityForTreasure(uint256 _treasureId) public view returns(TreasureCategory) {
        return treasureIdToCardInfo[_treasureId].category;
    }
}
