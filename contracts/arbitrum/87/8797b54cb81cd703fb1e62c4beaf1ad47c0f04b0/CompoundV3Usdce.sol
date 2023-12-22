// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {LocalDefii} from "./LocalDefii.sol";
import {Supported1Token} from "./Supported1Token.sol";

import "./arbitrumOne.sol";

contract CompoundV3Usdce is LocalDefii, Supported1Token {
    // contracts
    CometMainInterface constant comet =
        CometMainInterface(0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA);

    constructor()
        Supported1Token(USDCe)
        LocalDefii(ONEINCH_ROUTER, USDC, "Compound V3 Arbitrum USDC.e")
    {
        IERC20(USDCe).approve(address(comet), type(uint256).max);
    }

    function totalLiquidity() public view override returns (uint256) {
        return comet.balanceOf(address(this));
    }

    function _enterLogic() internal override {
        comet.supply(USDCe, IERC20(USDCe).balanceOf(address(this)));
    }

    function _exitLogic(uint256 liquidity) internal override {
        comet.withdraw(USDCe, liquidity);
    }

    function _returnUnusedFunds(address recipient) internal override {
        // we use all funds (all token balance) in enter
    }
}

interface CometMainInterface {
    function supply(address asset, uint amount) external;

    function withdraw(address asset, uint amount) external;

    function balanceOf(address owner) external view returns (uint256);
}

