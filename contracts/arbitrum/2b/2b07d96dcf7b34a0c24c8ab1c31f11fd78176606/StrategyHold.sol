// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";
import {IPSwapAggregator, IPRouter, IPMarket, ILpOracleHelper} from "./IPendle.sol";

interface IPair is IERC20 {
    function token0() external view returns (IERC20);
    function token1() external view returns (IERC20);
    function burn(address) external;
}

interface ICamelot {
    function tokenId() external view returns (uint256);
    function getStakingPosition(uint256 id) external view returns (uint256);
    function withdrawFromPosition(uint256 id, uint256 amt) external;
}

contract StrategyHold is Strategy {
    string public name = "Hold";
    IERC20 public token;

    constructor(address _strategyHelper, address _token) Strategy(_strategyHelper) {
        token = IERC20(_token);
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        uint256 val = strategyHelper.value(address(token), token.balanceOf(address(this)));
        return sha * val / totalShares;
    }

    function _mint(address, uint256, bytes calldata) internal override returns (uint256) {
        revert("Strategy on hold");
    }

    function _burn(address, uint256 sha, bytes calldata) internal override returns (uint256) {
        uint256 tma = token.balanceOf(address(this));
        uint256 amt = sha * tma / totalShares;
        token.transfer(msg.sender, amt);
        return amt;
    }

    function _earn() internal override {}

    function _move(address old) internal override {
        name = string(abi.encodePacked("Hold ", StrategyHold(old).name()));
        IPair pair = IPair(0xBfCa4230115DE8341F3A3d5e8845fFb3337B2Be3);
        IPSwapAggregator.SwapData memory swapData = IPSwapAggregator.SwapData({
            swapType: IPSwapAggregator.SwapType.NONE,
            extRouter: address(0),
            extCalldata: "",
            needScale: false
        });
        IPRouter.TokenOutput memory output = IPRouter.TokenOutput({
            tokenOut: address(pair),
            minTokenOut: 0,
            tokenRedeemSy: address(pair),
            bulk: address(0),
            pendleSwap: address(0),
            swapData: swapData
        });

        address market = 0x24e4Df37ea00C4954d668e3ce19fFdcffDEc2cF6;
        uint256 amt = IERC20(market).balanceOf(address(this));
        IERC20(market).approve(0x0000000001E4ef00d069e71d6bA041b0A16F7eA0, amt);
        (uint256 netTokenOut,) = IPRouter(0x0000000001E4ef00d069e71d6bA041b0A16F7eA0).removeLiquiditySingleToken(address(this), market, amt, output);
        pair.transfer(address(pair), netTokenOut);
        pair.burn(address(this));
        swap(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
        swap(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    }

    function _exit(address str) internal override {
        push(token, str, token.balanceOf(address(this)));
    }

    function swap(address _tok) internal {
        IERC20 tok = IERC20(_tok);
        uint256 amt = tok.balanceOf(address(this));
        tok.approve(address(strategyHelper), amt);
        strategyHelper.swap(address(tok), address(token), amt, slippage, address(this));
    }

    function onNFTWithdraw(address, uint256, uint256) public returns (bool) {
        return true;
    }

    function onNFTHarvest(address, address, uint256, uint256, uint256) public returns (bool) {
        return true;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return StrategyHold.onERC721Received.selector;
    }
}

