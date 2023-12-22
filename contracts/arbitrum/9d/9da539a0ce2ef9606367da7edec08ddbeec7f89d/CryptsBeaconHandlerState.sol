//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155HolderUpgradeable.sol";
import "./Initializable.sol";
import "./IERC1155.sol";
import "./ICryptsCharacterHandler.sol";
import "./AdminableUpgradeable.sol";
import "./ICorruptionCrypts.sol";

abstract contract CryptsBeaconHandlerState is
    Initializable,
    AdminableUpgradeable,
    ERC1155HolderUpgradeable,
    ICryptsCharacterHandler
{
    event BeaconDiversionPointsChanged(uint24 _diversionPoints);
    event BeaconPercentOfPoolClaimedChanged(uint32 _percent);

    ICorruptionCrypts public corruptionCrypts;
    address public beaconAddress;

    bool public stakingAllowed;

    uint24 public beaconDiversionPoints;
    uint32 public beaconPercentOfPoolClaimed;

    function __CryptsBeaconHandlerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();
    }
}
