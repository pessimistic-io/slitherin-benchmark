// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "./ISwapRouter.sol";
import "./IERC20.sol";

interface ISockFeeManager {

    struct CashOutParams {
        uint256 amountOutMinimum;
        uint24 fee;
        IERC20 tokenIn;
    }

    function changeCashOutToken(IERC20 aCashOutToken) external;

    function isAllowedToken(IERC20 aToken) external view returns (bool);

    function addAllowedTokens(IERC20[] calldata someTokens) external;

    function removeAllowedTokens(IERC20[] calldata someTokens) external;

    function cashOut(CashOutParams[] calldata cashOutParams) external;

    function cashOutToken() external view returns (IERC20);

    function cashOutDestination() external view returns (address);

    function swapRouter() external view returns (ISwapRouter);
}
