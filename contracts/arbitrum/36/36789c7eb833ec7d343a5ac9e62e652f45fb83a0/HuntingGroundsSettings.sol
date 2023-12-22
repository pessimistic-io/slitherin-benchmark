//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./HuntingGroundsContracts.sol";

abstract contract HuntingGroundsSettings is Initializable, HuntingGroundsContracts {

    function __HuntingGroundsSettings_init() internal initializer {
        HuntingGroundsContracts.__HuntingGroundsContracts_init();
    }

    function setBugzBadgezAmounts(
        uint256[] calldata _badgezAmounts,
        uint256[] calldata _badgezIds)
    external
    nonZeroLength(_badgezIds)
    onlyAdminOrOwner
    {
        require(_badgezAmounts.length == _badgezIds.length, "HuntingGrounds: Bad badgez array lengths");

        delete bugzBadgezAmounts;

        bugzBadgezAmounts = _badgezAmounts;

        for(uint256 i = 0; i < _badgezIds.length; i++) {
            require(_badgezIds[i] > 0, "HuntingGrounds: Bad badgez ids");
            bugzAmountToBadgeId[_badgezAmounts[i]] = _badgezIds[i];
        }
    }
}
