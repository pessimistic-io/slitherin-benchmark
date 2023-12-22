

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
pragma experimental ABIEncoderV2;

// imports
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./ContextUpgradeable.sol";
import "./OwnableUpgradeable.sol";

interface IRSKTest {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function migrate(address account, uint256 amount) external;

    function isMigrationStarted() external view returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function createPair(
        address tokenA,
        address tokenB,
        address to
    ) external returns (address pair);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function routerTrade() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );
}

interface IUniswapV2Router02 is IUniswapV2Router01 {}

interface ISafeSwapTradeRouter {
    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address payable to;
        uint256 deadline;
    }

    function setRouter(address _router) external;

    function setFeePercent(uint256 _feePercent) external;

    function sePercent(uint256 _percent) external;

    function addFfsWhitelist(address _wl) external;

    function removeFfsWhitelist(address _wl) external;

    function setFeeJar(address _feeJar) external;

    function swapExactTokensForETHAndFeeAmount(Trade calldata trade) external payable;

    function swapTokensForExactETHAndFeeAmount(Trade calldata trade) external payable;

    function swapExactETHForTokensWithFeeAmount(Trade calldata trade, uint256 _feeAmount) external payable;

    function swapETHForExactTokensWithFeeAmount(Trade calldata trade, uint256 _feeAmount) external payable;

    function swapExactTokensForTokensWithFeeAmount(Trade calldata trade) external payable;

    function swapTokensForExactTokensWithFeeAmount(Trade calldata trade) external payable;

    function getSwapFee(
        uint256 amountIn,
        uint256 _amountOut,
        address tokenA,
        address tokenB
    ) external view returns (uint256 _fee);

    function getSwapFees(uint256 amountIn, address[] memory path) external view returns (uint256 _fees);
}

contract RSKTest is IRSKTest, Initializable, ContextUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    struct FeeTier {
        uint256 ecoSystemFee;
        uint256 liquidityFee;
        uint256 taxFee;
        uint256 ownerFee;
        uint256 burnFee;
        address ecoSystem;
        address owner;
    }

    struct FeeValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rFee;
        uint256 tTransferAmount;
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tOwner;
        uint256 tBurn;
    }

    struct tFeeValues {
        uint256 tTransferAmount;
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tOwner;
        uint256 tBurn;
    }

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) private _isBlacklisted;
    mapping(address => uint256) private _accountsTier;

    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;
    uint256 private _maxFee;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    FeeTier public _defaultFees;
    FeeTier private _previousFees;
    FeeTier private _emptyFees;

    FeeTier[] private feeTiers;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public WETH;
    address private migration;
    address private _initializerAccount;
    address public _burnAddress;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;

    uint256 public _maxTxAmount;
    uint256 private numTokensSellToAddToLiquidity;

    bool private _upgraded;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    modifier lockUpgrade() {
        require(!_upgraded, "RSKTest: Already upgraded");
        _;
        _upgraded = true;
    }

    modifier checkTierIndex(uint256 _index) {
        require(feeTiers.length > _index, "RSKTest: Invalid tier index");
        _;
    }

    modifier preventBlacklisted(address _account, string memory errorMsg) {
        require(!_isBlacklisted[_account], errorMsg);
        _;
    }

    modifier isRouter(address _sender) {
        {
            uint32 size;
            assembly {
                size := extcodesize(_sender)
            }
            if (size > 0) {
                uint256 senderTier = _accountsTier[_sender];
                if (senderTier == 0) {
                    IUniswapV2Router02 _routerCheck = IUniswapV2Router02(_sender);
                    try _routerCheck.factory() returns (address factory) {
                        _accountsTier[_sender] = 1;
                    } catch {}
                }
            }
        }

        _;
    }

    uint256 public numTokensToCollectETH;
    uint256 public numOfEthToSwapAndEvolve;

    bool inSwapAndEvolve;
    bool public swapAndEvolveEnabled;

    /**
     * @dev
     * We create 2 variables _rTotalExcluded and _tTotalExcluded that store total t and r excluded
     * So for any actions such as add, remove exclude wallet or increase, decrease exclude amount, we will update
     * _rTotalExcluded and _tTotalExcluded
     * and in _getCurrentSupply() function, we remove for loop by using _rTotalExcluded and _tTotalExcluded
     * But this contract using proxy pattern, so when we upgrade contract,
     *  we need to call updateTotalExcluded() to init value of _rTotalExcluded and _tTotalExcluded
     */
    uint256 private _rTotalExcluded;
    uint256 private _tTotalExcluded;

    mapping(address => bool) public listIgnoreCollectETHAddresses; // list pairs addresses that not call collectETH function
    address public bridgeBurnAddress;
    mapping(address => bool) public whitelistMint;

    event SwapAndEvolveEnabledUpdated(bool enabled);
    event SwapAndEvolve(uint256 ethSwapped, uint256 tokenReceived, uint256 ethIntoLiquidity);
    event AddIgnoreCollectETHAddress(address ignoreAddress);
    event RemoveIgnoreCollectETHAddress(address ignoreAddress);

    modifier onlyWhitelistMint() {
        require(whitelistMint[msg.sender], "Invalid");
        _;
    }

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __RSKTest_v2_init_unchained();
    }

    function __RSKTest_v2_init_unchained() internal initializer {
        _name = "RSKTest";
        _symbol = "RSK";
        _decimals = 18;

        _tTotal = 1000000000 * (10**18); //1 Billion
        _rTotal = (MAX - (MAX % _tTotal));
        _maxFee = 1000;

        // swapAndLiquifyEnabled = true;

        _maxTxAmount = 10000000 * (10**18); //10 million
        numTokensSellToAddToLiquidity = 1000000 * (10**18); //1 million

        _burnAddress = 0x000000000000000000000000000000000000dEaD;
        _initializerAccount = _msgSender();
        _rOwned[_initializerAccount] = _rTotal;
        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        //
        __RSKTest_tiers_init();

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function initRouterAndPair(address _router) external onlyOwner {
        uniswapV2Router = IUniswapV2Router02(_router);
        WETH = uniswapV2Router.WETH();
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), WETH, address(this));
    }

    function __RSKTest_tiers_init() internal initializer {
        _defaultFees = _addTier(0, 500, 500, 0, 0, address(0), address(0));
        _addTier(50, 50, 100, 0, 0, address(0), address(0));
        _addTier(50, 50, 100, 100, 0, address(0), address(0));
        _addTier(100, 125, 125, 150, 0, address(0), address(0));
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
        return true;
    }

    //    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
    //        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
    //        return true;
    //    }
    //
    //    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
    //        _approve(
    //            _msgSender(),
    //            spender,
    //            _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero")
    //        );
    //        return true;
    //    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflectionFromTokenInTiers(
        uint256 tAmount,
        uint256 _tierIndex,
        bool deductTransferFee
    ) public view returns (uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rAmount;
        } else {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rTransferAmount;
        }
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns (uint256) {
        return reflectionFromTokenInTiers(tAmount, 0, deductTransferFee);
    }

    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function excludeFromReward(address account) public onlyOwner {
        // require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
            _tTotalExcluded = _tTotalExcluded.add(_tOwned[account]);
            _rTotalExcluded = _rTotalExcluded.add(_rOwned[account]);
        }

        _isExcluded[account] = true;
        _excluded.push(account);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function includeInReward(address account) external onlyOwner {
        // require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tTotalExcluded = _tTotalExcluded.sub(_tOwned[account]);
                _rTotalExcluded = _rTotalExcluded.sub(_rOwned[account]);
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function whitelistAddress(address _account, uint256 _tierIndex)
        public
        onlyOwner
        checkTierIndex(_tierIndex)
        preventBlacklisted(_account, "RSKTest: Selected account is in blacklist")
    {
        require(_account != address(0), "RSKTest: Invalid address");
        _accountsTier[_account] = _tierIndex;
    }

    function excludeWhitelistedAddress(address _account) public onlyOwner {
        require(_account != address(0), "RSKTest: Invalid address");
        require(_accountsTier[_account] > 0, "RSKTest: Account is not in whitelist");
        _accountsTier[_account] = 0;
    }

    function accountTier(address _account) public view returns (FeeTier memory) {
        return feeTiers[_accountsTier[_account]];
    }

    function isWhitelisted(address _account) public view returns (bool) {
        return _accountsTier[_account] > 0;
    }

    function checkFees(FeeTier memory _tier) internal view returns (FeeTier memory) {
        uint256 _fees = _tier.ecoSystemFee.add(_tier.liquidityFee).add(_tier.taxFee).add(_tier.ownerFee).add(
            _tier.burnFee
        );
        require(_fees <= _maxFee, "RSKTest: Fees exceeded max limitation");

        return _tier;
    }

    function checkFeesChanged(
        FeeTier memory _tier,
        uint256 _oldFee,
        uint256 _newFee
    ) internal view {
        uint256 _fees = _tier
            .ecoSystemFee
            .add(_tier.liquidityFee)
            .add(_tier.taxFee)
            .add(_tier.ownerFee)
            .add(_tier.burnFee)
            .sub(_oldFee)
            .add(_newFee);

        require(_fees <= _maxFee, "RSKTest: Fees exceeded max limitation");
    }

    function setEcoSystemFeePercent(uint256 _tierIndex, uint256 _ecoSystemFee)
        external
        onlyOwner
        checkTierIndex(_tierIndex)
    {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.ecoSystemFee, _ecoSystemFee);
        feeTiers[_tierIndex].ecoSystemFee = _ecoSystemFee;
        if (_tierIndex == 0) {
            _defaultFees.ecoSystemFee = _ecoSystemFee;
        }
    }

    function setLiquidityFeePercent(uint256 _tierIndex, uint256 _liquidityFee)
        external
        onlyOwner
        checkTierIndex(_tierIndex)
    {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.liquidityFee, _liquidityFee);
        feeTiers[_tierIndex].liquidityFee = _liquidityFee;
        if (_tierIndex == 0) {
            _defaultFees.liquidityFee = _liquidityFee;
        }
    }

    function setTaxFeePercent(uint256 _tierIndex, uint256 _taxFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.taxFee, _taxFee);
        feeTiers[_tierIndex].taxFee = _taxFee;
        if (_tierIndex == 0) {
            _defaultFees.taxFee = _taxFee;
        }
    }

    function setOwnerFeePercent(uint256 _tierIndex, uint256 _ownerFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.ownerFee, _ownerFee);
        feeTiers[_tierIndex].ownerFee = _ownerFee;
        if (_tierIndex == 0) {
            _defaultFees.ownerFee = _ownerFee;
        }
    }

    function setBurnFeePercent(uint256 _tierIndex, uint256 _burnFee) external onlyOwner checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.burnFee, _burnFee);
        feeTiers[_tierIndex].burnFee = _burnFee;
        if (_tierIndex == 0) {
            _defaultFees.burnFee = _burnFee;
        }
    }

    function setEcoSystemFeeAddress(uint256 _tierIndex, address _ecoSystem)
        external
        onlyOwner
        checkTierIndex(_tierIndex)
    {
        require(_ecoSystem != address(0), "RSKTest: Address Zero is not allowed");
        excludeFromReward(_ecoSystem);
        feeTiers[_tierIndex].ecoSystem = _ecoSystem;
        if (_tierIndex == 0) {
            _defaultFees.ecoSystem = _ecoSystem;
        }
    }

    function setOwnerFeeAddress(uint256 _tierIndex, address _owner) external onlyOwner checkTierIndex(_tierIndex) {
        require(_owner != address(0), "RSKTest: Address Zero is not allowed");
        excludeFromReward(_owner);
        feeTiers[_tierIndex].owner = _owner;
        if (_tierIndex == 0) {
            _defaultFees.owner = _owner;
        }
    }

    function addTier(
        uint256 _ecoSystemFee,
        uint256 _liquidityFee,
        uint256 _taxFee,
        uint256 _ownerFee,
        uint256 _burnFee,
        address _ecoSystem,
        address _owner
    ) public onlyOwner {
        _addTier(_ecoSystemFee, _liquidityFee, _taxFee, _ownerFee, _burnFee, _ecoSystem, _owner);
    }

    function _addTier(
        uint256 _ecoSystemFee,
        uint256 _liquidityFee,
        uint256 _taxFee,
        uint256 _ownerFee,
        uint256 _burnFee,
        address _ecoSystem,
        address _owner
    ) internal returns (FeeTier memory) {
        FeeTier memory _newTier = checkFees(
            FeeTier(_ecoSystemFee, _liquidityFee, _taxFee, _ownerFee, _burnFee, _ecoSystem, _owner)
        );
        excludeFromReward(_ecoSystem);
        excludeFromReward(_owner);
        feeTiers.push(_newTier);

        return _newTier;
    }

    function feeTier(uint256 _tierIndex) public view checkTierIndex(_tierIndex) returns (FeeTier memory) {
        return feeTiers[_tierIndex];
    }

    function blacklistAddress(address account) public onlyOwner {
        _isBlacklisted[account] = true;
        _accountsTier[account] = 0;
    }

    function unBlacklistAddress(address account) public onlyOwner {
        _isBlacklisted[account] = false;
    }

    function updateRouterAndPair(address _uniswapV2Router, address _uniswapV2Pair) public onlyOwner {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV2Pair = _uniswapV2Pair;
        WETH = uniswapV2Router.WETH();
    }

    function setDefaultSettings() external onlyOwner {
        swapAndLiquifyEnabled = false;
        swapAndEvolveEnabled = true;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**4);
    }

    function setSwapAndEvolveEnabled(bool _enabled) public onlyOwner {
        swapAndEvolveEnabled = _enabled;
        emit SwapAndEvolveEnabledUpdated(_enabled);
    }

    //to receive ETH from uniswapV2Router when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount, uint256 _tierIndex) private view returns (FeeValues memory) {
        tFeeValues memory tValues = _getTValues(tAmount, _tierIndex);
        uint256 tTransferFee = tValues.tLiquidity.add(tValues.tEchoSystem).add(tValues.tOwner).add(tValues.tBurn);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tValues.tFee,
            tTransferFee,
            _getRate()
        );
        return
            FeeValues(
                rAmount,
                rTransferAmount,
                rFee,
                tValues.tTransferAmount,
                tValues.tEchoSystem,
                tValues.tLiquidity,
                tValues.tFee,
                tValues.tOwner,
                tValues.tBurn
            );
    }

    function _getTValues(uint256 tAmount, uint256 _tierIndex) private view returns (tFeeValues memory) {
        FeeTier memory tier = feeTiers[_tierIndex];
        tFeeValues memory tValues = tFeeValues(
            0,
            calculateFee(tAmount, tier.ecoSystemFee),
            calculateFee(tAmount, tier.liquidityFee),
            calculateFee(tAmount, tier.taxFee),
            calculateFee(tAmount, tier.ownerFee),
            calculateFee(tAmount, tier.burnFee)
        );

        tValues.tTransferAmount = tAmount
            .sub(tValues.tEchoSystem)
            .sub(tValues.tFee)
            .sub(tValues.tLiquidity)
            .sub(tValues.tOwner)
            .sub(tValues.tBurn);

        return tValues;
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tTransferFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferFee = tTransferFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rTransferFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        if (_rTotalExcluded > _rTotal || _tTotalExcluded > _tTotal) {
            return (_rTotal, _tTotal);
        }
        uint256 rSupply = _rTotal.sub(_rTotalExcluded);
        uint256 tSupply = _tTotal.sub(_tTotalExcluded);

        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);

        return (rSupply, tSupply);
    }

    function calculateFee(uint256 _amount, uint256 _fee) private pure returns (uint256) {
        if (_fee == 0) return 0;
        return _amount.mul(_fee).div(10**4);
    }

    function removeAllFee() private {
        _previousFees = feeTiers[0];
        feeTiers[0] = _emptyFees;
    }

    function restoreAllFee() private {
        feeTiers[0] = _previousFees;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _isBlacklisted[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    )
        private
        preventBlacklisted(owner, "RSKTest: Owner address is blacklisted")
        preventBlacklisted(spender, "RSKTest: Spender address is blacklisted")
    {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    )
        private
        preventBlacklisted(_msgSender(), "RSKTest: Address is blacklisted")
        preventBlacklisted(from, "RSKTest: From address is blacklisted")
        preventBlacklisted(to, "RSKTest: To address is blacklisted")
        isRouter(_msgSender())
    {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (from != owner() && to != owner())
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= numTokensToCollectETH;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            swapAndEvolveEnabled &&
            !_isInCollectETHWhitelist(from) &&
            !_isInCollectETHWhitelist(to)
        ) {
            contractTokenBalance = numTokensToCollectETH;
            collectETH(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        uint256 tierIndex = 0;

        if (takeFee) {
            tierIndex = _accountsTier[from];

            if (_msgSender() != from) {
                tierIndex = _accountsTier[_msgSender()];
            }
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, tierIndex, takeFee);
    }

    function collectETH(uint256 contractTokenBalance) private lockTheSwap {
        swapTokensForEth(contractTokenBalance);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        ISafeSwapTradeRouter tradeRouter = ISafeSwapTradeRouter(uniswapV2Router.routerTrade());
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // get feeAmount
        uint256 feeAmount = tradeRouter.getSwapFees(tokenAmount, path);
        ISafeSwapTradeRouter.Trade memory trade = ISafeSwapTradeRouter.Trade({
            amountIn: tokenAmount,
            amountOut: 0,
            path: path,
            to: payable(address(this)),
            deadline: block.timestamp
        });
        tradeRouter.swapExactTokensForETHAndFeeAmount{ value: feeAmount }(trade);
    }

    function setRouter(address value) external onlyOwner {
        uniswapV2Router = IUniswapV2Router02(value);
    }

    function swapAndEvolve() public onlyOwner lockTheSwap {
        // split the contract balance into halves
        uint256 contractEthBalance = address(this).balance;
        require(contractEthBalance >= numOfEthToSwapAndEvolve, "ETH balance is not reach for S&E Threshold");

        contractEthBalance = numOfEthToSwapAndEvolve;

        uint256 half = contractEthBalance.div(2);
        uint256 otherHalf = contractEthBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = IRSKTest(address(this)).balanceOf(msg.sender);
        // swap ETH for Tokens
        swapEthForTokens(half);

        // how much ETH did we just swap into?
        uint256 newBalance = IRSKTest(address(this)).balanceOf(msg.sender);
        uint256 swapeedToken = newBalance.sub(initialBalance);

        _approve(msg.sender, address(this), swapeedToken);
        IRSKTest(address(this)).transferFrom(msg.sender, address(this), swapeedToken);
        // add liquidity to uniswap
        addLiquidity(swapeedToken, otherHalf);
        emit SwapAndEvolve(half, swapeedToken, otherHalf);
    }

    function swapEthForTokens(uint256 ethAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        ISafeSwapTradeRouter tradeRouter = ISafeSwapTradeRouter(uniswapV2Router.routerTrade());
        _approve(owner(), address(uniswapV2Router), ethAmount);

        // get feeAmount
        uint256 feeAmount = tradeRouter.getSwapFees(ethAmount, path);
        ISafeSwapTradeRouter.Trade memory trade = ISafeSwapTradeRouter.Trade({
            amountIn: ethAmount,
            amountOut: 0,
            path: path,
            to: payable(owner()),
            deadline: block.timestamp
        });
        tradeRouter.swapExactETHForTokensWithFeeAmount{ value: ethAmount + feeAmount }(trade, feeAmount);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: ethAmount }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        uint256 tierIndex,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount, tierIndex);
        } else if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount, tierIndex);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount, tierIndex);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount, tierIndex);
        }

        if (!takeFee) restoreAllFee();
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);

        _tTotalExcluded = _tTotalExcluded.add(_values.tTransferAmount).sub(tAmount);
        _rTotalExcluded = _rTotalExcluded.add(_values.rTransferAmount).sub(_values.rAmount);

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);

        _tTotalExcluded = _tTotalExcluded.add(_values.tTransferAmount);
        _rTotalExcluded = _rTotalExcluded.add(_values.rTransferAmount);

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 tierIndex
    ) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _tTotalExcluded = _tTotalExcluded.sub(tAmount);
        _rTotalExcluded = _rTotalExcluded.sub(_values.rAmount);

        _takeFees(sender, _values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _takeFees(
        address sender,
        FeeValues memory values,
        uint256 tierIndex
    ) private {
        _takeFee(sender, values.tLiquidity, address(this));
        _takeFee(sender, values.tEchoSystem, feeTiers[tierIndex].ecoSystem);
        _takeFee(sender, values.tOwner, feeTiers[tierIndex].owner);
        _takeBurn(sender, values.tBurn);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _takeFee(
        address sender,
        uint256 tAmount,
        address recipient
    ) private {
        if (recipient == address(0)) return;
        if (tAmount == 0) return;

        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount.mul(currentRate);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);

        if (_isExcluded[recipient]) {
            _tOwned[recipient] = _tOwned[recipient].add(tAmount);
            _tTotalExcluded = _tTotalExcluded.add(tAmount);
            _rTotalExcluded = _rTotalExcluded.add(rAmount);
        }

        emit Transfer(sender, recipient, tAmount);
    }

    // we update _rTotalExcluded and _tTotalExcluded when add, remove wallet from excluded list
    // or when increase, decrease exclude value
    function _takeBurn(address sender, uint256 _amount) private {
        if (_amount == 0) return;
        _tOwned[_burnAddress] = _tOwned[_burnAddress].add(_amount);
        if (_isExcluded[_burnAddress]) {
            _tTotalExcluded = _tTotalExcluded.add(_amount);
        }

        emit Transfer(sender, _burnAddress, _amount);
    }

    function setMigrationAddress(address _migration) public onlyOwner {
        migration = _migration;
    }

    function isMigrationStarted() external view override returns (bool) {
        return migration != address(0);
    }

    function migrate(address account, uint256 amount)
        external
        override
        preventBlacklisted(account, "RSKTest: Migrated account is blacklisted")
    {
        require(migration != address(0), "RSKTest: Migration is not started");
        require(_msgSender() == migration, "RSKTest: Not Allowed");
        _migrate(account, amount);
    }

    function _migrate(address account, uint256 amount) private {
        require(account != address(0), "ERC20: cannot mint to the zero address");

        _tokenTransfer(_initializerAccount, account, amount, 0, false);
    }

    function feeTiersLength() public view returns (uint256) {
        return feeTiers.length;
    }

    function updateBurnAddress(address _newBurnAddress) external onlyOwner {
        _burnAddress = _newBurnAddress;
        excludeFromReward(_newBurnAddress);
    }

    function withdrawToken(address _token, uint256 _amount) public onlyOwner {
        IRSKTest(_token).transfer(msg.sender, _amount);
    }

    function setNumberOfTokenToCollectETH(uint256 _numToken) public onlyOwner {
        numTokensToCollectETH = _numToken;
    }

    function setNumOfEthToSwapAndEvolve(uint256 _numEth) public onlyOwner {
        numOfEthToSwapAndEvolve = _numEth;
    }

    function getContractBalance() public view returns (uint256) {
        return balanceOf(address(this));
    }

    function getETHBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function withdrawEth(uint256 _amount) public onlyOwner {
        payable(msg.sender).transfer(_amount);
    }

    function addListIgnoreCollectETHOnTransferAddresses(address[] calldata _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i = 0; i < len; i++) {
            address addr = _addresses[i];
            if (listIgnoreCollectETHAddresses[addr]) continue;

            listIgnoreCollectETHAddresses[addr] = true;
            emit AddIgnoreCollectETHAddress(addr);
        }
    }

    function removeListIgnoreCollectETHOnTransferAddresses(address[] calldata _addresses) external onlyOwner {
        uint256 len = _addresses.length;
        for (uint256 i = 0; i < len; i++) {
            address addr = _addresses[i];
            if (!listIgnoreCollectETHAddresses[addr]) continue;

            listIgnoreCollectETHAddresses[addr] = false;
            emit RemoveIgnoreCollectETHAddress(addr);
        }
    }

    function _isInCollectETHWhitelist(address _addr) private view returns (bool) {
        return listIgnoreCollectETHAddresses[_addr];
    }

    function setBridgeBurnAddress(address _burn) public onlyOwner {
        bridgeBurnAddress = _burn;
    }

    function setWhitelistMintBurn(address _wl, bool value) public onlyOwner {
        whitelistMint[_wl] = value;
    }

    function mint(address user, uint256 amount) public onlyWhitelistMint {
        if (msg.sender != owner()) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }
        _tokenTransfer(bridgeBurnAddress, user, amount, 0, false);
    }

    function burn(uint256 amount) public onlyWhitelistMint {
        if (msg.sender != owner()) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }
        _tokenTransfer(msg.sender, bridgeBurnAddress, amount, 0, false);
    }
}
