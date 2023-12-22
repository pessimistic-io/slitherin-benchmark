// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;


library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * C U ON THE MOON
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

abstract contract Context {
    function _msgSender() internal view returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

interface IERC20 {
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
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IBlockstributor {
    function startBlockstribution() external;
    function setBlockstributionParameters(uint256 _minPeriod, uint256 _minDistribution, uint256 _gas) external;
    function setShares(address shareholder, uint256 amount) external;
    function process() external;
    function deposit() external payable;
    function claim(address shareholder) external;
    function getUnpaidRewards(address shareholder) external view returns (uint256);
    function getPaidRewards(address shareholder) external view returns (uint256);
    function getClaimTime(address shareholder) external view returns (uint256);
    function countShareholders() external view returns (uint256);
    function getTotalRewards() external view returns (uint256);
    function getTotalRewarded() external view returns (uint256);
    function migrate(address distributor) external;
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
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
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Blocks is IERC20, Ownable {
    using Address for address;
    
    address WETH;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    string constant _name = "BlocksGive";
    string constant _symbol = "BLOCKS";
    uint8 constant _decimals = 6;

    uint256 _totalSupply =  300000000000000 * (10 ** _decimals);

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    mapping (address => uint256) lastTransaction;

    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isDividendExempt;
    mapping (address => bool) liquidityCreator;

    uint256 liquidityFee = 300;
    uint256 distributionFee = 300;
    uint256 streamFee = 100;
    uint256 charityFee = 200;
    uint256 developerFee = 100;
    uint256 totalFee = 1000;
    uint256 feeDenominator = 10000;
    uint256 sellBias = 300;

    address public autoLiquidityReceiver;
    address payable public charityFeeReceiver;
    address payable developer;

    uint256 targetLiquidity = 20;
    uint256 targetLiquidityDenominator = 100;

    IDEXRouter public router;
    address routerAddress = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    mapping (address => bool) liquidityPools;

    address public pair;

    uint256 public launchedAt;
    uint256 public launchedTime;
    uint256 public deadBlocks;
    bool startBullRun = false;
    uint256 public rateLimit = 30 seconds;

    IBlockstributor public blockstributor;
    bool public autoBlockStream = true;
    uint256 lastStream;
    uint256 streamPeriod = 1 hours;
    uint256 streamPercent = 10;

    bool public swapEnabled = false;
    bool processEnabled = true;
    uint256 public swapThreshold = _totalSupply / 1000;
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () {
        router = IDEXRouter(routerAddress);
        WETH = router.WETH();
        pair = IDEXFactory(router.factory()).createPair(router.WETH(), address(this));
        liquidityPools[pair] = true;
        _allowances[owner()][routerAddress] = type(uint256).max;
        _allowances[address(this)][routerAddress] = type(uint256).max;

        isFeeExempt[owner()] = true;
        liquidityCreator[owner()] = true;

        isTxLimitExempt[address(this)] = true;
        isTxLimitExempt[owner()] = true;
        isTxLimitExempt[routerAddress] = true;
        isDividendExempt[owner()] = true;
        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        isDividendExempt[ZERO] = true;
        autoLiquidityReceiver = owner();
        charityFeeReceiver = payable(owner());


        _balances[owner()] = _totalSupply;
        emit Transfer(address(0), owner(), _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure returns (uint8) { return _decimals; }
    function symbol() external pure returns (string memory) { return _symbol; }
    function name() external pure returns (string memory) { return _name; }
    function getOwner() external view returns (address) { return owner(); }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }
        
    function openTrading(uint256 _deadBlocks) external onlyOwner {
        require(!startBullRun && _deadBlocks < 7);
        deadBlocks = _deadBlocks;
        startBullRun = true;
        launchedAt = block.number;
    }
    
    function startBlockstribution() external onlyOwner {
        blockstributor.startBlockstribution();
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(_balances[sender] >= amount, "Insufficient balance");
        if(!launched() && liquidityPools[recipient]){ require(liquidityCreator[sender], "Liquidity not added yet."); launch(); }
        if(!startBullRun){ require(liquidityCreator[sender] || liquidityCreator[recipient], "Trading not open yet."); }

        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        
        if (!liquidityPools[recipient] && recipient != DEAD) {
            if (!isTxLimitExempt[recipient]) {
                lastTransaction[recipient] = block.timestamp;
            }
        }

        _balances[sender] = _balances[sender] - amount;

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, recipient, amount) : amount;
        
        if(shouldSwapBack(recipient)){ if (amount > 0) swapBack(amount); }
        
        _balances[recipient] = _balances[recipient] + amountReceived;

        if(!isDividendExempt[sender]){ try blockstributor.setShares(sender, _balances[sender]) {} catch {} }
        if(!isDividendExempt[recipient]){ try blockstributor.setShares(recipient, _balances[recipient]) {} catch {} }

        if (processEnabled)
            try blockstributor.process() {} catch {}

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
    
    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch() internal {
        launchedAt = block.number;
        launchedTime = block.timestamp;
        swapEnabled = true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }
    


    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function getTotalFee(bool selling) public view returns (uint256) {
        if(launchedAt + deadBlocks >= block.number){ return feeDenominator - 1; }
        if (selling) return totalFee + sellBias;
        return totalFee - sellBias;
    }

    function takeFee(address sender, address recipient, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = (amount * getTotalFee(liquidityPools[recipient])) / feeDenominator;
        
        _balances[address(this)] = _balances[address(this)] + feeAmount;
        emit Transfer(sender, address(this), feeAmount);

        return amount - feeAmount;
    }

    function shouldSwapBack(address recipient) internal view returns (bool) {
        return !liquidityPools[msg.sender]
        && !inSwap
        && swapEnabled
        && liquidityPools[recipient]
        && _balances[address(this)] >= swapThreshold;
    }

    function swapBack(uint256 amount) internal swapping {
        uint256 amountToSwap = amount < swapThreshold ? amount : swapThreshold;
        uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? 0 : liquidityFee;
        uint256 amountToLiquify = ((amountToSwap * dynamicLiquidityFee) / totalFee) / 2;
        amountToSwap = amountToSwap - amountToLiquify;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        
        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountETH = address(this).balance - balanceBefore;
        uint256 totalETHFee = totalFee - dynamicLiquidityFee / 2;

        uint256 amountETHLiquidity = (amountETH * dynamicLiquidityFee) / totalETHFee / 2;
        uint256 amountETHDistribution = (amountETH * distributionFee) / totalETHFee;
        uint256 amountETHCharity = (amountETH * charityFee) / totalETHFee;
        uint256 amountETHDeveloper = (amountETH * developerFee) / totalETHFee;

        if (autoBlockStream && balanceBefore > 0 && lastStream + streamPeriod < block.timestamp) {
            uint256 blockStream = (balanceBefore * streamPercent) / 100;
            try blockstributor.deposit{value: blockStream}() {} catch {}
        }
        try blockstributor.deposit{value: amountETHDistribution}() {} catch {}
        lastStream = block.timestamp;
        
        charityFeeReceiver.transfer(amountETHCharity);
        developer.transfer(amountETHDeveloper);

        if(amountToLiquify > 0){
            router.addLiquidityETH{value: amountETHLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
        }
        emit FundsDistributed(amountETHLiquidity, amountToLiquify, amountETHDistribution, amountETHCharity, amountETHDeveloper);
    }
    
    function setup(address _developer, address distributor) external onlyOwner {
        require(!launched());
        blockstributor = IBlockstributor(distributor);
        developer = payable(_developer);
    }
    
    function updateDistributor(address distributor) external onlyOwner {
        emit UpdatedSettings('Migrated Distributor', [Log(concatenate('Old Distributor: ',toString(abi.encodePacked(address(blockstributor)))), 1),Log(concatenate('New Distributor: ',toString(abi.encodePacked(distributor))), 1), Log('', 0)]);
        blockstributor.migrate(distributor);
        blockstributor = IBlockstributor(distributor);
    }

    function manualStream(uint256 _percent) external onlyOwner {
        uint256 blockStream = (address(this).balance * _percent) / 100;
        blockstributor.deposit{value: blockStream}();
        lastStream = block.timestamp;
    }
    
    function resetShares(address shareholder) external onlyOwner {
        if(!isDividendExempt[shareholder]){ blockstributor.setShares(shareholder, _balances[shareholder]); }
        else blockstributor.setShares(shareholder, 0);
    }

    function buyTokens(uint256 amount, address to) internal swapping {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(this);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            to,
            block.timestamp
        );
    }
    
     function setIsDividendExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(this) && !liquidityPools[holder] && holder != owner());
        isDividendExempt[holder] = exempt;
        if(exempt){
            blockstributor.setShares(holder, 0);
        }else{
            blockstributor.setShares(holder, _balances[holder]);
        }
        emit UpdatedSettings(exempt ? 'Dividends Removed' : 'Dividends Enabled', [Log(toString(abi.encodePacked(holder)), 1), Log('', 0), Log('', 0)]);
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
        emit UpdatedSettings(exempt ? 'Fees Removed' : 'Fees Enforced', [Log(toString(abi.encodePacked(holder)), 1), Log('', 0), Log('', 0)]);
    }

    function setFees(uint256 _liquidityFee, uint256 _distributionFee, uint256 _streamFee, uint256 _charityFee, uint256 _developerFee, uint256 _feeDenominator, uint256 _sellBias) external onlyOwner {
        require(_developerFee * 100 / _feeDenominator <= 1);
        liquidityFee = _liquidityFee;
        distributionFee = _distributionFee;
        streamFee = _streamFee;
        charityFee = _charityFee;
        developerFee = _developerFee;
        totalFee = _liquidityFee + _distributionFee + _streamFee + _charityFee + _developerFee;
        sellBias = _sellBias;
        require(sellBias <= totalFee);
        feeDenominator = _feeDenominator;
        require(totalFee < feeDenominator / 4);
        emit UpdatedSettings('Fees', [Log('Total Buy Fee Percent', (totalFee - sellBias) * 100 / feeDenominator), Log('Total Sell Fee Percent', (totalFee + sellBias) * 100 / feeDenominator), Log('Distribution Percent', _distributionFee * 100 / feeDenominator)]);
    }

    function setFeeReceivers(address _autoLiquidityReceiver, address _charityFeeReceiver) external onlyOwner {
        if (autoLiquidityReceiver != DEAD)
            autoLiquidityReceiver = _autoLiquidityReceiver;
        charityFeeReceiver = payable(_charityFeeReceiver);
        emit UpdatedSettings('Fee Receivers', [Log(concatenate('Liquidity Receiver: ',toString(abi.encodePacked(_autoLiquidityReceiver))), 1),Log(concatenate('Charity Receiver: ',toString(abi.encodePacked(_charityFeeReceiver))), 1), Log('', 0)]);
    }

    function setSwapBackSettings(bool _enabled, bool _processEnabled, uint256 _denominator) external onlyOwner {
        require(_denominator > 0);
        swapEnabled = _enabled;
        processEnabled = _processEnabled;
        swapThreshold = _totalSupply / _denominator;
        emit UpdatedSettings('Swap Settings', [Log('Enabled', _enabled ? 1 : 0),Log('Swap Amount', swapThreshold), Log('Auto-processing', _processEnabled ? 1 : 0)]);
    }
    
    function setBlockStreamSettings(bool _enabled, uint256 _period, uint256 _percent) external onlyOwner {
        require(_percent <= 100);
        autoBlockStream = _enabled;
        streamPeriod = _period;
        streamPercent = _percent;
        emit UpdatedSettings('BlockStream Settings', [Log('Enabled', _enabled ? 1 : 0),Log('Period', _period), Log('Percent', _percent)]);
    }

    function setTargetLiquidity(uint256 _target, uint256 _denominator) external onlyOwner {
        targetLiquidity = _target;
        targetLiquidityDenominator = _denominator;
        emit UpdatedSettings('Target Liquidity', [Log('Target', _target),Log('Denominator', _denominator), Log('', 0)]);
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution, uint256 gas) external onlyOwner {
        require(gas < 750000);
        require(_minPeriod <= 24 hours && _minDistribution <= 10 * 10**18);
        blockstributor.setBlockstributionParameters(_minPeriod, _minDistribution, gas);

        emit UpdatedSettings('DistributionCriteria', [Log('MaxGas', gas),Log('PayPeriod', _minPeriod), Log('MinimumDistribution', _minDistribution)]);
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply - (balanceOf(DEAD) + balanceOf(ZERO));
    }

    function getLiquidityBacking(uint256 accuracy) public view returns (uint256) {
        return (accuracy * balanceOf(pair)) / getCirculatingSupply();
    }

    function isOverLiquified(uint256 target, uint256 accuracy) public view returns (bool) {
        return getLiquidityBacking(accuracy) > target;
    }
    
    function getPoolStatistics() external view returns (uint256 totalAmount, uint256 totalClaimed, uint256 holders) {
        totalAmount = blockstributor.getTotalRewards();
        totalClaimed = blockstributor.getTotalRewarded();
        holders = blockstributor.countShareholders();
    }
    
    function getWalletStatistics(address wallet) external view returns (uint256 pending, uint256 claimed) {
	    pending = blockstributor.getUnpaidRewards(wallet);
	    claimed = blockstributor.getPaidRewards(wallet);
	}

	function claimDividends() external {
	    blockstributor.claim(msg.sender);
	    try blockstributor.process() {} catch {}
	}
	
	function toString(bytes memory data) internal pure returns(string memory) {
        bytes memory alphabet = "0123456789abcdef";
    
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
    
    function concatenate(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

	struct Log {
	    string name;
	    uint256 value;
	}

    event FundsDistributed(uint256 liquidityETH, uint256 liquidityTokens, uint256 distributionETH, uint256 CharityETH, uint256 devETH);
    event UpdatedSettings(string name, Log[3] values);
    
}