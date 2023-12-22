// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {TokenExposure, NetTokenExposure} from "./TokenExposure.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {RebalanceAction} from "./RebalanceAction.sol";
import {PositionManagerStats} from "./PositionManagerStats.sol";

abstract contract IPositionManager {
    event Compound(uint256 amount);
    event WethCompound(uint256 amount);

    modifier onlyVaultOrOwner() {
        require(
            msg.sender == protohedgeVaultAddress() ||
                msg.sender == contractOwner()
        );
        _;
    }

    uint256 public id;

    function name() public view virtual returns (string memory);

    function positionWorth() external view virtual returns (uint256);

    function costBasis() external view virtual returns (uint256);

    function pnl() external view virtual returns (int256);

    function exposures() external view virtual returns (TokenExposure[] memory);

    function allocations()
        external
        view
        virtual
        returns (TokenAllocation[] memory);

    function buy(uint256) external virtual returns (uint256);

    function sell(uint256) external virtual returns (uint256);

    function price() external view virtual returns (uint256);

    function canRebalance(
        uint256
    ) external view virtual returns (bool, string memory);

    function canCompound() external view virtual returns (bool);

    function compound() external virtual returns (uint256);

    function rebalance(
        uint256 usdcAmountToHave
    ) external virtual onlyVaultOrOwner returns (bool) {
        (RebalanceAction rebalanceAction, uint256 amountToBuyOrSell) = this
            .rebalanceInfo(usdcAmountToHave);

        if (rebalanceAction == RebalanceAction.Buy) {
            this.buy(amountToBuyOrSell);
        } else if (rebalanceAction == RebalanceAction.Sell) {
            this.sell(amountToBuyOrSell);
        }

        return true;
    }

    function rebalanceInfo(
        uint256 usdcAmountToHave
    ) public view virtual returns (RebalanceAction, uint256 amountToBuyOrSell) {
        RebalanceAction rebalanceAction = this.getRebalanceAction(
            usdcAmountToHave
        );
        uint256 worth = this.positionWorth();
        uint256 usdcAmountToBuyOrSell = rebalanceAction == RebalanceAction.Buy
            ? usdcAmountToHave - worth
            : worth - usdcAmountToHave;

        return (rebalanceAction, usdcAmountToBuyOrSell);
    }

    function allocationByToken(
        address tokenAddress
    ) external view returns (TokenAllocation memory) {
        TokenAllocation[] memory tokenAllocations = this.allocations();
        for (uint256 i = 0; i < tokenAllocations.length; i++) {
            if (tokenAllocations[i].tokenAddress == tokenAddress) {
                return tokenAllocations[i];
            }
        }

        revert("Token not found");
    }

    function getRebalanceAction(
        uint256 usdcAmountToHave
    ) external view returns (RebalanceAction) {
        uint256 worth = this.positionWorth();
        if (usdcAmountToHave > worth) return RebalanceAction.Buy;
        if (usdcAmountToHave < worth) return RebalanceAction.Sell;
        return RebalanceAction.Nothing;
    }

    function stats()
        external
        view
        virtual
        returns (PositionManagerStats memory)
    {
        return
            PositionManagerStats({
                positionManagerAddress: address(this),
                name: this.name(),
                positionWorth: this.positionWorth(),
                costBasis: this.costBasis(),
                pnl: this.pnl(),
                tokenExposures: this.exposures(),
                tokenAllocations: this.allocations(),
                price: this.price(),
                collateralRatio: this.collateralRatio(),
                loanWorth: 0,
                liquidationLevel: 0,
                collateral: 0
            });
    }

    function liquidate() external virtual;

    function collateralRatio() external view virtual returns (uint256);

    function protohedgeVaultAddress() public view virtual returns (address);

    function contractOwner() public view virtual returns (address);
}

