// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./IFeeder.sol";
import "./ITrade.sol";
import "./IRegistry.sol";
import "./IDripOperator.sol";
import "./IPriceFeed.sol";
import "./Upgradeable.sol";

import "./console.sol";

// @address:REGISTRY
IRegistry constant registry = IRegistry(0x5517dB2A5C94B3ae95D3e2ec12a6EF86aD5db1a5);

contract DripOperator is Upgradeable, IDripOperator {

    struct ReportState {
        bool isReporting;
        uint256 tokenSupply;
        uint256 depositTvl;
        uint256 debt;
        uint256 toWithdraw;
        bool withdrawalsProcessed;
        uint256 finalTvl;
        uint256 withdrawTvl;
    }

    mapping (uint256 => ReportState) public reportState;
    mapping (uint256 => uint256) public reportDates;
    uint256 public reportDelay;

    function initialize(uint256 _reportDelay) public initializer {
        __Ownable_init();
        reportDelay = _reportDelay;
    }

    function drip(uint256 fundId, uint256 tradeTvl) external override returns (bool) {
        require(msg.sender == address(registry.interaction()), "DO/SNI"); // sender not interaction
        require(isDripEnabled(fundId), "DO/DNE"); // delay not expired
        IFeeder feeder = registry.feeder();
        IFeeder.FundInfo memory fund = feeder.getFund(fundId);
        if (!reportState[fundId].isReporting) {
            uint256 executionFee = feeder.getPendingExecutionFee(fundId, tradeTvl, 0);
            uint256 tvlAfterEF = tradeTvl > executionFee ? tradeTvl - executionFee : tradeTvl;
            (uint256 toDeposit, uint256 toWithdraw, uint256 pf) = feeder.pendingTvl(fundId, tvlAfterEF);
            reportState[fundId] = ReportState(
                true,
                fund.itoken.totalSupply(),
                tradeTvl - pf,
                0,
                feeder.fundTotalWithdrawals(fundId),
                false,
                tradeTvl + toDeposit - toWithdraw - pf - executionFee,
                tvlAfterEF - pf
            );
            int256 toFeeder = int256(toWithdraw) + int256(pf) + int256(executionFee);
            int256 subtracted = toFeeder - int256(ITrade(fund.trade).usdtAmount());
            if (subtracted > 0) {
                require(uint256(subtracted) < toDeposit, "DO/NEL"); // not enough liquidity (deposits or usdt on Trade)
                toFeeder -= subtracted;
                reportState[fundId].debt = uint256(subtracted);
            }

            if (toFeeder > 0) {
                feeder.transferFromTrade(fundId, uint256(toFeeder));
            }

            feeder.gatherFees(fundId, tvlAfterEF, executionFee);
        }
        uint256 batchSize = MAX_USERS_PER_BATCH;
        ReportState storage _reportState = reportState[fundId];
        (uint256 depositsProcessed, uint256 debtLeft) = feeder.drip(
            fundId,
            _reportState.debt,
            _reportState.tokenSupply,
            _reportState.depositTvl,
            batchSize
        );
        _reportState.debt = debtLeft;
        batchSize -= depositsProcessed;
        if (batchSize == 0) {
            return false;
        }
        if (!_reportState.withdrawalsProcessed) {
            uint256 withdrawalsProcessed = feeder.withdrawMultiple(
                fundId,
                _reportState.tokenSupply,
                _reportState.toWithdraw,
                _reportState.withdrawTvl,
                batchSize
            );
            batchSize -= withdrawalsProcessed;
            if (batchSize == 0) {
                return false;
            }
        }
        _reportState.withdrawalsProcessed = true;
        uint256 indentedWithdrawalsLeft = feeder.moveIndentedWithdrawals(fundId, batchSize);
        if (indentedWithdrawalsLeft == 0) {
            feeder.saveHWM(fundId, _reportState.finalTvl);
            delete reportState[fundId];
            reportDates[fundId] = block.timestamp;
            return true;
        } else {
            return false;
        }
    }

    function isDripInProgress(uint256 fundId) external view returns (bool) {
        return reportState[fundId].isReporting;
    }

    function isDripEnabled(uint256 fundId) public override view returns (bool) {
        return reportDates[fundId] == 0 || block.timestamp > reportDates[fundId] + reportDelay;
    }
}
