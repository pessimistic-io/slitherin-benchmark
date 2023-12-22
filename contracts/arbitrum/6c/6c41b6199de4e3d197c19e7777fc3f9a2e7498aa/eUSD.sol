// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.9;

import "./IERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./Initializable.sol";

contract eUSD is Initializable, IERC20Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public USDC;

    string private _name;
    string private _symbol;
    uint256 private _totalSupply;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _balances; // base balance

    uint256 private liquidity;
    address public feeRecipient;
    uint256 public maxFee;

    uint256 public exchangeRate; // USDC per eUSD
    mapping(address => uint256) public lastWithdraw; // address to block number
    uint256 public blockTimeout;

    bool public allowDeposit;
    bool public allowWithdraw;

    function initialize(address _USDCAddress, uint256 _blockTimeout)
        public
        initializer
    {
        __Ownable_init();
        _name = "eUSD";
        _symbol = "eUSD";
        USDC = IERC20Upgradeable(_USDCAddress); // USDC mainnet address
        feeRecipient = msg.sender;
        liquidity = 0;
        exchangeRate = 10**6;
        maxFee = 0.1 * (10**6);
        allowDeposit = true;
        allowWithdraw = true;
        blockTimeout = _blockTimeout; //blocks (around 21 days for mainnet)
    }

    function baseToScaled(uint256 _amount) private view returns (uint256) {
        return _amount.mul(exchangeRate).div(10**this.decimals());
    }

    function scaledToBase(uint256 _amount) private view returns (uint256) {
        return _amount.mul(10**this.decimals()).div(exchangeRate);
    }

    // ERC20 features
    function decimals() public pure returns (uint8) {
        return 6;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function totalSupply() public view returns (uint256) {
        return baseToScaled(_totalSupply);
    }

    function getBaseTotalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address user) public view override returns (uint256) {
        return baseToScaled(_balances[user]);
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(msg.sender, to, amount);

        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();

        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(
            msg.sender != address(0),
            "ERC20: transfer from the zero address"
        );
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 _amount = scaledToBase(amount);
        require(
            _balances[from] >= _amount,
            "ERC20: transfer amount exceeds balance"
        );

        _beforeTokenTransfer(msg.sender, to);

        _balances[from] = _balances[from] - _amount;
        _balances[to] += _amount;

        emit Transfer(from, to, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function setDeposit(bool _allow) public onlyOwner {
        allowDeposit = _allow;
    }

    function setWithdraw(bool _allow) public onlyOwner {
        allowWithdraw = _allow;
    }

    function setExchangeRate(uint256 _newExchangeRate) public onlyOwner {
        exchangeRate = _newExchangeRate;
    }

    function setMaxFee(uint256 _maxFee) public onlyOwner {
        maxFee = _maxFee;
    }

    // WARNING: applies to accounts currently serving a penalty
    function setBlockTimeout(uint256 _blockTimeout) public onlyOwner {
        blockTimeout = _blockTimeout;
    }

    function setUSDC(address _address) public onlyOwner {
        USDC = IERC20Upgradeable(_address);
    }

    function availableLiquidity() public view returns (uint256) {
        return liquidity;
    }

    function withdrawLiquidity(uint256 value) public onlyOwner {
        require(value <= liquidity, "Not enough liquidity to withdraw");
        liquidity -= value;
        USDC.safeTransfer(this.owner(), value);
    }

    function addLiquidity(uint256 value) public onlyOwner {
        USDC.safeTransferFrom(this.owner(), address(this), value);
        liquidity += value;
    }

    function updateFeeRecipient(address to) public onlyOwner {
        feeRecipient = to;
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        _transferOwnership(newOwner);
        feeRecipient = newOwner;
    }

    // value = number of USDC to mint with
    function mint(uint256 value) public {
        require(allowDeposit, "Deposits are disabled");
        USDC.safeTransferFrom(msg.sender, address(this), value);
        liquidity += value;

        // first time depositing
        if (lastWithdraw[msg.sender] <= 0) {
            lastWithdraw[msg.sender] = block.number; // begin initial lock
        }

        uint256 _baseValue = scaledToBase(value);
        _balances[msg.sender] += _baseValue;
        _totalSupply += _baseValue;
        emit Transfer(address(0), msg.sender, value);
    }

    // // value = number of USDC to mint with
    // function mintUnbacked(uint256 value) public onlyOwner {
    //     uint256 _baseValue = scaledToBase(value);
    //     _balances[msg.sender] += _baseValue;
    //     _totalSupply += _baseValue;
    //     emit Transfer(address(0), msg.sender, value);
    // }

    // value = number of eUSD to burn
    function withdraw(uint256 value) public {
        require(allowWithdraw, "Withdraws are disabled");
        require(liquidity >= value, "Not enough liquidity");

        uint256 _baseValue = scaledToBase(value);
        require(_balances[msg.sender] >= _baseValue, "Not enough balance");

        _balances[msg.sender] -= _baseValue;
        _totalSupply -= _baseValue;
        emit Transfer(msg.sender, address(0), value);

        uint256 USDAmount = value;
        liquidity -= USDAmount;

        // subtract linear fee
        uint256 percentFee = maxFee.mul(getWithdrawFee(msg.sender)).div(
            10**this.decimals()
        );
        lastWithdraw[msg.sender] = block.number;

        uint256 fee = USDAmount.mul(percentFee).div(10**this.decimals());
        USDAmount -= fee;

        USDC.safeTransfer(this.owner(), fee);
        USDC.safeTransfer(msg.sender, USDAmount);
    }

    // % of penalty served
    function getWithdrawFee(address _address) public view returns (uint256) {
        if (block.number >= lastWithdraw[_address] + blockTimeout) {
            return 0;
        }

        uint256 fee = 1**this.decimals();
        uint256 penaltyCompletion = block.number - lastWithdraw[_address];
        penaltyCompletion = penaltyCompletion.mul(10**this.decimals()).div(
            blockTimeout
        );

        fee = fee.mul((10**this.decimals()).sub(penaltyCompletion));

        return fee;
    }

    function _beforeTokenTransfer(address from, address to) internal virtual {
        if (lastWithdraw[to] < lastWithdraw[from]) {
            lastWithdraw[to] = lastWithdraw[from];
        }
    }
}

