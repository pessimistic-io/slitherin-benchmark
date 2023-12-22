// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { IERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { PerpMath } from "./PerpMath.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { IRewardMiner } from "./IRewardMiner.sol";
import { BlockContext } from "./BlockContext.sol";
import { RewardMinerStorage } from "./RewardMinerStorage.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract RewardMiner is IRewardMiner, BlockContext, OwnerPausable, RewardMinerStorage {
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using PerpSafeCast for uint256;
    using PerpSafeCast for int256;
    using PerpMath for uint256;
    using PerpMath for int256;

    event Mint(uint256 indexed periodNumber, address indexed trader, uint256 amount);
    event MintWithPnl(uint256 indexed periodNumber, address indexed trader, uint256 amount, int256 pnl);
    event Spend(address indexed trader, uint256 amount);

    //
    // EXTERNAL NON-VIEW
    //

    function _requireOnlyClearingHouse() internal view {
        // only ClearingHouse
        require(_msgSender() == _clearingHouse, "RM_OCH");
    }

    /// @dev this function is public for testing
    // solhint-disable-next-line func-order
    function initialize(
        address clearingHouseArg,
        address pnftTokenArg,
        uint256 periodDurationArg,
        uint256[] memory starts,
        uint256[] memory ends,
        uint256[] memory totals,
        uint256 limitClaimPeriodArg
    ) public initializer {
        // ClearingHouse address is not contract
        // _isContract(clearingHouseArg, "RM_CHNC");
        _isContract(pnftTokenArg, "RM_PTNC");
        require(periodDurationArg > 0, "RM_PDZ");
        require(starts.length == ends.length && ends.length == totals.length, "RM_IL");

        __OwnerPausable_init();

        _clearingHouse = clearingHouseArg;
        _pnftToken = pnftTokenArg;
        _periodDuration = periodDurationArg;
        _limitClaimPeriod = limitClaimPeriodArg;

        for (uint256 i = 0; i < ends.length; i++) {
            // RM_ISE: invalid start end
            require(starts[i] <= ends[i], "RM_ISE");
            if (i > 0) {
                // RM_IS: invalid start
                require(starts[i] > starts[i - 1], "RM_IS");
            }
            // RM_IT: invalid total
            require(totals[i] > 0, "RM_IT");
            PeriodConfig memory cfg = PeriodConfig({ start: starts[i], end: ends[i], total: totals[i] });
            _periodConfigs.push(cfg);
        }
    }

    function _isContract(address contractArg, string memory errorMsg) internal view {
        require(contractArg.isContract(), errorMsg);
    }

    function setClearingHouse(address clearingHouseArg) external {
        _isContract(clearingHouseArg, "RM_CHNC");
        _clearingHouse = clearingHouseArg;
    }

    // function setPnftToken(address pnftTokenArg) external {
    //     _isContract(pnftTokenArg, "RM_PTNC");
    //     _pnftToken = pnftTokenArg;
    // }

    function setLimitClaimPeriod(uint256 limitClaimPeriodArg) external {
        _limitClaimPeriod = limitClaimPeriodArg;
    }

    function getLimitClaimPeriod() external view returns (uint256 limitClaimPeriod) {
        limitClaimPeriod = _limitClaimPeriod;
    }

    function getPeriodDuration() external view returns (uint256 periodDuration) {
        periodDuration = _periodDuration;
    }

    function getStart() external view returns (uint256 start) {
        start = _start;
    }

    function getStartPnlNumber() external view returns (uint256 startPnlNumber) {
        startPnlNumber = _startPnlNumber;
    }

    function getAllocation() external view returns (uint256 allocation) {
        allocation = _allocation;
    }

    function getSpend() external view returns (uint256 spend) {
        spend = _spend;
    }

    function getCurrentPeriodInfo()
        external
        view
        returns (uint256 periodNumber, uint256 start, uint256 end, uint256 total, uint256 amount, int256 pnlAmount)
    {
        periodNumber = _getPeriodNumber();
        (start, end, total, amount, pnlAmount) = _getCurrentPeriodInfoByNumner(periodNumber);
    }

    function getCurrentPeriodInfoByNumner(
        uint256 periodNumber
    ) external view returns (uint256 start, uint256 end, uint256 total, uint256 amount, int256 pnlAmount) {
        (start, end, total, amount, pnlAmount) = _getCurrentPeriodInfoByNumner(periodNumber);
    }

    function _getCurrentPeriodInfoByNumner(
        uint256 periodNumber
    ) internal view returns (uint256 start, uint256 end, uint256 total, uint256 amount, int256 pnlAmount) {
        (start, end, total, amount, pnlAmount) = _getPeriodInfo(periodNumber);
    }

    function getCurrentPeriodInfoTrader(
        address trader
    )
        external
        view
        returns (
            uint256 periodNumber,
            uint256 start,
            uint256 end,
            uint256 total,
            uint256 amount,
            int256 pnlAmount,
            uint256 traderAmount,
            int256 traderPnl
        )
    {
        periodNumber = _getPeriodNumber();
        (start, end, total, amount, pnlAmount, traderAmount, traderPnl) = _getCurrentPeriodInfoTrader(
            trader,
            periodNumber
        );
    }

    function _getCurrentPeriodInfoTrader(
        address trader,
        uint256 periodNumber
    )
        internal
        view
        returns (
            uint256 start,
            uint256 end,
            uint256 total,
            uint256 amount,
            int256 pnlAmount,
            uint256 traderAmount,
            int256 traderPnl
        )
    {
        (start, end, total, amount, pnlAmount) = _getPeriodInfo(periodNumber);
        traderAmount = _periodDataMap[periodNumber].users[trader];
        traderPnl = _periodDataMap[periodNumber].pnlUsers[trader];
    }

    function _getPeriodInfo(
        uint256 periodNumber
    ) internal view returns (uint256 start, uint256 end, uint256 total, uint256 amount, int256 pnlAmount) {
        require(_blockTimestamp() >= _start, "RM_IT");
        PeriodData storage periodData = _periodDataMap[periodNumber];
        if (periodData.periodNumber != 0) {
            total = periodData.total;
            amount = periodData.amount;
            pnlAmount = periodData.pnlAmount;
        } else {
            for (uint256 i = 0; i < _periodConfigs.length; i++) {
                PeriodConfig memory cfg = _periodConfigs[i];
                if (cfg.start <= periodNumber && periodNumber <= cfg.end) {
                    total = cfg.total;
                }
            }
        }
        start = _start + (periodNumber - 1) * _periodDuration;
        end = start + _periodDuration;
    }

    function getPeriodNumber() external view returns (uint256 periodNumber) {
        return _getPeriodNumber();
    }

    function _getPeriodNumber() internal view returns (uint256 periodNumber) {
        uint256 timestamp = _blockTimestamp();
        require(timestamp >= _start, "RM_IT");
        periodNumber = timestamp.sub(_start).div(_periodDuration).add(1);
    }

    function _createPeriodData() internal returns (PeriodData storage periodData) {
        uint256 periodNumber = _getPeriodNumber();
        periodData = _periodDataMap[periodNumber];
        if (periodData.periodNumber == 0) {
            (, , uint256 total, , ) = _getPeriodInfo(periodNumber);
            if (total > 0) {
                // periodData
                periodData.periodNumber = periodNumber;
                periodData.total = total;
                _periodNumbers.push(periodData.periodNumber);
                // _allocation
                _allocation = _allocation.add(total);
            }
        }
    }

    function getClaimable(address trader) external view returns (uint256 amount) {
        return _getClaimable(trader);
    }

    struct InternalSetClaimableVars {
        uint256 periodNumber;
        uint256 lastPeriodNumber;
        int256 endPeriod;
        uint256 userAmount;
        int256 pnlUserAmount;
    }

    function _getClaimable(address trader) internal view returns (uint256 amount) {
        InternalSetClaimableVars memory vars;
        vars.periodNumber = _getPeriodNumber();
        vars.lastPeriodNumber = _lastClaimPeriodNumberMap[trader];
        if (_periodNumbers.length > 0) {
            vars.endPeriod = 0;
            if (_limitClaimPeriod > 0 && (_periodNumbers.length - 1).toInt256() >= _limitClaimPeriod.toInt256()) {
                vars.endPeriod = (_periodNumbers.length - 1).toInt256().sub(_limitClaimPeriod.toInt256());
            }
            for (int256 i = (_periodNumbers.length - 1).toInt256(); i >= vars.endPeriod; i--) {
                PeriodData storage periodData = _periodDataMap[_periodNumbers[uint256(i)]];

                vars.userAmount = periodData.users[trader];
                vars.pnlUserAmount = periodData.pnlUsers[trader];

                if (
                    (vars.userAmount > 0 || vars.pnlUserAmount > 0) &&
                    periodData.periodNumber < vars.periodNumber &&
                    periodData.periodNumber > vars.lastPeriodNumber
                ) {
                    if (_startPnlNumber == 0 || periodData.periodNumber < _startPnlNumber) {
                        amount = amount.add(vars.userAmount.mul(periodData.total).div(periodData.amount));
                    } else {
                        if (vars.userAmount > 0) {
                            amount = amount.add(
                                vars
                                    .userAmount
                                    .mul(periodData.total)
                                    .div(periodData.amount)
                                    .mul(uint256(1e6).sub(_pnlRatio))
                                    .div(1e6)
                            );
                        }
                        if (vars.pnlUserAmount > 0) {
                            amount = amount.add(
                                vars
                                    .pnlUserAmount
                                    .mul(periodData.total.toInt256())
                                    .div(periodData.pnlAmount)
                                    .mul(_pnlRatio.toInt256())
                                    .div(1e6)
                                    .abs()
                            );
                        }
                    }
                }
                if (periodData.periodNumber <= vars.lastPeriodNumber) {
                    break;
                }
            }
        }
    }

    function startMiner(uint256 startArg) external onlyOwner {
        // RM_SZ: start zero
        require(_start == 0, "RM_SZ");
        // RM_IT: invalid time
        require(startArg >= _blockTimestamp(), "RM_IT");
        _start = startArg;
    }

    function startPnlMiner(uint256 startPnlNumberArg, uint256 pnlRatioArg) external onlyOwner {
        // RM_SZ: start zero
        require(_startPnlNumber == 0, "RM_SZ");
        // RM_IT: invalid number
        require(startPnlNumberArg >= _getPeriodNumber(), "RM_IN");
        _startPnlNumber = startPnlNumberArg;
        _pnlRatio = pnlRatioArg;
    }

    function mint(address trader, uint256 amount, int256 pnl) external override {
        _requireOnlyClearingHouse();
        if (_start > 0 && _blockTimestamp() >= _start) {
            PeriodData storage periodData = _createPeriodData();
            if (periodData.total > 0) {
                // for volume
                {
                    periodData.users[trader] = periodData.users[trader].add(amount);
                    periodData.amount = periodData.amount.add(amount);

                    _userAmountMap[trader] = _userAmountMap[trader].add(amount);
                }
                // for pnl
                if (_startPnlNumber > 0) {
                    if (periodData.periodNumber >= _startPnlNumber) {
                        if (periodData.pnlUsers[trader] >= 0) {
                            if (pnl >= 0) {
                                periodData.pnlAmount = periodData.pnlAmount.add(pnl);
                            } else {
                                int256 newUserAmount = periodData.pnlUsers[trader].add(pnl);
                                if (newUserAmount < 0) {
                                    periodData.pnlAmount = periodData.pnlAmount.sub(periodData.pnlUsers[trader]);
                                } else {
                                    periodData.pnlAmount = periodData.pnlAmount.add(pnl);
                                }
                            }
                        } else {
                            if (pnl >= 0) {
                                int256 newUserAmount = periodData.pnlUsers[trader].add(pnl);
                                if (newUserAmount >= 0) {
                                    periodData.pnlAmount = periodData.pnlAmount.add(newUserAmount);
                                }
                            }
                        }
                        periodData.pnlUsers[trader] = periodData.pnlUsers[trader].add(pnl);
                    }
                }
                emit MintWithPnl(periodData.periodNumber, trader, amount, pnl);
            }
        }
    }

    function _claim(address trader) internal returns (uint256 amount) {
        amount = _getClaimable(trader);
        //
        _spend = _spend.add(amount);
        // transfer reward
        IERC20Upgradeable(_pnftToken).transfer(trader, amount);
        // update last claim period
        _lastClaimPeriodNumberMap[trader] = (_getPeriodNumber() - 1);

        _userSpendMap[trader] = _userSpendMap[trader].add(amount);

        emit Spend(trader, amount);
    }

    function claim() external returns (uint256 amount) {
        return _claim(_msgSender());
    }

    function emergencyWithdraw(uint256 amount) external onlyOwner {
        IERC20Upgradeable(_pnftToken).transfer(_msgSender(), amount);
    }
}

