// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMPair1155ERC20} from "./LSSVMPair1155ERC20.sol";
import {LSSVMPair1155MissingEnumerable} from "./LSSVMPair1155MissingEnumerable.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";

contract LSSVMPair1155MissingEnumerableERC20 is 
    LSSVMPair1155MissingEnumerable,
    LSSVMPair1155ERC20
{
    function pairVariant()
        public
        pure
        override
        returns (ILSSVMPairFactoryLike.PairVariant)
    {
        return ILSSVMPairFactoryLike.PairVariant.MISSING_ENUMERABLE_1155_ERC20;
    }
}

