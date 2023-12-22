// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

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
        IPair pool = IPair(0x905dfCD5649217c42684f23958568e533C711Aa3);
        pool.transfer(address(pool), pool.balanceOf(address(this)));
        pool.burn(address(this));
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

