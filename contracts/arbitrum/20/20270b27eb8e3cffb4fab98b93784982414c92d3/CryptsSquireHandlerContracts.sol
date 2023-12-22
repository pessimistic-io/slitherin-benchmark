//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CryptsSquireHandlerState.sol";

abstract contract CryptsSquireHandlerContracts is Initializable, CryptsSquireHandlerState{

    function __CryptsSquireHandlerContracts_init() internal initializer {
        CryptsSquireHandlerState.__CryptsSquireHandlerState_init();
    }

    function setContracts(
        address _squireAddress,
        address _corruptionCryptsAddress
    ) public onlyOwner {
        squireAddress = _squireAddress;
        corruptionCrypts = ICorruptionCrypts(_corruptionCryptsAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "CorruptionCryptsRewards: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return squireAddress != address(0)
            && address(corruptionCrypts) != address(0);
    }
}
