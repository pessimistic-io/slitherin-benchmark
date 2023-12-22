//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CryptsLegionHandlerState.sol";

abstract contract CryptsLegionHandlerContracts is Initializable, CryptsLegionHandlerState{

    function __CryptsLegionHandlerContracts_init() internal initializer {
        CryptsLegionHandlerState.__CryptsLegionHandlerState_init();
    }

    function setContracts(
        address _legionContractAddress,
        address _legionMetadataStoreAddress,
        address _corruptionCryptsAddress
    ) public onlyOwner {
        legionContract = ILegion(_legionContractAddress);
        legionMetadataStore = ILegionMetadataStore(_legionMetadataStoreAddress);
        corruptionCrypts = ICorruptionCrypts(_corruptionCryptsAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "CorruptionCryptsRewards: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(legionContract) != address(0)
            && address(legionMetadataStore) != address(0)
            && address(corruptionCrypts) != address(0);
    }
}
