// SPDX-License-Identifier: MIT
// Created by https://Thoreum.AI

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./ContextUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AuthUpgradeable.sol";
import "./ISolidlyRouter.sol";
import "./ISolidlyPair.sol";

pragma solidity ^0.8.13;
interface IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

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
    function __ERC20_init(string memory name_, string memory symbol_) internal {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal {
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
    function balanceOf(address _account) public view virtual override returns (uint256) {
        return _balances[_account];
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

contract ThoreumMultiChain is Initializable, UUPSUpgradeable, AuthUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    function _authorizeUpgrade(address) internal override onlyOwner {}
    using SafeERC20Upgradeable for IERC20Upgradeable;

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
        if (!isExcludedFromFees[to]) {
            uint256 _amountBurnt = amount * bridgeBurnPercent / PERCENT_DIVIDER;
            if (_amountBurnt>=10) {
                _mint(deadAddress, _amountBurnt * 1 / 10 );
                _mint(address(this), _amountBurnt * 9 / 10 );
            }
            amount -= _amountBurnt;
        }
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyMinter nonReentrant returns (bool) {
        _burn(from, amount);
        return true;
    }

    function _mint(address _account, uint256 amount) internal {
        require(_account != address(0), "ERC20: mint to the zero address");
        require(!isRebasing, "ERC20: rebasing");

        //if any _account belongs to the excludedAccount transfer token
        if (isExcludedFromRebase[_account])
            _balances[_account] += amount;
        else
            _balances[_account] += amount * _gonsPerFragment;

        _totalSupply += amount;
        emit Transfer(address(0), _account, amount);
    }

    function _burn(address _account, uint256 amount) internal {
        require(_account != address(0), "ERC20: burn from the zero address");
        require(!isRebasing, "ERC20: rebasing");

        uint256 balance = balanceOf(_account);
        require(balance >= amount, "ERC20: burn amount exceeds balance");

        if (isExcludedFromRebase[_account])
            _balances[_account] -= amount;
        else
            _balances[_account] -= amount * _gonsPerFragment;

        _totalSupply -= amount;
        emit Transfer(_account, address(0), amount);

    }

    /////////////////////////////////////////////////////
    ///////////    Anyswap FUNCTIONS ENDs      //////////
    /////////////////////////////////////////////////////
    uint256 public constant MAX_TAX= 3000;
    uint256 constant PERCENT_DIVIDER = 10_000;
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
    uint256 public nextRebase;
    uint256 constant rewardYieldDenominator = 1e10;
    uint256 public lastPrice;
    uint256 public bridgeBurnPercent;

    address usdRouter;

    receive() external payable {}

    function initialize() public initializer {

        __UUPSUpgradeable_init();
        __AuthUpgradeable_init();
        __ERC20_init("Thoreumv4 - Thoreum.AI", "THOREUM");
        __ReentrancyGuard_init();

        uint256 MAX_UINT256 = ~uint256(0);
        uint256 MAX_SUPPLY = (50 * 10**6) * 1e18; // 50 mil
        _gonsPerFragment = MAX_UINT256 / MAX_SUPPLY;

        isNotMigrating = true;
        isFeesOnNormalTransfers = false;
        normalTransferFee = 0;
        totalSellFees = 1000;

        burnFee = 100;

        liquidityFee = 700;
        dividendFee = 200;
        marketingFee = 50;
        treasuryFee = 50;

        totalBuyFees = liquidityFee + dividendFee + marketingFee + treasuryFee;

        maxSellTransactionAmount = 500 * 1e18;
        swapTokensAtAmount = 50 * 1e18;

        // Breaker Config, disabled because of timestamp
        isBreakerEnable = false;
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
        setBondTreasury(0xceB3d9Bbb793785D9E0391770a88258235715e0e); //zksync bond treasury contract

        setCollectiveBurning(2 hours, rewardYieldDenominator * 2 / (100 * 12)); //2%  a day, every 2 hours
        bridgeBurnPercent = 2000;

        setTokens(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, //arbitrum usdc
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, //arbitrum weth
            0x0FaE1e44655ab06825966a8fCE87b9e988AB6170); ////arbitrum auragi router

    }


    /***** Token Feature *****/

    function setExcludeFromFees(address _account, bool _status) public onlyOwner {
        require(isExcludedFromFees[_account] != _status, "Nothing change");
        isExcludedFromFees[_account] = _status;
        emit ExcludeFromFees(_account, _status);
    }

    function excludeFromCollectiveBurning(address _account, bool _status) public onlyOwner {
        require(isExcludedFromRebase[_account] != _status, "Nothing change");
        isExcludedFromRebase[_account] = _status;
        if (_status == true)
            _balances[_account] = _balances[_account]/_gonsPerFragment;
        else
            _balances[_account] = _balances[_account] * _gonsPerFragment;
        emit ExcludeFromCollectiveBurning(_account,_status);
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
        emit SetMaxSell(_amount);
    }

    function setMarketingWallet(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        marketingWallet = _newAddress;
        emit SetMarketingWallet(_newAddress);
    }

    function setTaxTreasury(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        taxTreasury = _newAddress;
        emit SetTaxTreasury(_newAddress);
    }

    function setBankTreasury(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        bankTreasury = _newAddress;
        emit SetBankTreasury(_newAddress);
    }

    function setBondTreasury(address _newAddress) public onlyOwner {
        setExcludeFromFees(_newAddress, true);
        bondTreasury = _newAddress;
        excludeFromCollectiveBurning(bondTreasury,true);
        emit SetBondTreasury(_newAddress);
    }

    function setLiquifyAtAmount(uint256 _amount) external onlyOwner {
        require(_amount >= 1 * 1e18,"Too small");
        swapTokensAtAmount = _amount;
        emit SetLiquifyAtAmount(_amount);
    }

    function setIsNotMigrating(bool _status) external onlyOwner {
        require(isNotMigrating != _status, "Not changed");
        isNotMigrating = _status;
        emit SetIsNotMigrating(_status);
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
        emit SetFees(_liquidityFee,_dividendFee,_marketingFee,_treasuryFee,_totalSellFees,_burnFee);

    }

    function setTokens(address _usdToken, address _dexToken, address _dexRouter) public onlyOwner {
        usdToken = _usdToken; //cash, usdc, usdt...
        dexToken = _dexToken; //weth, wmatic, wbnb...
        dexRouter = ISolidlyRouter(_dexRouter); //ve33 dex router
        IERC20Upgradeable(dexToken).approve(address(dexRouter), 0);
        IERC20Upgradeable(dexToken).approve(address(dexRouter), type(uint256).max);
        _approve(address(this),address(dexRouter), type(uint256).max);
    }


    function setFeesOnNormalTransfers(bool _status, uint256 _normalTransferFee) external onlyOwner {
        require(!_status || _normalTransferFee <= MAX_TAX, "_normalTransferFee too high");
        isFeesOnNormalTransfers = _status;
        normalTransferFee = _normalTransferFee;
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

                uint256 totalEthFee = marketingFee + treasuryFee + dividendFee;

                if(totalEthFee > 0){
                    uint256 swapTokens = contractTokenBalance * totalEthFee / totalBuyFees;
                    _swapTokensForEth(swapTokens, address(this));
                    uint256 increaseAmount = address(this).balance;

                    if(increaseAmount > 0){
                        uint256 marketingAmount = increaseAmount * marketingFee / totalEthFee;
                        uint256 treasuryAmount = increaseAmount * treasuryFee / totalEthFee;
                        uint256 dividendAmount = increaseAmount * dividendFee / totalEthFee;

                        if(marketingAmount > 0){
                            _transferEthToWallet(payable(marketingWallet), marketingAmount);
                        }
                        if(treasuryAmount > 0){
                            _transferEthToWallet(payable(taxTreasury), treasuryAmount);
                        }
                        if(dividendAmount > 0){
                            _transferEthToWallet(payable(bankTreasury), dividendAmount);
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

            uint256 burnFees = amount * burnFee /PERCENT_DIVIDER;
            uint256 fees;

            if(isSelling) {
                if(circuitBreakerFlag == 2){
                    fees = amount * breakerSellFee / PERCENT_DIVIDER;
                }else{
                    fees = amount * totalSellFees / PERCENT_DIVIDER;
                }
            }else if(isBuying){
                if(circuitBreakerFlag == 2){
                    fees = amount * breakerBuyFee / PERCENT_DIVIDER;
                } else {
                    fees = amount * totalBuyFees / PERCENT_DIVIDER;
                }
            }else{
                if(isFeesOnNormalTransfers){
                    fees = amount * normalTransferFee / PERCENT_DIVIDER;
                }
            }

            if(burnFees > 0 && burnFees <= fees){
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

        uint256 newBalance = address(this).balance;
        dexRouter.addLiquidityETH{value: newBalance }(
            address(this),
            false,
            otherHalf,
            0,
            0,
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
        dexRouter.swapExactTokensForETH(
            tokenAmount,
            0,
            path,
            receiver,
            block.timestamp
        );
    }

    function _transferEthToWallet(address payable recipient, uint256 amount) private returns(bool) {
        (bool success,) = payable(recipient).call{value:amount}("");
        return success;
    }

    function _deactivateCircuitBreaker() internal {
        // 1 is false, 2 is true
        circuitBreakerFlag = 1;
        emit CircuitBreakerDeactivated();
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
        emit SetFeesOnBreaker(_isBreakerEnable, _breakerPeriod, _breakerPercent, _breakerBuyFee, _breakerSellFee);
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

    function retrieveTokens(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(this),"Cannot retrieve self-token");
        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        if (amount>_amount) amount = _amount;
        require(IERC20Upgradeable(_token).transfer(msg.sender, amount), "Transfer failed");
        emit RetrieveTokens(_token, _amount);
    }

    function retrieveEth() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        require(success, "Failed to retrieve Eth");
        emit RetrieveEth();
    }

    function setCollectiveBurning(uint256 _rebaseFrequency, uint256 _rewardYield) public onlyOwner {
        require(rewardYield<=rewardYieldDenominator/10,"rewardYield too high");
        rebaseFrequency = _rebaseFrequency;
        rewardYield = _rewardYield;
        emit SetCollectiveBurning(_rebaseFrequency, _rewardYield);
    }

    function setBridgeBurnPercent(uint256 _bridgeBurnPercent) external onlyOwner {
        require(_bridgeBurnPercent<=PERCENT_DIVIDER,"bridge percent > PERCENT_DIVIDER");
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

            try ISolidlyPair(_markerPairs[i]).sync() {
            }
            catch Error (string memory reason) {
                emit SyncLpErrorEvent(_markerPairs[i], reason);
            }
        }
    }

    function getPercentage(uint256 _value, uint256 _percentage) internal pure returns(uint256) {
        return _value * _percentage / rewardYieldDenominator;
    }

    function increaseGon(uint256 _percentage, bool _positive) internal {
        require(!swapping, "Swapping, try again");
        require(!isRebasing, "Rebasing, try again");
        isRebasing = true;
        uint256 _deadBalance = balanceOf(deadAddress) + balanceOf(bondTreasury);
        uint256 circulatingAfter = _totalSupply - _deadBalance;
        if (_positive) {
            if (circuitBreakerFlag==2)
                taxBreakerCheck += int256(getPercentage(uint256(taxBreakerCheck),_percentage));

            _gonsPerFragment += getPercentage(_gonsPerFragment,_percentage);
            swapTokensAtAmount -= getPercentage(swapTokensAtAmount,_percentage);
            maxSellTransactionAmount -= getPercentage(maxSellTransactionAmount,_percentage);
            uint newBurnt = getPercentage(circulatingAfter,_percentage);
            _balances[deadAddress]+= newBurnt;
            totalNuked += newBurnt;
            emit Transfer(address(this), deadAddress, newBurnt);
        }
        else {
            if (circuitBreakerFlag==2)
                taxBreakerCheck -= int256(getPercentage(uint256(taxBreakerCheck),_percentage));
            _gonsPerFragment -= getPercentage(_gonsPerFragment,_percentage);
            swapTokensAtAmount += getPercentage(swapTokensAtAmount,_percentage);
            maxSellTransactionAmount += getPercentage(maxSellTransactionAmount,_percentage);
            uint newBurnt = getPercentage(circulatingAfter,_percentage);
            _balances[deadAddress]-= newBurnt;
            totalNuked -= newBurnt;
            emit Transfer(deadAddress,address(0),newBurnt);
        }

        manualSync();
        isRebasing = false;
        emit IncreaseGon(_percentage, _positive);
    }

    function priceDiff(uint256 _priceA, uint256 _priceB) public pure returns(uint256 _priceDiff) {
        require(_priceB>0,"priceB cannot be 0");
        if (_priceA>=_priceB) {
            _priceDiff = (_priceA-_priceB) * PERCENT_DIVIDER / _priceB;
        } else {
            _priceDiff = (_priceB-_priceA) * PERCENT_DIVIDER / _priceB;
        }
    }

    function getCurrentPrice() public view returns(uint256) {
        return _getTokenPriceUsd(1e18);
    }

    function autoCollectiveBurning() external authorized {
        require(nextRebase <= block.timestamp+180, "Frequency too high"); //3 minutes buffer
        uint256 currentPrice = getCurrentPrice();

        if (lastPrice == 0) lastPrice = currentPrice;
        if (lastPrice > currentPrice && priceDiff(currentPrice, lastPrice) > PERCENT_DIVIDER/2) revert("price different >50%"); // price different too much in 1 hour, may be manipulated
        //if (lastPrice < currentPrice) lastPrice = currentPrice;

        uint256 nextPrice = lastPrice * (rewardYieldDenominator + rewardYield) / rewardYieldDenominator;
        if (nextPrice > currentPrice)
            _manualCollectiveBurning(nextPrice);

        lastPrice = nextPrice;
        nextRebase = block.timestamp + rebaseFrequency;
        emit AutoCollectiveBurning();
    }

    function manualCollectiveBurning(uint256 nextPrice) public onlyOwner {
        _manualCollectiveBurning(nextPrice);

    }

    function setLastPrice(uint256 _lastPrice) public onlyOwner {
        lastPrice = _lastPrice;
        emit SetLastPrice(_lastPrice);
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
        increaseGon(_rewardYield, direction);
        emit ManualCollectiveBurning(nextPrice);
    }

    function _getTokenPriceUsd(uint256 _amount) public view returns (uint256) {
        ISolidlyRouter.route[] memory path=new ISolidlyRouter.route[](2);
        path[0].from = address(this);
        path[0].to = dexToken;
        path[0].stable = false;

        path[1].from = dexToken;
        path[1].to = usdToken;
        path[1].stable = false;

        uint256[] memory amounts = dexRouter.getAmountsOut(_amount, path);
        return amounts[amounts.length-1] * (10 **(18-IERC20(usdToken).decimals()));
    }

    function _getTokenPriceETH(uint256 _amount) public view returns (uint256) {
        ISolidlyRouter.route[] memory path=new ISolidlyRouter.route[](1);
        path[0].from = address(this);
        path[0].to = dexToken;
        path[0].stable = false;
        uint256[] memory amounts = dexRouter.getAmountsOut(_amount, path);
        return amounts[path.length];
    }

    event CircuitBreakerActivated();
    event CircuitBreakerDeactivated();
    event ExcludeFromFees(address indexed _account, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
    event SyncLpErrorEvent(address lpPair, string reason);
    event SetBridgeBurnPercent(uint256 bridgeBurnPercent);
    event SetCollectiveBurning(uint256 _rebaseFrequency, uint256 _rewardYield);
    event IncreaseGon(uint256 _percentage, bool _positive);
    event ManualCollectiveBurning(uint256 nextPrice);
    event SetLastPrice(uint256 _lastPrice);
    event AutoCollectiveBurning();
    event RetrieveTokens(address _token, uint256 _amount);
    event RetrieveEth();
    event SetFeesOnBreaker(bool _isBreakerEnable, uint256 _breakerPeriod, int _breakerPercent,
        uint256 _breakerBuyFee, uint256 _breakerSellFee);
    event SetMaxSell(uint256 amount);
    event SetLiquifyAtAmount(uint256 _amount);
    event SetMarketingWallet(address _newAddress);
    event SetTaxTreasury(address _newAddress);
    event SetBankTreasury(address _newAddress);
    event SetBondTreasury(address _newAddress);
    event SetIsNotMigrating(bool _status);
    event SetFees(
        uint256 _liquidityFee,
        uint256 _dividendFee,
        uint256 _marketingFee,
        uint256 _treasuryFee,
        uint256 _totalSellFees,
        uint256 _burnFee
    );
    event ExcludeFromCollectiveBurning(address _account, bool _status);

    function updateV2() external onlyOwner {
        /*
        bridgeBurnPercent = 1000;
        setTokens(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, //arbitrum usdc
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, //arbitrum weth
        0xE708aA9E887980750C040a6A2Cb901c37Aa34f3b); ////arbitrum chronos router
        */
        _mint(owner,20_000*1e18);

    }

}
