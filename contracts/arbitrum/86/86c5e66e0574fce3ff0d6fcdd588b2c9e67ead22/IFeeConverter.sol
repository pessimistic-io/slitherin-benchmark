// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";

import {IOneInchRouter} from "./IOneInchRouter.sol";
import {IBaseComponent} from "./IBaseComponent.sol";

interface IFeeConverter is IBaseComponent {
    error FeeConverter__InvalidLength();
    error FeeConverter__HashMismatch(address lpToken);
    error FeeConverter__InsufficientBalance(address lpToken);
    error FeeConverter__InvalidReceiver();
    error FeeConverter__InvalidDstToken();
    error FeeConverter__ZeroAmount();
    error FeeConverter__InsufficientRedistributedTokenBalance();

    event Swap(
        address recipient, address indexed srcToken, address indexed dstToken, uint256 amountIn, uint256 amountOut
    );

    function getOneInchRouter() external view returns (IOneInchRouter);

    function getRedistributedToken() external view returns (IERC20);

    function getReceiver() external view returns (address);

    function convert(address executor, IOneInchRouter.SwapDescription calldata desc, bytes calldata data) external;

    function batchConvert(address executor, IOneInchRouter.SwapDescription[] calldata descs, bytes[] calldata data)
        external;

    function unwrapLpToken(address lpToken) external;

    function batchUnwrapLpToken(address[] calldata lpTokens) external;
}

