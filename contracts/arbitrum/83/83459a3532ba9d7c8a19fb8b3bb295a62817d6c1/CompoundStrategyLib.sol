// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {IOptionStrategy} from "./IOptionStrategy.sol";
import {IRouter} from "./IRouter.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

library CompoundStrategyLib {
    using FixedPointMathLib for uint256;

    /**
     * @notice Get current epoch and end time.
     */
    function epochEndTime(ICompoundStrategy self) external view returns (uint256, uint64) {
        uint256 _epoch = self.currentEpoch();
        return (_epoch, self.epochData(_epoch).endTime);
    }

    /**
     * @notice Get current epoch, end time and both option risks.
     */
    function epochEndTimeAndOptionRisk(ICompoundStrategy self)
        external
        view
        returns (uint256, uint64, uint256, uint256)
    {
        uint256 _epoch = self.currentEpoch();
        ICompoundStrategy.Epoch memory epochData = self.epochData(_epoch);
        return (_epoch, epochData.endTime, epochData.optionBullRisk, epochData.optionBearRisk);
    }

    /**
     * @notice Get current epoch, end time and withdraw rate.
     */
    function epochEndTimeAndWithdrawRates(ICompoundStrategy self, uint256 _epoch, IRouter.OptionStrategy _strategy)
        external
        view
        returns (uint256, uint256, uint256)
    {
        uint256 epoch_ = self.currentEpoch();
        ICompoundStrategy.Epoch memory epochData = self.epochData(_epoch);

        uint256 exchangeRate = _strategy == IRouter.OptionStrategy.BULL
            ? uint256(epochData.withdrawBullExchangeRate)
            : uint256(epochData.withdrawBearExchangeRate);

        return (epoch_, epochData.endTime, exchangeRate);
    }

    /**
     * @notice Get current epoch, end time and depsoit rate.
     */
    function epochEndTimeAndDepositRate(ICompoundStrategy self, uint256 _epoch, IRouter.OptionStrategy _strategy)
        external
        view
        returns (uint256, uint256, uint256)
    {
        uint256 epoch_ = self.currentEpoch();
        ICompoundStrategy.Epoch memory epochData = self.epochData(_epoch);
        uint256 rate;

        if (_strategy == IRouter.OptionStrategy.BULL) {
            rate = epochData.depositBullRatio;
        } else {
            rate = epochData.depositBearRatio;
        }

        return (epoch_, epochData.endTime, rate);
    }

    /**
     * @notice Get custom epoch, end time and flip rate.
     */
    function epochEndTimeAndFlipRate(
        ICompoundStrategy self,
        uint256 _targetEpoch,
        IRouter.OptionStrategy _oldStrategy,
        IRouter.OptionStrategy _newStrategy
    ) external view returns (uint256, uint256, uint256) {
        uint256 _epoch = self.currentEpoch();
        ICompoundStrategy.Epoch memory epochData;

        if (_targetEpoch == 0) {
            epochData = self.epochData(_epoch);
        } else {
            epochData = self.epochData(_targetEpoch - 1);
        }

        uint256 flipRate;

        if (_oldStrategy == IRouter.OptionStrategy.BULL && _newStrategy == IRouter.OptionStrategy.BEAR) {
            flipRate = uint256(epochData.flipBullToBearExchangeRate);
        }
        if (_oldStrategy == IRouter.OptionStrategy.BULL && _newStrategy == IRouter.OptionStrategy.CRAB) {
            flipRate = uint256(epochData.flipBullToCrabExchangeRate);
        }
        if (_oldStrategy == IRouter.OptionStrategy.BEAR && _newStrategy == IRouter.OptionStrategy.BULL) {
            flipRate = uint256(epochData.flipBearToBullExchangeRate);
        }
        if (_oldStrategy == IRouter.OptionStrategy.BEAR && _newStrategy == IRouter.OptionStrategy.CRAB) {
            flipRate = uint256(epochData.flipBearToCrabExchangeRate);
        }
        if (_oldStrategy == IRouter.OptionStrategy.CRAB && _newStrategy == IRouter.OptionStrategy.BULL) {
            flipRate = uint256(epochData.flipCrabToBullExchangeRate);
        }
        if (_oldStrategy == IRouter.OptionStrategy.CRAB && _newStrategy == IRouter.OptionStrategy.BEAR) {
            flipRate = uint256(epochData.flipCrabToBearExchangeRate);
        }

        return (_epoch, epochData.endTime, flipRate);
    }

    /**
     * @notice Get current epoch, shares with penalty, retention incentive and incentive receiver.
     */
    function retentionAndPenalty(ICompoundStrategy self, uint256 _shares, IRouter.OptionStrategy _strategy)
        external
        view
        returns (uint256, uint256, uint256, uint256, address)
    {
        uint256 _epoch = self.currentEpoch();
        ICompoundStrategy.Epoch memory epochData = self.epochData(_epoch);

        uint256 sharesWithPenalty;

        if (_strategy == IRouter.OptionStrategy.BULL) {
            sharesWithPenalty = _shares - _shares.mulDivDown(epochData.optionBullRisk, 1e12);
        } else if (_strategy == IRouter.OptionStrategy.BEAR) {
            sharesWithPenalty = _shares - _shares.mulDivDown(epochData.optionBearRisk, 1e12);
        } else {
            sharesWithPenalty = _shares;
        }

        return (_epoch, epochData.endTime, sharesWithPenalty, self.retentionIncentive(), self.incentiveReceiver());
    }
}

