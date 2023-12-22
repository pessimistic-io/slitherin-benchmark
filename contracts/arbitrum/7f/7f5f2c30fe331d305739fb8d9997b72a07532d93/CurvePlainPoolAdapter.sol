// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {IERC20} from "./IERC20.sol";
import {IBeefyStrategyAdapter} from "./IBeefyStrategyAdapter.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";

interface ICurvePlainPool {
    // solhint-disable-next-line func-name-mixedcase
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 minAmountOut
    ) external returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function remove_liquidity(
        uint256 amount,
        uint256[2] calldata amounts
    ) external returns (uint256[2] memory);

    // solhint-disable-next-line func-name-mixedcase
    function calc_token_amount(
        uint256[2] calldata amounts,
        bool isDeposit
    ) external view returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function calc_withdraw_one_coin(
        uint256 tokenAmount,
        int128 tokenIndex
    ) external view returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function remove_liquidity_one_coin(
        uint256 lpTokenAmount,
        int128 index,
        uint256 minAmount
    ) external returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function get_virtual_price() external view returns (uint256);
}

/// @title CurveAdapter
/// @notice Supports adding liquidity to and removing liquidity from a Curve
/// @dev Explain to a developer any extra details
contract CurvePlainPoolAdapter is IBeefyStrategyAdapter {
    error UnsupportedToken(address token);
    error MinAmountNotMet(uint256 minAmount, uint256 amountOut);

    event LiquidityAdded(
        address indexed token,
        address indexed by,
        uint256 amount
    );
    event LiquidityRemoved(
        address indexed token,
        address indexed by,
        uint256 amount
    );

    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 internal immutable _poolTokensLength;
    address internal _pool;
    address[] internal _poolTokens;

    /// @notice Constructor
    /// @param pool the pool address.
    /// @param poolTokens the tokens that can be deposited into this pool.
    constructor(address pool, address[] memory poolTokens) {
        _pool = pool;
        _poolTokens = poolTokens;
        _poolTokensLength = poolTokens.length;
        for (uint256 i = 0; i < _poolTokensLength; i++) {
            _poolTokens.push(poolTokens[i]);
        }
    }

    /// @notice Adds liquidity to a curve pool
    /// @param token the token to deposit
    /// @param amount the amount to deposit
    /// @param minAmountOut the minimum amount of LP token to receive for this deposit. Transaction will revert if receives less than this number.
    /// @return amountOut The amount of LP tokens received.
    function addLiquidity(
        address token,
        uint256 amount,
        uint256 minAmountOut
    ) external returns (uint256) {
        uint256 tokenIndex = _getTokenIndex(token);
        if (tokenIndex == type(uint256).max) {
            revert UnsupportedToken(token);
        }
        uint256[2] memory amounts;
        amounts[tokenIndex] = amount;
        address caller = msg.sender;
        IERC20(token).safeTransferFrom(caller, address(this), amount);
        IERC20(token).safeIncreaseAllowance(_pool, amount);
        uint256 amountOut = ICurvePlainPool(_pool).add_liquidity(
            amounts,
            minAmountOut
        );
        if (amountOut < minAmountOut) {
            revert MinAmountNotMet(minAmountOut, amountOut);
        }
        IERC20(_pool).safeTransfer(msg.sender, amountOut);
        return amountOut;
    }

    /// @notice Remove liquidity
    /// @dev Removes liquidity from curve pool. The tokens received will depend on the makeup of assets
    /// in the pool.
    /// @param token This is used to specify the min amount of this token you want to recieve
    /// @param lpTokenAmount The amount of LP token to burn in this withdrawal
    /// @param minAmountOut The min amount of `token` to receive.
    /// @return amountsReceived array containing the amounts of each token received.
    function removeLiquidity(
        address token,
        uint256 lpTokenAmount,
        uint256 minAmountOut
    ) external returns (uint256[2] memory) {
        uint256 tokenIndex = _getTokenIndex(token);
        if (tokenIndex == type(uint256).max) {
            revert UnsupportedToken(token);
        }
        uint256[2] memory minAmounts;
        minAmounts[tokenIndex] = minAmountOut;
        IERC20(_pool).safeTransferFrom(
            msg.sender,
            address(this),
            lpTokenAmount
        );
        IERC20(_pool).safeIncreaseAllowance(_pool, lpTokenAmount);
        uint256[2] memory amountsReceived = ICurvePlainPool(_pool)
            .remove_liquidity(lpTokenAmount, minAmounts);
        for (uint256 i = 0; i < _poolTokensLength; i++) {
            if (amountsReceived[i] != 0) {
                IERC20(_poolTokens[i]).safeTransfer(
                    msg.sender,
                    amountsReceived[i]
                );
            }
        }
        return amountsReceived;
    }

    /// @notice Remove liquidity and receive only one token
    /// @dev Removes liquidity from curve pool and receive only one token in return.
    /// @param token This is used to specify the min amount of this token you want to recieve
    /// @param lpTokenAmount The amount of LP token to burn in this withdrawal
    /// @param minAmountOut The min amount of `token` to receive.
    /// @return amountReceived The amount of `token` received.
    function removeLiquidityOneCoin(
        address token,
        uint256 lpTokenAmount,
        uint256 minAmountOut
    ) public returns (uint256) {
        uint256 tokenIndex = _getTokenIndex(token);
        if (tokenIndex == type(uint256).max) {
            revert UnsupportedToken(token);
        }
        IERC20(_pool).safeTransferFrom(
            msg.sender,
            address(this),
            lpTokenAmount
        );
        IERC20(_pool).safeIncreaseAllowance(_pool, lpTokenAmount);
        uint256 amountReceived = ICurvePlainPool(_pool)
            .remove_liquidity_one_coin(
                lpTokenAmount,
                tokenIndex.toInt256().toInt128(),
                minAmountOut
            );
        IERC20(token).safeTransfer(msg.sender, amountReceived);
        return amountReceived;
    }

    function removeLiquidityOneCoinByCoinAmount(
        address token,
        uint256 coinAmount,
        uint256 minAmountOut
    ) external returns (uint256) {
        uint256 lpTokenAmount = calculateLpTokenAmount(
            token,
            coinAmount,
            false // isDeposit
        );
        return removeLiquidityOneCoin(token, lpTokenAmount, minAmountOut);
    }

    function calculateLpTokenAmount(
        address token,
        uint256 tokenAmount,
        bool isDeposit
    ) public view returns (uint256) {
        uint256 tokenIndex = _getTokenIndex(token);
        if (tokenIndex == type(uint256).max) {
            revert UnsupportedToken(token);
        }
        uint256[2] memory amounts;
        amounts[tokenIndex] = tokenAmount;
        return ICurvePlainPool(_pool).calc_token_amount(amounts, isDeposit);
    }

    function calculateLpTokenAmountOneCoin(
        address token,
        uint256 lpTokenAmount
    ) external view returns (uint256) {
        uint256 tokenIndex = _getTokenIndex(token);
        if (tokenIndex == type(uint256).max) {
            revert UnsupportedToken(token);
        }
        return
            ICurvePlainPool(_pool).calc_withdraw_one_coin(
                lpTokenAmount,
                tokenIndex.toInt256().toInt128()
            );
    }

    function getLpTokenPrice() external view returns (uint256) {
        return ICurvePlainPool(_pool).get_virtual_price();
    }

    function getPool() external view returns (address) {
        return _pool;
    }

    function _getTokenIndex(address token) private view returns (uint256) {
        uint256 tokenLength = _poolTokens.length;
        for (uint256 i = 0; i < tokenLength; i++) {
            if (token == _poolTokens[i]) {
                return i;
            }
        }
        return type(uint256).max;
    }
}

