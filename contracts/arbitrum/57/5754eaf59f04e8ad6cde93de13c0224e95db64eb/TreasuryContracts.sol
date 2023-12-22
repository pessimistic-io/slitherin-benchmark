//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasuryState.sol";

abstract contract TreasuryContracts is Initializable, TreasuryState {

    function __TreasuryContracts_init() internal initializer {
        TreasuryState.__TreasuryState_init();
    }

    function setContracts(
        address _masterOfCoinAddress,
        address _atlasMineAddress,
        address _magicAddress)
    external onlyAdminOrOwner
    {
        masterOfCoin = IMasterOfCoin(_masterOfCoinAddress);
        atlasMine = IAtlasMine(_atlasMineAddress);
        magic = IMagic(_magicAddress);
    }

    modifier contractsAreSet() {
        require(address(masterOfCoin) != address(0)
            && address(magic) != address(0)
            && address(atlasMine) != address(0), "Contracts aren't set");

        _;
    }
}
