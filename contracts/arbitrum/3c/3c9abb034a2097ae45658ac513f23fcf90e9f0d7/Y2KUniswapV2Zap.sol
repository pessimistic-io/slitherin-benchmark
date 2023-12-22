// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IUniswapPair} from "./IUniswapPair.sol";
import {IEarthquake} from "./IEarthquake.sol";
import {IErrors} from "./IErrors.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";
import {IPermit2} from "./IPermit2.sol";

contract Y2KUniswapV2Zap is IErrors, ISignatureTransfer {
    using SafeTransferLib for ERC20;
    address public immutable uniswapV2ForkFactory;
    IPermit2 public immutable permit2;

    constructor(address _sushiV2Factory, address _permit2) {
        if (_sushiV2Factory == address(0)) revert InvalidInput();
        if (_permit2 == address(0)) revert InvalidInput();
        uniswapV2ForkFactory = _sushiV2Factory;
        permit2 = IPermit2(_permit2);
    }

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    function zapIn(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver
    ) external {
        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), fromAmount);
        uint256 amountOut = _swap(path, fromAmount, toAmountMin);
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    function zapInPermit(
        address[] calldata path,
        uint256 toAmountMin,
        uint256 id,
        address vaultAddress,
        address receiver,
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        bytes calldata sig
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, sig);
        uint256 amountOut = _swap(
            path,
            transferDetails.requestedAmount,
            toAmountMin
        );
        _deposit(path[path.length - 1], id, amountOut, vaultAddress, receiver);
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    function _deposit(
        address fromToken,
        uint256 id,
        uint256 amountIn,
        address vaultAddress,
        address receiver
    ) private {
        ERC20(fromToken).safeApprove(vaultAddress, amountIn);
        IEarthquake(vaultAddress).deposit(id, amountIn, receiver);
    }

    function _swap(
        address[] calldata path,
        uint256 fromAmount,
        uint256 toAmountMin
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

        // NOTE: Use amountOut to reduce declaration of additional variable
        amountOut = fromAmount;
        for (uint256 i = 0; i < path.length - 1; ) {
            {
                address fromToken = path[i];
                address toToken = path[i + 1];

                pairs[i] = _getPair(fromToken, toToken);
                (uint256 reserveA, uint256 reserveB, ) = IUniswapPair(pairs[i])
                    .getReserves();

                if (fromToken > toToken)
                    (reserveA, reserveB) = (reserveB, reserveA);

                amounts[i] =
                    ((amountOut * 997) * reserveB) /
                    ((reserveA * 1000) + (amountOut * 997));
                amountOut = amounts[i];
            }

            unchecked {
                i++;
            }
        }

        if (amounts[amounts.length - 1] < toAmountMin)
            revert InvalidMinOut(amounts[amounts.length - 1]);

        SafeTransferLib.safeTransfer(ERC20(path[0]), pairs[0], fromAmount);

        return _executeSwap(path, pairs, amounts);
    }

    function _getPair(
        address tokenA,
        address tokenB
    ) internal view returns (address pair) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            uniswapV2ForkFactory,
                            keccak256(abi.encodePacked(tokenA, tokenB)),
                            hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303" // init code hash
                        )
                    )
                )
            )
        );
    }

    function _executeSwap(
        address[] memory path,
        address[] memory pairs,
        uint256[] memory amounts
    ) internal returns (uint256) {
        bool zeroForOne = path[0] < path[1];
        if (pairs.length > 1) {
            IUniswapPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                pairs[1],
                ""
            );
            for (uint256 i = 1; i < pairs.length - 1; ) {
                zeroForOne = path[i] < path[i + 1];
                IUniswapPair(pairs[i]).swap(
                    zeroForOne ? 0 : amounts[i],
                    zeroForOne ? amounts[i] : 0,
                    pairs[i + 1],
                    ""
                );
                unchecked {
                    i++;
                }
            }
            zeroForOne = path[path.length - 2] < path[path.length - 1];
            IUniswapPair(pairs[pairs.length - 1]).swap(
                zeroForOne ? 0 : amounts[pairs.length - 1],
                zeroForOne ? amounts[pairs.length - 1] : 0,
                address(this),
                ""
            );
        } else {
            IUniswapPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                address(this),
                ""
            );
        }

        return amounts[amounts.length - 1];
    }
}

