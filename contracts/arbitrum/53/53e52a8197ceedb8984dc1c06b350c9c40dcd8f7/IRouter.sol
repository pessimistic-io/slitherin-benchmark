// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IOptionStrategy} from "./IOptionStrategy.sol";
import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {ILPVault} from "./ILPVault.sol";
import {IERC20} from "./SafeERC20.sol";

interface IRouter {
    enum OptionStrategy {
        BULL,
        BEAR,
        CRAB
    }

    struct DepositInfo {
        address receiver;
        OptionStrategy strategy;
        address thisAddress;
        uint256 epoch;
        uint64 endTime;
        uint256 optionBullRisk;
        uint256 optionBearRisk;
        address strategyAddress;
        address optionsAddress;
        ICompoundStrategy compoundStrategy;
        IOptionStrategy optionStrategy;
        IERC20 lpToken;
        ILPVault vault;
        uint256 assets;
        uint256 toFarm;
        uint256 toBuyOptions;
        uint256 shares;
    }

    struct WithdrawInfo {
        uint256 currentEpoch;
        uint256 endTime;
        uint256 withdrawExchangeRate;
        uint256 currentBalance;
        uint256 lpAssets;
        uint256 retention;
        uint256 toTreasury;
        uint256 redemeed;
    }

    struct CancelWithdrawInfo {
        uint256 commitEpoch;
        uint256 currentEpoch;
        uint256 endTime;
        uint256 finalShares;
        uint256 flipRate;
    }

    struct DepositParams {
        uint256 _assets;
        OptionStrategy _strategy;
        address _receiver;
    }

    struct WithdrawalSignal {
        uint256 targetEpoch;
        uint256 commitedShares;
        OptionStrategy strategy;
        uint256 redeemed;
    }

    struct FlipSignal {
        uint256 targetEpoch;
        uint256 commitedShares;
        OptionStrategy oldStrategy;
        OptionStrategy newStrategy;
        uint256 redeemed;
    }

    function deposit(uint256 _assets, OptionStrategy _strategy, bool _instant, address _receiver)
        external
        returns (uint256);
    function claim(uint256 _targetEpoch, OptionStrategy _strategy, address _receiver) external returns (uint256);
    function signalWithdraw(address _receiver, OptionStrategy _strategy, uint256 _shares) external returns (uint256);
    function cancelSignal(uint256 _targetEpoch, OptionStrategy _strategy, address _receiver)
        external
        returns (uint256);
    function withdraw(uint256 _epoch, OptionStrategy _strategy, address _receiver) external returns (uint256);
    function instantWithdraw(uint256 _shares, OptionStrategy _strategy, address _receiver) external returns (uint256);
    function signalFlip(uint256 _shares, OptionStrategy _oldtrategy, OptionStrategy _newStrategy, address _receiver)
        external
        returns (uint256);
    function cancelFlip(
        uint256 _targetEpoch,
        OptionStrategy _oldtrategy,
        OptionStrategy _newStrategy,
        address _receiver
    ) external returns (uint256);
    function flipWithdraw(uint256 _epoch, OptionStrategy _oldtrategy, OptionStrategy _newStrategy, address _receiver)
        external
        returns (uint256);
    function executeFinishEpoch() external;
    function nextEpochDeposits(OptionStrategy _strategy) external view returns (uint256);
    function withdrawSignals(OptionStrategy _strategy) external view returns (uint256);
    function getWithdrawSignal(address _user, uint256 _targetEpoch, OptionStrategy _strategy)
        external
        view
        returns (WithdrawalSignal memory);
    function flipSignals(OptionStrategy _oldStrategy, OptionStrategy _newStrategy) external view returns (uint256);
    function getFlipSignal(
        address _user,
        uint256 _targetEpoch,
        OptionStrategy _oldStrategy,
        OptionStrategy _newStrategy
    ) external view returns (FlipSignal memory);
    function premium() external view returns (uint256);
    function slippage() external view returns (uint256);
}

