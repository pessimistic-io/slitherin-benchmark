// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IFeeConfig.sol";

contract StrategyManager is Ownable, Pausable {

    struct CommonAddresses {
        address vault;
        address unirouter;
        address owner;
    }

    // common addresses for the strategy
    address public vault;
    address public unirouter;

    uint256 constant DIVISOR = 1 ether;
    uint256 FEE = 3 * 10**17; // 30%%

    event SetVault(address vault);
    event SetUnirouter(address unirouter);
    event SetOwner(address owner);

    constructor(
        CommonAddresses memory _commonAddresses
    ) {
        vault = _commonAddresses.vault;
        unirouter = _commonAddresses.unirouter;
        transferOwnership(_commonAddresses.owner);
    }

    // set new vault (only for strategy upgrades)
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    // set new unirouter
    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
        emit SetUnirouter(_unirouter);
    }

    function beforeDeposit() external virtual {}
}

