// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./INameVersion.sol";
import "./IAdmin.sol";
import "./IDToken.sol";

interface IPoolPyth is INameVersion, IAdmin {

    function implementation() external view returns (address);

    function protocolFeeCollector() external view returns (address);

    function liquidity() external view returns (int256);

    function lpsPnl() external view returns (int256);

    function cumulativePnlPerLiquidity() external view returns (int256);

    function protocolFeeAccrued() external view returns (int256);

    function setImplementation(address newImplementation) external;

    function addMarket(address market) external;

    function approveSwapper(address underlying) external;

    function collectProtocolFee() external;

    function setRouter(address, bool) external;

    function claimVenusLp(address account) external;

    function claimVenusTrader(address account) external;

    struct PythData {
        bytes[] vaas;
        bytes32[] ids;
    }

    function addLiquidity(address underlying, uint256 amount, PythData memory pythData) external payable;

    function removeLiquidity(address underlying, uint256 amount, PythData memory pythData) external;

    function addMargin(address account, address underlying, uint256 amount, PythData memory pythData) external payable;

    function removeMargin(address account, address underlying, uint256 amount, PythData memory pythData) external;

    function trade(address account, string memory symbolName, int256 tradeVolume, int256 priceLimit) external;

    function liquidate(uint256 pTokenId, PythData memory pythData) external;

    struct LpInfo {
        address vault;
        int256 amountB0;
        int256 liquidity;
        int256 cumulativePnlPerLiquidity;
    }

    function lpInfos(uint256) external view returns (LpInfo memory);

    function tokenB0() external view returns (address);

    function vTokenB0() external view returns (address);

    function minRatioB0() external view returns (int256);

    function lToken() external view returns (IDToken);

    function pToken() external view returns (IDToken);

    function decimalsB0() external view returns (uint256);

}

