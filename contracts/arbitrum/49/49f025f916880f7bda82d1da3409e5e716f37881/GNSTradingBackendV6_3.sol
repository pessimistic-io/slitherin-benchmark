// SPDX-License-Identifier: MIT
import "./StorageInterfaceV5.sol";
pragma solidity 0.8.17;

// Temporary contract to maintain compatibility with the website backend
contract GNSTradingBackendV6_3 {
    StorageInterfaceV5 public immutable storageT;

    constructor(StorageInterfaceV5 _storageT){
        storageT = _storageT;
    }

    function backend(
        address _trader
    ) external view returns(
        uint,
        uint,
        uint,
        uint[] memory,
        StorageInterfaceV5.PendingMarketOrder[] memory,
        uint[][5] memory
    ){
        uint[] memory pendingIds = storageT.getPendingOrderIds(_trader);

        StorageInterfaceV5.PendingMarketOrder[] memory pendingMarket =
            new StorageInterfaceV5.PendingMarketOrder[](pendingIds.length);

        for(uint i = 0; i < pendingIds.length; i++){
            pendingMarket[i] = storageT.reqID_pendingMarketOrder(pendingIds[i]);
        }

        uint[][5] memory nftIds;

        for(uint j = 0; j < 5; j++){
            uint nftsCount = storageT.nfts(j).balanceOf(_trader);
            nftIds[j] = new uint[](nftsCount);
            
            for(uint i = 0; i < nftsCount; i++){ 
                nftIds[j][i] = storageT.nfts(j).tokenOfOwnerByIndex(_trader, i); 
            }
        }

        return (
            storageT.dai().allowance(_trader, address(storageT)),
            storageT.dai().balanceOf(_trader),
            storageT.linkErc677().allowance(_trader, address(storageT)),
            pendingIds, 
            pendingMarket, 
            nftIds
        );
    }
}
