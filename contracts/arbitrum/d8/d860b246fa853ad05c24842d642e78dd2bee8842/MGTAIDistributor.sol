// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IDistributionPool.sol";

contract MGTAIDistributor is Ownable {
    using SafeMath for uint256;
    IERC20 public mgtai;
    IDistributionPool public pool;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public maxClaimable;
    uint256 public totalClaimed;

    uint256 public minAirdrop;
    uint256 public maxAirdrop;

    uint256 public totalIdo;
    uint256 public idoed;
    uint256 public minPrice;
    uint256 public maxPrice;
    uint256 public bonusRate;
    uint256 public BASE_DIVISOR = 10000;

    mapping(address=>bool) public isClaimed;
    mapping(address=>bool) public isWhitelist;

    event Buy(address user, uint256 price, uint256 amount, uint256 bonus);
    event Claim(address user, uint256 claimed);

    constructor(
        address _mgtai, 
        address _pool, 
        uint256 _startTime, 
        uint256 _endTime, 
        uint256 _maxClaimable, 
        uint256 _minAirdrop, 
        uint256 _maxAirdrop, 
        uint256 _totalIdo, 
        uint256 _minPrice, 
        uint256 _maxPrice,
        uint256 _bonusRate
    ) 
    {
        mgtai = IERC20(_mgtai);
        pool = IDistributionPool(_pool);
        startTime = _startTime;
        endTime = _endTime;
        maxClaimable = _maxClaimable;
        minAirdrop = _minAirdrop;
        maxAirdrop = _maxAirdrop;
        totalIdo = _totalIdo;
        minPrice = _minPrice;
        maxPrice = _maxPrice;
        bonusRate = _bonusRate;
    }
    
    function claim() public {
        require(block.timestamp > startTime, "not start");
        require(block.timestamp <= endTime && totalClaimed < maxClaimable, "ended");
        uint256 claimable = getClaimable(msg.sender);
        totalClaimed++;
        isClaimed[msg.sender] = true;
        mgtai.transfer(msg.sender, claimable.mul(1 ether));
        emit Claim(msg.sender, claimable);
    }

    function buy(address _refer) public payable {
        require(block.timestamp > startTime, "not start");
        require(block.timestamp <= endTime && idoed <= totalIdo, "ended");
        uint256 value = msg.value;
        require(value > 0, "not pay");
        uint256 price = getPrice();
        uint256 amount = value.div(price);
        uint256 bonus;
        if(_refer != address(0) && _refer != msg.sender) {
            bonus = amount.mul(bonusRate).div(BASE_DIVISOR);
            mgtai.transfer(_refer, bonus.mul(1 ether));
        }

        idoed = idoed.add(amount).add(bonus);
        mgtai.transfer(msg.sender, amount.mul(1 ether));
        emit Buy(msg.sender, price, amount, bonus);
    }

    function getClaimable(address _user) public view returns(uint256 amount) {
        if((isWhitelist[_user] || pool._claimedUser(_user)) && !isClaimed[_user]){
            uint256 subAmount = totalClaimed.mul(maxAirdrop.sub(minAirdrop)).div(maxClaimable);
            if(maxAirdrop > subAmount) amount = maxAirdrop.sub(subAmount);
        }
    }

    function getPrice() public view returns(uint256 price) {
        price = minPrice.add(idoed.mul(maxPrice.sub(minPrice)).div(totalIdo));
    }

    function getStatus(address _user) public view returns(bool) {
        return pool._claimedUser(_user);
    }

    function withdraw(address _token) public onlyOwner {
        if(_token != address(0)){
            uint256 bal = IERC20(_token).balanceOf(address(this));
            IERC20(_token).transfer(msg.sender, bal);
        }else{
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function setTime(uint256 _startTime, uint256 _endTime) public onlyOwner {
        startTime = _startTime;
        endTime = _endTime;
    }

    function setBonusRate(uint256 _bonusRate) public onlyOwner {
        bonusRate = _bonusRate;
    }

    function setAirdropInfos(
        uint256 _maxClaimable, 
        uint256 _minAirdrop, 
        uint256 _maxAirdrop
    ) 
        public 
        onlyOwner 
    {
        maxClaimable = _maxClaimable;
        minAirdrop = _minAirdrop;
        maxAirdrop = _maxAirdrop;
    }

    function setIdoInfos(
        uint256 _totalIdo, 
        uint256 _minPrice, 
        uint256 _maxPrice
    ) 
        public 
        onlyOwner 
    {
        totalIdo = _totalIdo;
        minPrice = _minPrice;
        maxPrice = _maxPrice;
    }

    function addWhitelist(address[] memory _users) public onlyOwner {
        for(uint256 i = 0; i < _users.length; i++){
            isWhitelist[_users[i]] = true;
        }
    }

    function removeWhitelist(address[] memory _users) public onlyOwner() {
        for(uint256 i = 0; i < _users.length; i++){
            isWhitelist[_users[i]] = false;
        }
    }
}

