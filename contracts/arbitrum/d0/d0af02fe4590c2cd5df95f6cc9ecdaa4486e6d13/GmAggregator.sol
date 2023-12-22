// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Ownable} from "./Ownable.sol";
import {IReader} from "./IReader.sol";
import {GmxV2Market} from "./GmxV2Market.sol";
import {GmxV2Price} from "./GmxV2Price.sol";
import {GmxV2MarketPoolValueInfo} from "./GmxV2MarketPoolValueInfo.sol";

struct Market {
    address addr;
    string name;
    string symbol;
    uint8 decimals;
    uint256 balance;
    uint256 totalSupply;
    int256 poolValue;
    int256 netPnl;
    uint256 totalBorrowingFees;
    uint256 impactPoolAmount;
    Balance longBalance;
    Balance shortBalance;
}

struct Balance {
    address addr;
    string name;
    string symbol;
    uint8 decimals;
    uint256 balance;
    uint256 poolBalance;
    uint256 totalSupply;
} 

contract GmAggregator is Ownable {
    address public GMXV2_READER;
    address public GMXV2_DATASTORE;
    IReader private reader;

    constructor() {
        GMXV2_READER = 0xf60becbba223EEA9495Da3f606753867eC10d139;
        GMXV2_DATASTORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
        reader = IReader(GMXV2_READER);
    }

    function changeGmxV2Reader(address newAddress) public onlyOwner {
        GMXV2_READER = newAddress;
        reader = IReader(GMXV2_READER);
    }

    function changeGmxV2Datastore(address newAddress) public onlyOwner {
        GMXV2_DATASTORE = newAddress;
    }

    function _getMarkets() internal virtual view returns(GmxV2Market[] memory markets){
        return reader.getMarkets(GMXV2_DATASTORE, 0, 20);
    }

    function _getMarketTokenPrice(GmxV2Market memory market) internal virtual view returns(int256 poolValue, GmxV2MarketPoolValueInfo memory poolValueInfo) {
        try reader.getMarketTokenPrice(GMXV2_DATASTORE, market, GmxV2Price(1, 1), GmxV2Price(1,1), GmxV2Price(1,1), keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS")), true) returns (int256 pv, GmxV2MarketPoolValueInfo memory pvi) {
            return (pv, pvi);
        } catch {
            return (poolValue, poolValueInfo);
        }
    }

    function _calculateMarket(address gmAddress, address userAddress, GmxV2MarketPoolValueInfo memory poolVal) internal virtual view returns(uint256 longBal, uint256 shortBal) {
        IERC20 token = IERC20(gmAddress);
        IERC20Metadata gmToken = IERC20Metadata(gmAddress);

        longBal = (token.balanceOf(userAddress) * 1e18) / gmToken.totalSupply() * uint256(poolVal.longTokenAmount);
        shortBal = (token.balanceOf(userAddress) * 1e18) / gmToken.totalSupply() * uint256(poolVal.shortTokenAmount);

        return (longBal, shortBal);
    }

    function getBalances(address user) public virtual view returns(Market[] memory markets) {
        GmxV2Market[] memory gms = _getMarkets();
        markets = new Market[](gms.length);
        for (uint256 i=0;i<gms.length;i++) {
            IERC20Metadata token = IERC20Metadata(gms[i].marketToken);
            IERC20Metadata longToken = IERC20Metadata(gms[i].longToken);
            IERC20Metadata shortToken = IERC20Metadata(gms[i].shortToken);

            (int256 poolValue, GmxV2MarketPoolValueInfo memory poolValueInfo) = _getMarketTokenPrice(gms[i]);
            (uint256 longBal, uint256 shortBal) = _calculateMarket(gms[i].marketToken, user, poolValueInfo);
            
            markets[i] = Market(gms[i].marketToken, string.concat(token.name()," ",longToken.name(),"/",shortToken.name()), token.symbol(), token.decimals(), token.balanceOf(user), token.totalSupply(), poolValue, poolValueInfo.netPnl, poolValueInfo.totalBorrowingFees, poolValueInfo.impactPoolAmount, Balance(gms[i].longToken, longToken.name(), longToken.symbol(), longToken.decimals(), longBal, poolValueInfo.longTokenAmount, longToken.totalSupply()), Balance(gms[i].shortToken, shortToken.name(), shortToken.symbol(), shortToken.decimals(), shortBal, poolValueInfo.shortTokenAmount, shortToken.totalSupply()));
        }
        return markets;
    }
}
