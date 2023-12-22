//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ISLP.sol";
import "./IBalancerCrystalExchange.sol";
import "./IBalancerCrystal.sol";
import "./AdminableUpgradeable.sol";

abstract contract BalancerCrystalExchangeState is Initializable, IBalancerCrystalExchange, AdminableUpgradeable {

    IBalancerCrystal public balancerCrystal;
    ISLP public slp;

    // Address to send slp that is exchanged for balancer crystals.
    address public daoAddress;

    // ID of the balancer crystal on the 1155 balancer crystal contract.
    uint256 public balancerCrystalId;

    function __BalancerCrystalExchangeState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
    }
}
