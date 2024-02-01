// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeCast.sol";
import "./Multicall.sol";
import "./IBank.sol";

abstract contract Bank is ReentrancyGuardUpgradeable, IBank {
    address public market;
    uint256[64] private __gap;

    modifier onlyMarket() {
        require(msg.sender == market, "only market");
        _;
    }

    function bindMarket(address market_) external {
        require(market_ != address(0), "market_ cannot be Zero Address");
        if (market == address(0)) {
            market = market_;
        } else {
            require(market == market_, "market was bind");
        }
    }
}

