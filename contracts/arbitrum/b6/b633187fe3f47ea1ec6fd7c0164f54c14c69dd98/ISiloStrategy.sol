// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISiloStrategy {
    struct AssetStorage {
        /// @dev Token that represents a share in totalDeposits of Silo
        address collateralToken;
        /// @dev Token that represents a share in collateralOnlyDeposits of Silo
        address collateralOnlyToken;
        /// @dev Token that represents a share in totalBorrowAmount of Silo
        address debtToken;
        /// @dev COLLATERAL: Amount of asset token that has been deposited to Silo with interest earned by depositors.
        /// It also includes token amount that has been borrowed.
        uint256 totalDeposits;
        /// @dev COLLATERAL ONLY: Amount of asset token that has been deposited to Silo that can be ONLY used
        /// as collateral. These deposits do NOT earn interest and CANNOT be borrowed.
        uint256 collateralOnlyDeposits;
        /// @dev DEBT: Amount of asset token that has been borrowed with accrued interest.
        uint256 totalBorrowAmount;
    }

    function assetStorage(address _asset) external view returns (AssetStorage memory);

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

    function borrow(address _asset, uint256 _amount) external returns (uint256 debtAmount, uint256 debtShare);

    function repay(address _asset, uint256 _amount) external returns (uint256 repaidAmount, uint256 burnedShare);
}

interface ISiloLens {
    function depositAPY(ISiloStrategy _silo, address _asset) external view returns (uint256);

    function totalDepositsWithInterest(
        ISiloStrategy _silo,
        address _asset
    ) external view returns (uint256 _totalDeposits);
}

interface ISiloIncentiveController {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);

    function getUserUnclaimedRewards(address user) external view returns (uint256);
}

interface ISiloRepository {
    function isSiloPaused(address _silo, address _asset) external view returns (bool);

    function getSilo(address _asset) external view returns (address);
}

