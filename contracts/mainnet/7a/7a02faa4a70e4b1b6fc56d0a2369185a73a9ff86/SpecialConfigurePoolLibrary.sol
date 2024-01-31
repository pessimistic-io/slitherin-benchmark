//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;


import "./ISpecialPool.sol";
import "./SpecialValidatePoolLibrary.sol";

library SpecialConfigurePoolLibrary {

    function updateExtraData(
        string calldata _extraData,
        ISpecialPool.PoolModel storage poolInformation,
        ISpecialPool.PoolDetails storage poolDetails
    ) external {
        SpecialValidatePoolLibrary._poolIsNotCancelled(poolInformation);
        poolDetails.extraData = _extraData;
    }

    function updateKYCStatus(
        bool _kyc,
        ISpecialPool.PoolDetails storage poolDetails
    ) external {
        poolDetails.kyc = _kyc;
    }

    function updateAuditStatus(
        bool _audit,
        string calldata _auditLink,
        ISpecialPool.PoolDetails storage poolDetails
    ) external {
        poolDetails.audit = _audit;
        poolDetails.auditLink = _auditLink;
    }

    function addAddressesToWhitelist(
        address[] calldata whitelistedAddresses,
        ISpecialPool.PoolModel storage poolInformation,
        mapping(address => bool) storage whitelistedAddressesMap,
        address[] storage whitelistedAddressesArray
    ) external {
        SpecialValidatePoolLibrary._poolIsNotCancelled(poolInformation);        

        for (uint256 i = 0; i < whitelistedAddresses.length; i++) {
            address userAddress = whitelistedAddresses[i];
            require(
                address(0) != address(userAddress),
                "zero address not accepted!"
            );

            if (!whitelistedAddressesMap[userAddress]) {
                whitelistedAddressesMap[userAddress] = true;
                whitelistedAddressesArray.push(userAddress);
            }
        }
    }

    function addAddressesToWhitelistForTiered(
        address[] calldata whitelistedAddressesForTiered,
        ISpecialPool.PoolModel storage poolInformation,
        mapping(address => bool) storage whitelistedAddressesMapForTiered,
        address[] storage whitelistedAddressesArrayForTiered
    ) external {        
        for (uint256 i = 0; i < whitelistedAddressesForTiered.length; i++) {
            require(
                address(0) != address(whitelistedAddressesForTiered[i]),
                "zero address not accepted!"
            );

            if (
                !whitelistedAddressesMapForTiered[
                    whitelistedAddressesForTiered[i]
                ]
            ) {
                whitelistedAddressesMapForTiered[
                    whitelistedAddressesForTiered[i]
                ] = true;
                whitelistedAddressesArrayForTiered.push(
                    whitelistedAddressesForTiered[i]
                );
            }
        }
        require(
            whitelistedAddressesArrayForTiered.length
             <= poolInformation.softCap/poolInformation.maxAllocationPerUser+1,
            "whitelist exceeds limit"
        );
    }

    function updateWhitelistable(
        address _pool,
        bool[2] memory whitelistable,
        mapping(address => bool) storage isTieredWhitelist,
        ISpecialPool.PoolModel storage poolInformation,
        ISpecialPool.PoolDetails storage poolDetails,
        mapping(address => bool) storage whitelistedAddressesMap,
        mapping(address => address[]) storage whitelistedAddressesArray,
        mapping(address => bool) storage whitelistedAddressesMapForTiered,
        mapping(address => address[]) storage whitelistedAddressesArrayForTiered
    ) external {
        SpecialValidatePoolLibrary._poolIsUpcoming(poolInformation);
        poolDetails.whitelistable = whitelistable[0];
        isTieredWhitelist[_pool] = whitelistable[1];
        if(!whitelistable[0]){
            for (uint256 i = 0; i < whitelistedAddressesArray[_pool].length; i++) {
                whitelistedAddressesMap[
                    whitelistedAddressesArray[_pool][i]
                ] = false;
            }
            delete whitelistedAddressesArray[_pool];    
        }
        if(!whitelistable[1]){
            for (
                uint256 i = 0;
                i < whitelistedAddressesArrayForTiered[_pool].length;
                i++
            ) {
                whitelistedAddressesMapForTiered[
                    whitelistedAddressesArrayForTiered[_pool][i]
                ] = false;
            }
            delete whitelistedAddressesArrayForTiered[_pool];
        }

        if (!whitelistable[0]) {
            require(!whitelistable[1], "not whitelist!");
        }
    }
    function updateHidePool(
        address pool,
        bool isHide,
        mapping(address => bool) storage isHiddenPool
    ) external {
        isHiddenPool[pool] = isHide;
    }
}

