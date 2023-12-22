// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./FundState.sol";

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

    event GmxIncreasePosition(address tokenFrom, address indexToken, uint256 tokenFromAmount, uint256 usdDelta);
    event GmxDecreasePosition(address collateralAsset, address indexToken, uint256 collateralAmount, uint256 usdDelta);
    
    event WhitelistMaskUpdated(bytes _newMask);
    event AllowedServicesUpdated(uint256 _newMask);
    /**
    * Public
    */
    function swap(
        address tokenA,
        address tokenB,
        uint256 amountA,
        bytes memory payload
    ) external returns(uint256);

    function multiSwap(
        bytes[] calldata data
    ) external;

    function gmxIncreasePosition(
        address tokenFrom,
        address indexToken,
        uint256 collateralAmount,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable;

    function gmxDecreasePosition(
        address collateralToken,
        address indexToken,
        address receiveToken,
        uint256 collateralDelta,
        uint256 usdDelta,
        bool isLong,
        uint256 acceptablePrice, // usd amount [1e6]
        uint256 executionFee
    ) external payable;

    function aaveSupply(address _asset, uint256 _amount) external;
    function aaveWithdraw(address _asset, uint256 _amount) external;
    function setCollateralAsset(address collateralAsset) external;
    function setTradingScope(bytes memory whitelistMask, uint256 serviceMask) external;
    function setAaveReferralCode(uint16 refCode) external;
    function setGmxRefCode(bytes32 _gmxRefCode) external;
    function setState(FundState newState) external;
    function chargeDebt() external;
    function isManager(address _address) external view returns (bool);
    function whitelistMask() external view returns (bytes memory);
    function servicesEnabled() external view returns (bool[] memory);
    /**
    * Auth
    */
    function transferToFeeder(uint256 amount) external;

    function setManager(address manager, bool enable) external;

    function initialize(
        address _manager,
        bytes calldata _whitelistMask,
        uint256 serviceMask,
        uint256 fundId
    ) external;
    /**
    * View
    */
    function usdtAmount() external view returns(uint256);
    function debt() external view returns(uint256);

    function getAavePositionSizes(address[] calldata _assets) external view
        returns (uint256[] memory assetPositions);

    function getAssetsSizes(address[] calldata assets) external view returns(uint256[] memory);

    function status() external view returns(FundState);

    function fundId() external view returns(uint256);
}

