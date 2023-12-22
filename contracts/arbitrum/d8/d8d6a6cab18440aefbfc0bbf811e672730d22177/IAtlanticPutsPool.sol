//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Contracts, VaultConfig, OptionsState} from "./AtlanticPutsPoolEnums.sol";

import {DepositPosition, OptionsPurchase, Checkpoint} from "./AtlanticPutsPoolStructs.sol";

interface IAtlanticPutsPool {
    function purchasePositionsCounter() external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function getOptionsPurchase(
        uint256 positionId
    ) external view returns (OptionsPurchase memory);

    function getEpochTickSize(uint256 _epoch) external view returns (uint256);

    function addresses(Contracts _contractType) external view returns (address);

    function getOptionsState(
        uint256 _purchaseId
    ) external view returns (OptionsState);

    function purchase(
        uint256 _strike,
        uint256 _amount,
        address _delegate,
        address _account
    ) external returns (uint256 purchaseId);

    function calculateFundingFees(
        uint256 _collateralAccess,
        uint256 _entryTimestamp
    ) external view returns (uint256 fees);

    function relockCollateral(
        uint256 purchaseId,
        uint256 relockAmount
    ) external;

    function unwind(uint256 purchaseId, uint256 unwindAmount) external;

    function calculatePurchaseFees(
        address account,
        uint256 strike,
        uint256 amount
    ) external view returns (uint256 finalFee);

    function calculatePremium(
        uint256 _strike,
        uint256 _amount
    ) external view returns (uint256 premium);

    function unlockCollateral(
        uint256 purchaseId,
        address to
    ) external returns (uint256 unlockedCollateral);

    function getDepositPosition(
        uint256 positionId
    ) external view returns (DepositPosition memory);

    function strikeMulAmount(
        uint256 _strike,
        uint256 _amount
    ) external view returns (uint256 result);

    function getEpochStrikes(
        uint256 epoch
    ) external view returns (uint256[] memory maxStrikes);

    function getEpochCheckpoints(
        uint256 _epoch,
        uint256 _maxStrike
    ) external view returns (Checkpoint[] memory _checkpoints);

    function depositPositionsCounter() external view returns (uint256);

    function isWithinBlackoutWindow() external view returns (bool);
}

