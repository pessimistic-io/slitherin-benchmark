//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721HolderUpgradeable.sol";
import "./Initializable.sol";
import "./IERC721.sol";
import "./ICryptsCharacterHandler.sol";
import "./AdminableUpgradeable.sol";
import "./ICorruptionCrypts.sol";

abstract contract CryptsSquireHandlerState is
    Initializable,
    AdminableUpgradeable,
    ERC721HolderUpgradeable,
    ICryptsCharacterHandler
{
    event SquireDiversionPointsChanged(uint24 _diversionPoints);
    event SquirePercentOfPoolClaimedChanged(uint32 _percent);

    ICorruptionCrypts public corruptionCrypts;
    address public squireAddress;

    bool public stakingAllowed;

    uint24 public squireDiversionPoints;
    uint32 public squirePercentOfPoolClaimed;

    function __CryptsSquireHandlerState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }
}
