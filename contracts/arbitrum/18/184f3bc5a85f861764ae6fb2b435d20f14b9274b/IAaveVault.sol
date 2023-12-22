// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./IActionPoolDcRouter.sol";
import "./IPool.sol";
import "./IRewardsController.sol";
import "./IWETHGateway.sol";
import "./IDebtTokenBase.sol";
import "./ILayerZeroEndpointUpgradeable.sol";

interface IAaveVault {
    event OpenPositionEvent(IERC20 baseAsset, uint256 amount);
    event ClosePositionEvent(IERC20 baseAsset, uint256 amount);
    event BorrowEvent(IERC20 baseAsset, uint256 amount);
    event RepayEvent(IERC20 baseAsset, uint256 amount);
    event ClaimedRewardsEvent(address[] assets, address user);
    event SwapEvent(address[] path, uint256 amountIn, uint256 amountOut);
    event SetCollateralEvent(IERC20 asset);
    event SetUserEMode(uint8 emode);

    struct AaveVaultInitParams {
        IPoolAddressesProvider aaveProviderAddress;
        IWETHGateway wethGatewayAddress;
        IRewardsController rewardsControllerAddress;
        IActionPoolDcRouter actionPoolDcRouter;
        ILayerZeroEndpointUpgradeable nativeLZEndpoint;
        IERC20 usdcToken;
        address wavaxVariableDebtTokenAddress;
        uint16 nativeId;
        uint16 actionPoolId;
    }

    function aaveProvider() external view returns (IPoolAddressesProvider);

    function aaveLendingPool() external view returns (IPool);

    function wethGateway() external view returns (IWETHGateway);

    function rewardsController() external view returns (IRewardsController);

    function wavaxVariableDebtToken() external view returns (address);

    function aaveStrategy() external view returns (address);

    function transferToStrategy(address _asset, uint256 _amount) external;

    function setAaveStrategy(bytes memory _data) external;

    function setUserEMode(bytes memory _data) external;

    function setCollateralAsset(bytes memory _data) external;

    function openPosition(bytes memory _data) external;

    function borrow(bytes memory _data) external;

    function repay(bytes memory _data) external;

    function closePosition(bytes memory _data) external;

    function claimAllRewards(bytes memory _data) external;
}

