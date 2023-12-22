// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import "./TickMath.sol";

import "./IRamsesV2SwapCallback.sol";

import "./IRamsesV2Pool.sol";

contract TestRamsesV2ReentrantCallee is IRamsesV2SwapCallback {
    string private constant expectedReason = "LOK";

    function swapToReenter(address pool) external {
        IRamsesV2Pool(pool).swap(
            address(0),
            false,
            1,
            TickMath.MAX_SQRT_RATIO - 1,
            new bytes(0)
        );
    }

    function ramsesV2SwapCallback(
        int256,
        int256,
        bytes calldata
    ) external override {
        // try to reenter swap
        try
            IRamsesV2Pool(msg.sender).swap(
                address(0),
                false,
                1,
                0,
                new bytes(0)
            )
        {} catch Error(string memory reason) {
            require(
                keccak256(abi.encode(reason)) ==
                    keccak256(abi.encode(expectedReason))
            );
        }

        // try to reenter mint
        try
            IRamsesV2Pool(msg.sender).mint(address(0), 0, 0, 0, new bytes(0))
        {} catch Error(string memory reason) {
            require(
                keccak256(abi.encode(reason)) ==
                    keccak256(abi.encode(expectedReason))
            );
        }

        // try to reenter collect
        try
            IRamsesV2Pool(msg.sender).collect(address(0), 0, 0, 0, 0)
        {} catch Error(string memory reason) {
            require(
                keccak256(abi.encode(reason)) ==
                    keccak256(abi.encode(expectedReason))
            );
        }

        // try to reenter burn
        try IRamsesV2Pool(msg.sender).burn(0, 0, 0) {} catch Error(
            string memory reason
        ) {
            require(
                keccak256(abi.encode(reason)) ==
                    keccak256(abi.encode(expectedReason))
            );
        }

        // try to reenter flash
        try
            IRamsesV2Pool(msg.sender).flash(address(0), 0, 0, new bytes(0))
        {} catch Error(string memory reason) {
            require(
                keccak256(abi.encode(reason)) ==
                    keccak256(abi.encode(expectedReason))
            );
        }

        // try to reenter collectProtocol
        try
            IRamsesV2Pool(msg.sender).collectProtocol(address(0), 0, 0)
        {} catch Error(string memory reason) {
            require(
                keccak256(abi.encode(reason)) ==
                    keccak256(abi.encode(expectedReason))
            );
        }

        require(false, "Unable to reenter");
    }
}

