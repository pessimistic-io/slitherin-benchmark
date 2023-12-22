// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library ParameterVerificationHelper {
    function verifyNotZeroAddress(address inputAddress) internal pure {
        require(inputAddress != address(0), "input zero address");
    }

    function verifyGreaterThanZero(uint256 inputNumber) internal pure {
        require(inputNumber > 0, "input 0");
    }

    function verifyGreaterThanZero(int24 inputNumber) internal pure {
        require(inputNumber > 0, "input 0");
    }

    function verifyGreaterThanOne(int24 inputNumber) internal pure {
        require(inputNumber > 1, "input <= 1");
    }

    function verifyGreaterThanOrEqualToZero(int24 inputNumber) internal pure {
        require(inputNumber >= 0, "input less than 0");
    }

    function verifyPairTokensHaveWeth(
        address token0Address,
        address token1Address,
        address wethAddress
    ) internal pure {
        require(
            token0Address == wethAddress || token1Address == wethAddress,
            "pair token not have WETH"
        );
    }

    function verifyMsgValueEqualsInputAmount(
        uint256 inputAmount
    ) internal view {
        require(msg.value == inputAmount, "msg.value != inputAmount");
    }

    function verifyPairTokensHaveInputToken(
        address token0Address,
        address token1Address,
        address inputToken
    ) internal pure {
        require(
            token0Address == inputToken || token1Address == inputToken,
            "pair token not have inputToken"
        );
    }
}

