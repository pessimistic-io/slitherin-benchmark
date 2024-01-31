/*
 * This file is part of the Qomet Technologies contracts (https://github.com/qomet-tech/contracts).
 * Copyright (c) 2022 Qomet Technologies (https://qomet.tech)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// SPDX-License-Identifier: GNU General Public License v3.0

pragma solidity 0.8.1;

/// @author Kam Amini <kam@arteq.io>
///
/// @notice Use at your own risk. Just got the basic
///         idea from: https://github.com/solidstate-network/solidstate-solidity
library FiatHandlerStorage {

    struct Discount {
        bool enabled;
        bool useFixed;
        uint256 discountF;
        uint256 discountP;
        // reserved for future usage
        mapping(bytes32 => bytes) extra;
    }

    struct Layout {
        bool initialized;

        // UniswapV2Factory contract address:
        //  On mainnet: 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
        address uniswapV2Factory;
        // WETH ERC-20 contract address:
        //   On mainnet: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        address wethAddress;
        // USDT ERC-20 contract address:
        //   On Mainnet: 0xdAC17F958D2ee523a2206206994597C13D831ec7
        address microUSDAddress;

        uint256 payIdCounter;
        uint256 maxNegativeSlippage;

        Discount weiDiscount;
        mapping(address => Discount) erc20Discounts;

        address[] erc20sList;
        mapping(address => uint256) erc20sListIndex;
        mapping(address => bool) allowedErc20s;

        // reserved for future usage
        mapping(bytes32 => bytes) extra;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("qomet-tech.contracts.facets.txn.fiat-handler.storage");

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        /* solhint-disable no-inline-assembly */
        assembly {
            s.slot := slot
        }
        /* solhint-enable no-inline-assembly */
    }
}

