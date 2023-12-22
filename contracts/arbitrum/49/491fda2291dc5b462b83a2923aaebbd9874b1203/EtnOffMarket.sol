pragma solidity =0.6.6;

/**
 * Math operations with safety checks
 */
library SafeMath {
    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint a, uint b) internal pure returns (uint) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        require(b <= a, errorMessage);
        uint c = a - b;

        return c;
    }
    function mul(uint a, uint b) internal pure returns (uint) {
        if (a == 0) {
            return 0;
        }

        uint c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint a, uint b) internal pure returns (uint) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint c = a / b;

        return c;
    }
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }


    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }


    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}


interface ERC20 {
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function selfBurn(uint256 value) external returns (bool);
}

contract EtnOffMarket is Ownable{
    using SafeMath for uint;
    ERC20 public etn;
    address public globalPool;

    uint public price = 1 ether;
    uint public burnKRate = 25;
    uint public rewardKRate = 25;

    bool public enableBuy = true;
    bool public enableSale = true;
    mapping (address => bool) public whitelist;

    event AddedWhiteList( address indexed to);
    event RemoveWhiteList( address indexed to);

    event ToGlobalPool( uint256 amount);
    event BuyToken(address indexed from,uint etnValue, uint ethValue);
    event SaleToken(address indexed from,uint etnValue, uint ethValue);
    event GovWithdraw(address indexed to, uint256 value);
    event GovWithdrawToken( address indexed to, uint256 value);

    constructor(address _etn, address _pool)public {
        etn = ERC20(_etn);
        globalPool = _pool;
    }

    function getBuyCost(uint _value) public view returns (uint){
        return _value.mul(price).div(1 ether);
    }

    function getSaleCost(uint _value) public view returns (uint){
        return _value.mul(1 ether).div(price);
    }

    function buy(uint256 _entValue) public payable{
        require(enableBuy, "!enabled");
        uint amount = getBuyCost(_entValue);
        require(
            amount <= msg.value,
            "Not enough coin sent"
        );

        uint received = burnAndReward(msg.sender, _entValue);
        etn.transfer( msg.sender, received);
        uint change = msg.value.sub(amount);
        if(change > 0){
            payable(msg.sender).transfer(change);
        }
        //update price
        afterBuy(_entValue);
        emit BuyToken(msg.sender,_entValue, amount);
    }


    //_amount需要收到多少eth
    function sale(uint256 _amount) public {
        require(enableSale, "!enabled");
        uint cost = getSaleCost(_amount);

        uint allowed = etn.allowance(msg.sender,address(this));
        uint balanced = etn.balanceOf(msg.sender);
        require(allowed >= cost, "!allowed");
        require(balanced >= cost, "!balanced");
        etn.transferFrom(msg.sender,address(this), cost);
        burnAndReward(msg.sender, cost);

        require(address(this).balance >= _amount, "Address: insufficient balance");
        payable(msg.sender).transfer(_amount);
        afterSale(cost);
        emit SaleToken(msg.sender,cost, _amount);
    }

    function burnAndReward(address _addr, uint _entValue) private returns (uint) {
        if(whitelist[_addr] == true){
            return _entValue;
        }
        uint toBurn = _entValue.mul(burnKRate).div(1000);
        etn.selfBurn(toBurn);
        uint toReward = _entValue.mul(rewardKRate).div(1000);
        toGlobalPool(toReward);
        return _entValue.sub(toBurn).sub(toReward);
    }

    function toGlobalPool(uint _value) private {
        etn.transfer(globalPool , _value);
        emit ToGlobalPool(_value);
    }

    function setGlobalPool(address _addr) public onlyOwner{
        globalPool = _addr;
    }

    function afterBuy(uint _value) private {
        price = price.sub(price.mul(_value).div(1 ether).div(1000));
    }
    function afterSale(uint _value) private {
        price = price.add(price.mul(_value).div(1 ether).div(1000));
    }

    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
    }

    function setToken(address _etn) public onlyOwner {
        etn = ERC20(_etn);
    }

    function setEnableSale(bool _enableSale) public onlyOwner {
        enableSale = _enableSale;
    }

    function setEnableBuy(bool _enableBuy) public onlyOwner {
        enableBuy = _enableBuy;
    }

    function addWhite (address _user) public onlyOwner {
        whitelist[_user] = true;
        emit AddedWhiteList(_user);
    }

    function removeWhite (address _user) public onlyOwner {
        delete whitelist[_user];
        emit RemoveWhiteList(_user);
    }

    function withdraw(address _to,uint256 _amount) public onlyOwner {
        require(_amount > 0, "!zero input");
        payable(_to).transfer(_amount);
        emit GovWithdraw( _to, _amount);
    }

    function withdrawToken(address _to,uint256 _amount) public onlyOwner {
        require(_amount > 0, "!zero input");
        etn.transfer( _to, _amount);
        emit GovWithdrawToken( _to, _amount);
    }
}