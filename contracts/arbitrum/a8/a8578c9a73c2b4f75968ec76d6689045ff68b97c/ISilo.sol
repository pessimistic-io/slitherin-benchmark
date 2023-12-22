// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

interface ISilo {
    struct AssetStorage {
        address collateralToken;
        address collateralOnlyToken;
        address debtToken;
        uint256 totalDeposits;
        uint256 collateralOnlyDeposits;
        uint256 totalBorrowAmount;
    }

    struct UtilizationData {
        uint256 totalDeposits;
        uint256 totalBorrowAmount;
        /// @dev timestamp of last interest accrual
        uint64 interestRateTimestamp;
    }

    function assetStorage(address _asset) external view returns (AssetStorage memory);

    function liquidity(address _asset) external view returns (uint256);

    function utilizationData(address _asset) external view returns (UtilizationData memory data);

    function accrueInterest(address _asset) external;

    function deposit(
        address _asset,
        uint256 _amount,
        bool _collateralOnly
    ) external returns (uint256 collateralAmount, uint256 collateralShare);

    function withdraw(
        address _asset,
        uint256 _amount,
        bool _collateralOnly
    ) external returns (uint256 withdrawnAmount, uint256 withdrawnShare);
}

interface ISiloInterestRateModel {
    struct Config {
        // uopt ∈ (0, 1) – optimal utilization;
        int256 uopt;
        // ucrit ∈ (uopt, 1) – threshold of large utilization;
        int256 ucrit;
        // ulow ∈ (0, uopt) – threshold of low utilization
        int256 ulow;
        // ki > 0 – integrator gain
        int256 ki;
        // kcrit > 0 – proportional gain for large utilization
        int256 kcrit;
        // klow ≥ 0 – proportional gain for low utilization
        int256 klow;
        // klin ≥ 0 – coefficient of the lower linear bound
        int256 klin;
        // beta ≥ 0 - a scaling factor
        int256 beta;
        // ri ≥ 0 – initial value of the integrator
        int256 ri;
        // Tcrit ≥ 0 - the time during which the utilization exceeds the critical value
        int256 Tcrit;
    }

    function getConfig(address silo_, address asset_) external view returns (Config memory);
}

interface ISiloLens {
    function balanceOfUnderlying(
        uint256 _assetTotalDeposits,
        address _shareToken,
        address _user
    ) external view returns (uint256);

    function totalDepositsWithInterest(
        address _silo,
        address _asset
    ) external view returns (uint256);
}

interface ISiloIncentivesController {
    function getRewardsBalance(
        address[] calldata _assets,
        address _user
    ) external view returns (uint256);

    function claimRewards(address[] calldata _assets, uint256 _amount, address _to) external;
}

