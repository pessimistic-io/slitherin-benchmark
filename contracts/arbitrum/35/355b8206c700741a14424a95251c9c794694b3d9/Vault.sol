// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./Pausable.sol";
import "./IERC20.sol";
import "./Ownable.sol";

contract Vault is Ownable, Pausable {
    mapping(address => bool) public LP;
    mapping(address => bool) public bet;
    address public revenue;
    address public immutable usdt;

    uint public refereeCnt;
    mapping(address => address) public referee;

    event Referee(address indexed _account, address indexed _referee);

    constructor(address _usdt, address _rev, address _lp, address _lpu) Ownable() Pausable() {
        usdt = _usdt;
        revenue = _rev;
        LP[_lp] = true;
        LP[_lpu] = true;
    }

    modifier onlyLP() {
        require(LP[msg.sender], "not lp");
        _;
    }

    modifier onlyBet() {
        require(bet[msg.sender], "not bet");
        _;
    }

    function setLP(address _lp) external onlyOwner() {
        LP[_lp] = !LP[_lp];
    }

    function setBet(address _bet) external onlyOwner() {
        bet[_bet] = !bet[_bet];
    }

    function setRevenue(address _revenue) external onlyOwner() {
        revenue = _revenue;
    }

    function setReferee(address _referee) external {
        if(_referee != referee[msg.sender] && referee[msg.sender] == address(0)) {
            refereeCnt += 1;
        }
        else if(_referee == address(0) && referee[msg.sender] != address(0)) {
            refereeCnt -= 1;
        }
        referee[msg.sender] = _referee;
        emit Referee(msg.sender, _referee);
    }

    function withdraw(address _account, uint _amt, uint _total) external onlyLP() whenNotPaused() {
        payable(_account).transfer(_amt * address(this).balance / _total);
    }

    function withdrawFee(uint _amt) external onlyLP() whenNotPaused() {
        payable(revenue).transfer(_amt);
    }

    function withdrawUSDT(address _account, uint _amt, uint _total) external onlyLP() whenNotPaused() {
        IERC20(usdt).transfer(_account, _amt * address(this).balance / _total);
    }

    function withdrawFeeUSDT(uint _amt) external onlyLP() whenNotPaused() {
        IERC20(usdt).transfer(revenue, _amt);
    }

    function pay(address _account, uint _amt) external onlyBet() whenNotPaused() {
        payable(_account).transfer(_amt);
    }

    function payUSDT(address _account, uint _amt) external onlyBet() whenNotPaused() {
        IERC20(usdt).transfer(_account, _amt);
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

