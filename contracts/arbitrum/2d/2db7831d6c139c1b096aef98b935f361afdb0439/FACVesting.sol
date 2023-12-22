// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SafeMath.sol";
import "./Math.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./FAC.sol";
import "./SignatureLens.sol";
import "./AssetTransfer.sol";

contract FACVesting is ReentrancyGuard,SignatureLens{
    using SafeMath for uint256;
    using Math for uint256;

    struct Config{
        uint256 cliff;
        uint256 gap;
        uint256 duration;
        uint256 initShare;
        uint256 wholeShare;
    }

    struct Vest{
        uint256 initReleased;
        uint256 released;
        uint256 unreleased;
    }

    FAC public fac;
    uint256 public start;
    uint public airdropped;

    mapping(address => Config) public accountConfig;
    mapping(address => Vest) public accountVest;
    mapping(address => uint) public userAirdropped;

    event Released(address indexed operator, uint amount);
    event Airdrop(address indexed operator,uint amount);

    constructor(string memory _name
    , string memory _symbol
    , uint256 _initialSupply
    , uint256 _start
    , address[] memory _accounts
    , Config[] memory _configs
    , address _signer) SignatureLens(_signer){
        require(_accounts.length >0 && _accounts.length == _configs.length,"Parameter error");

        start = _start;
        fac = new FAC(_name, _symbol, _initialSupply);
        init(_initialSupply, _accounts, _configs);
    }

    function init(uint256 _initialSupply, address[] memory _accounts, Config[] memory _configs) private{
        uint totalShare = totalShare(_configs);

        for(uint i=0;i<_configs.length;i++){
            Config memory _config = _configs[i];
            address _account = _accounts[i];
            if(_account == address(0)){
                _account = address(this);
            }

            configInit(_account, _config);
            vestInit(_initialSupply, _account, _config, totalShare);
        }
    }

    function configInit(address _account, Config memory _config) private{
        require(_config.gap <= _config.duration,"Gap Cannot be greater than duration");
        accountConfig[_account] = _config;
    }

    function vestInit(uint256 _initialSupply, address _account, Config memory _config, uint _totalShare) private{
        require(_config.initShare <= _config.wholeShare,"InitShare Cannot be greater than wholeShare");

        uint wholeSupply = _initialSupply.mul(_config.wholeShare).div(_totalShare);
        uint initSupply = _initialSupply.mul(_config.initShare).div(_totalShare);

        Vest storage vest = accountVest[_account];
        vest.initReleased = initSupply;
        vest.released = initSupply;
        vest.unreleased = wholeSupply.sub(initSupply);

        if(_account != address(this) && initSupply >0){
            IERC20(fac).transfer(_account, initSupply);
        }
    }

    function totalShare(Config[] memory _configs) private pure returns(uint){
        uint totalShare = 0;
        for(uint i=0;i<_configs.length;i++){
            Config memory config = _configs[i];
            totalShare = totalShare.add(config.wholeShare);
        }
        return totalShare;
    }

    function release(address account) public onlyOwner{
        uint256 releasableAmount = currentPhaseTotalReleasingAmount(account);
        release(account, releasableAmount);
    }

    function release(address account, uint256 releasableAmount) internal {
        require(releasableAmount > 0,"The releasable quantity is insufficient");

        Vest storage vest = accountVest[account];
        vest.unreleased = vest.unreleased.sub(releasableAmount);
        vest.released = vest.released.add(releasableAmount);

        if(account != address(this)){
            IERC20(fac).transfer(account, releasableAmount);
        }

        emit Released(account, releasableAmount);
    }

    function currentPhaseTotalReleasingAmount(address account) public view returns (uint256) {
        Vest memory vest = accountVest[account];
        return currentPhaseTotalMarketableAmount(account).sub(vest.released);
    }

    function currentPhaseTotalReleasableAmount(address account) public view returns (uint256) {
        uint currentPhase = currentPhase(account);
        return phaseTotalReleasableAmount(account, currentPhase);
    }

    function currentPhaseTotalMarketableAmount(address account) public view returns (uint256) {
        Vest memory vest = accountVest[account];
        uint total = vest.unreleased.add(vest.released);
        if(block.timestamp >= endReleaseTime(account)) {
            return total;
        }

        uint phase = currentPhase(account);
        if(phase == 0){
            return vest.initReleased;
        }

        return phaseTotalReleasableAmount(account, phase).add(vest.initReleased);
    }

    function phaseTotalReleasableAmount(address account, uint phase) public view returns(uint256) {
        Vest memory vest = accountVest[account];
        uint total = vest.unreleased.add(vest.released);
        uint locked = total.sub(vest.initReleased);
        if(phase == 0){
            return 0;
        }

        uint totalPhase = totalPhase(account);
        require(phase <= totalPhase,"The phase cannot be greater than totalPhase");
        if(totalPhase == 0){
            return 0;
        }
        if(phase == totalPhase){
            return locked;
        }
        return locked.mul(phase).div(totalPhase);
    }

    function currentPhase(address account) public view returns(uint){
        Config memory config = accountConfig[account];
        if(config.gap == 0 || config.duration == 0){
            return 0;
        }

        uint currentTime = block.timestamp;
        uint _startReleaseTime = startReleaseTime(account);
        uint _endReleaseTime = endReleaseTime(account);
        if(currentTime <= _startReleaseTime){
            return 0;
        }

        uint _totalPhase = totalPhase(account);
        if(currentTime >= _endReleaseTime){
            return _totalPhase;
        }

        return  (currentTime.sub(_startReleaseTime)).div(config.gap);
    }

    function totalPhase(address account) public view returns(uint){
        Config memory config = accountConfig[account];
        if(config.gap == 0 || config.duration == 0){
            return 0;
        }
        return config.duration.ceilDiv(config.gap);
    }

    function allocationQuantity(address account) public view returns(uint) {
        Vest memory vest = accountVest[account];
        return vest.unreleased.add(vest.released);
    }

    function startReleaseTime(address account) public view returns(uint){
        Config memory config = accountConfig[account];
        return start.add(config.cliff);
    }

    function endReleaseTime(address account) public view returns(uint){
        uint startReleaseTime = startReleaseTime(account);
        Config memory config = accountConfig[account];
        return startReleaseTime.add(config.duration);
    }

    function airdrop(uint amount, Signature calldata signature) external nonReentrant{
        require(userAirdropped[msg.sender] == 0, "The airdrop has been received");
        bytes32 params = keccak256(abi.encodePacked(amount));
        require(verifySignature("Airdrop(uint,Signature)", params, signature), "Illegal operation");

        Vest memory vest = accountVest[address(this)];
        require(vest.released >= airdropped.add(amount), "The airdrop has been completed");

        AssetTransfer.reward(address(this), msg.sender, address(fac), amount);
        userAirdropped[msg.sender] = amount;
        airdropped = airdropped.add(amount);

        emit Airdrop(msg.sender, amount);
    }
}
