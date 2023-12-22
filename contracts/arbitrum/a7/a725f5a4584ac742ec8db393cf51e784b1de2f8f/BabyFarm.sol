// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./Ownable.sol";
import "./SafeMath.sol";


contract BabyFarm is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    modifier canMine() {
        require(openMining == true, "mining paused!");
        _;
    }

    modifier canWithdraw() {
      require(openWithdraw == true, "withdraw  paused!");
      require(blacklist[msg.sender] == false, "withdraw  blacklisted!");
      _;
    }

    event Withdraw(address who, uint256 amount, uint256 time);
    event Active(address who, uint256 refcode, uint256 time);
    event Boost(address who, uint256 time);

    struct Miner {
      uint256 uid;
      uint256 time;
      uint256 refCode;
      uint256 affCount;
      uint256 boostTime;
      uint256 bonusTime;
      uint256 interestProfit;
      address affFrom;
    }

    struct Rank {
      address addr;
      uint256 affCount;
    }

    uint256 constant public bonusPeriod = 1 hours;// 1 hours
    uint256 constant public boostPeriod = 1 days; // 1 days
    uint256 public startRate; //
    uint256 public totalMiners = 0;
    uint256 public halvingCount = 0; // halving period
    uint256 constant MAX_HALVING = 21; // max halving times
    uint256 public totalPayout;
    uint256 public baseRate;
    uint256 public bonusPercent = 5; //5%
    uint256 public REF_CODE = 88888;
    uint256 public minWithdrawAmount = 0;
    uint256 public startTime;
    IERC20 public rewardToken;

    uint256 public activeFee = 0.0005 * 10 ** 18;
    uint256 public transactionFee = 0.0005 * 10 ** 18;

    bool private openMining = true;
    bool private openWithdraw = true;

    mapping(address => Miner) public address2miner;
    mapping(uint256 => address) public uid2address;
    mapping(address => bool) public blacklist;

    constructor(IERC20  _rewardToken, uint256 _startTime) public {
      startTime = _startTime;
      startRate = uint256(5000000).mul(10 ** 18).div(3600);
      baseRate = startRate;
      rewardToken = _rewardToken;
      uid2address[REF_CODE] = owner();
      address2miner[owner()] = Miner(REF_CODE,now, REF_CODE, 0, now.add(boostPeriod), now, 0, address(0));
    }

    function register(address _addr, uint256 _refCode) private{
      REF_CODE = REF_CODE.add(8);
      address _affAddr = uid2address[_refCode];

      address2miner[_addr] = Miner(REF_CODE,now, _refCode, 0, now.add(boostPeriod), now, 0, _affAddr);

      collect(_affAddr);
      address2miner[_affAddr].affCount = address2miner[_affAddr].affCount.add(1);
      uid2address[REF_CODE] = _addr;


      if(now < address2miner[_affAddr].bonusTime){
        address2miner[_affAddr].bonusTime = address2miner[_affAddr].bonusTime.add(bonusPeriod);
      }
      else{
        address2miner[_affAddr].bonusTime = now.add(bonusPeriod);
      }
    }

    function shouldHalve() internal view returns (bool) {
        if (halvingCount >= MAX_HALVING) {
            return false;
        }

        // halve
        uint256 threshold = 5000 * (2 ** halvingCount);
        return totalMiners >= threshold;
    }

    function halving() internal {
        if (halvingCount < (MAX_HALVING - 1)) {
            baseRate /= 2;
        } else {
            baseRate = 1; // after 21 times of halving
        }

        halvingCount++;
    }

    function activate(uint256 _refCode) public payable canMine() {
        require(startTime < now, "not started");
        require(msg.value == activeFee, "incorrect activeFee!");
        require(address2miner[msg.sender].time == 0, "already registered!");
        payable(owner()).transfer(msg.value);
        totalMiners++;
        if(_refCode <= REF_CODE  && address2miner[uid2address[_refCode]].uid > 0){
          register(msg.sender, _refCode);
        }
        else{
          _refCode = 88888;
          register(msg.sender, _refCode);
        }

        if (shouldHalve()) {
            halving();
        }
        emit Active(msg.sender, _refCode, now);
    }

    function withdraw() public payable canWithdraw(){
      require(msg.value == transactionFee, "incorrect transactionFee!");
      payable(owner()).transfer(msg.value);

      collect(msg.sender);
      require(address2miner[msg.sender].interestProfit >= minWithdrawAmount, "have not reached minWithdrawAmount!");

      transferPayout(msg.sender, address2miner[msg.sender].interestProfit);

      totalMiners++;
      if (shouldHalve()) {
          halving();
      }
    }

    function boost() public payable canMine() returns (bool){
      require(msg.value == transactionFee, "incorrect transactionFee!");
      payable(owner()).transfer(msg.value);

      collect(msg.sender);
      Miner storage miner = address2miner[msg.sender];
      if(now < miner.boostTime){
        miner.boostTime = miner.boostTime.add(boostPeriod);
      }
      else{
        miner.boostTime = now.add(boostPeriod);
      }

      address upline = miner.affFrom;
      collect(upline);
      if(now < address2miner[upline].bonusTime){
        address2miner[upline].bonusTime = address2miner[upline].bonusTime.add(bonusPeriod);
      }
      else{
        address2miner[upline].bonusTime = now.add(bonusPeriod);
      }

      totalMiners++;
      if (shouldHalve()) {
          halving();
      }

      emit Boost(msg.sender, now);
      return true;
    }


    function collect(address _addr) internal {
      Miner storage miner = address2miner[_addr];
      miner.interestProfit = getTotalRewards(_addr);
      miner.time = now;
    }

    function transferPayout(address _receiver, uint256 _amount) internal {
        if (_amount > 0 && _receiver != address(0)) {

            totalPayout = totalPayout.add(_amount);

            Miner storage miner = address2miner[_receiver];
            miner.interestProfit = miner.interestProfit.sub(_amount);

            rewardToken.safeTransfer(_receiver, _amount);

            emit Withdraw(_receiver,_amount, now);
        }
    }

    function getBaseRewards(address _addr) public view returns (uint256) {
      Miner storage miner = address2miner[_addr];
      uint256 secPassed;
      if(now < miner.boostTime){
        secPassed = now.sub(miner.time);
      }
      else if(miner.time < miner.boostTime){
        secPassed = miner.boostTime.sub(miner.time);
      }
      else{
        secPassed = 0;
      }
      return secPassed.mul(baseRate);
    }

    function getBonusRewards(address _addr) public view returns (uint256) {
      Miner storage miner = address2miner[_addr];
      uint256 secPassed;

      if(now < miner.bonusTime){
        secPassed = now.sub(miner.time);
      }
      else if(miner.time < miner.bonusTime){
        secPassed = miner.bonusTime.sub(miner.time);
      }
      else{
        secPassed = 0;
      }
      return secPassed.mul(baseRate.mul(miner.affCount).mul(bonusPercent).div(100));
    }

    function getTotalRewards(address _addr) public view returns (uint256) {
      return address2miner[_addr].interestProfit.add(getBonusRewards(_addr)).add(getBaseRewards(_addr));
    }

    function getMyRate(address _addr) public view returns (uint256) {
      Miner storage miner = address2miner[_addr];
      uint256 bonusRate;

      if(now < miner.bonusTime){
        bonusRate = baseRate.mul(miner.affCount).mul(bonusPercent).div(100);
      }

      else{
        bonusRate = 0;
      }
      return bonusRate.add(baseRate);
    }

    function getHalfThreshold() public view returns (uint256) {
        return 5000 * (2 ** halvingCount);
    }

    function validateReferrer(uint256 refCode) public view returns (bool) {
      return address2miner[uid2address[refCode]].uid > 0;
    }

    /*************************************
    ******** OWNER FUNCTION CALLS ********
    *************************************/
    function minerTest(uint256 _miner) public onlyOwner returns (bool){
      totalMiners = _miner;
      if (shouldHalve()) {
          halving();
      }
      return true;
    }

    function add2blacklist(address _addr) public onlyOwner returns (bool){
      blacklist[_addr] = true;
      return true;
    }
    function removeFromBlacklist(address _addr) public onlyOwner returns (bool){
      blacklist[_addr] = false;
      return true;
    }

    function setMinWithdrawAmount(uint256 amount) public onlyOwner returns (bool){
      minWithdrawAmount = amount;
      return true;
    }

    function setContractStatus(bool status) public onlyOwner returns (bool){
      openMining = status;
      return true;
    }

    function setWithdrawStatus(bool status) public onlyOwner returns (bool){
      openWithdraw = status;
      return true;
    }

    function setTransactionFee(uint256 amount) public onlyOwner returns (bool){
      transactionFee = amount;
      return true;
    }

    //admin can transfer any token in emergency
    function transferSourceToken(IERC20 token, address to, uint256 amount) onlyOwner external {
        token.safeTransfer(to, amount);
    }

    //admin can transfer any bnb in emergency
    function emergencyWithdraw(address to) onlyOwner external returns(uint256 amount) {
        amount = address(this).balance;
        payable(to).transfer(amount);
    }
}

