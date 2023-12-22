// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {Strings} from "./Strings.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

import {CouponKey} from "./CouponKey.sol";
import {Coupon} from "./Coupon.sol";
import {Epoch} from "./Epoch.sol";

library Wrapped1155MetadataBuilder {
    function buildWrapped1155Metadata(CouponKey memory couponKey) internal view returns (bytes memory) {
        string memory tokenSymbol = IERC20Metadata(couponKey.asset).symbol();
        string memory epochString = Strings.toString(Epoch.unwrap(couponKey.epoch));
        // @dev assume that tokenSymbol.length <= 12
        bytes32 nameData = bytes32(abi.encodePacked(tokenSymbol, " Bond Coupon (", epochString, ")"));
        bytes32 symbolData = bytes32(abi.encodePacked(tokenSymbol, "-CP", epochString));
        assembly {
            let addLength := mul(2, add(mload(tokenSymbol), mload(epochString)))
            nameData := add(nameData, add(30, addLength))
            symbolData := add(symbolData, add(6, addLength))
        }
        return abi.encodePacked(nameData, symbolData, bytes1(IERC20Metadata(couponKey.asset).decimals()));
    }

    function buildWrapped1155BatchMetadata(CouponKey[] memory couponKeys) internal view returns (bytes memory data) {
        unchecked {
            for (uint256 i = 0; i < couponKeys.length; ++i) {
                data = bytes.concat(data, buildWrapped1155Metadata(couponKeys[i]));
            }
        }
    }

    function buildWrapped1155BatchMetadata(Coupon[] memory coupons) internal view returns (bytes memory data) {
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                data = bytes.concat(data, buildWrapped1155Metadata(coupons[i].key));
            }
        }
    }
}

