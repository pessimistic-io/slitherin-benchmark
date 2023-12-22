//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {IGmxVault} from "./IGmxVault.sol";

interface IGmxReader {
    function getMaxAmountIn(
        IGmxVault _vault,
        address _tokenIn,
        address _tokenOut
    ) external view returns (uint256);

    function getAmountOut(
        IGmxVault _vault,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256, uint256);
}

