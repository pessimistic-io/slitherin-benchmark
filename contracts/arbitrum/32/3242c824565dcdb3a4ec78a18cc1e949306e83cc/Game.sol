// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;


import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

interface GameToken {
    function mint(address _to, uint256 _amount) external;
}

contract GameControl is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    GameToken public token;

    // fee config
    uint16 public devFee = 1000; // 10%
    uint16 public burnFee = 9000; // 90%
    uint16 public punishFee = 4000; //40%
    uint16 public percentRate = 10000;
    uint public tokenDecimals = 18;
    uint16 public dailyRewardLimit = 10;
    uint256 public lastReset;
    uint256 public resetTime = 1 days;
    uint256 public entryFee = 20 * 10 ** tokenDecimals;

    //address config
    address public TokenContract;
    address public DevWallet;
    address public constant BurnAddress = 0x000000000000000000000000000000000000dEaD;// Dead address for token burn

    bool public paused; // game pause at the beginning

    //game control
    mapping(address => bool) public entryStatus;
    mapping(uint => uint) public rewards;// or banishment || when user reach level out, will be reward, vs banishment
    uint16 public revivalFee = 4000;
    mapping(address => levelInfo) playerInfo;
    mapping(address => uint) public dailyRewards;

    struct levelInfo {
        uint levelNo;
        bool start;
        bool finish;
        bool revival;
        bool claimAble;
    }

    modifier onlyPaused {
        require(paused, "You can use this function when distribution is paused!");
        _;
    }

    constructor(address _devWallet, address _tokenContract) {
        require(_devWallet != address(0), "Please provide a valid Dev Wallet address");
        require(_tokenContract != address(0), "Please provide a valid Token Contract address");
        DevWallet = _devWallet;
        TokenContract = _tokenContract;
        token = GameToken(_tokenContract);
        lastReset = block.timestamp;
    }

    // Game hooks ///////////////////////////////////////////////////////////////////////////////
    function entryFeeDeposit(uint amount) external nonReentrant {
        require(!paused, "game is paused");
        require(entryFee == amount, "Please enter valid entry Fee amount");
        require(devFee + burnFee == percentRate, "Fee rates are not correct");
        uint devTax = (amount * devFee) / percentRate;
        uint burnTax = (amount * burnFee) / percentRate;
        IERC20(TokenContract).safeTransferFrom(msg.sender, DevWallet, devTax);
        IERC20(TokenContract).safeTransferFrom(msg.sender, BurnAddress, burnTax);
        playerInfo[msg.sender] = levelInfo(1, true, false, false, false);
        entryStatus[msg.sender] = true;
    }

    function levelReward(uint levelNo, bool levelStatus) external nonReentrant {
        require(!paused, "game is paused");
        require(entryStatus[msg.sender], "You didn't pay entry fee yet!");

        uint rewardAmount = rewards[levelNo];

        if (levelStatus) {
            if (block.timestamp > lastReset + resetTime) {
                lastReset = block.timestamp;
                dailyRewards[msg.sender] = 0;
            }
            require(dailyRewardLimit > dailyRewards[msg.sender], "Your daily reward limit exceeded");
            token.mint(msg.sender, rewardAmount);
            // new token mint for winners

            playerInfo[msg.sender].levelNo = levelNo;
            dailyRewards[msg.sender] += 1;
        } else {
            uint punishTax = (rewardAmount * punishFee) / percentRate;
            uint devTax = (punishTax * devFee) / percentRate;
            uint burnTax = (punishTax * burnFee) / percentRate;
            IERC20(TokenContract).safeTransferFrom(msg.sender, DevWallet, devTax);
            IERC20(TokenContract).safeTransferFrom(msg.sender, BurnAddress, burnTax);
            playerInfo[msg.sender] = levelInfo(1, true, false, false, false);
        }
    }

    function revival(uint levelNo) external {
        require(!paused, "game is paused");
        require(entryStatus[msg.sender], "You didn't pay entry fee yet!");
        uint revivalTax = (rewards[levelNo] * revivalFee) / percentRate;
        uint devTax = (revivalTax * devFee) / percentRate;
        uint burnTax = (revivalTax * burnFee) / percentRate;

        IERC20(TokenContract).safeTransferFrom(msg.sender, DevWallet, devTax);
        IERC20(TokenContract).safeTransferFrom(msg.sender, BurnAddress, burnTax);

        playerInfo[msg.sender].levelNo = levelNo;
        playerInfo[msg.sender].revival = true;
    }


    // Game Configuration ////////////////////////////////////////////////////////////////////////
    function setRewards(uint _levelNo, uint _levelFee) public onlyOwner {
        rewards[_levelNo] = _levelFee;
    }

    function setRevivalFee(uint16 _newFee) public onlyOwner {
        revivalFee = _newFee;
    }

    function setEntryFee(uint _newFee) public onlyOwner {
        entryFee = _newFee;
    }

    function setDevFee(uint16 _newDevFee) public onlyOwner {
        devFee = _newDevFee;
        burnFee = percentRate - devFee;
    }

    function setResetTime(uint256 _newTime) public onlyOwner{
        resetTime = _newTime;
    }

    function setDailyLimit(uint16 _newLimit) public onlyOwner{
        dailyRewardLimit = _newLimit;
    }

    function setPunishFee(uint16 _newPunishFee) public onlyOwner {
        punishFee = _newPunishFee;
    }

    function gameStart() public onlyOwner {
        paused = !paused;
    }
    // Game Configuration ends //////////////////////////////////////////////////////////////////////

    function withdrawRestFunds() external onlyOwner nonReentrant onlyPaused {
        uint contractBalance = IERC20(TokenContract).balanceOf(address(this));
        // transfer fund
        IERC20(TokenContract).safeTransfer(msg.sender, contractBalance);
    }
}
