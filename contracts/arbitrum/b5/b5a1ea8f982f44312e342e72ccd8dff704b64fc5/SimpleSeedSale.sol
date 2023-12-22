
// SPDX-License-Identifier: BUSL-1.1

import "./ReentrancyGuard.sol";
import "./Controllable.sol";
import "./MultiSigWithdrawable.sol";
import "./IDataLog.sol";

pragma solidity 0.8.15;


contract SimpleSeedSale is MultiSigWithdrawable, Controllable, ReentrancyGuard {

    struct SaleInfo {
        address currency;
        uint userFeePcnt;
        uint hardCap;
        uint unitPrice;
        uint startTime;
        uint endTime;
        uint minAlloc; // In currency unit
        uint maxAlloc; // In currency unit

        uint totalSold;          // In currency unit
        uint totalFeesCollected; // In currency unit

        uint totalFundSentToDao;
        bool finished;
    }
    SaleInfo public saleInfo;

    struct Purchase {
        uint[] buys;      // In currency unit //
        uint[] fees;      // In currency unit //  
        uint[] times;     // Time of purchases
        uint totalBought; // In currency unit //
        uint totalFees;   // In currency unit //
    }

    mapping(address=>Purchase) public userPurchaseMap;
    address[] private _buyerList; // For exporting purpose

    // Rebates for SL users
    mapping(address=>uint) public userRebateMap;
   
    // Pause and Refund support
    bool public paused;
    bool public refundEnabled;
    mapping(address=>bool) public userRefundMap;

    IDataLog private _logger;

    event BuyToken(address indexed user, uint fund, uint fee);
    event FinishUp();
    event Pause(bool set);
    event Refund(address indexed user, uint fund);
    event DaoRetrieveFund(uint amount);
    event UpdateSaleParam(uint unitPrice, uint hardCap);


    // As token is not yet issued, we assume the token is 18 dp.
    constructor (address currency, uint userFeePcnt, uint hardCap, uint price, uint start, uint end, uint minAlloc, uint maxAlloc, IDataLog log) {
        require(currency != Constant.ZERO_ADDRESS, "Invalid address");
        require(hardCap > 0 && price > 0 && start > block.timestamp, "Invalid param");
        require(end > start, "Invalid timing");
        require(minAlloc > 0 && maxAlloc > 0 && maxAlloc > minAlloc, "Invalid min, max");
    
        saleInfo.currency = currency;
        saleInfo.userFeePcnt = userFeePcnt; // Can be zero
        saleInfo.hardCap = hardCap;  
        saleInfo.unitPrice = price;
        saleInfo.startTime = start;
        saleInfo.endTime = end;
        saleInfo.minAlloc = minAlloc;
        saleInfo.maxAlloc = maxAlloc;
        _logger = log;
    }

    // In case of last minute changes 
    function updateSaleParams(uint unitPrice, uint hardCap) external onlyController {

        // Check to make sure sale in not live yet
        require(block.timestamp < saleInfo.startTime, "Already started");
        require(unitPrice > 0 && hardCap > 0, "Invalid param");

        saleInfo.unitPrice = unitPrice;
        saleInfo.hardCap = hardCap;   
        emit UpdateSaleParam(unitPrice, hardCap);
    }

    function importRebates(address[] memory users, uint[] memory discounts) external onlyController {

        uint len = users.length;
        require(len == discounts.length, "Invalid inputs");

        for (uint n=0; n<len; n++) {
            userRebateMap[users[n]] = discounts[n];
        }
    }

    // FCFS sale. Fund contribute to the token purchase. Fee is the nett fee after rebate.
    // A total of (fund + fee) is required for the purchase. 
    function buyToken(uint fund, uint fee) external nonReentrant {

        require(block.timestamp >= saleInfo.startTime, "Not started");
        require(block.timestamp < saleInfo.endTime && !saleInfo.finished, "Ended or finished");
        require(fund > 0, "Invalid amount");
        require(!paused, "Paused");
    
        // Make sure doesn't exceed max alloc. 
        Purchase storage purchase = userPurchaseMap[msg.sender];
        require((purchase.totalBought + fund) <= saleInfo.maxAlloc, "Exceed allocation");

        // Make sure no over-sold
        uint capLeft = getCapLeft();
        require(fund <= capLeft, "Not enough tokens");

        // If reminaning is less than min-alloc, then user can buy all.
        if (fund < saleInfo.minAlloc) {
            require(fund == capLeft, "Less than minimum purchase");
        }

        // Check the fee (after any rebate) is correct 
        (, uint requiredFee, ) = getFee(msg.sender, fund);
        require(fee == requiredFee, "Wrong fee");
        
        // Record new buying address if users first time buying.
        if (purchase.totalBought == 0) {
            _buyerList.push(msg.sender);
        }
        
        // Update
        purchase.totalBought += fund;
        purchase.totalFees += fee;
        purchase.buys.push(fund);
        purchase.fees.push(fee);
        purchase.times.push(block.timestamp);
        
        saleInfo.totalSold += fund;
        saleInfo.totalFeesCollected += fee;
        _transferTokenIn(saleInfo.currency, fund + fee);

        emit BuyToken(msg.sender, fund, fee);

        // DataLog
         _log(DataAction.Buy, fund, fee);
    }

    // Pause and Refund support
    function setPause(bool set) external onlyOwner {
        require(!saleInfo.finished,"finished");
        require(paused != set, "wrong value");

        if (!set) {
            require(!refundEnabled, "Cannot un-pause");
        }
        paused = set;
        emit Pause(set);
    }

    function enableRefund() external onlyOwner {
        // Can only enable refund if paused
        require(!saleInfo.finished,"finished");
        require(paused, "Not paused");
        refundEnabled = true;
    }

    // Note: A sale can be manually ended by calling finishUp before endTime.
    function finishUp() external onlyController {
        require(!paused,"Paused");
        require(block.timestamp >= saleInfo.startTime, "Not started");

        saleInfo.finished = true;
    }

    function refund() external nonReentrant {
        require(refundEnabled, "not enabled");

        // Already refunded ?
        bool refunded = userRefundMap[msg.sender];
        require(!refunded, "Already refunded");

        Purchase storage purchase = userPurchaseMap[msg.sender];
        uint total = purchase.totalBought + purchase.totalFees;
        require(total > 0, "No purchase");

        _transferTokenOut(saleInfo.currency, total, msg.sender);

        // update
        userRefundMap[msg.sender] = true;

        emit Refund(msg.sender, total);

        // DataLoglive 
        _log(DataAction.Refund, total, 0);
    }

    // Dao can retrieve fund for project since this is a seed sale. Multiple retrivals possible.
    function daoRetrieveFund(uint amount) external onlyOwner {
        saleInfo.totalFundSentToDao += amount;
        _transferTokenOut(saleInfo.currency, amount, msg.sender); // Let it fail if balance is insufficient
        emit DaoRetrieveFund(amount);
    }

    // Query
    function getCapLeft() public view returns (uint) {
        return saleInfo.hardCap - saleInfo.totalSold;
    }

    function getCost(uint tokenAmt) public view returns (uint) {
        return (tokenAmt * saleInfo.unitPrice) / Constant.E18;
    }

    function getTokenQty(uint fund) public view returns (uint) {
        return (fund * Constant.E18) / saleInfo.unitPrice;
    }

    function getUserPurchase(address user) external view returns (Purchase memory) {
        return  userPurchaseMap[user];
    }

    function getRebatePcnt(address user) public view returns (uint rebatePcnt) {
        rebatePcnt = userRebateMap[user]; // Non-zero for qualified stakers
    }

    function getFee(address user, uint fund) public view returns (uint rebatePcnt, uint fee, uint rebateAmt) {
        rebatePcnt = getRebatePcnt(user);

        if (saleInfo.userFeePcnt > rebatePcnt) {
            uint feePcnt = saleInfo.userFeePcnt - rebatePcnt;
            fee = (feePcnt * fund ) / Constant.PCNT_100;
        }

        // Do not rebate more than user's fee
        uint minPcnt = _min(saleInfo.userFeePcnt, rebatePcnt);
        rebateAmt = (minPcnt * fund ) / Constant.PCNT_100;
    }

    // Export 
    function getTotalSold() external view returns (uint fund, uint fee) {
        fund = saleInfo.totalSold;
        fee = saleInfo.totalFeesCollected;
    }

    function getBuyersCount() external view returns (uint) {
        return _buyerList.length;
    }

    function export(uint from, uint to) external view returns (uint, address[] memory, uint[] memory) {

        uint len =  _buyerList.length;
        require(len > 0  && from <= to, "Invalid range");
        require(to < len, "Out of range");

        uint count = to - from + 1;

        address[] memory add = new address[](count);
        uint[] memory amounts = new uint[](count);

        address tmp;
        for (uint n = 0; n < count; n++) {
            tmp = _buyerList[n + from];
            add[n] = tmp;
            amounts[n] = userPurchaseMap[tmp].totalBought;
        }
        return (count, add, amounts);
    }
    
    function exportAll() external view returns (uint, address[] memory, uint[] memory) {

        uint len =  _buyerList.length;
        address[] memory add = new address[](len);
        uint[] memory amounts = new uint[](len);

        address tmp;
        for (uint n = 0; n < len; n++) {
            tmp = _buyerList[n];
            add[n] = tmp;
            amounts[n] = userPurchaseMap[tmp].totalBought;
        }
        return (len, add, amounts);
    }

    // Helpers
    function _min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    function _log(DataAction action, uint data1, uint data2) private {
        _logger.log(address(this), msg.sender, uint(DataSource.Campaign), uint(action), data1, data2);
    }

    function _log(address user, DataAction action, uint data1, uint data2) private {
        _logger.log(address(this), user, uint(DataSource.Campaign), uint(action), data1, data2);
    }
}
