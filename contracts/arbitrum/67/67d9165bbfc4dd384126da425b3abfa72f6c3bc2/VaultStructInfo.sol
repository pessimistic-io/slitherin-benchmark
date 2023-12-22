// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;
pragma abicoder v2;

import "./TransferHelper.sol";
import "./ISwapRouter02.sol";
import "./INonfungiblePositionManager.sol";

library VaultStructInfo {


    /*
        Soc Basic Info
    */
    struct BasicInfo {
        string vaultName;
        address dispatcher;
        address socMainContract;
    }

    function initBasicInfo(BasicInfo storage basicInfo, string memory _vaultName, address _dispatcher, address _socMainContract) internal {
        basicInfo.vaultName = _vaultName;
        basicInfo.dispatcher = _dispatcher;
        basicInfo.socMainContract = _socMainContract;
    }


    /*
        Vault Allowlist Token Mapping
    */
    struct AllowTokenObj {
        address tokenAddress;
        address aTokenAddress;
        bool allowed;
    }

    struct TokenAllowedInfo {
        AllowTokenObj[] allowList;
        mapping(address => AllowTokenObj) tokenExists;
    }

    function initTokenAllowedInfo(TokenAllowedInfo storage tokenAllowedInfo, address[] memory allowTokens) internal {
        for (uint i = 0; i < allowTokens.length; i++) {
            AllowTokenObj memory obj = AllowTokenObj({
                tokenAddress : allowTokens[i],
                aTokenAddress : address(0),
                allowed : true
            });
            tokenAllowedInfo.allowList.push(obj);
            tokenAllowedInfo.tokenExists[allowTokens[i]] = obj;
        }
    }

    function setSwapAllowList(TokenAllowedInfo storage tokenAllowedInfo, AllowTokenObj[] memory _allowList) internal {
        delete tokenAllowedInfo.allowList;
        for (uint i = 0; i < _allowList.length; i++) {
            tokenAllowedInfo.allowList.push(_allowList[i]);
            tokenAllowedInfo.tokenExists[_allowList[i].tokenAddress] = _allowList[i];
        }
    }


    /*
        Uniswap Info
    */
    struct UniInfo {
        address WETH;
        ISwapRouter02 swapRouter;
        INonfungiblePositionManager nonfungiblePositionManager;
    }

    function initUniInfo(UniInfo storage uniInfo) internal {
        uniInfo.WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        uniInfo.nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        uniInfo.swapRouter = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    }


    /*
        Trading Fee Info
    */
    struct TradingFeeObj {
        uint256 pendingCollectFee;
        uint16 txCount;
    }

    struct TradingInfo {
        uint8 sendTradingFeeInterval;
        uint8 tradingFee;
        uint16 swapTradingFeeRate;
        uint16 lpTradingFeeRate;
        mapping(address => TradingFeeObj) tradingFeeMap;
    }

    function initTradingInfo(TradingInfo storage tradingInfo) internal {
        tradingInfo.tradingFee = 1;
        tradingInfo.swapTradingFeeRate = 5000;
        tradingInfo.lpTradingFeeRate = 10;
        tradingInfo.sendTradingFeeInterval = 1;
    }

    function collectTradingFee(TradingInfo storage tradingInfo, uint256 amount, uint16 feeRate, address token, address socMainContract) internal returns (uint256) {
        if (amount > 0) {
            uint256 fee = (amount * tradingInfo.tradingFee) / feeRate;
            tradingInfo.tradingFeeMap[token].txCount = tradingInfo.tradingFeeMap[token].txCount + 1;
            tradingInfo.tradingFeeMap[token].pendingCollectFee = tradingInfo.tradingFeeMap[token].pendingCollectFee + fee;
            if (tradingInfo.tradingFeeMap[token].txCount >= tradingInfo.sendTradingFeeInterval && IERC20(token).balanceOf(address(this)) >= tradingInfo.tradingFeeMap[token].pendingCollectFee) {
                TransferHelper.safeTransfer(token, socMainContract, tradingInfo.tradingFeeMap[token].pendingCollectFee);
                tradingInfo.tradingFeeMap[token].txCount = 0;
                tradingInfo.tradingFeeMap[token].pendingCollectFee = 0;
            }
            return amount - fee;
        } else {
            return amount;
        }
    }

    function collectTradingFeeForETH(TradingInfo storage tradingInfo, uint256 amount, uint16 feeRate, address socMainContract) internal returns (uint256) {
        if (amount > 0) {
            uint256 fee = (amount * tradingInfo.tradingFee) / feeRate;
            TransferHelper.safeTransferETH(socMainContract, fee);
            return amount - fee;
        } else {
            return amount;
        }
    }


    /*
        Vault Approve Info
    */
    struct ApproveInfo {
        mapping(address => bool) liquidityApproveMap;
        mapping(address => bool) swapApproveMap;
    }


    /*
        LP Removed Info
    */
    struct LpRemoveRecord {
        address token0;
        address token1;
        uint256 token0Amount;
        uint256 token1Amount;
        uint256 token0FeeAmount;
        uint256 token1FeeAmount;
    }

}
