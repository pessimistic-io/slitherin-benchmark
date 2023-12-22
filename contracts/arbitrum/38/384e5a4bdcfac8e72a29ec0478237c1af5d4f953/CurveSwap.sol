// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Proxy.sol";
import "./IWETH9.sol";
import "./SafeERC20.sol";

interface ICurveSwap {
    function exchange_multiple(
        address[9] memory _route,
        uint256[3][4] memory _swap_params,
        uint256 _amount,
        uint256 _expected,
        address[4] memory _pools,
        address _receiver
    ) external payable returns (uint256);
}

/// @title Curve swap proxy contract
/// @author Matin Kaboli
/// @notice Exchanges tokens from different pools
contract CurveSwap is Proxy {
    using SafeERC20 for IERC20;

    ICurveSwap public immutable CurveSwapInterface;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Receives swap contract address
    /// @param _curveSwap Swap contract address
    constructor(Permit2 _permit2, IWETH9 _weth, ICurveSwap _curveSwap) Proxy(_permit2, _weth) {
        CurveSwapInterface = _curveSwap;
    }

    /// @notice Perform up to four swaps in a single transaction
    /// @dev Routing and swap params must be determined off-chain. This functionality is designed for gas efficiency over ease-of-use.
    /// @param _route Array of [initial token, pool, token, pool, token, ...]
    /// The array is iterated until a pool address of 0x00, then the last
    /// given token is transferred to `_receiver`
    /// @param _swap_params Multidimensional array of [i, j, swap type] where i and j are the correct
    /// values for the n'th pool in `_route`. The swap type should be
    /// 1 for a stableswap `exchange`,
    /// 2 for stableswap `exchange_underlying`,
    /// 3 for a cryptoswap `exchange`,
    /// 4 for a cryptoswap `exchange_underlying`,
    /// 5 for factory metapools with lending base pool `exchange_underlying`,
    /// 6 for factory crypto-meta pools underlying exchange (`exchange` method in zap),
    /// 7-9 for underlying coin -> LP token "exchange" (actually `add_liquidity`),
    /// 10-11 for LP token -> underlying coin "exchange" (actually `remove_liquidity_one_coin`)
    /// @param _expected The minimum amount received after the final swap.
    /// @param _pools Array of pools for swaps via zap contracts. This parameter is only needed for
    /// Polygon meta-factories underlying swaps.
    /// @param _permit Permit2 PermitTransferFrom struct, includes receiver, token and amount
    /// @param _signature Signature, used by Permit2
    function exchangeMultiple(
        address[9] memory _route,
        uint256[3][4] memory _swap_params,
        uint256 _expected,
        address[4] memory _pools,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata _signature
    ) external payable {
        permit2.permitTransferFrom(
            _permit,
            ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
            msg.sender,
            _signature
        );

        CurveSwapInterface.exchange_multiple(
            _route, _swap_params, _permit.permitted.amount, _expected, _pools, msg.sender
        );
    }

    /// @notice Perform up to four swaps in a single transaction
    /// @dev Routing and swap params must be determined off-chain. This functionality is designed for gas efficiency over ease-of-use.
    /// @param _route Array of [initial token, pool, token, pool, token, ...]
    /// The array is iterated until a pool address of 0x00, then the last
    /// given token is transferred to `_receiver`
    /// @param _swap_params Multidimensional array of [i, j, swap type] where i and j are the correct
    /// values for the n'th pool in `_route`. The swap type should be
    /// 1 for a stableswap `exchange`,
    /// 2 for stableswap `exchange_underlying`,
    /// 3 for a cryptoswap `exchange`,
    /// 4 for a cryptoswap `exchange_underlying`,
    /// 5 for factory metapools with lending base pool `exchange_underlying`,
    /// 6 for factory crypto-meta pools underlying exchange (`exchange` method in zap),
    /// 7-9 for underlying coin -> LP token "exchange" (actually `add_liquidity`),
    /// 10-11 for LP token -> underlying coin "exchange" (actually `remove_liquidity_one_coin`)
    /// @param _amount The amount of `_route[0]` token being sent.
    /// @param _expected The minimum amount received after the final swap.
    /// @param _pools Array of pools for swaps via zap contracts. This parameter is only needed for
    /// Polygon meta-factories underlying swaps.
    /// @param _fee Fee of the proxy
    function exchangeMultipleEth(
        address[9] memory _route,
        uint256[3][4] memory _swap_params,
        uint256 _amount,
        uint256 _expected,
        address[4] memory _pools,
        uint256 _fee
    ) external payable {
        uint256 ethValue = 0;

        ethValue = msg.value - _fee;

        CurveSwapInterface.exchange_multiple{value: ethValue}(
            _route, _swap_params, _amount, _expected, _pools, msg.sender
        );
    }
}

