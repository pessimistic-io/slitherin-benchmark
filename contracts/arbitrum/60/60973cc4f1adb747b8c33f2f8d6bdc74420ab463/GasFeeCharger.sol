// SPDX-License-Identifier: MIT
// Metaline Contracts (GasFeeCharger.sol)

pragma solidity ^0.8.0;

library GasFeeCharger {

    struct MethodWithExrtraFee {
        address target;
        uint256 value;
    }

    struct MethodExtraFees {
        mapping(uint8=>MethodWithExrtraFee) extraFees;
    }

    function setMethodExtraFee(MethodExtraFees storage extraFees, uint8 methodKey, uint256 value, address target) internal {
        MethodWithExrtraFee storage fee = extraFees.extraFees[methodKey];
        fee.value = value;
        fee.target = target;
    }

    function removeMethodExtraFee(MethodExtraFees storage extraFees, uint8 methodKey) internal {
        delete extraFees.extraFees[methodKey];
    }

    function chargeMethodExtraFee(MethodExtraFees storage extraFees, uint8 methodKey)  internal returns(uint256) {
        MethodWithExrtraFee storage fee = extraFees.extraFees[methodKey];
        if(fee.target == address(0)){
            return 0; // no need charge fee
        }

        require(msg.value >= fee.value, "msg fee not enough");

        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool sent, ) = fee.target.call{value: fee.value}("");
        require(sent, "Trans fee err");

        return fee.value;
    }
    
}


