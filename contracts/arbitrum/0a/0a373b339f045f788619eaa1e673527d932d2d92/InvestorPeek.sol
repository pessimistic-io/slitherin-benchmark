// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IInvestor} from "./IInvestor.sol";
import {IStrategy} from "./IStrategy.sol";

contract InvestorPeek {
    uint256 private constant ONE_YEAR = 31536000;
    IInvestor public immutable i;

    constructor(address _i) {
        i = IInvestor(_i);
    }

    function peek()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        (uint256 borrowIndex, uint256 supplyIndex) = indexes();
        uint256 totalSupply = i.totalSupply() * supplyIndex / 1e18;
        uint256 totalBorrow = i.totalBorrow() * borrowIndex / 1e18;
        uint256 utilization = 0;
        if (totalSupply > 0) {
            utilization = totalBorrow * 1e18 / totalSupply;
        }
        uint256 supplyRate = i.getSupplyRate(utilization) * ONE_YEAR;
        uint256 borrowRate = i.getBorrowRate(utilization) * ONE_YEAR;
        return (
            utilization,
            supplyIndex,
            borrowIndex,
            supplyRate,
            borrowRate,
            totalSupply,
            totalBorrow
        );
    }

    function peekPosition(uint256 id)
        external
        view
        returns (
            string memory,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 borrowIndex,) = indexes();
        (, address strategy, uint256 ini, uint256 sha, uint256 bor) =
            i.positions(id);
        uint256 health = i.life(id);
        return (
            IStrategy(strategy).name(),
            ini,
            sha,
            IStrategy(strategy).rate(sha),
            bor * borrowIndex / 1e18,
            i.getBorrowRate(i.getUtilization()) * ONE_YEAR,
            health
        );
    }

    function indexes() internal view returns (uint256, uint256) {
        uint256 borrowIndex = i.borrowIndex();
        uint256 supplyIndex = i.supplyIndex();
        uint256 utilization = i.getUtilization();
        uint256 time = block.timestamp - i.lastGain();
        borrowIndex +=
            (borrowIndex * i.getBorrowRate(utilization) * time) / 1e18;
        supplyIndex +=
            (supplyIndex * i.getSupplyRate(utilization) * time) / 1e18;
        return (borrowIndex, supplyIndex);
    }
}

