//SPDX-License-Identifier: MIT
pragma solidity ^0.8;
import {IERC4626} from "./ERC4626.sol";
import "./ICoreVault.sol";
import {IFeeRouter} from "./IFeeRouter.sol";

interface IVaultRouter {
    function totalFundsUsed() external view returns (uint256);

    function feeRouter() external view returns (IFeeRouter);

    function initialize(address _coreVault, address _feeRouter) external;

    function setMarket(address market, address vault) external;

    function borrowFromVault(uint256 amount) external;

    function repayToVault(uint256 amount) external;

    function transferToVault(address account, uint256 amount) external;

    function transferFromVault(address to, uint256 amount) external;

    function getAUM() external view returns (uint256);

    function getGlobalPnl() external view returns (int256);

    function getLPPrice(address coreVault) external view returns (uint256);

    function getUSDBalance() external view returns (uint256);

    function priceDecimals() external view returns (uint256);

    function buyLpFee(ICoreVault vault) external view returns (uint256);

    function sellLpFee(ICoreVault vault) external view returns (uint256);

    function sell(
        IERC4626 vault,
        address to,
        uint256 amount,
        uint256 minAssetsOut
    ) external returns (uint256 assetsOut);

    function buy(
        IERC4626 vault,
        address to,
        uint256 amount,
        uint256 minSharesOut
    ) external returns (uint256 sharesOut);

    function transFeeTofeeVault(
        address account,
        address asset,
        uint256 fee, // assets decimals
        bool isBuy
    ) external;
}

