// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import "./AccessControl.sol";

import "./Gangs.sol";

contract GangsMultiplierManagement is AccessControl {
    mapping (uint256 => uint256) multiplierByLeaderRarity; // leaderRarity => multiplier

    Gangs public gangs;

    event MultiplierChanged(uint256 leaderRarity, uint256 multiplier);

    constructor(
        address gangsAddress_
    )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        gangs = Gangs(gangsAddress_);

        multiplierByLeaderRarity[10] = 300;
        multiplierByLeaderRarity[25] = 250;
        multiplierByLeaderRarity[100] = 200;
        multiplierByLeaderRarity[250] = 150;
        multiplierByLeaderRarity[1500] = 125;
        multiplierByLeaderRarity[10000] = 110;
        multiplierByLeaderRarity[25000] = 105;
    }

    function getMultiplierBySharkId(uint256 sharkId_)
        public
        view
        returns (uint256)
    {
        uint256 _gangId = gangs.getGangIdBySharkId(sharkId_);
        if (_gangId > 0 && gangs.isActive(_gangId))
        {
            return multiplierByLeaderRarity[gangs.getLeaderRarity(_gangId)];
        } else {
            return 100;
        }
    }

    function setMultiplierByLeaderRarity(uint256 leaderRarity_, uint256 multiplier_)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        multiplierByLeaderRarity[leaderRarity_] = multiplier_;

        emit MultiplierChanged(leaderRarity_, multiplier_);
    }
}
