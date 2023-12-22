// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./Pausable.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./ILP.sol";

contract Revenue is Ownable, Pausable {
    address public lp;
    address public lpu;
    mapping(address => bool) public bet;
    mapping(address => bool) public stake;
    // uint private eth_reserve;
    uint public market_revenue;
    uint public lp_revenue;
    uint public stake_revenue;
    address public immutable usdt;
    uint public usdt_market_revenue;
    uint public usdt_lp_revenue;
    uint public usdt_stake_revenue;

    uint private total_reward;
    uint private usdt_total_reward; 

    constructor(address _usdt, address _lp, address _lpu) Ownable() Pausable() { 
        market_revenue = 0;
        lp_revenue = 0;
        stake_revenue = 0;
        usdt_market_revenue = 0;
        usdt_lp_revenue = 0;
        usdt_stake_revenue = 0;
        usdt = _usdt;
        lp = _lp;
        lpu = _lpu;
    }

    modifier onlyLP() {
        require(msg.sender == lp || msg.sender == lpu, "not lp");
        _;
    }

    modifier onlyBet() {
        require(bet[msg.sender], "not bet");
        _;
    }

    modifier onlyStake() {
        require(stake[msg.sender], "not stake");
        _;
    }

    function resetLP(address _lp) external onlyOwner() {
        lp = _lp;
    }

    function resetLPU(address _lpu) external onlyOwner() {
        lpu = _lpu;
    }

    function setBet(address _bet) external onlyOwner() {
        bet[_bet] = !bet[_bet];
    }

    function setStake(address _stake) external onlyOwner() {
        stake[_stake] = !stake[_stake];
    }

    function distribute(uint _amt, bool _withReferee) external onlyBet() whenNotPaused() {
        IERC20(usdt).transferFrom(msg.sender, address(this), _amt);
        if (_withReferee) {
            uint _lp_amt = _amt * 10 / 35;
            uint _stake_amt = _amt * 5 / 35;

            usdt_lp_revenue += _lp_amt;
            usdt_stake_revenue += _stake_amt;
            usdt_market_revenue = usdt_market_revenue + (_amt - _lp_amt - _stake_amt);
        }
        else {
            uint _lp_amt = _amt * 15 / 50;
            uint _stake_amt = _amt * 10 / 50;

            usdt_lp_revenue += _lp_amt;
            usdt_stake_revenue += _stake_amt;
            usdt_market_revenue = usdt_market_revenue + (_amt - _lp_amt - _stake_amt);
        }
    }

    function distribute(bool _withReferee) external payable onlyBet() whenNotPaused() {
        if (_withReferee) {
            uint _lp_amt = msg.value * 10 / 35;
            uint _stake_amt = msg.value * 5 / 35;

            lp_revenue += _lp_amt;
            stake_revenue += _stake_amt;
            market_revenue = market_revenue + (msg.value - _lp_amt - _stake_amt);
        }
        else {
            uint _lp_amt = msg.value * 15 / 50;
            uint _stake_amt = msg.value * 10 / 50;

            lp_revenue += _lp_amt;
            stake_revenue += _stake_amt;
            market_revenue = market_revenue + (msg.value - _lp_amt - _stake_amt);
        }
    }

    function lpDividend(address _account, uint _share, uint _total) external onlyLP() whenNotPaused() {
        uint _amt = lp_revenue * _share / _total;
        lp_revenue -= _amt;
        total_reward += _amt;
        payable(_account).transfer(_amt);
    }

    function lpDividendUSDT(address _account, uint _share, uint _total) external onlyLP() whenNotPaused() {
        uint _amt = usdt_lp_revenue * _share / _total;
        usdt_lp_revenue -= _amt;
        usdt_total_reward += _amt;
        IERC20(usdt).transfer(_account, _amt);
    }

    function stakeReward(address _account, uint _amt) external onlyStake() whenNotPaused() {
        stake_revenue -= _amt;
        payable(_account).transfer(_amt);
    }

    function stakeRewardUSDT(address _account, uint _amt) external onlyStake() whenNotPaused() {
        usdt_stake_revenue -= _amt;
        IERC20(usdt).transfer(_account, _amt);
    }

    function getTotalIncome() external view returns(uint, uint) {
        return (lp_revenue + total_reward + ILP(lp).total_reward(), usdt_lp_revenue + usdt_total_reward + ILP(lpu).total_reward());
    }

    function pause() external onlyOwner() {
        _pause();
    }

    function unpause() external onlyOwner() {
        _unpause();
    }

    function rescue(address _token) external onlyOwner() {
        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this))-1);
    }

    function rescueETH() external onlyOwner() {
        payable(address(owner())).transfer(address(this).balance);
    }

    receive() payable external { }
}

