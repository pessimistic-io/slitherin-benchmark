// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IERC20 } from "./IERC20.sol";
import { Ownable } from "./Ownable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { ISwapFactory } from "./ISwapFactory.sol";
import { Rebaser } from "./Rebaser.sol";

contract Erection is Ownable, IERC20 {

    struct DailyTransfer {
        uint256 startTime;
        uint256 endTime;
        uint256 periodTransfers;
    }

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    ISwapRouter public swapRouter;
    address public swapPair;
    address public immutable USDC;
    address public admin;

    bool public rebaseEnabled;
    bool public inRebase;    
    uint256 private quoteBase = 1 * 10**3;
    uint256 public targetPrice;
    uint256 public rebaseThreshold = 9900; // 99%
    uint256 public minRebasePercent = 10100; // 101%
    uint256 public rebaseAdjustFactor = 7000; // 70%
    uint256 public currentDate;
    uint256 public lastRebase;
    uint256 public currentPrice;
    uint256 public quoteTime;

    uint256 public constant DIVISOR = 10000;

    Rebaser public rebaser;

    mapping (address => bool) public isAddressWhitelistedIn;
    mapping (address => bool) public isAddressWhitelistedOut;
    mapping (address => bool) public isAddressBlacklistedIn;
    mapping (address => bool) public isAddressBlacklistedOut;
    mapping (address => bool) public isContractWhitelisted;

    bool public transferLimitEnabled = true;
    uint256 public dailyPercentLimit = 200; // 2%
    uint256 public dailyUSDLimit = 10000 * 10**18; // $10,000
    uint256 public transferLimit = 100000 * 10**18;

    mapping (address => DailyTransfer) public dailyTransfers;

    event Rebased(
        uint256 rebasedFromPrice, 
        uint256 rebasedToPrice, 
        uint256 usdcSwapped, 
        uint256 usdcAdded, 
        uint256 erectionBurned, 
        uint256 rebasedTimestamp
    );
    event UpdatedTarget(uint256 targetPrice, uint256 dailyUSDLimit, uint256 transferLimit, uint256 currentDate);
    event AdminUpdated(address newAdmin);
    event AdminRenounced();

    constructor (
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        uint8 decimals_,
        uint256 _startDate,
        address _teamAddress,
        address _usdc,
        address _router
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _mint(_msgSender(), (totalSupply_ * 10**_decimals));

        currentDate = _startDate;

        USDC = _usdc;

        admin = msg.sender;

        swapRouter = ISwapRouter(_router);
        swapPair = ISwapFactory(swapRouter.factory())
        .createPair(address(this), USDC);

        rebaser = new Rebaser(_router, _usdc, msg.sender, _teamAddress, swapPair);

        rebaser.setTeamAddress(_teamAddress);
        rebaser.setSwapPair(swapPair);

        isContractWhitelisted[swapPair] = true;
        isContractWhitelisted[address(swapRouter)] = true;
        isContractWhitelisted[address(this)] = true;
        isContractWhitelisted[address(rebaser)] = true;

        isAddressWhitelistedOut[swapPair] = true;
        isAddressWhitelistedOut[address(swapRouter)] = true;
        isAddressWhitelistedOut[address(this)] = true;
        isAddressWhitelistedOut[address(rebaser)] = true;
        isAddressWhitelistedOut[msg.sender] = true;
    }

    function setRebaseEnabled(bool flag) external {
        require(msg.sender == admin, "Caller not allowed");
        rebaseEnabled = flag;
        rebaser.setRebaseEnabled(flag);
    }

    function setRebaseThreshold(uint256 _percent) external {
        require(msg.sender == admin, "Caller not allowed");
        rebaseThreshold = DIVISOR - _percent;
    }

    function setMinRebasePercent(uint256 _percent) external {
        require(msg.sender == admin, "Caller not allowed");
        minRebasePercent = _percent + DIVISOR;
    }

    function setRebaseAdjustFactor(uint256 _percent) external {
        require(msg.sender == admin, "Caller not allowed");
        rebaseAdjustFactor = DIVISOR - _percent;
    }

    function setTransferLimitEnabled(bool flag) external {
        require(msg.sender == admin, "Caller not allowed");
        transferLimitEnabled = flag;
    }
    
    function setTransferLimit(uint256 _amount) external {
        require(msg.sender == admin, "Caller not allowed");
        transferLimit = _amount;
    }

    function setDailyPercentLimit(uint256 _percent) external {
        require(msg.sender == admin, "Caller not allowed");
        dailyPercentLimit = _percent;
    }

    /// Functions to whitelist selected wallets
    function setWhitelistWalletOut(address wallet, bool flag) external {
        require(msg.sender == admin, "Caller not allowed");
        isAddressWhitelistedOut[wallet] = flag;
    }
    function setWhitelistWalletIn(address wallet, bool flag) external {
        require(msg.sender == admin, "Caller not allowed");
        isAddressWhitelistedIn[wallet] = flag;
    }
    function setContractWhitelisted(address contr, bool flag) external {
        require(msg.sender == admin, "Caller not allowed");
        isContractWhitelisted[contr] = flag;
    }

    /// Function to blacklist and restrict buys to selected wallets
    function setBlacklistIn(address wallet, bool flag) external {
        require(msg.sender == admin, "Caller not allowed");
        isAddressBlacklistedIn[wallet] = flag;
    }
    function setBlacklistOut(address wallet, bool flag) external {
        require(msg.sender == admin, "Caller not allowed");
        isAddressBlacklistedOut[wallet] = flag;
    }

    function changeAdmin(address _newAdmin) external {
        require(msg.sender == admin, "Caller not allowed");
        admin = _newAdmin;
        emit AdminUpdated(_newAdmin);
    }

    function renounceAdminRole() external {
        require(msg.sender == admin, "Caller not allowed");
        admin = address(0);
        emit AdminRenounced();
    }

    function transfer(address recipient, uint256 amount) external virtual override returns (bool) {
        require(
            !isAddressBlacklistedOut[msg.sender] && 
            !isAddressBlacklistedIn[recipient], 
            "Erection: recip is blacklisted"
        );
        if(!transferLimitEnabled || isAddressWhitelistedOut[msg.sender]) {
            _transfer(_msgSender(), recipient, amount);

            return true;

        } else if(dailyTransfers[msg.sender].endTime < block.timestamp) {
            require(amount <= transferLimit, "Erection: exceeds daily limit");
            dailyTransfers[msg.sender].startTime = block.timestamp;
            dailyTransfers[msg.sender].endTime = block.timestamp + 1 days;
            dailyTransfers[msg.sender].periodTransfers = amount;

            _transfer(_msgSender(), recipient, amount);

            return true;

        } else {
            require(
                dailyTransfers[msg.sender].periodTransfers + amount <= transferLimit, 
                "Erection: exceeds daily limit"
            );

            dailyTransfers[msg.sender].periodTransfers = dailyTransfers[msg.sender].periodTransfers + amount;

            _transfer(_msgSender(), recipient, amount);

            return true; 
        }
    }

    function transferFrom(address sender, address recipient, uint256 amount) external virtual override returns (bool) {
        require(
            !isAddressBlacklistedOut[sender] && 
            !isAddressBlacklistedIn[recipient], 
            "Erection: recip is blacklisted"
        );
        if(!transferLimitEnabled || isAddressWhitelistedOut[sender] || isAddressWhitelistedIn[recipient]) {
            _transfer(sender, recipient, amount);

            _approve(
                sender, 
                _msgSender(), 
                _allowances[sender][_msgSender()] - amount
            );
            return true;

        } else if(dailyTransfers[sender].endTime < block.timestamp) {
            require(amount <= transferLimit, "Erection: exceeds daily limit");

            dailyTransfers[sender].startTime = block.timestamp;
            dailyTransfers[sender].endTime = block.timestamp + 1 days;
            dailyTransfers[sender].periodTransfers = amount;

            _transfer(sender, recipient, amount);

            _approve(
                sender, 
                _msgSender(), 
                _allowances[sender][_msgSender()] - amount
            );
            return true;

        } else {
            require(
                dailyTransfers[sender].periodTransfers + amount <= transferLimit, 
                "Erection: exceeds daily limit"
            );

            dailyTransfers[sender].periodTransfers = dailyTransfers[sender].periodTransfers + amount;

            _transfer(sender, recipient, amount);

            _approve(
                sender, 
                _msgSender(), 
                _allowances[sender][_msgSender()] - amount
            );
            return true;
        }
    }

    // Remove bnb that is sent here by mistake
    function removeBNB(uint256 amount, address to) external onlyOwner{
        payable(to).transfer(amount);
      }

    // Remove tokens that are sent here by mistake
    function removeToken(IERC20 token, uint256 amount, address to) external onlyOwner {
        if( token.balanceOf(address(this)) < amount ) {
            amount = token.balanceOf(address(this));
        }
        token.transfer(to, amount);
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            _msgSender(), 
            spender, 
            _allowances[_msgSender()][spender] - subtractedValue
        );
        return true;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply + amount;
        _balances[account] = _balances[account] + amount;
        emit Transfer(address(0), account, amount);
    }


    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve the zero address");
        require(spender != address(0), "ERC20: approve the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: from the zero address");
        require(recipient != address(0), "ERC20: to the zero address");
        require(!_isContract(sender) && !_isContract(recipient), "Erection: no contracts");
        require(
            isContractWhitelisted[sender] || 
            isContractWhitelisted[recipient] || 
            sender == tx.origin || 
            recipient == tx.origin, 
            "Erection: no proxy contract"
        );           

        if(rebaseEnabled) { 
            currentPrice = (quoteBase * 10**30) / getQuote(); 
        
            if(!inRebase) {
                if(block.timestamp > currentDate + 1 days) {
                    currentDate = currentDate + 1 days;
                    if(currentPrice * rebaseAdjustFactor / DIVISOR >= targetPrice * minRebasePercent / DIVISOR) {
                        targetPrice = (currentPrice * rebaseAdjustFactor) / DIVISOR;
                    } else {
                        targetPrice = (targetPrice * minRebasePercent) / DIVISOR;
                    }
                    dailyUSDLimit = (IERC20(USDC).balanceOf(swapPair) * dailyPercentLimit) / DIVISOR;
                    transferLimit = (dailyUSDLimit * 10**36) / currentPrice;

                    emit UpdatedTarget(targetPrice, dailyUSDLimit, transferLimit, currentDate);
                } else if((currentPrice * rebaseAdjustFactor) / DIVISOR > targetPrice) {
                    targetPrice = (currentPrice * rebaseAdjustFactor) / DIVISOR;
                    dailyUSDLimit = (IERC20(USDC).balanceOf(swapPair) * dailyPercentLimit) / DIVISOR;
                    transferLimit = (dailyUSDLimit * 10**36) / currentPrice;

                    emit UpdatedTarget(targetPrice, dailyUSDLimit, transferLimit, currentDate);
                }
        
                if(currentPrice <= (targetPrice * rebaseThreshold) / DIVISOR && recipient == swapPair) {
                    inRebase = true;
                    lastRebase = block.timestamp;
                    uint256 prePrice = currentPrice;
                    (uint256 swapAmount, uint256 addAmount, uint256 burnAmount) = 
                        rebaser.rebase(currentPrice, targetPrice);
                    currentPrice = (quoteBase * 10**30) / getQuote();
                    emit Rebased(prePrice, currentPrice, swapAmount, addAmount, burnAmount, block.timestamp);
                }
            }
        }

        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);

        inRebase = false;  
    }

    function getQuote() internal view returns (uint256) {
        address[] memory quotePath = new address[](2);
            quotePath[0] = USDC;
            quotePath[1] = address(this);                    

        uint256[] memory fetchedQuote = swapRouter.getAmountsOut(quoteBase, quotePath);

        return fetchedQuote[1];
    } 

    function _isContract(address _addr) internal view returns (bool) {
        if (isContractWhitelisted[_addr]){
            return false;
        } else {
            uint256 size;
            assembly {
                size := extcodesize(_addr)
            }
            return size > 0;
        }
    }
}
