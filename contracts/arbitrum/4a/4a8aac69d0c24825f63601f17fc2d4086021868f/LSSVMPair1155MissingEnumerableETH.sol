// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMPair1155ETH} from "./LSSVMPair1155ETH.sol";
import {LSSVMPair1155MissingEnumerable} from "./LSSVMPair1155MissingEnumerable.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";

contract LSSVMPair1155MissingEnumerableETH is 
    LSSVMPair1155MissingEnumerable,
    LSSVMPair1155ETH
{
    function pairVariant()
        public
        pure
        override
        returns (ILSSVMPairFactoryLike.PairVariant)
    {
        return ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_1155_ETH;
    }
}

