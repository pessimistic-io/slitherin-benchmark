// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./PTokenBase.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract PToken is
    PTokenBase,
    Initializable,
    UUPSUpgradeable
{

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() AdminControl(msg.sender) {}

    function initialize(
        address _underlying,
        address _middleLayer,
        uint256 _masterCID
    ) external payable initializer() {
        __UUPSUpgradeable_init();

        initializeBase(_underlying, _middleLayer, _masterCID);
    }

    function _authorizeUpgrade(address) internal override onlyAdmin() {}
}

