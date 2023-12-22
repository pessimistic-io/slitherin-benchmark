// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./ITradeStorage.sol";
import "./EnumerableValues.sol";

contract TradeStorage is Ownable, ITradeStorage{
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private recorders; // Record positions keys tracks all open positions
    
    mapping(address => mapping(uint256 => uint256)) public override tradeVol;
    mapping(address => mapping(uint256 => uint256)) public override swapVol;
    mapping(uint256 => uint256) public override totalTradeVol;
    mapping(uint256 => uint256) public override totalSwapVol;
    
    event UpdateTrade(address account, uint256 volUsd, uint256 day);
    event UpdateSwap(address account, uint256 volUsd, uint256 day);

    modifier onlyRecorder() {
        require(recorders.contains(msg.sender), "[TradeRec] only recorder");
        _;
    }

    // ---------- owner setting part ----------
    function setRecorder(address _rec, bool _status) external onlyOwner{
        if (_status && (!recorders.contains(_rec))){
            recorders.add(_rec);
        }
        else if (!_status && recorders.contains(_rec)){
            recorders.remove(_rec);
        }
    }

    function updateTrade(address _account, uint256 _volUsd) external override onlyRecorder{
        uint256 _day = block.timestamp.div(86400);
        tradeVol[_account][_day] = tradeVol[_account][_day].add(_volUsd);
        totalTradeVol[_day] = totalTradeVol[_day].add(_volUsd);
        emit UpdateTrade(_account, _volUsd, _day);
    }

    function updateSwap(address _account, uint256 _volUsd) external override onlyRecorder{
        uint256 _day = block.timestamp.div(86400);
        swapVol[_account][_day] = swapVol[_account][_day].add(_volUsd);
        totalSwapVol[_day] = totalSwapVol[_day].add(_volUsd);
        emit UpdateSwap(_account, _volUsd, _day);
    }

    function getRecorders( ) external view returns (address[] memory){
        return recorders.valuesAt(0, recorders.length());
    }

}

