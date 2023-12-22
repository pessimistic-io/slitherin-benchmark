// SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.17;

import "./Ownable.sol";
import "./ERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

/// @title Base Jumper
contract BaseJumper is ERC20, Ownable {

    bool internal _inSwap = false;

    uint private constant MAX_UINT256 = ~uint(0);
    uint private constant INITIAL_FRAGMENTS_SUPPLY = 420_069_000 ether;
    uint private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint private constant MAX_SUPPLY = ~uint128(0);
    /// @dev REBASE_BUFFER is not set to 24 hours so that oracle can call it on the dot
    uint private constant REBASE_BUFFER = 23.5 hours;
    uint private constant MAX_TOTAL_TAX_RATE = 100;
    uint private constant TAX_RATE_DENOMINATOR = 1000;
    uint private constant MIN_SWAP_THRESHOLD_DENOMINATOR = 10000;
    uint private constant LP_TAX_LOCK_UP_PERIOD = 180 days;
    /// @dev 1/1,000 of the total supply
    uint private constant MIN_HOLDER_BALANCE_THRESHOLD = 1_000;
    /// @dev 1/100,000 of the total supply
    uint private constant MAX_HOLDER_BALANCE_THRESHOLD = 100_000;
    address private constant FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address private constant ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    /// @dev minSwapThreshold = 0.5%
    uint public minSwapThreshold = 50;
    /// @dev 1/10,000 of the total supply
    uint public holderBalanceThreshold = 10_000;
    /// @dev treasuryTaxRate = 3%
    uint public treasuryTaxRate = 30;
    /// @dev liquidityTaxRate = 3%
    uint public liquidityTaxRate = 30;
    uint private _totalSupply;
    uint private _gonsPerFragment;

    uint public totalHolders;
    uint public totalTransfers;
    uint public latestRebaseEpoch;
    uint public rebaseUpdatedAtTimestamp;
    uint public rebaseUpdatedAtBlock;
    uint public lpTaxLockedUntil;
    address public oracle;
    address public treasury;
    bool public isAutoSwapEnabled = true;

    IUniswapV2Router02 private _router;
    address private _pair;

    struct RebaseLog {
        uint holders;
        uint transfers;
        uint marketCap;
        uint blockNumber;
    }

    mapping(uint => RebaseLog) public rebaseLogs;
    mapping(address => bool) public isTaxExcluded;
    mapping(address => bool) public isWhitelistedForGonTransfer;
    mapping(address => uint) private _gonBalances;
    mapping(address => bool) private _holders;

    modifier lockSwap {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    modifier onlyOracle {
        require(_msgSender() == oracle, "BaseJumper: caller not oracle");
        _;
    }

    event Rebased(uint _percent, bool _isPositive, uint _prevTotalSupply, uint _newTotalSupply);
    event OracleUpdated(address oracle);
    event TreasuryUpdated(address treasury);
    event TaxExclusion(address wallet, bool isExcluded);
    event MinSwapThresholdUpdated(uint minSwapThreshold);
    event HolderBalanceThresholdUpdated(uint holderBalanceThreshold);
    event TaxRateUpdated(uint treasuryTaxRate, uint liquidityTaxRate);
    event AutoSwapConfigured(bool isEnabled);
    event WhitelistGonTransfer(address wallet);

    constructor(address _oracle, address _treasury) ERC20("Base Jumper", "BJ") {
        setOracle(_oracle);
        setTreasury(_treasury);
        setTaxExclusion(owner(), true);
        setTaxExclusion(address(this), true);
        lpTaxLockedUntil = block.timestamp + LP_TAX_LOCK_UP_PERIOD;
        /// @dev transfer total supply to owner
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[owner()] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS / _totalSupply;
        _handleHolder(owner());
        totalTransfers++;
        /// @dev initialise router and create Uniswap pair
        _router = IUniswapV2Router02(ROUTER);
        IUniswapV2Factory factory = IUniswapV2Factory(FACTORY);
        _pair = factory.createPair(address(this), _router.WETH());
        emit Transfer(address(0), owner(), _totalSupply);
    }

    /// @notice Set Oracle address (owner)
    /// @param _oracle Oracle address
    function setOracle(address _oracle) public onlyOwner {
        require(_oracle != address(0), "BaseJumper: _oracle cannot be the zero address");
        oracle = _oracle;
        emit OracleUpdated(oracle);
    }

    /// @notice Set Treasury address (owner)
    /// @param _treasury Treasury address
    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "BaseJumper: _treasury cannot be the zero address");
        if (treasury != address(0) && treasury != owner()) {
            setTaxExclusion(treasury, false);
        }
        treasury = _treasury;
        setTaxExclusion(treasury, true);
        emit TreasuryUpdated(treasury);
    }

    /// @notice Set tax exclusion (owner)
    /// @param _wallet Wallet address
    /// @param _exclude True - Exclude from tax, False - Include tax
    function setTaxExclusion(address _wallet, bool _exclude) public onlyOwner {
        require(_wallet != address(0), "BaseJumper: _wallet cannot be the zero address");
        require(_exclude || _wallet != address(this), "BaseJumper: _wallet cannot equal this address");
        isTaxExcluded[_wallet] = _exclude;
        emit TaxExclusion(_wallet, _exclude);
    }

    /// @notice Set minimum threshold before a swap occurs (owner)
    /// @notice _minSwapThreshold Min swap threshold as a percentage, e.g. 50 = 0.5%
    function setMinSwapThreshold(uint _minSwapThreshold) external onlyOwner {
        require(_minSwapThreshold > 0, "BaseJumper: _minSwapThreshold must be greater than 0");
        minSwapThreshold = _minSwapThreshold;
        emit MinSwapThresholdUpdated(minSwapThreshold);
    }

    /// @notice Set tax rate, max total tax 10% (100) (owner)
    /// @notice _treasuryTaxRate Treasury tax rate swap e.g. 30 = 3%
    /// @notice _liquidityTaxRate Liquidity tax rate swap e.g. 30 = 3%
    function setTaxRate(uint _treasuryTaxRate, uint _liquidityTaxRate) external onlyOwner {
        require(_treasuryTaxRate + _liquidityTaxRate <= MAX_TOTAL_TAX_RATE, "BaseJumper: total tax rate must be less than to equal to 10%");
        treasuryTaxRate = _treasuryTaxRate;
        liquidityTaxRate = _liquidityTaxRate;
        emit TaxRateUpdated(treasuryTaxRate, liquidityTaxRate);
    }

    /// @notice Enable/disable auto swap (owner)
    /// @param _isAutoSwapEnabled True - Auto swap will occur on sells and transfers once over the threshold, False - No auto-swap
    function setIsAutoSwapEnabled(bool _isAutoSwapEnabled) external onlyOwner {
        isAutoSwapEnabled = _isAutoSwapEnabled;
        emit AutoSwapConfigured(isAutoSwapEnabled);
    }

    /// @notice Rebase (oracle)
    /// @param _percent Percent e.g. 1 = 1%
    /// @param _isPositive True _percent is positive, False _percent is negative
    function rebase(uint _percent, bool _isPositive) external onlyOracle {
        require(_percent <= 5, "BaseJumper: Rebase percent must be less than or equal to 5%");
        require(block.timestamp >= rebaseUpdatedAtTimestamp + REBASE_BUFFER, "BaseJumper: Cannot rebase more than once per day");
        rebaseUpdatedAtTimestamp = block.timestamp;
        rebaseUpdatedAtBlock = block.number;
        uint prevTotalSupply = _totalSupply;
        if (_percent > 0) {
            uint delta = _totalSupply * _percent / 100;
            if (_isPositive) {
                _totalSupply += delta;
            } else {
                _totalSupply -= delta;
            }
            if (_totalSupply > MAX_SUPPLY) {
                _totalSupply = MAX_SUPPLY;
            }
            _gonsPerFragment = TOTAL_GONS / _totalSupply;
            IUniswapV2Pair(_pair).sync();
        }
        emit Rebased(_percent, _isPositive, prevTotalSupply, _totalSupply);
    }

    /// @notice Get Gon balance of _address
    /// @param _address Address
    /// @return uint Gon balance
    function gonBalanceOf(address _address) external view returns (uint) {
        return _gonBalances[_address];
    }

    /// @notice Calculate the Gon value for _amount
    /// @param _amount Amount
    /// @return uint Gon value
    function calculateGonValue(uint _amount) public view returns (uint) {
        return _amount * _gonsPerFragment;
    }

    /// @notice Calculate the amount for _gonValue
    /// @param _gonValue Gon value
    /// @return uint Amount
    function calculateAmount(uint _gonValue) public view returns (uint) {
        return _gonValue / _gonsPerFragment;
    }

    /// @notice Whitelist an address so it can call gonTransfer (owner)
    /// @param _address Address to whitelist
    function whitelistGonTransfer(address _address) external onlyOwner {
        require(_address != address(0), "BaseJumper: _address cannot be the zero address");
        isWhitelistedForGonTransfer[_address] = true;
        emit WhitelistGonTransfer(_address);
    }

    /// @notice Transfer in Gon rather than amount
    /// @param _to To address
    /// @param _gonValue Gon value
    function gonTransfer(address _to, uint _gonValue) external {
        address from = _msgSender();
        require(isWhitelistedForGonTransfer[from], "BaseJumper: Only whitelisted addresses can call this function");
        require(_gonValue > 0, "BaseJumper: Cannot transfer 0 gon");
        require(from != address(0), "ERC20: transfer to the zero address");
        require(_to != address(0), "ERC20: transfer to the zero address");
        _gonTransfer(from, _to, _gonValue);
        uint amount = calculateAmount(_gonValue);
        emit Transfer(from, _to, amount);
    }

    /// @notice Claim tax generated LP tokens, locked for 6 months (owner)
    function claimTaxGeneratedLP() external onlyOwner {
        require(block.timestamp >= lpTaxLockedUntil, "BaseJumper: Cannot withdraw yet");
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);
        uint lpBalance = pair.balanceOf(address(this));
        require(lpBalance > 0, "BaseJumper: Nothing to withdraw");
        pair.transfer(owner(), lpBalance);
    }

    /// @notice Get holder balance threshold as an amount
    /// @return uint Holder balance threshold
    function holderBalanceThresholdAmount() external view returns (uint) {
        return calculateAmount(TOTAL_GONS / holderBalanceThreshold);
    }

    /// @notice Set balance threshold used to determine if a wallet is a "holder" (owner)
    /// @param _threshold Holder balance threshold
    function setHolderBalanceThreshold(uint _threshold) external onlyOwner {
        require(
            MIN_HOLDER_BALANCE_THRESHOLD <= _threshold && _threshold <= MAX_HOLDER_BALANCE_THRESHOLD,
            "BaseJumper: _threshold must be within range"
        );
        holderBalanceThreshold = _threshold;
        emit HolderBalanceThresholdUpdated(holderBalanceThreshold);
    }

    function totalSupply() public override view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address _address) public override view returns (uint) {
        return _gonBalances[_address] / _gonsPerFragment;
    }

    function _transfer(
        address _from,
        address _to,
        uint _amount
    ) internal override {
        require(_amount > 0, "BaseJumper: Cannot transfer 0 tokens");
        if (!_inSwap) {
            /// @dev do not include transfers from handling fees
            totalTransfers++;
        }
        if (isTaxExcluded[_from] || isTaxExcluded[_to]) {
            _rawTransfer(_from, _to, _amount);
            return;
        }
        /// @dev only handle tax when not buying, the tax is over the threshold, and auto swap is enabled
        if (_from != _pair && _isTaxOverMinThreshold() && isAutoSwapEnabled) {
            _autoSwapTax();
        }
        uint amountToSend = _amount;
        /// @dev apply tax when buying or selling
        if (_from == _pair || _to == _pair) {
            uint tax = _calculateTax(_amount);
            if (tax > 0) {
                amountToSend -= tax;
                _rawTransfer(_from, address(this), tax);
            }
        }
        _rawTransfer(_from, _to, amountToSend);
    }

    /// @dev Raw transfer, calls _gonTransfer
    /// @param _from From address
    /// @param _to To address
    /// @param _amount Amount
    function _rawTransfer(
        address _from,
        address _to,
        uint _amount
    ) internal {
        require(_from != address(0), "ERC20: transfer from the zero address");
        require(_to != address(0), "ERC20: transfer to the zero address");
        uint gonValue = calculateGonValue(_amount);
        _gonTransfer(_from, _to, gonValue);
        emit Transfer(_from, _to, _amount);
    }

    /// @dev Gon transfer
    /// @param _from From address
    /// @param _to To address
    /// @param _gonValue Gon value
    function _gonTransfer(address _from, address _to, uint _gonValue) internal {
        require(_gonBalances[_from] >= _gonValue, "ERC20: transfer amount exceeds balance");
        _gonBalances[_from] -= _gonValue;
        _gonBalances[_to] += _gonValue;
        _handleHolder(_from);
        _handleHolder(_to);
    }

    /// @dev Auto swap tax from Base Jumper to ETH, add liquidity, transfer treasury tax to treasury
    function _autoSwapTax() internal lockSwap {
        uint amount = balanceOf(address(this));
        uint taxRate = _getTotalTaxRate();
        if (taxRate > 0) {
            uint liquidityAmount = amount * liquidityTaxRate / taxRate;
            uint tokensForLP = liquidityAmount / 2;
            uint amountToSwap = amount - tokensForLP;
            _approve(address(this), ROUTER, amountToSwap);
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = _router.WETH();
            _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                amountToSwap,
                0,
                path,
                address(this),
                block.timestamp
            );
            uint ethBalance = address(this).balance;
            uint taxRateRelativeToSwap = taxRate - (liquidityTaxRate / 2);
            uint treasuryTaxETH = ethBalance * treasuryTaxRate / taxRateRelativeToSwap;
            uint liquidityTaxETH = ethBalance - treasuryTaxETH;
            if (treasuryTaxETH > 0) {
                payable(treasury).transfer(treasuryTaxETH);
            }
            if (tokensForLP > 0 && liquidityTaxETH > 0) {
                _addLiquidity(tokensForLP, liquidityTaxETH);
            }
        }
    }

    /// @param _bj Amount of BJ
    /// @param _eth Amount of ETH
    function _addLiquidity(uint _bj, uint _eth) internal {
        _approve(address(this), ROUTER, _bj);
        _router.addLiquidityETH{value : _eth}(
            address(this),
            _bj,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /// @param _amount Amount to apply tax to
    /// @return uint Tax owed on _amount
    function _calculateTax(uint _amount) internal view returns (uint) {
        return _amount * _getTotalTaxRate() / TAX_RATE_DENOMINATOR;
    }

    /// @return uint Total tax rate
    function _getTotalTaxRate() internal view returns (uint) {
        return treasuryTaxRate + liquidityTaxRate;
    }

    /// @return bool True if over min threshold, otherwise false
    function _isTaxOverMinThreshold() internal view returns (bool){
        return balanceOf(address(this)) >= _totalSupply * minSwapThreshold / MIN_SWAP_THRESHOLD_DENOMINATOR;
    }

    /// @param _holder Address of a potential holder
    function _handleHolder(address _holder) internal {
        if (_gonBalances[_holder] >= TOTAL_GONS / holderBalanceThreshold) {
            if (!_holders[_holder]) {
                _holders[_holder] = true;
                totalHolders += 1;
            }
        } else {
            if (_holders[_holder]) {
                _holders[_holder] = false;
                totalHolders -= 1;
            }
        }
    }

    receive() external payable {}
}

