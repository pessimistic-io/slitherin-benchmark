// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITrade {

    /**
    * Events
    */
    event SwapSuccess(address tokenA, address tokenB, uint256 amountIn, uint256 amountOut);
    event ManagerAdded(address newManager);
    event ManagerRemoved(address manager);

    event AaveSupply(address asset, uint256 amount);
    event AaveWithdraw(address asset, uint256 amount);
    event AaveBorrowEvent(address asset, uint256 amount);
    event AaveRepayEvent(address asset, uint256 amount);
    event AaveSetCollateralEvent(address asset);

    event GmxIncreasePosition(address collateralAsset, address indexToken, uint256 collateralAmount, uint256 usdDelta);
    event GmxDecreasePosition(address collateralAsset, address indexToken, uint256 collateralAmount, uint256 usdDelta);
    /**
    * Public
    */
    function swap(address swapper,
        address tokenA,
        address tokenB,
        uint256 amountA,
        bytes memory payload
    ) external returns(uint256);

    function aaveSupply(address _asset, uint256 _amount) external;
    function aaveWithdraw(address _asset, uint256 _amount) external;
    function setCollateralAsset(address collateralAsset) external;
    function aaveRepay(address asset, uint256 amount, uint16 borrowRate) external payable;
    function aaveBorrow(address borrowAsset, uint256 amount, uint16 borrowRate) external;
    function setAaveReferralCode(uint16 refCode) external;
    /**
    * Auth
    */
    function transferToFeeder(uint256 amount, address feeder) external;

    function setManager(address manager, bool enable) external;

    function initialize(
        address _usdt,
        address _manager,
        address _trigger,
        address _interaction,
        address _poolDataProvider,
        address _lendingPool
    ) external;
    /**
    * View
    */
    function usdtAmount() external view returns(uint256);

    function getAavePositionSizes(address[] calldata _assets) external view
        returns (uint256[] memory assetPositions);

    function getAssetsSizes(address[] calldata assets) external view returns(uint256[] memory);

    function setGMXData(address _gmxRouter, address _gmxPositionRouter) external;

    function gmxMinExecutionFee() external view returns(uint256);

    function gmxIncreasePosition(
        address collateralToken,
        address indexToken,
        uint256 collateralAmount,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice
    ) external payable;

    function gmxDecreasePosition(
        address collateralToken,
        address indexToken,
        address receiveToken,
        uint256 collateralDelta, //usd amount [1e6]
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice // usd amount [1e6]
    ) external payable;

    function gmxApprovePlugin() external;
}

