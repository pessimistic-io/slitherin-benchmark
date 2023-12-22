// SPDX-License-Identifier: MIT
// A produce of https://Thoreum.Capital

import "./IERC20Upgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./ContextUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";
import "./AuthUpgradeable.sol";
import "./IUniswap.sol";
import "./ISolidlyRouter.sol";

pragma solidity ^0.8.13;

contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 internal _totalSupply;
    string internal _name;
    string internal _symbol;


    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        //not used anymore
    }


    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
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

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
    unchecked {
        _approve(owner, spender, currentAllowance - subtractedValue);
    }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
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

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
        unchecked {
            _approve(owner, spender, currentAllowance - amount);
        }
        }
    }
}

contract ThoreumAnyChain is Initializable, UUPSUpgradeable, AuthUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /////////////////////////////////////////////////////
    ///////////    Anyswap FUNCTIONS           //////////
    /////////////////////////////////////////////////////

    address public constant underlying = address(0);
    mapping(address => bool) public isMinter;

    modifier onlyMinter() {
        require(isMinter[_msgSender()],"AnyswapV6ERC20: only Minter"); _;
    }

    function setMinter(address _auth) public onlyOwner {
        require(_auth != address(0), "AnyswapV6ERC20: address(0)");
        isMinter[_auth] = true;
    }

    function revokeMinter(address _auth) public onlyOwner {
        isMinter[_auth] = false;
    }

    function mint(address to, uint256 amount) external onlyMinter nonReentrant returns (bool) {
        uint256 amountBurnt = amount * bridgeBurnPercent / PERCENT_DIVIER;
        if (amountBurnt>5) {
            _mint(deadAddress, amountBurnt * 1 / 5 );
            _mint(address(this), amountBurnt * 4 / 5 );
        }

        amount -= amountBurnt;
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyMinter nonReentrant returns (bool) {
        _burn(from, amount);
        return true;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        require(!isRebasing, "ERC20: rebasing");

        //if any account belongs to the excludedAccount transfer token
        if (isExcludedFromRebase[account])
            _balances[account] += amount;
        else
            _balances[account] += amount * _gonsPerFragment;

        _totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        require(!isRebasing, "ERC20: rebasing");

        uint256 balance = balanceOf(account);
        require(balance >= amount, "ERC20: burn amount exceeds balance");

        if (isExcludedFromRebase[account])
            _balances[account] -= amount;
        else
            _balances[account] -= amount * _gonsPerFragment;

        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);

    }

    /////////////////////////////////////////////////////
    ///////////    Anyswap FUNCTIONS ENDs      //////////
    /////////////////////////////////////////////////////
    uint256 public constant MAX_TAX= 3000;
    uint256 constant PERCENT_DIVIER = 10_000;
    bool private swapping;

    mapping (address => bool) private isExcludedFromFees;
    mapping (address => bool) public automatedMarketMakerPairs;
    address[] private _markerPairs;

    ISolidlyRouter public dexRouter;


    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;

    address public usdToken;
    address public dexToken;
    address public marketingWallet;
    address public taxTreasury;
    address public bondTreasury;
    address public bankTreasury;

    bool public isNotMigrating;
    bool public isFeesOnNormalTransfers;
    uint256 public normalTransferFee;
    uint256 public totalSellFees;
    uint256 public liquidityFee;
    uint256 public dividendFee;
    uint256 public marketingFee;
    uint256 public treasuryFee;
    uint256 public totalBuyFees;
    uint256 public totalNuked;
    uint256 public burnFee;

    uint256 public maxSellTransactionAmount;
    uint256 public swapTokensAtAmount;

    /** Breaker Config **/
    bool public isBreakerEnable;
    int taxBreakerCheck;
    uint256 public breakerPeriod; // 1 hour
    int public breakerPercent; // activate at 0.5%
    uint256 public breakerBuyFee;  // buy fee 1%
    uint256 public breakerSellFee; // sell fee 30%
    uint public circuitBreakerFlag;
    uint public circuitBreakerTime;
    uint timeBreakerCheck;

    mapping (address => bool) public isExcludedFromRebase;

    uint256 private _gonsPerFragment; // to do: change to priavte in official contract

    bool private isRebasing;

    uint256 public rewardYield;
    uint256 private rebaseFrequency;
    uint256 private nextRebase;
    uint256 constant rewardYieldDenominator = 1e10;
    uint256 public lastPrice;
    uint256 public bridgeBurnPercent;

    address usdRouter;

    receive() external payable {}

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AuthUpgradeable_init();
        __ERC20_init("Thoreumv4 - Thoreum.AI", "THOREUM");

        uint256 MAX_UINT256 = ~uint256(0);
        uint256 MAX_SUPPLY = (50 * 10**6) * 1e18; // 50 mil
        _gonsPerFragment = MAX_UINT256 / MAX_SUPPLY;

        isNotMigrating = true;
        isFeesOnNormalTransfers = true;
        normalTransferFee = 500;
        totalSellFees = 500;

        burnFee = 100;

        liquidityFee = 70;
        dividendFee = 20;
        marketingFee = 5;
        treasuryFee = 5;

        totalBuyFees = liquidityFee + dividendFee + marketingFee + treasuryFee;

        maxSellTransactionAmount = 1000 * 1e18;
        swapTokensAtAmount = 50 * 1e18;

        // Breaker Config
        isBreakerEnable = true;
        breakerPeriod = 3600; // 1 hour
        breakerPercent = 50; // activate at 0.5%
        breakerBuyFee = 50;  // buy fee 0.5%
        breakerSellFee = 3000; // sell fee 30%

        setExcludeFromFees(address(this), true);
        setExcludeFromFees(owner, true);
        setExcludeFromFees(deadAddress,true);
        excludeFromCollectiveBurning(deadAddress,true);

        setMarketingWallet(0x8Ad9CB111d886dBAbBbf232c9A1339B13cB168F8);
        setTaxTreasury(0xeA8BDB211241549CD48A23B18c97f71CB3e22fd7);
        setBankTreasury(0x312874C97CdD918Fa45cd3A3625E012037850EBE);
        setBondTreasury(0x44E92a6379477535c976DfaB88F99706bD4425e2);

        setCollectiveBurning(1 hours, rewardYieldDenominator * 2 / (100 * 24)); //2%  a day, every hour
        bridgeBurnPercent = 500;

    }


    /***** Token Feature *****/

    function setExcludeFromFees(address account, bool _status) public onlyOwner {
        require(isExcludedFromFees[account] != _status, "Nothing change");
        isExcludedFromFees[account] = _status;
        emit ExcludeFromFees(account, _status);
    }

    function excludeFromCollectiveBurning(address account, bool _status) public onlyOwner {
        require(isExcludedFromRebase[account] != _status, "Nothing change");
        isExcludedFromRebase[account] = _status;
        if (_status == true)
            _balances[account] = _balances[account]/_gonsPerFragment;
        else
            _balances[account] = _balances[account] * _gonsPerFragment;
    }

    function checkIsExcludedFromFees(address _account) external view returns (bool) {
        return(isExcludedFromFees[_account]);
    }

    function setAutomatedMarketMakerPair(address _dexPair, bool _status) public onlyOwner {
        require(automatedMarketMakerPairs[_dexPair] != _status,"no change");
        automatedMarketMakerPairs[_dexPair] = _status;

        if(_status){
            _markerPairs.push(_dexPair);
        }else{
            for (uint256 i = 0; i < _markerPairs.length; i++) {
                if (_markerPairs[i] == _dexPair) {
                    _markerPairs[i] = _markerPairs[_markerPairs.length - 1];
                    _markerPairs.pop();
                    break;
                }
            }
        }

        emit SetAutomatedMarketMakerPair(_dexPair, _status);
    }

    function setMaxSell(uint256 _amount) external onlyOwner {
        require(_amount >= 1 * 1e18,"Too small");
        maxSellTransactionAmount = _amount;
    }

    function setMarketingWallet(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        marketingWallet = _newAddress;
    }

    function setTaxTreasury(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        taxTreasury = _newAddress;
    }

    function setBankTreasury(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        bankTreasury = _newAddress;
    }

    function setBondTreasury(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        bondTreasury = _newAddress;
        excludeFromCollectiveBurning(bondTreasury,true);
    }

    function setSwapTokensAtAmount(uint256 _amount) external onlyOwner {
        swapTokensAtAmount = _amount;
    }

    function setIsNotMigrating(bool _status) external onlyOwner {
        require(isNotMigrating != _status, "Not changed");
        isNotMigrating = _status;
    }

    function setFees(
        uint256 _liquidityFee,
        uint256 _dividendFee,
        uint256 _marketingFee,
        uint256 _treasuryFee,
        uint256 _totalSellFees,
        uint256 _burnFee
    ) public onlyOwner {
        uint256 _totalBuyFees = _liquidityFee + _dividendFee + _marketingFee + _treasuryFee;

        require(_totalBuyFees <= MAX_TAX, "Buy fee too high");
        require(_totalSellFees <= MAX_TAX, "Sell fee too high");
        require(_burnFee <= MAX_TAX, "burn fee too high");

        liquidityFee = _liquidityFee;
        dividendFee = _dividendFee;
        marketingFee = _marketingFee;
        treasuryFee = _treasuryFee;

        burnFee = _burnFee;

        totalBuyFees = _totalBuyFees;
        totalSellFees = _totalSellFees;
    }

    function setTokens(address _usdToken, address _dexToken, address _usdRouter, address _dexRouter) external onlyOwner {
        usdToken = _usdToken; //usdc
        dexToken = _dexToken; //weth
        usdRouter = _usdRouter; //uniswap router
        dexRouter = ISolidlyRouter(_dexRouter); //ve33 dex
        IERC20Upgradeable(dexToken).approve(address(dexRouter), type(uint256).max);
        _approve(address(this),address(dexRouter), type(uint256).max);
    }


    function setFeesOnNormalTransfers(bool _status, uint256 _normalTransferFee) external onlyOwner {
        require(!_status || _normalTransferFee <= MAX_TAX, "_normalTransferFee too high");
        isFeesOnNormalTransfers = _status;
        normalTransferFee = _normalTransferFee;
    }

    function set_USD_TOKEN(address _usdToken) external onlyOwner {
        usdToken = _usdToken;
    }

    function _transfer(address from, address to, uint256 amount) internal override {

        require(!isRebasing,"no transfer while rebasing");
        require(isNotMigrating || tx.origin==owner, "Trading not started");
        require((from != address(0)) && (to != address(0)), "zero address");

        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];
        bool isSelling = automatedMarketMakerPairs[to];
        bool isBuying = automatedMarketMakerPairs[from];
        if (isSelling && !excludedAccount) {
            require(amount <= maxSellTransactionAmount, "Sell amount too big");
        }

        if (!isBuying && !excludedAccount && !swapping) {

            uint256 contractTokenBalance = balanceOf(address(this));

            if (contractTokenBalance >= swapTokensAtAmount) {
                swapping = true;

                uint256 totalBnbFee = marketingFee + treasuryFee + dividendFee;

                if(totalBnbFee > 0){
                    uint256 swapTokens = contractTokenBalance * totalBnbFee / totalBuyFees;
                    _swapTokensForEth(swapTokens, address(this));
                    uint256 increaseAmount = IERC20Upgradeable(dexToken).balanceOf(address(this));

                    if(increaseAmount > 0){
                        uint256 marketingAmount = increaseAmount * marketingFee / totalBnbFee;
                        uint256 treasuryAmount = increaseAmount * treasuryFee / totalBnbFee;
                        uint256 dividendAmount = increaseAmount * dividendFee / totalBnbFee;

                        if(marketingAmount > 0){
                            IERC20Upgradeable(dexToken).transfer(marketingWallet, marketingAmount);
                            //_transferBNBToWallet(payable(marketingWallet), marketingAmount);
                        }
                        if(treasuryAmount > 0){
                            IERC20Upgradeable(dexToken).transfer(taxTreasury, treasuryAmount);
                            //_transferBNBToWallet(payable(taxTreasury), treasuryAmount);
                        }
                        if(dividendAmount > 0){
                            IERC20Upgradeable(dexToken).transfer(bankTreasury, dividendAmount);
                            //_transferBNBToWallet(payable(bankTreasury), dividendAmount);
                        }

                    }
                }

                if(liquidityFee > 0){
                    _swapAndLiquify(contractTokenBalance * liquidityFee / totalBuyFees,address(bankTreasury));
                }

                swapping = false;
            }

        }

        if(isBreakerEnable && (isSelling || isBuying)){
            _accuTaxSystem(amount);
        }

        if(!excludedAccount) {

            uint256 burnFees = amount * burnFee /PERCENT_DIVIER;
            uint256 fees;

            if(isSelling) {
                if(circuitBreakerFlag == 2){
                    fees = amount * breakerSellFee / PERCENT_DIVIER;
                }else{
                    fees = amount * totalSellFees / PERCENT_DIVIER;
                }
            }else if(isBuying){
                if(circuitBreakerFlag == 2){
                    fees = amount * breakerBuyFee / PERCENT_DIVIER;
                } else {
                    fees = amount * totalBuyFees / PERCENT_DIVIER;
                }
            }else{
                if(isFeesOnNormalTransfers){
                    fees = amount * normalTransferFee / PERCENT_DIVIER;
                }
            }

            if(burnFees > 0){
                amount -= burnFees;
                basicTransfer(from, deadAddress, burnFees);
            }

            if(fees > burnFees){
                fees -= burnFees;
                amount -= fees;
                basicTransfer(from, address(this), fees);
            }
        }

        basicTransfer(from, to, amount);
    }
    function _swapAndLiquify(uint256 contractTokenBalance, address liquidityReceiver) private {
        uint256 half = contractTokenBalance / 2;
        uint256 otherHalf = contractTokenBalance - half;

        _swapTokensForEth(half, address(this));
        uint256 newBalance = IERC20Upgradeable(dexToken).balanceOf(address(this));

        dexRouter.addLiquidity(
            address(this),
            dexToken,
            false,
            otherHalf,
            newBalance,
            1,
            1,
            liquidityReceiver,
            block.timestamp
        );
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }
    function _swapTokensForEth(uint256 tokenAmount, address receiver) private {

        ISolidlyRouter.route[] memory path=new ISolidlyRouter.route[](1);
        path[0].from = address(this);
        path[0].to = dexToken;
        path[0].stable = false;

        dexRouter.swapExactTokensForTokens(
            tokenAmount,
            0,
            path,
            receiver,
            block.timestamp
        );
    }
    /*
    function _transferBNBToWallet(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }*/

    function _deactivateCircuitBreaker() internal {
        // 1 is false, 2 is true
        circuitBreakerFlag = 1;
    }

    function _activateCircuitBreaker() internal {
        // 1 is false, 2 is true
        circuitBreakerFlag = 2;
        circuitBreakerTime = block.timestamp;
        emit CircuitBreakerActivated();
    }

    function setFeesOnBreaker(bool _isBreakerEnable, uint256 _breakerPeriod, int _breakerPercent,
        uint256 _breakerBuyFee, uint256 _breakerSellFee) external onlyOwner {
        require(_breakerBuyFee <= MAX_TAX, "Buy fee too high");
        require(_breakerSellFee <= MAX_TAX, "Sell fee too high");

        isBreakerEnable = _isBreakerEnable;
        //reset flag if isBreakerEnable disabled
        if (!isBreakerEnable) {
            _deactivateCircuitBreaker();
        }
        breakerPeriod = _breakerPeriod;
        breakerPercent = _breakerPercent;

        breakerBuyFee = _breakerBuyFee;
        breakerSellFee = _breakerSellFee;
    }

    function _accuTaxSystem(uint256 amount) internal {

        if (circuitBreakerFlag == 2) {
            if (circuitBreakerTime + breakerPeriod < block.timestamp) {
                _deactivateCircuitBreaker();
            }
        }

        if (taxBreakerCheck==0) taxBreakerCheck = int256(_getTokenPriceETH(1e18));
        uint256 _currentPriceInEth = _getTokenPriceETH(amount) * 1e18 / amount;

        uint256 priceChange = priceDiff(_currentPriceInEth, uint256(taxBreakerCheck));
        if (_currentPriceInEth < uint256(taxBreakerCheck) && priceChange > uint256(breakerPercent) ) {
            _activateCircuitBreaker();
        }

        if (block.timestamp - timeBreakerCheck >= breakerPeriod) {
            taxBreakerCheck = int256(_getTokenPriceETH(1e18));
            timeBreakerCheck = block.timestamp;
        }
    }
    /*
        function retrieveTokens(address _token) external onlyOwner {
            require(_token != address(this),"Cannot retrieve self-token");
            uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));

            require(IERC20Upgradeable(_token).transfer(msg.sender, amount), "Transfer failed");
        }

        function retrieveBNB() external onlyOwner {
            uint256 amount = address(this).balance;

            (bool success,) = payable(msg.sender).call{ value: amount }("");
            require(success, "Failed to retrieve BNB");
        }
    */
    event CircuitBreakerActivated();
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 bnbReceived, uint256 tokensIntoLiqudity);
    event SyncLpErrorEvent(address lpPair, string reason);
    event SetBridgeBurnPercent(uint256 bridgeBurnPercent);

    function setCollectiveBurning(uint256 _rebaseFrequency, uint256 _rewardYield) public onlyOwner {
        rebaseFrequency = _rebaseFrequency;
        rewardYield = _rewardYield;
    }

    function setBridgeBurnPercent(uint256 _bridgeBurnPercent) external onlyOwner {
        require(_bridgeBurnPercent<=normalTransferFee,"bridge percent > normalTransferFee");
        bridgeBurnPercent = _bridgeBurnPercent;
        emit SetBridgeBurnPercent(bridgeBurnPercent);
    }

    function balanceOf(address who) public view override returns (uint256) {
        return (!isExcludedFromRebase[who]) ? _balances[who] / _gonsPerFragment : _balances[who];
    }

    function basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {

        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!isRebasing, "rebasing, cannot transfer");
        emit Transfer(from, to, amount);

        if (from == to || amount==0) return true;
        uint256 gonAmount = amount * _gonsPerFragment;

        if (isExcludedFromRebase[from]) {
            require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
            _balances[from] -= amount;
        }
        else {
            require(_balances[from] >= gonAmount, "ERC20: transfer amount exceeds balance");
            _balances[from] -= gonAmount;
        }
        // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
        // decrementing then incrementing.
        if (isExcludedFromRebase[to])
            _balances[to] += amount;
        else
            _balances[to] += gonAmount;

        return(true);
    }

    function manualSync() public {
        for(uint i = 0; i < _markerPairs.length; i++){

            try IUniswapV2Pair(_markerPairs[i]).sync() {
            }
            catch Error (string memory reason) {
                emit SyncLpErrorEvent(_markerPairs[i], reason);
            }
        }
    }

    function getPercentage(uint256 _value, uint256 _percentage) internal pure returns(uint256) {
        return _value * _percentage / rewardYieldDenominator;
    }

    function increase_gon(uint256 _percentage, bool positive) internal {
        require(!swapping, "Swapping, try again");
        require(!isRebasing, "Rebasing, try again");
        isRebasing = true;
        uint256 _deadBalance = balanceOf(deadAddress) + balanceOf(bondTreasury);
        uint256 circulatingAfter = _totalSupply - _deadBalance;
        if (positive) {
            if (circuitBreakerFlag==2)
                taxBreakerCheck += int256(getPercentage(uint256(taxBreakerCheck),_percentage));

            _gonsPerFragment += getPercentage(_gonsPerFragment,_percentage);
            swapTokensAtAmount -= getPercentage(swapTokensAtAmount,_percentage);
            maxSellTransactionAmount -= getPercentage(maxSellTransactionAmount,_percentage);
            _balances[deadAddress]+= getPercentage(circulatingAfter,_percentage);
            totalNuked += getPercentage(circulatingAfter,_percentage);
        }
        else {
            if (circuitBreakerFlag==2)
                taxBreakerCheck -= int256(getPercentage(uint256(taxBreakerCheck),_percentage));
            _gonsPerFragment -= getPercentage(_gonsPerFragment,_percentage);
            swapTokensAtAmount += getPercentage(swapTokensAtAmount,_percentage);
            maxSellTransactionAmount += getPercentage(maxSellTransactionAmount,_percentage);
            _balances[deadAddress]-= getPercentage(circulatingAfter,_percentage);
            totalNuked -= getPercentage(circulatingAfter,_percentage);
        }

        manualSync();
        isRebasing = false;
    }

    function priceDiff(uint256 priceA, uint256 priceB) public pure returns(uint256 _priceDiff) {
        if (priceB==0) revert("priceB is 0");
        _priceDiff = (Math.max(priceA,priceB) - Math.min(priceA,priceB)) * PERCENT_DIVIER / priceB;
    }

    function getCurrentPrice() public view returns(uint256 currentPrice) {
        currentPrice = _getTokenPriceUsd(1e18);
    }

    function autoCollectiveBurning() external authorized {
        require(nextRebase <= block.timestamp+180, "Frequency too high"); //3 minutes buffer
        uint256 currentPrice = getCurrentPrice();

        if (lastPrice == 0) lastPrice = currentPrice;
        if (lastPrice > currentPrice && priceDiff(currentPrice, lastPrice) > PERCENT_DIVIER/2) revert("price different >50%"); // price different too much in 1 hour, may be manipulated
        //if (lastPrice < currentPrice) lastPrice = currentPrice;

        uint256 nextPrice = lastPrice * (rewardYieldDenominator + rewardYield) / rewardYieldDenominator;
        if (nextPrice > currentPrice)
            _manualCollectiveBurning(nextPrice);

        lastPrice = nextPrice;
        nextRebase = block.timestamp + rebaseFrequency;
    }

    function manualCollectiveBurning(uint256 nextPrice) public onlyOwner {
        _manualCollectiveBurning(nextPrice);
    }

    function SET_LAST_PRICE(uint256 _lastPrice) public onlyOwner {
        lastPrice = _lastPrice;
    }

    function _manualCollectiveBurning(uint256 nextPrice) internal {
        require(nextPrice>0,"price invalid");
        uint256 currentPrice = getCurrentPrice();
        uint256 _rewardYield;
        bool direction;
        if (currentPrice < nextPrice) {
            _rewardYield = (nextPrice - currentPrice) * rewardYieldDenominator / currentPrice;
            direction = true; // pump price -> increase gon
        } else {
            _rewardYield = (currentPrice - nextPrice) * rewardYieldDenominator / currentPrice;
            direction = false; // dump price -> decrease gon
        }
        require(_rewardYield < rewardYieldDenominator,"price increase too much");
        increase_gon(_rewardYield, direction);
    }

    function _getTokenPriceUsd(uint256 _amount) public view returns (uint256) {
        ISolidlyRouter.route[] memory path=new ISolidlyRouter.route[](1);
        path[0].from = address(this);
        path[0].to = dexToken;
        path[0].stable = false;
        uint256[] memory amounts = dexRouter.getAmountsOut(_amount, path);
        uint256 _dexTokenAmount = amounts[amounts.length-1];

        address[] memory pathPrice = new address[](2);
        pathPrice[0] = dexToken;
        pathPrice[1] = usdToken;

        IUniswapV2Router priceRouter = IUniswapV2Router(usdRouter);
        uint256[] memory amountsPrice = priceRouter.getAmountsOut(_dexTokenAmount, pathPrice);
        return amountsPrice[amountsPrice.length - 1];
    }

    function _getTokenPriceETH(uint256 _amount) public view returns (uint256) {
        ISolidlyRouter.route[] memory path=new ISolidlyRouter.route[](1);
        path[0].from = address(this);
        path[0].to = dexToken;
        path[0].stable = false;
        uint256[] memory amounts = dexRouter.getAmountsOut(_amount, path);
        return amounts[path.length];
    }

    function updateV2() external onlyOwner {
    }

}
