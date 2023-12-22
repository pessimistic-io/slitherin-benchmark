// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IFeeConfig.sol";
import "./Manager.sol";
import "./Stoppable.sol";

contract StrategyManager is Manager, Stoppable {

    struct CommonAddresses {
        address vault;
        address unirouter;
        address owner;
    }

    // common addresses for the strategy
    address public vault;
    address public unirouter;

    event SetUnirouter(address unirouter);

    constructor(
        CommonAddresses memory _commonAddresses
    ) {
        vault = _commonAddresses.vault;
        unirouter = _commonAddresses.unirouter;
        transferOwnership(_commonAddresses.owner);
    }

    // set new unirouter
    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
        emit SetUnirouter(_unirouter);
    }

    function beforeDeposit() external virtual {}
}

