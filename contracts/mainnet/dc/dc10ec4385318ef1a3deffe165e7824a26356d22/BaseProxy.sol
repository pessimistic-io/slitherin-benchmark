// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

abstract contract BaseProxy is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

