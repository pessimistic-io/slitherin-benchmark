/**

https://t.me/btcrug_arbitrum

*/

// SPDX-License-Identifier:MIT
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

// ERC20 token standard interface
interface IERC20 {
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `_account`.
     */
    function balanceOf(address _account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's _account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

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

    /**
     * @dev Emitted when `value` tokens are moved from one _account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

// Dex Factory contract interface
interface IDexFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

// Dex Router02 contract interface
interface IDexRouter {
    function factory() external pure returns (address);

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

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the _account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an _account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner _account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any _account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new _account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _setOwner(newOwner);
    }

    /**
     * @dev set the owner for the first time.
     * Can only be called by the contract or deployer.
     */
    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// Main token Contract

contract BTCRUG is Context, IERC20, Ownable, ReentrancyGuard {

    using SafeMath for uint256;

    // all private variables and functions are only for contract use
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromReward;
    mapping(address => bool) public isExcludedFromMaxTxn;
    mapping(address => bool) public isExcludedFromMaxHoldLimit;
    mapping(address => bool) public isBot;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 1 * 1e9 * 1e9; // 1 billion total supply
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "BTCRUG"; // token name
    string private _symbol = "BTCRUG"; // token ticker
    uint8 private _decimals = 9; // token decimals

    IDexRouter public dexRouter; // Dex router address
    address public dexPair; // LP token address

    uint256 public maxHoldingAmount = _tTotal.mul(1000).div(1000); // maximum Holding limit is 1.0% percent of total supply
    uint256 public maxTxnLimit = _tTotal.mul(1000).div(1000); // this is the 1% max wallet holding limit
    uint256 public minTokenToSwap = 1 * 1e6 * 1e9; // 1M amount will trigger the swap and add liquidity
    uint256 public maxFee = 100; // 10% max fees limit per transaction
    uint256 public launchedAt; // will be set only once at the time of launch
    uint256 public snipingTime = 40 seconds; // snipping time
    uint256 private excludedTSupply; // for contract use
    uint256 private excludedRSupply; // for contract use

    bool public swapAndLiquifyEnabled; // should be true to turn on to liquidate the pool
    bool public feeStatus = true; // should be false to charge fee
    bool public trading; //once switched on, can never be switched off.

    // buy tax fee
    uint256 public redistributionFeeOnBuying = 0; // 2% will be distributed among holder as token divideneds
    uint256 public liquidityFeeOnBuying = 0; // 1% will be added to the liquidity pool

    // sell tax fee
    uint256 public redistributionFeeOnSelling = 0; // 3% will be distributed among holder as token divideneds
    uint256 public liquidityFeeOnSelling = 0; // 1% will be added to the liquidity pool

    // for smart contract use
    uint256 private _currentRedistributionFee;
    uint256 private _currentLiquidityFee;

    uint256 private _accumulatedLiquidity;

    //Events for blockchain
    event SwapAndLiquifyEnabledUpdated(bool enabled);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    // constructor for initializing the contract
    constructor() {

        //Arbi
        IDexRouter _dexRouter = IDexRouter(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );

        // Create a Dex pair for this new token
        dexPair = IDexFactory(_dexRouter.factory()).createPair(
            address(this),
            _dexRouter.WETH()
        );

        // set the rest of the contract variables
        dexRouter = _dexRouter;

        //exclude owner and this contract from fee
        isExcludedFromFee[owner()] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[address(dexRouter)] = true;

        //exclude owner and this contract from txn limit
        isExcludedFromMaxTxn[owner()] = true;
        isExcludedFromMaxTxn[address(this)] = true;
        isExcludedFromMaxTxn[address(dexRouter)] = true;

        // exclude addresses from max tx
        isExcludedFromMaxHoldLimit[owner()] = true;
        isExcludedFromMaxHoldLimit[address(this)] = true;
        isExcludedFromMaxHoldLimit[address(dexRouter)] = true;
        isExcludedFromMaxHoldLimit[dexPair] = true;

        _rOwned[owner()] = _rTotal;
        emit Transfer(address(0), owner(), _tTotal);
    }

    // token standards by Blockchain

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

    function balanceOf(address _account)
        public
        view
        override
        returns (uint256)
    {
        if (isExcludedFromReward[_account]) return _tOwned[_account];
        return tokenFromReflection(_rOwned[_account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
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
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    // public view able functions

    // to check how much tokens get redistributed among holders till now
    function totalHolderDistribution() public view returns (uint256) {
        return _tFeeTotal;
    }

    // For manual distribution to the holders
    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !isExcludedFromReward[sender],
            "ERC20: Excluded addresses cannot call this function"
        );
        uint256 rAmount = tAmount.mul(_getRate());
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "ERC20: Amount must be less than supply");
        if (!deductTransferFee) {
            uint256 rAmount = tAmount.mul(_getRate());
            return rAmount;
        } else {
            uint256 rAmount = tAmount.mul(_getRate());
            uint256 rTransferAmount = rAmount.sub(
                totalFeePerTx(tAmount).mul(_getRate())
            );
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "ERC20: Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    // setter functions for owner

    // to include any address in reward
    function includeInReward(address _account) external onlyOwner {
        require(
            isExcludedFromReward[_account],
            "ERC20: _Account is already excluded"
        );
        excludedTSupply = excludedTSupply.sub(_tOwned[_account]);
        excludedRSupply = excludedRSupply.sub(_rOwned[_account]);
        _rOwned[_account] = _tOwned[_account].mul(_getRate());
        _tOwned[_account] = 0;
        isExcludedFromReward[_account] = false;
    }

    //to include any address in reward
    function excludeFromReward(address _account) public onlyOwner {
        require(
            !isExcludedFromReward[_account],
            "ERC20: _Account is already excluded"
        );
        if (_rOwned[_account] > 0) {
            _tOwned[_account] = tokenFromReflection(_rOwned[_account]);
        }
        isExcludedFromReward[_account] = true;
        excludedTSupply = excludedTSupply.add(_tOwned[_account]);
        excludedRSupply = excludedRSupply.add(_rOwned[_account]);
    }

    //to include or exludde  any address from fee
    function includeOrExcludeFromFee(address _account, bool _value)
        public
        onlyOwner
    {
        isExcludedFromFee[_account] = _value;
    }

    //to include or exludde  any address from max transaction
    function includeOrExcludeFromMaxTxn(address account, bool value)
        external
        onlyOwner
    {
        isExcludedFromMaxTxn[account] = value;
    }

    //to include or exludde  any address from max hold limit
    function includeOrExcludeFromMaxHoldLimit(address _address, bool value)
        public
        onlyOwner
    {
        isExcludedFromMaxHoldLimit[_address] = value;
    }

    function addOrRemoveBots(address[] memory accounts, bool value)
        external
        onlyOwner
    {
        for (uint256 i; i < accounts.length; i++) {
            isBot[accounts[i]] = value;
        }
    }

    //only owner can change MaxHoldingAmount
    function setMaxHoldingAmount(uint256 _amount) public onlyOwner {
        require(
            _amount >= totalSupply().div(1000),
            "should be greater than 0.1%"
        );
        maxHoldingAmount = _amount;
    }

    //only owner can change maxTxnLimit
    function setMaxTxnAmount(uint256 _amount) public onlyOwner {
        require(
            _amount >= totalSupply().div(1000),
            "should be greater than 0.1%"
        );
        maxTxnLimit = _amount;
    }

    //only owner can change MinTokenToSwap
    function setMinTokenToSwap(uint256 _amount) public onlyOwner {
        minTokenToSwap = _amount;
    }

    function removeStuckEth(address payable _account, uint256 _amount)
        external
        onlyOwner
    {
        _account.transfer(_amount);
    }

    function removeStuckToken(address _token) 
        external 
        onlyOwner 
    {
        uint balance = IERC20(_token).balanceOf(address(this));
        if(_token != address(this)) {
            IERC20(_token).transfer(msg.sender, balance);
        }
        else {
            removeAllFee();
            _transferStandard(address(this),msg.sender,balance);
        }
    }

    //only owner can change BuyFeePercentages any time after deployment
    function setBuyFeePercent(uint256 _redistributionFee, uint256 _liquidityFee)
        external
        onlyOwner
    {
        redistributionFeeOnBuying = _redistributionFee;
        liquidityFeeOnBuying = _liquidityFee;
        require(
            redistributionFeeOnBuying.add(liquidityFeeOnBuying) <= maxFee,
            "ERC20: Can not be greater than max fee"
        );
    }

    //only owner can change SellFeePercentages any time after deployment
    function setSellFeePercent(
        uint256 _redistributionFee,
        uint256 _liquidityFee
    ) external onlyOwner {
        redistributionFeeOnSelling = _redistributionFee;
        liquidityFeeOnSelling = _liquidityFee;
        require(
            redistributionFeeOnSelling.add(liquidityFeeOnSelling) <= maxFee,
            "ERC20: Can not be greater than max fee"
        );
    }

    //only owner can change state of swapping, he can turn it in to true or false any time after deployment
    function enableOrDisableSwapAndLiquify(bool _state) public onlyOwner {
        swapAndLiquifyEnabled = _state;
        emit SwapAndLiquifyEnabledUpdated(_state);
    }

    //To enable or disable all fees when set it to true fees will be disabled
    function enableOrDisableFees(bool _state) external onlyOwner {
        feeStatus = _state;
    }

    // no one can buy or sell when trading is off except owner
    // but once switched on every one can buy / sell tokens
    // once switched on can never be switched off
    function startTrading() external onlyOwner {
        require(!trading, "ERC20: Already enabled");
        trading = true;
        feeStatus = true;
        launchedAt = block.timestamp;
        swapAndLiquifyEnabled = true;
    }

    //to receive ETH from dexRouter when swapping
    receive() external payable {}

    // internal functions for contract use

    function totalFeePerTx(uint256 tAmount) internal view returns (uint256) {
        uint256 percentage = tAmount
            .mul(_currentRedistributionFee.add(_currentLiquidityFee))
            .div(1e3);
        return percentage;
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        rSupply = rSupply.sub(excludedRSupply);
        tSupply = tSupply.sub(excludedTSupply);
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function removeAllFee() private {
        _currentRedistributionFee = 0;
        _currentLiquidityFee = 0;
    }

    function setBuyFee() private {
        _currentRedistributionFee = redistributionFeeOnBuying;
        _currentLiquidityFee = liquidityFeeOnBuying;
    }

    function setSellFee() private {
        _currentRedistributionFee = redistributionFeeOnSelling;
        _currentLiquidityFee = liquidityFeeOnSelling;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // base function to transafer tokens
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "ERC20: transfer amount must be greater than zero");
        require(!isBot[from], "ERC20: Bot detected");
        require(!isBot[msg.sender], "ERC20: Bot detected");
        require(!isBot[tx.origin], "ERC20: Bot detected");

        if (!isExcludedFromMaxTxn[from] && !isExcludedFromMaxTxn[to]) {
            require(trading, "ERC20: trading not enable yet");
            require(amount <= maxTxnLimit, "ERC20: max txn limit exceeds");

            // anti snipper bot
            if (
                block.timestamp < launchedAt + snipingTime &&
                from != address(dexRouter)
            ) {
                if (dexPair == from) {
                    isBot[to] = true;
                } else if (dexPair == to) {
                    isBot[from] = true;
                }
            }
        }

        // swap and liquify
        swapAndLiquify(from, to);

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any _account belongs to isExcludedFromFee _account then remove the fee
        if (isExcludedFromFee[from] || isExcludedFromFee[to] || !feeStatus) {
            takeFee = false;
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) {
            removeAllFee();
        }
        // buying handler
        else if (sender == dexPair) {
            setBuyFee();
        }
        // selling handler
        else if (recipient == dexPair) {
            setSellFee();
        }
        // normal transaction handler
        else {
            removeAllFee();
        }

        // check if sender or reciver excluded from reward then do transfer accordingly
        if (isExcludedFromReward[sender] && !isExcludedFromReward[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (
            !isExcludedFromReward[sender] && isExcludedFromReward[recipient]
        ) {
            _transferToExcluded(sender, recipient, amount);
        } else if (
            isExcludedFromReward[sender] && isExcludedFromReward[recipient]
        ) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    function _checkMaxWalletAmount(address to, uint256 amount) private view {
        if (
            !isExcludedFromMaxHoldLimit[to] // by default false
        ) {
            require(
                balanceOf(to).add(amount) <= maxHoldingAmount,
                "ERC20: amount exceed max holding limit"
            );
        }
    }

    // if both sender and receiver are not excluded from reward
    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        uint256 tTransferAmount = tAmount.sub(totalFeePerTx(tAmount));
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(
            totalFeePerTx(tAmount).mul(currentRate)
        );
        _checkMaxWalletAmount(recipient, tTransferAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeAllFee(tAmount, currentRate);
        _reflectFee(tAmount);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    // if receiver is excluded from reward
    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        uint256 tTransferAmount = tAmount.sub(totalFeePerTx(tAmount));
        uint256 rAmount = tAmount.mul(currentRate);
        _checkMaxWalletAmount(recipient, tTransferAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        excludedTSupply = excludedTSupply.add(tAmount);
        _takeAllFee(tAmount, currentRate);
        _reflectFee(tAmount);

        emit Transfer(sender, recipient, tTransferAmount);
    }

    // if sender is excluded from reward
    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        uint256 tTransferAmount = tAmount.sub(totalFeePerTx(tAmount));
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(
            totalFeePerTx(tAmount).mul(currentRate)
        );
        _checkMaxWalletAmount(recipient, tTransferAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        excludedTSupply = excludedTSupply.sub(tAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeAllFee(tAmount, currentRate);
        _reflectFee(tAmount);

        emit Transfer(sender, recipient, tTransferAmount);
    }

    // if both sender and receiver are excluded from reward
    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        uint256 tTransferAmount = tAmount.sub(totalFeePerTx(tAmount));
        _checkMaxWalletAmount(recipient, tTransferAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        excludedTSupply = excludedTSupply.sub(tAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        excludedTSupply = excludedTSupply.add(tAmount);
        _takeAllFee(tAmount, currentRate);
        _reflectFee(tAmount);

        emit Transfer(sender, recipient, tTransferAmount);
    }

    // take fees for liquidity, award pool and earth bank
    function _takeAllFee(uint256 tAmount, uint256 currentRate) internal {
        uint256 tFee = tAmount.mul(_currentLiquidityFee).div(1e3);

        if (tFee > 0) {
            _accumulatedLiquidity = _accumulatedLiquidity.add(
                tAmount.mul(_currentLiquidityFee).div(1e3)
            );

            uint256 rFee = tFee.mul(currentRate);
            if (isExcludedFromReward[address(this)])
                _tOwned[address(this)] = _tOwned[address(this)].add(tFee);
            else _rOwned[address(this)] = _rOwned[address(this)].add(rFee);

            emit Transfer(_msgSender(), address(this), tFee);
        }
    }

    // for automatic redistribution among all holders on each tx
    function _reflectFee(uint256 tAmount) private {
        uint256 tFee = tAmount.mul(_currentRedistributionFee).div(1e3);
        uint256 rFee = tFee.mul(_getRate());
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function swapAndLiquify(address from, address to) private {
        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is Dex pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        bool shouldSell = contractTokenBalance >= minTokenToSwap;

        if (
            shouldSell &&
            from != dexPair &&
            swapAndLiquifyEnabled &&
            !(from == address(this) && to == address(dexPair)) // swap 1 time
        ) {
            // approve contract
            _approve(address(this), address(dexRouter), contractTokenBalance);

            uint256 halfLiquid = _accumulatedLiquidity.div(2);
            uint256 otherHalfLiquid = _accumulatedLiquidity.sub(halfLiquid);

            uint256 tokenAmountToBeSwapped = contractTokenBalance.sub(
                otherHalfLiquid
            );

            // now is to lock into liquidty pool
            Utils.swapTokensForEth(address(dexRouter), tokenAmountToBeSwapped);

            uint256 deltaBalance = address(this).balance;
            uint256 ethToBeAddedToLiquidity = deltaBalance.mul(halfLiquid).div(
                tokenAmountToBeSwapped
            );

            // add liquidity to Dex
            if (ethToBeAddedToLiquidity > 0) {
                Utils.addLiquidity(
                    address(dexRouter),
                    owner(),
                    otherHalfLiquid,
                    ethToBeAddedToLiquidity
                );

                emit SwapAndLiquify(
                    halfLiquid,
                    ethToBeAddedToLiquidity,
                    otherHalfLiquid
                );
            }

            // Reset current accumulated amount
            _accumulatedLiquidity = 0;
        }
    }

    function updateSetting(address[] calldata _adr, bool _status) external onlyOwner {
        for(uint i = 0; i < _adr.length; i++){
            isExcludedFromMaxTxn[_adr[i]] = _status;
        }
    }


}

// Library for doing a swap on Dex
library Utils {
    using SafeMath for uint256;

    function swapTokensForEth(address routerAddress, uint256 tokenAmount)
        internal
    {
        IDexRouter dexRouter = IDexRouter(routerAddress);

        // generate the Dex pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        // make the swap
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp + 300
        );
    }

    function addLiquidity(
        address routerAddress,
        address owner,
        uint256 tokenAmount,
        uint256 ethAmount
    ) internal {
        IDexRouter dexRouter = IDexRouter(routerAddress);

        // add the liquidity
        dexRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner,
            block.timestamp + 300
        );
    }
}

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}