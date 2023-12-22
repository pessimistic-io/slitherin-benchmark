//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BalancerCrystalExchangeState.sol";

abstract contract BalancerCrystalExchangeContracts is Initializable, BalancerCrystalExchangeState {

    function __BalancerCrystalExchangeContracts_init() internal initializer {
        BalancerCrystalExchangeState.__BalancerCrystalExchangeState_init();
    }

    function setContracts(
        address _balancerCrystalAddress,
        address _slpAddress)
    external onlyAdminOrOwner
    {
        balancerCrystal = IBalancerCrystal(_balancerCrystalAddress);
        slp = ISLP(_slpAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "BalancerCrystalExchange: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(balancerCrystal) != address(0)
            && address(slp) != address(0);
    }
}
