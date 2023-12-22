// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.18;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { ERC20OnceSetter } from "./ERC20OnceSetter.sol";
import { Ownable } from "./Ownable.sol";
import { ITaxSlotForTokens, ITaxSlotForWeth, ITaxSlotSellDecision, SwapKind, SwapKindReaction } from "./ITaxSlot.sol";



contract IceDogeVaultForWeth is ITaxSlotForWeth, Ownable {
    IERC20 public immutable WETH;

    constructor(IERC20 _weth) {
        WETH = _weth;
    }

    function withdrawCollected() public {
        WETH.transferFrom(msg.sender, owner(), WETH.balanceOf(address(this)));
    }

    // token callback
    function receiveTaxInWeth(
        address _actor,
        uint256 _tokenAmount,
        uint256 _wethAmount,
        SwapKind _swapKind
    ) external {
        WETH.transferFrom(msg.sender, address(this), _wethAmount);
    }

    function shouldSellTaxTokensToWeth()
        external
        pure
        override
        returns (bool)
    {
        return true;
    }

    function reactOnSwapsKind() external pure override returns (SwapKindReaction) {
        return SwapKindReaction.ALL;
    }
}

