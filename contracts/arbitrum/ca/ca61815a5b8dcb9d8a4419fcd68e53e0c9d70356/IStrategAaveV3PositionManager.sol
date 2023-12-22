// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {IStrategPortal} from "./IStrategPortal.sol";

import {IAaveOracle} from "./IAaveOracle.sol";

interface IStrategAaveV3PositionManager {

    error AlreadyInitialized();
    error NotOwner();
    error NotOperator();
    error NotAavePool();
    error BorrowOnly();
    error LeverageOnly();
    error RepayNotCoveredWithSwap();
    error LeverageHealthfactorNotMatch();
    error UnleverageNotComplete();
    error WrongInitiator();

    enum FlashloanCallbackType {
        LEVERAGE,
        UNLEVERAGE
    }
    
    struct InitializationParams {
        bool leverageMode;
        IERC20 collateral;
        uint256 collateralDecimals;

        IERC20 borrowed;
        uint256 borrowedDecimals;

        uint8 eModeCategoryId;
        uint256 deptType;
        uint256 hfMin;
        uint256 hfMax;
        uint256 hfDesired;
    }
    
    struct Position {
        bool leverageMode;
        uint8 eModeCategoryId;
        IAaveOracle oracle;
        Collateral collateral;
        Dept dept;
        Healthfactor healthfactor;
    }

    struct Collateral {
        IERC20 token; 
        IERC20 aToken;
        uint256 decimals;
        uint256 ltv;
        uint256 lts;
        uint256 cap;
    }

    struct Dept {
        IERC20 token; 
        IERC20 deptToken;
        uint256 deptType;
        uint256 decimals;
        uint256 cap;
    }

    struct Healthfactor {
        uint256 min;
        uint256 max;
        uint256 desired;
    }

    struct BorrowStatus {
        bool emptyBorrow;
        bool toRebalance;
        bool positionDeltaIsPositive;
        uint256 availableTokenForRepay;
        uint256 deltaAmount;
        uint256 healthFactor;
        uint256 healthFactorDesired;
        uint256 rebalanceAmountToRepay;
    }

    struct LeverageStatus {
        bool emptyLeverage;
        bool toRebalance;

        uint256 collateralAmount;
        uint256 deptAmount;
        uint256 healthFactor;
        uint256 healthFactorDesired;
    }

    struct RebalanceData {
        bool isBelow;
        bytes data;
        uint256[] partialExecutionEnterDynamicParamsIndex;
        bytes[] partialExecutionEnterDynamicParams;
        uint256[] partialExecutionExitDynamicParamsIndex;
        bytes[] partialExecutionExitDynamicParams;
    }

    struct FlashloanData {
        FlashloanCallbackType callback;
        bytes data;
    }

    function position() external view returns (Position memory);
    function borrow(uint256 _addCollateralAmount) external;
    function repay(bytes memory _dynamicParams) external;
    function leverage(uint256 _addCollateralAmount, bytes memory _dynamicParams) external;
    function unleverage(bytes memory _dynamicParams) external;
    function rebalance(bytes memory _dynamicParams) external;
    function borrowAmountFor(uint256 _collateral) external view returns (uint256);
    function returnedAmountAfterRepay(uint256 _repay) external view returns (uint256);
    function returnedAmountAfterUnleverage() external view returns (uint256);
    function refreshAaveData() external;
    function borrowStatus(bool _withSpecificAvailableTokenForRepay, uint256 _availableTokenForRepay) external view returns (BorrowStatus memory status);
    function leverageStatus() external view returns (LeverageStatus memory status);

    function executeOperation(
        address[] calldata _assets,
        uint256[] calldata _amounts,
        uint256[] calldata _premiums,
        address _initiator,
        bytes calldata _params
    )  external returns (bool);
}

