// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./CurvePool.sol";
import "./SafeERC20.sol";

interface Pool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint) external payable;
    function remove_liquidity(uint256 _amount, uint256[2] memory min_amounts) external;
    function remove_liquidity_one_coin(uint256 _amount, uint256 _i, uint256 _min) external returns (uint256);
    function remove_liquidity_one_coin(uint256 _amount, int128 _i, uint256 _min) external returns (uint256);
}

/// @title Curve proxy contract
/// @author Matin Kaboli
/// @notice Add/Remove liquidity, and exchange tokens in a pool
/// @dev works for different pools, but use with caution (tested only for StableSwap)
contract Curve2Token is CurvePool {
    using SafeERC20 for IERC20;

    constructor(
        Permit2 _permit2,
        IWETH9 _weth,
        address _pool,
        address[] memory _tokens,
        address _token,
        uint8 _ethIndex
    ) CurvePool(_permit2, _weth, _pool, _tokens, _token, _ethIndex) {}

    /// @notice Adds liquidity to a pool
    /// @param _minMintAmount Minimum liquidity expected to receive after adding liquidity
    /// @param _fee Fee of the proxy
    function addLiquidity(
        ISignatureTransfer.PermitBatchTransferFrom calldata _permit,
        bytes calldata _signature,
        uint256[2] memory _amounts,
        uint256 _minMintAmount,
        uint256 _fee
    ) public payable {
        uint256 ethValue = 0;

        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](_permit.permitted.length);

        for (uint8 i = 0; i < _permit.permitted.length; ++i) {
            details[i].to = address(this);
            details[i].requestedAmount = _permit.permitted[i].amount;
        }

        permit2.permitTransferFrom(_permit, details, msg.sender, _signature);

        if (ethIndex != 100) {
            ethValue = msg.value - _fee;
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        Pool(pool).add_liquidity{value: ethValue}(_amounts, _minMintAmount);

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        IERC20(token).transfer(msg.sender, balanceAfter - balanceBefore);
    }

    /// @notice Removes liquidity from the pool
    /// @param minAmounts Minimum amounts expected to receive after withdrawal
    function removeLiquidity(
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature,
        uint256[2] memory minAmounts
    ) public payable {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        uint256 balance0Before = getBalance(0);
        uint256 balance1Before = getBalance(1);

        Pool(pool).remove_liquidity(_permit.permitted.amount, minAmounts);

        uint256 balance0After = getBalance(0);
        uint256 balance1After = getBalance(1);

        send(0, balance0After - balance0Before);
        send(1, balance1After - balance1Before);
    }

    /// @notice Removes liquidity and received only 1 token in return
    /// @dev Use this for those pools that use int128 for _i
    /// @param _i Index of receiving token in the pool
    /// @param min_amount Minimum amount expected to receive from token[i]
    function removeLiquidityOneCoinI(
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature,
        int128 _i,
        uint256 min_amount
    ) public payable {
        uint256 i = 0;
        if (_i == 1) {
            i = 1;
        }

        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        uint256 balanceBefore = getBalance(i);

        Pool(pool).remove_liquidity_one_coin(_permit.permitted.amount, _i, min_amount);

        uint256 balanceAfter = getBalance(i);

        send(i, balanceAfter - balanceBefore);
    }

    /// @notice Removes liquidity and received only 1 token in return
    /// @dev Use this for those pools that use uint256 for _i
    /// @param _i Index of receiving token in the pool
    /// @param min_amount Minimum amount expected to receive from token[i]
    function removeLiquidityOneCoinU(
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature,
        uint256 _i,
        uint256 min_amount
    ) public payable {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        uint256 balanceBefore = getBalance(_i);

        Pool(pool).remove_liquidity_one_coin(_permit.permitted.amount, _i, min_amount);

        uint256 balanceAfter = getBalance(_i);

        send(_i, balanceAfter - balanceBefore);
    }
}

