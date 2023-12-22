// SPDX-License-Identifier: UNLINCESED
pragma solidity 0.8.20;

import { Swapper } from "./Swapper.sol";
import { Quoter } from "./Quoter.sol";
import { LibSwap } from "./LibSwap.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { LibUtil } from "./LibUtil.sol";
import { LibAsset } from "./LibAsset.sol";

error InvalidReceiver();

contract OneTwoRouterFacet is Swapper, Quoter, ReentrancyGuard {
    function oneTwoSwap(
        address payable _receiver,
        uint256 _fromAmount,
        uint256 _minAmout,
        address _weth,
        address _partner,
        LibSwap.SwapData[] calldata _swaps
    ) external payable nonReentrant{
        if (LibUtil.isZeroAddress(_receiver)) revert InvalidReceiver();

        uint256 receivedAmount = _swap(
            _fromAmount,
            _minAmout,
            _weth,
            _swaps,
            0,
            _partner
        );

        address receivedToken = _swaps[_swaps.length - 1].toToken;
        LibAsset.transferAsset(receivedToken, _receiver, receivedAmount);
    }

    function oneTwoQuote(
        address,
        uint256 _fromAmount,
        uint256,
        address _weth,
        address,
        LibSwap.SwapData[] calldata _swaps
    ) public returns(uint256) {
        uint256 receivedAmount = _quote(
            _fromAmount,
            0,
            _weth,
            _swaps,
            0,
            address(0)
        );
        return receivedAmount;
    }
}
