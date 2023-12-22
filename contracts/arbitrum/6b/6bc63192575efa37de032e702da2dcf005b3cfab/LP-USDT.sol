// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
import "./Pausable.sol";
import "./Ownable.sol";
import "./IVault.sol";
import "./IRevenue.sol";
import "./IERC20.sol";

contract LP_USDT is Ownable, Pausable {
    mapping(address => uint256) private _balances;

    event Transfer(address indexed from, address indexed to, uint256 value);

    // mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    uint public depositFee;
    uint public withdrawFee;
    uint constant private denominator = 10000;

    mapping(address => uint) public depositTime;
    mapping(address => uint) public rewardTime;

    address public vault;
    address public revenue;

    address public immutable usdt;

    constructor(address _usdt) Ownable() Pausable() { 
        depositFee = 20;
        withdrawFee = 50;
        usdt = _usdt;
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

    function deposit(uint _amt) external payable whenNotPaused() {
        require(_amt != 0, "value is 0");
        IERC20(usdt).transferFrom(msg.sender, address(this), _amt);
        IERC20(usdt).transfer(revenue, _amt * depositFee / denominator);
        uint _lpAmt = _amt - _amt * depositFee / denominator;
        IERC20(usdt).transfer(vault, _lpAmt);

        depositTime[msg.sender] = block.timestamp;
        
        _mint(msg.sender, _lpAmt);
    }

    function withdraw(uint _lpAmt) external whenNotPaused() {
        require(_lpAmt != 0, "amount is 0");
        uint _amt = _lpAmt;
        if (block.timestamp - depositTime[msg.sender] <= 24 hours) {
            IVault(vault).withdrawFee(_lpAmt * withdrawFee / denominator);
            _amt = _lpAmt - _lpAmt * withdrawFee / denominator;

        }
        IVault(vault).withdrawUSDT(msg.sender, _amt, totalSupply());
        _burn(msg.sender, _lpAmt);
    }

    function getReward() external whenNotPaused() {
        require(rewardTime[msg.sender] + 24 hours <= block.timestamp, "reward not expire");
        IRevenue(revenue).lpDividendUSDT(msg.sender, balanceOf(msg.sender), totalSupply());
        rewardTime[msg.sender] = block.timestamp;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
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

