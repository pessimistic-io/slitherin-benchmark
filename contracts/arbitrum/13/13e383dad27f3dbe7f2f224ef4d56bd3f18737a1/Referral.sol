// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./SafeMath.sol";
import "./Ownable.sol";

contract Referal is Ownable{
    using SafeMath for uint256;

    struct ReferrerInfo {
        uint256 totalReferNum;
        uint256 totalReferProfitInUSDC;
        uint256 totalReferProfitInWETH;
    }

    struct ReferLog {
        uint256 count;
        address depositor;
        address referrer;
        address depositToken;
        uint256 referProfit;
    }

    mapping(address => ReferrerInfo) public referal;
    ReferLog[] public referLogs;

    uint256 public totalReferNum;
    uint256 public totalReferProfitInUSDC;
    uint256 public totalReferProfitInWETH;

    address public operator;

    constructor() {
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "RewardGenesisPool: caller is not the operator");
        _;
    }

    function setOperator(address _genesis) external onlyOwner {
        require(_genesis != address(0), "0 address");
        operator = _genesis;
    }

    function addReferUSDCAmount(address _depositor, address _referrer, address _token, uint256 _amount) external onlyOperator {
        if(_depositor != address(0)
            && _referrer != _depositor 
            && _referrer != address(0)
        ) {
            referal[_referrer].totalReferNum = referal[_referrer].totalReferNum.add(1);
            referal[_referrer].totalReferProfitInUSDC = referal[_referrer].totalReferProfitInUSDC.add(_amount);
            referLogs.push(
                ReferLog(
                    totalReferNum,
                    _depositor,
                    _referrer,
                    _token,
                    _amount
                )
            );
            totalReferNum = totalReferNum.add(1);
            totalReferProfitInUSDC = totalReferProfitInUSDC.add(_amount);
        }
    }

    function addReferWETHAmount(address _depositor, address _referrer, address _token, uint256 _amount) external onlyOperator {
       if(_depositor != address(0)
            && _referrer != _depositor 
            && _referrer != address(0)
        ) {
            referal[_referrer].totalReferNum = referal[_referrer].totalReferNum.add(1);
            referal[_referrer].totalReferProfitInWETH = referal[_referrer].totalReferProfitInWETH.add(_amount);
            referLogs.push(
                ReferLog(
                    totalReferNum,
                    _depositor,
                    _referrer,
                    _token,
                    _amount
                )
            );
            totalReferNum = totalReferNum.add(1);
            totalReferProfitInWETH = totalReferProfitInWETH.add(_amount);
        }
    }

    function getLatestReferLogs(uint256 length) public view returns(ReferLog[] memory) {
        if(length > totalReferNum) {
            length = totalReferNum;
        }
        ReferLog[] memory latestLogs = new ReferLog[](length);
        if(length > 0) {
            uint256 k = 0;
            for(uint256 i = totalReferNum; i > 0; i-- ){
                latestLogs[k] = referLogs[i-1];
                k += 1;
                if(k == length) {
                    break;
                }
            }
        }
        return latestLogs;
    }
}
