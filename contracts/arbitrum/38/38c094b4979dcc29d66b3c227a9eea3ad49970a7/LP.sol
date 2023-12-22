// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "./Pausable.sol";
import "./Ownable.sol";
import "./IVault.sol";
import "./IRevenue.sol";
import "./ERC20.sol";

contract LP is Ownable, Pausable, ERC20 {
    uint public depositFee;
    uint public withdrawFee;
    uint constant private denominator = 10000;

    mapping(address => uint) public depositTime;
    mapping(address => uint) public rewardTime;

    address public vault;
    address public revenue;

    uint public total_reward;

    constructor() Ownable() Pausable() ERC20("Vortex ETH LP", "VX-ELP"){ 
        depositFee = 20;
        withdrawFee = 50;
    }

    function setVault(address _vault) external onlyOwner() {
        vault = _vault;
    }

    function setRevenue(address _revenue) external onlyOwner() {
        revenue = _revenue;
    }

    function setDepositFee(uint _fee) external onlyOwner() {
        depositFee = _fee;
    }

    function setWithdrawFee(uint _fee) external onlyOwner() {
        withdrawFee = _fee;
    }

    function deposit() external payable whenNotPaused() {
        uint _amt = msg.value;
        require(_amt != 0, "value is 0");
        payable(revenue).transfer(_amt * depositFee / denominator);
        uint _lpAmt = _amt - _amt * depositFee / denominator;
        payable(vault).transfer(_lpAmt);

        depositTime[msg.sender] = block.timestamp;
        
        _mint(msg.sender, _lpAmt);
    }

    function withdraw(uint _lpAmt) external whenNotPaused() {
        require(_lpAmt != 0, "amount is 0");
        uint _amt = _lpAmt;
        if (block.timestamp - depositTime[msg.sender] <= 24 hours) {
            IVault(vault).withdrawFee(_lpAmt * withdrawFee / denominator, totalSupply());
            _amt = _lpAmt - _lpAmt * withdrawFee / denominator;
        }
        total_reward += _amt * vault.balance / totalSupply();
        IVault(vault).withdraw(msg.sender, _amt, totalSupply());
        _burn(msg.sender, _lpAmt);
    }

    function getReward() external whenNotPaused() {
        require(rewardTime[msg.sender] + 24 hours <= block.timestamp, "reward not expire");
        IRevenue(revenue).lpDividend(msg.sender, balanceOf(msg.sender), totalSupply());
        rewardTime[msg.sender] = block.timestamp;
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

