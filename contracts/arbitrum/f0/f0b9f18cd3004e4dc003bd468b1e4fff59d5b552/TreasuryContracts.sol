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
        address _magicAddress,
        address _middlemanAddress)
    external onlyAdminOrOwner
    {
        masterOfCoin = IMasterOfCoin(_masterOfCoinAddress);
        atlasMine = IAtlasMine(_atlasMineAddress);
        magic = IMagic(_magicAddress);
        middlemanAddress = _middlemanAddress;
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Treasury: Contracts aren't set");

        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(masterOfCoin) != address(0)
            && address(magic) != address(0)
            && address(atlasMine) != address(0)
            && middlemanAddress != address(0);
    }
}
