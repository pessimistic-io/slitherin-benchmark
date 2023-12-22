//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./FragmentSwapperState.sol";

abstract contract FragmentSwapperContracts is Initializable, FragmentSwapperState {

    function __FragmentSwapperContracts_init() internal initializer {
        FragmentSwapperState.__FragmentSwapperState_init();
    }

    function setContracts(
        address _treasureFragmentAddress)
    external onlyAdminOrOwner
    {
        treasureFragment = ITreasureFragment(_treasureFragmentAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "FragmentSwapper: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(treasureFragment) != address(0);
    }
}
