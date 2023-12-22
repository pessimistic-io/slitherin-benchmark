// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./IUpgradeableBase.sol";
import "./IERC20Full.sol";
import "./IREUSDMinterBase.sol";
import "./ICurveStableSwap.sol";
import "./ICurvePool.sol";
import "./ICurveGauge.sol";
import "./ISelfStakingERC20.sol";

interface IRECurveZapper is IREUSDMinterBase, IUpgradeableBase
{
    error UnsupportedToken();
    error ZeroAmount();
    error PoolMismatch();
    error TooManyPoolCoins();
    error TooManyBasePoolCoins();
    error MissingREUSD();
    error BasePoolWithREUSD();
    error UnbalancedProportions();

    function isRECurveZapper() external view returns (bool);
    function basePoolCoinCount() external view returns (uint256);
    function pool() external view returns (ICurveStableSwap);
    function basePool() external view returns (ICurvePool);
    function basePoolToken() external view returns (IERC20);
    function gauge() external view returns (ICurveGauge);
    function getBalancedZapREUSDAmount(IERC20 token, uint256 tokenAmount) external view returns (uint256 reusdAmount);

    function zap(IERC20 token, uint256 tokenAmount, bool mintREUSD) external;
    function zapPermit(IERC20Full token, uint256 tokenAmount, bool mintREUSD, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function unzap(IERC20 desiredToken, uint256 gaugeAmount) external;
    function unzapPermit(IERC20 desiredToken, uint256 gaugeAmount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function balancedZap(IERC20 token, uint256 tokenAmount) external;
    function balancedZapPermit(IERC20Full token, uint256 tokenAmount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function balancedUnzap(uint256 gaugeAmount, uint256 gaugeAmountForREUSD, uint32[] calldata basePoolProportions) external;
    function balancedUnzapPermit(uint256 gaugeAmount, uint256 gaugeAmountForREUSD, uint32[] calldata basePoolProportions, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function compound(ISelfStakingERC20 selfStakingToken) external;
    function compoundPermit(ISelfStakingERC20 selfStakingToken, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    struct TokenAmount
    {        
        IERC20 token;
        uint256 amount;
    }
    struct PermitData
    {
        IERC20Full token;
        uint32 deadline;
        uint8 v;
        uint256 permitAmount;
        bytes32 r;
        bytes32 s;
    }

    function multiZap(TokenAmount[] calldata mints, TokenAmount[] calldata tokenAmounts) external;
    function multiZapPermit(TokenAmount[] calldata mints, TokenAmount[] calldata tokenAmounts, PermitData[] calldata permits) external;
}
