// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {IDodoV2Pool} from "./IDodoV2Pool.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibDodoV2 {
    using LibAsset for address;

    function getPoolData(bytes memory poolData) private pure returns (bytes32 poolDataBytes32) {
        assembly {
            poolDataBytes32 := mload(add(poolData, 32))
        }
    }

    function convertPoolDataList(bytes[] memory poolDataList)
        private
        pure
        returns (bytes32[] memory poolDataListBytes32)
    {
        uint256 l = poolDataList.length;
        poolDataListBytes32 = new bytes32[](l);
        for (uint256 i = 0; i < l; ) {
            poolDataListBytes32[i] = getPoolData(poolDataList[i]);
            unchecked {
                i++;
            }
        }
    }

    function getDodoV2Data(bytes32[] memory poolData)
        private
        pure
        returns (address[] memory poolAddresses, uint256[] memory directions)
    {
        uint256 l = poolData.length;
        poolAddresses = new address[](l);
        directions = new uint256[](l);

        assembly {
            let i := 0
            let poolAddressesPosition := add(poolAddresses, 32)
            let directionsPosition := add(directions, 32)

            for {

            } lt(i, l) {
                i := add(i, 1)
                poolAddressesPosition := add(poolAddressesPosition, 32)
                directionsPosition := add(directionsPosition, 32)
            } {
                let poolDataPosition := add(add(poolData, 32), mul(i, 32))

                mstore(poolAddressesPosition, shr(96, mload(poolDataPosition)))
                mstore(directionsPosition, shr(248, shl(160, mload(poolDataPosition))))
            }
        }
    }

    function swapDodoV2(Hop memory h) internal {
        uint256 i;
        uint256 l = h.poolDataList.length;
        (address[] memory poolAddresses, uint256[] memory directions) = getDodoV2Data(
            convertPoolDataList(h.poolDataList)
        );

        h.path[0].transfer(payable(poolAddresses[0]), h.amountIn);

        for (i = 0; i < l; ) {
            if (directions[i] == 1) {
                IDodoV2Pool(poolAddresses[i]).sellBase((i == l - 1) ? h.recipient : poolAddresses[i + 1]);
            } else {
                IDodoV2Pool(poolAddresses[i]).sellQuote((i == l - 1) ? h.recipient : poolAddresses[i + 1]);
            }

            unchecked {
                i++;
            }
        }
    }
}

