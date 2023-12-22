/*

    Copyright 2022 Dolomite.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

*/

pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import "./IDolomiteMargin.sol";

import "./Types.sol";

import "./IDolomiteAmmFactory.sol";
import "./IDolomiteAmmPair.sol";

interface IDolomiteAmmRouterProxy {

    // ============ Structs ============

    struct ModifyPositionParams {
        uint accountNumber;
        Types.AssetAmount amountIn;
        Types.AssetAmount amountOut;
        address[] tokenPath;
        /// the token to be deposited/withdrawn to/from account number. To not perform any margin deposits or
        /// withdrawals, simply set this to `address(0)`
        address depositToken;
        /// a positive number means funds are deposited to `accountNumber` from accountNumber zero
        /// a negative number means funds are withdrawn from `accountNumber` and moved to accountNumber zero
        bool isPositiveMarginDeposit;
        /// the amount of the margin deposit/withdrawal, in wei
        uint marginDeposit;
        /// the amount of seconds from the time at which the position is opened to expiry. 0 for no expiration
        uint expiryTimeDelta;
    }

    struct ModifyPositionCache {
        ModifyPositionParams params;
        IDolomiteMargin dolomiteMargin;
        IDolomiteAmmFactory ammFactory;
        address account;
        uint[] marketPath;
        uint[] amountsWei;
        uint marginDepositDeltaWei;
    }

    struct PermitSignature {
        bool approveMax;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function getPairInitCodeHash() external view returns (bytes32);

    function addLiquidity(
        address to,
        uint fromAccountNumber,
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMinWei,
        uint amountBMinWei,
        uint deadline
    )
    external
    returns (uint amountAWei, uint amountBWei, uint liquidity);

    function swapExactTokensForTokens(
        uint accountNumber,
        uint amountInWei,
        uint amountOutMinWei,
        address[] calldata tokenPath,
        uint deadline
    )
    external;

    function getParamsForSwapExactTokensForTokens(
        address account,
        uint accountNumber,
        uint amountInWei,
        uint amountOutMinWei,
        address[] calldata tokenPath
    )
    external view returns (Account.Info[] memory, Actions.ActionArgs[] memory);

    function swapTokensForExactTokens(
        uint accountNumber,
        uint amountInMaxWei,
        uint amountOutWei,
        address[] calldata tokenPath,
        uint deadline
    )
    external;

    function getParamsForSwapTokensForExactTokens(
        address account,
        uint accountNumber,
        uint amountInMaxWei,
        uint amountOutWei,
        address[] calldata tokenPath
    )
    external view returns (Account.Info[] memory, Actions.ActionArgs[] memory);

    function removeLiquidity(
        address to,
        uint toAccountNumber,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMinWei,
        uint amountBMinWei,
        uint deadline
    ) external returns (uint amountAWei, uint amountBWei);

    function removeLiquidityWithPermit(
        address to,
        uint toAccountNumber,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMinWei,
        uint amountBMinWei,
        uint deadline,
        PermitSignature calldata permit
    ) external returns (uint amountAWei, uint amountBWei);

    function swapExactTokensForTokensAndModifyPosition(
        ModifyPositionParams calldata params,
        uint deadline
    ) external;

    function swapTokensForExactTokensAndModifyPosition(
        ModifyPositionParams calldata params,
        uint deadline
    ) external;
}

