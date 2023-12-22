// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "./console.sol";


enum SwapKind {
    BUY,
    SELL
}

enum SwapKindReaction {
    BUYS,
    SELLS,
    ALL
}



interface ITaxSlotSellDecision {
    function shouldSellTaxTokensToWeth() external view returns (bool);
    function reactOnSwapsKind() external view returns (SwapKindReaction);
}

interface ITaxSlotForWeth is ITaxSlotSellDecision {
    function receiveTaxInWeth(
        address _actor,
        uint256 _tokenAmount,
        uint256 _wethAmount,
        SwapKind _swapKind
    ) external;

}

interface ITaxSlotForTokens is ITaxSlotSellDecision {
    function receiveTaxInTokens(
        address _actor,
        uint256 _tokenAmount,
        SwapKind _swapKind
    ) external;
}

