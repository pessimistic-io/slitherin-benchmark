pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

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
    function selfBurn(uint256 amount) external returns (bool);
}

interface ERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

interface PreStake {
    function getUserStake(address _addr, uint _nftId, bool _canExpire) external view returns (uint);
}


contract EtnStake is Ownable{
    using SafeMath for uint;

    struct Record {
        uint stake;
        uint expire;
        uint level;
    }

    uint public level1Time = 2592000;   
    uint public level2Time = 17280000;   
    uint public level3Time = 60480000;   

    mapping (uint => mapping (address =>uint)) public extPowMap;  
    mapping (uint => address[]) public nftCountMap;              
    mapping( uint => mapping( address => Record[])) userRecordMap;    //用户的质押记录，显示在页面，加退的时候要用

    ERC20 public etn;
    ERC721 public etnNft;
    PreStake public pStake;
    address public globalPool;

    uint constant private minInvestmentLimit = 10 finney;

    event GovWithdrawToken( address indexed to, uint256 value);
    event Stake(address indexed from, uint nftId , uint amount, uint level);
    event ToGlobalPool(uint indexed nftId , uint256 amount);

    constructor(address _etn, address _etnNft, address _pStake, address _globalPool)public {
        etn = ERC20(_etn);
        etnNft = ERC721(_etnNft);
        pStake = PreStake(_pStake);
        globalPool = _globalPool;
    }

    function stake(uint _nftId,uint _value, uint _level) public returns (uint){
        require(_value >= minInvestmentLimit,"!stake limit");
        uint allowed = etn.allowance(msg.sender,address(this));
        uint balanced = etn.balanceOf(msg.sender);
        require(allowed >= _value, "!allowed");
        require(balanced >= _value, "!balanced");
        etn.transferFrom(msg.sender,address(this), _value);

        // get external stake
        uint expire = block.timestamp;
        if(_level == 1){
            expire += level1Time;
        }else if(_level == 2){
            expire += level2Time;
            _value = _value.mul(105).div(100);
        }else if(_level == 3){
            expire += level3Time;
            _value = _value.mul(110).div(100);
        }
        // add stake record
        addCount(_nftId, msg.sender);
        userRecordMap[_nftId][msg.sender].push(Record( _value,expire,_level));
        addGroupPower(_nftId,_value,_level);
        emit Stake( msg.sender,_nftId, _value,_level);
        return _value;
    }

    function withdraw(uint _nftId, uint _index, uint _value) public{
        Record storage record = userRecordMap[_nftId][msg.sender][_index];
        require(record.expire < block.timestamp, "not expired");
        record.stake = record.stake.sub(_value);
        uint toBurn = _value.mul(25).div(1000);
        uint toPool = _value.mul(25).div(1000);
        uint toUser = _value.sub(toPool).sub(toPool);
        toGlobalPool(_nftId,toPool);
        burn(toBurn);
        etn.transfer( msg.sender, toUser);
    }

    function stakeWithAdvice(uint _nftId,uint _value, uint _level, address _up) public{
        uint staked = stake(_nftId,_value,_level);
        if(_up == msg.sender){
            return;
        }
        uint power = _stakeToPower(staked, _level);
        uint toUp = 0;
        if(_level == 2){
            toUp = power.mul(15).div(100);
        }else if(_level == 3){
            toUp = power.mul(25).div(100);
        }
        if(toUp > 0 && _up != address(0)){
            addExtPow(_nftId,_up,toUp);
        }
    }

    function addGroupPower(uint _nftId,uint _value, uint _level) private{

        uint power = _stakeToPower(_value, _level);
        uint toOwner = 0;
        if(_level == 2){
            toOwner = power.mul(5).div(100);
        }else if(_level == 3){
            toOwner = power.mul(10).div(100);
        }
        if(toOwner > 0){
            address groupOwner = etnNft.ownerOf(_nftId);
            addExtPow(_nftId,groupOwner,toOwner);
        }
    }

    function addCount(uint _nftId, address _addr) private{
        if(userRecordMap[_nftId][_addr].length == 0){
            nftCountMap[_nftId].push(_addr);
        }
    }

    function toGlobalPool(uint _nftId,uint _value) private {
        etn.transfer(globalPool, _value);
        emit ToGlobalPool(_nftId,_value);
    }

    function burn(uint _value) private {
        etn.selfBurn(_value);
    }

    function addExtPow(uint _nftId, address _addr, uint _value) private {
        extPowMap[_nftId][_addr] += _value;
    }


    function getUserPower(uint _nftId, address _addr) public view returns (uint){
        uint rs = 0;
        Record[] memory records = userRecordMap[_nftId][_addr];
        uint count = records.length;
        for (uint i = 0; i < count; i++) {
            rs = rs.add(_stakeToPower(records[i].stake, records[i].level));
        }
        rs = rs.add(extPowMap[_nftId][_addr]);
        uint staked = getUserStake(_nftId,_addr);
        uint pStaked = getPreUserStake(_nftId, _addr,staked);
        uint pPower = _stakeToPower(pStaked,1);
        rs = rs.add(pPower);
        return rs;
    }

    function getUserStake(uint _nftId,address _addr) public view returns (uint){
        uint rs = 0;
        Record[] memory records = userRecordMap[_nftId][_addr];
        uint count = records.length;
        for (uint i = 0; i < count; i++) {
            rs = rs + records[i].stake;
        }
        return rs;
    }

    function getPreUserStake(uint _nftId, address _addr, uint staked) private view returns (uint){
        staked = staked.mul(2);
        uint preStake = pStake.getUserStake(_addr,_nftId,true);
        uint preAllStake = pStake.getUserStake(_addr,_nftId,false);
        return preStake+staked > preAllStake? preAllStake:preStake+staked;
    }

    function getPreActivePercent(uint _nftId, address _addr) public view returns (uint, uint){
        uint staked = getUserStake(_nftId,_addr);
        uint pStaked = getPreUserStake(_nftId, _addr,staked);
        uint preAllStake = pStake.getUserStake(_addr,_nftId,false);
//        return pStaked.mul(100).div(preAllStake);
        return (pStaked, preAllStake);
    }

    function getExtPower(uint _nftId, address _addr) public view returns (uint){
        return extPowMap[_nftId][_addr];
    }

    function getGroupStake(uint _nftId)public view returns (uint){
        uint rs = 0;
        address[] memory addrs = nftCountMap[_nftId];
        uint count = addrs.length;
        for(uint i = 0;i<count; i++){
            rs += getUserStake(_nftId,addrs[i]);
        }
        return rs;
    }
    function getGroupPower(uint _nftId)public view returns (uint){
        uint rs = 0;
        address[] memory addrs = nftCountMap[_nftId];
        uint count = addrs.length;
        for(uint i = 0;i<count; i++){
            rs += getUserPower(_nftId,addrs[i]);
        }
        return rs;
    }

    function _stakeToPower(uint _value, uint _level) private  pure  returns (uint){
        if(_level == 1){
            _value = _value.mul(10000).div(1 ether);
        }else if(_level == 2){
            _value = _value.mul(20000).div(1 ether);
        }else if(_level == 3){
            _value = _value.mul(30000).div(1 ether);
        }
        return _value;
    }

    function getUserStakeList(uint _nftId,address _addr) public view returns ( Record[] memory){
        return userRecordMap[_nftId][_addr];
    }

    function setToken(address _etn) public onlyOwner {
        etn = ERC20(_etn);
    }

    function setGlobalPool(address _addr) public onlyOwner{
        globalPool = _addr;
    }

    function govWithdrawToken(address _to,uint256 _amount) public onlyOwner {
        require(_amount > 0, "!zero input");
        etn.transfer( _to, _amount);
        emit GovWithdrawToken( _to, _amount);
    }


}