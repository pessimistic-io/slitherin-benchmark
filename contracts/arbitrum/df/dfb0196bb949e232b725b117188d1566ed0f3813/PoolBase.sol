// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ERC165Base} from "./ERC165Base.sol";
import {ERC1155Base} from "./ERC1155Base.sol";
import {ERC1155BaseInternal} from "./ERC1155BaseInternal.sol";
import {ERC1155Enumerable} from "./ERC1155Enumerable.sol";
import {ERC1155EnumerableInternal} from "./ERC1155EnumerableInternal.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Multicall} from "./Multicall.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolBase is
    PoolInternal,
    ERC1155Base,
    ERC1155Enumerable,
    ERC165Base,
    Multicall
{
    constructor(
        address ivolOracle,
        address wrappedNativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        address exchangeHelper
    )
        PoolInternal(
            ivolOracle,
            wrappedNativeToken,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            exchangeHelper
        )
    {}

    /**
     * @notice see IPoolBase; inheritance not possible due to linearization issues
     */
    function name() external view returns (string memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        return
            string(
                abi.encodePacked(
                    IERC20Metadata(l.underlying).symbol(),
                    " / ",
                    IERC20Metadata(l.base).symbol(),
                    " - Premia Options Pool"
                )
            );
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        virtual
        override(ERC1155BaseInternal, ERC1155EnumerableInternal, PoolInternal)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}

