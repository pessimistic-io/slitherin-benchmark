//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzBalanceState.sol";

abstract contract ToadzBalanceContracts is Initializable, ToadzBalanceState {

    function __ToadzBalanceContracts_init() internal initializer {
        ToadzBalanceState.__ToadzBalanceState_init();
    }

    function setContracts(
        address _toadzAddress,
        address _worldAddress)
    external onlyAdminOrOwner
    {
        toadz = IToadz(_toadzAddress);
        world = IWorld(_worldAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "ToadzBalance: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(toadz) != address(0)
            && address(world) != address(0);
    }
}
