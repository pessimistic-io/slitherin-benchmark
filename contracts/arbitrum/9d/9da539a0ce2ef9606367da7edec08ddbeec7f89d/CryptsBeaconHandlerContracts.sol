//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CryptsBeaconHandlerState.sol";

abstract contract CryptsBeaconHandlerContracts is Initializable, CryptsBeaconHandlerState{

    function __CryptsBeaconHandlerContracts_init() internal initializer {
        CryptsBeaconHandlerState.__CryptsBeaconHandlerState_init();
    }

    function setContracts(
        address _beaconAddress,
        address _corruptionCryptsAddress
    ) public onlyOwner {
        beaconAddress = _beaconAddress;
        corruptionCrypts = ICorruptionCrypts(_corruptionCryptsAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "CorruptionCryptsRewards: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return beaconAddress != address(0)
            && address(corruptionCrypts) != address(0);
    }
}
