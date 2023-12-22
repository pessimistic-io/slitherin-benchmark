//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./MagicStakingState.sol";

abstract contract MagicStakingContracts is Initializable, MagicStakingState {

    function __MagicStakingContracts_init() internal initializer {
        MagicStakingState.__MagicStakingState_init();
    }

    function setContracts(
        address _magicAddress,
        address _wartlocksHallowAddress)
    external onlyAdminOrOwner
    {
        magic = IMagic(_magicAddress);
        wartlocksHallow = IWartlocksHallow(_wartlocksHallowAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(magic) != address(0)
            && address(wartlocksHallow) != address(0);
    }
}
