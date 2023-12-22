// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

enum JoeVersion {
    V1,
    V2,
    V2_1
}

struct JoePath {
    uint256[] pairBinSteps;
    JoeVersion[] versions;
    address[] tokenPath;
}

interface IJoeLBPair {
    function getTokenX() external view returns (address);
    function getTokenY() external view returns (address);
    function getBinStep() external view returns (uint16);
    function getActiveId() external view returns (uint24);
    function totalSupply(uint256) external view returns (uint256);
    function balanceOf(address, uint256) external view returns (uint256);
    function getBin(uint24) external view returns (uint128, uint128);
    function getOracleSampleAt(uint40) external view returns (uint64, uint64, uint64);
    function getPriceFromId(uint24) external view returns (uint256);
    function approveForAll(address, bool) external;
}

interface IJoeLBRouter {
    struct LiquidityParameters {
        address tokenX;
        address tokenY;
        uint256 binStep;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        address refundTo;
        uint256 deadline;
    }

    function getIdFromPrice(address pair, uint256 price) external view returns (uint24);
    function getPriceFromId(address pair, uint24 id) external view returns (uint256);

    function addLiquidity(LiquidityParameters calldata liquidityParameters)
        external
        returns (
            uint256 amountXAdded,
            uint256 amountYAdded,
            uint256 amountXLeft,
            uint256 amountYLeft,
            uint256[] memory depositIds,
            uint256[] memory liquidityMinted
        );

    function removeLiquidity(
        address tokenX,
        address tokenY,
        uint16 binStep,
        uint256 amountXMin,
        uint256 amountYMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external returns (uint256 amountX, uint256 amountY);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] memory pairBinSteps,
        address[] memory tokenPath,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        JoePath memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

