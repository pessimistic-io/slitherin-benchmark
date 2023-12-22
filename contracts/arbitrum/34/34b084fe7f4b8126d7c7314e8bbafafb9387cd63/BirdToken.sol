// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./IBirdFundsHolder.sol";

contract BirdToken is ERC20 {
    using SafeMath for uint256;
    error OrderTooSmall();
    bool public initiated;
    address public Owner;
    address public Deployer;
    address public Rewards;
    IBirdFundsHolder public FundsHolder;
    string public Twitter;
    uint256 public maxSupply = 1000000000 ether;
    uint256 public buyReward;
    uint256 public sellPenalty;
    uint256 public maxEarlyBirds;
    uint256 public totalEarlyBirds;
    mapping(address => bool) public poolAddresses;
    mapping(address => bool) public earlyBirdClaimed;

    modifier onlyOwner() {
        require(msg.sender == Owner,"Only Owner");
        _;
    }

    modifier onlyDeployer() {
        require(msg.sender == Deployer,"only Deployer");
        _;
    }

    constructor () ERC20("Bird", "BIRD") {
        Deployer = msg.sender;
        Owner = msg.sender;
    }

    //Initialisation function

    function initBird(address _rewards, address _fundsHolder, address _marketing, address _team, uint256 _maxEarly, string memory _twitter) external onlyOwner {
        require(!initiated,"Already initiated.");
        initiated = true;
        buyReward = 5;
        sellPenalty = 8;
        Twitter = _twitter;
        Rewards = _rewards;
        maxEarlyBirds = _maxEarly;
        FundsHolder = IBirdFundsHolder(_fundsHolder);
        _mint(address(this), maxSupply);
        //Calculate percentages and amounts
        uint256 currTime = block.timestamp;
        uint256 lpFunds = totalSupply().mul(60).div(100);
        uint256 rewardFunds = totalSupply().mul(10).div(100);
        uint256 teamFunds = totalSupply().mul(5).div(100);
        uint256 marketingFunds = totalSupply().mul(10).div(100);
        uint256 stakeFunds = totalSupply().mul(10).div(100);
        uint256 cexFunds = totalSupply().mul(5).div(100);
        uint256 approvalAmount = stakeFunds + cexFunds + marketingFunds.mul(9).div(10) + teamFunds.mul(4).div(5);
        //Transfer funds
        _transfer(address(this), Deployer, lpFunds); //LP Funds
        _transfer(address(this), Rewards, rewardFunds); //Reward Funds
        _transfer(address(this), _marketing, marketingFunds.div(10)); //Initial Marketing Funds
        _transfer(address(this), _team, teamFunds.div(5)); // Initial Team Funds
        //Approve for Fund Holder
        _approve(address(this), address(FundsHolder), approvalAmount);
        //Staking
        FundsHolder.holdFunds("Bird Staking Rewards", address(this), Deployer, stakeFunds, currTime.add(86400 * 21)); // After 3 Weeks
        //CEX
        FundsHolder.holdFunds("Bird CEX Funds", address(this), Deployer, cexFunds, currTime.add(86400 * 7)); // After 1 Week
        //Team
        FundsHolder.holdFunds("Bird Team - Month 2", address(this), Deployer, teamFunds.mul(2).div(5), currTime.add(86400 * 30)); // After 1 Month
        FundsHolder.holdFunds("Bird Team - Month 3", address(this), Deployer, teamFunds.mul(2).div(5), currTime.add(86400 * 60)); // After 2 Months
        //Marketing
        FundsHolder.holdFunds("Bird Marketing - Month 2", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 60)); // After 2 Months
        FundsHolder.holdFunds("Bird Marketing - Month 4", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 120)); // After 4 Months
        FundsHolder.holdFunds("Bird Marketing - Month 6", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 180)); // After 6 Months
        FundsHolder.holdFunds("Bird Marketing - Month 8", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 240)); // After 8 Months
        FundsHolder.holdFunds("Bird Marketing - Month 10", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 300)); // After 10 Months
        FundsHolder.holdFunds("Bird Marketing - Month 12", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 360)); // After 12 Months
        FundsHolder.holdFunds("Bird Marketing - Month 14", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 420)); // After 14 Months
        FundsHolder.holdFunds("Bird Marketing - Month 16", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 480)); // After 16 Months
        FundsHolder.holdFunds("Bird Marketing - Month 18", address(this), Deployer, marketingFunds.div(10), currTime.add(86400 * 540)); // After 18 Months
    }

    //Ownership functions

    function renounceOwnership() external onlyOwner {
        Owner = address(0);
    }

    //Maintainence Functions

    function addPool(address poolAddress) external onlyDeployer {
        require(poolAddress != address(0),"Address ZERO");
        poolAddresses[poolAddress] = true;
    }

    // Override functions

    function _transfer(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            if (poolAddresses[from] && to != Deployer) {
                uint256 buyRewards = buyReward;
                if (!earlyBirdClaimed[to] && totalEarlyBirds < maxEarlyBirds) {
                    buyRewards = buyReward.mul(2);
                    earlyBirdClaimed[to] = true;
                    totalEarlyBirds++;
                }
                uint256 rewardAmount = amount.mul(buyRewards).div(100);
                if (balanceOf(Rewards) >= rewardAmount) {
                    super._transfer(Rewards, to, rewardAmount);
                } else {
                    super._transfer(Rewards, to, balanceOf(Rewards));
                }
            } else if (poolAddresses[to] && from != Deployer) {
                uint256 penaltyAmount = amount.mul(sellPenalty).div(100);
                if (amount > penaltyAmount) {
                    amount -= penaltyAmount;
                    super._transfer(from, Rewards, penaltyAmount);
                } else {
                    revert OrderTooSmall();
                }
            }
        }
        super._transfer(from, to, amount);
    }
}

