// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IRiskVault.sol";
import "./Operator.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IAavePoolV3.sol";
import "./Abs.sol";
import "./ISwapRouter.sol";
import "./IChainLink.sol";

/**
 * @dev Sharplabs Treasury Contract. It provides an interface for governance accounts to
 * operate the pool contract and also accepts parameters uploaded from off-chain by governance to
 * ensure the system runs smoothly.
 *
 * It also provides a pause mechanism to temporarily halt the system's operation
 * in case of emergencies (users' on-chain funds are safe).
 */
contract Treasury is Operator, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;
    using Abs for int256;

    address public governance;
    address public riskOnPool;
    address public receiver1;
    address public receiver2;

    uint256 public epoch;
    uint256 public startTime;
    uint256 public period = 24 hours;
    uint256 public riskOnPoolRatio;
    uint256 public lastEpochPoint;

    bool public initialized = false;
    address public aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address public wsteth = 0x5979D7b546E38E414F7E9822514be443A4800529;
    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public usdcBrdiged = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    address public ethOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address public wstethOracle = 0xb523AE262D20A936BC152e6023996e46FDC2A95D;
    address public usdcOracle = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address public usdtOracle = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;

    address[] public withdrawWhitelist;
    mapping(address => bool) public withdrawWhitelistedAddr;

    event Initialized(address indexed executor, uint256 at);
    event EpochUpdated(uint256 indexed atEpoch, uint256 timestamp);
    event AaveV3Updated(uint256 indexed atEpoch, address _aaveV3);
    event Open(uint256 _openAmount, uint256 _swapMaxIn, uint256 _repayAmount);
    event Close(uint256 _closeAmount, uint256 _swapMinOut, uint256 _withdrawAmount);

    modifier onlyGovernance() {
        require(governance == msg.sender, "caller is not the governance");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    receive() external payable {}

    function aaveData()
        public
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return IAavePoolV3(aaveV3).getUserAccountData(riskOnPool);
    }

    function aaveUserEMode() public view returns (uint256) {
        return IAavePoolV3(aaveV3).getUserEMode(riskOnPool);
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return lastEpochPoint + period;
    }

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    /* ========== CONFIG ========== */

    function setPeriod(uint _period) external onlyGovernance {
        require(_period > 0, "period cannot be zero");
        period = _period;
    }

    function setPool(address _riskOnPool) external onlyOperator {
        require(
            _riskOnPool != address(0),
            "pool address cannot be zero address"
        );
        riskOnPool = _riskOnPool;
    }

    function setReceiver1(address _receiver1) external onlyOperator {
        require(
            _receiver1 != address(0),
            "receiver1 address cannot be zero address"
        );
        receiver1 = _receiver1;
    }

    function setReceiver2(address _receiver2) external onlyOperator {
        require(
            _receiver2 != address(0),
            "receiver2 address cannot be zero address"
        );
        receiver2 = _receiver2;
    }

    function setRiskOnPoolRatio(uint _riskOnPoolRatio) external onlyGovernance {
        require(_riskOnPoolRatio > 0, "ratio cannot be zero");
        riskOnPoolRatio = _riskOnPoolRatio;
    }

    function setFee(uint _inFee, uint _outFee) external onlyGovernance {
        IRiskVault(riskOnPool).setFee(_inFee, _outFee);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == operator() || msg.sender == governance);
        require(
            _governance != address(0),
            "governance address cannot be zero address"
        );
        governance = _governance;
    }

    function setAaveV3(address _aaveV3) external onlyOperator {
        require(_aaveV3 != address(0), "address can not be zero address");
        aaveV3 = _aaveV3;
        emit AaveV3Updated(epoch, _aaveV3);
    }
    function setReferralCode(uint16 _referralCode) external onlyGovernance {
        IRiskVault(riskOnPool).setReferralCode(_referralCode);
    }

    function initialize(
        address _governance,
        address _riskOnPool,
        address _receiver1,
        address _receiver2,
        uint256 _riskOnPoolRatio,
        uint256 _startTime
    ) public notInitialized {
        require(
            _governance != address(0),
            "governance address can not be zero address"
        );
        require(
            _riskOnPool != address(0),
            "riskOnPool address can not be zero address"
        );
        require(
            _receiver1 != address(0),
            "receiver1 address can not be zero address"
        );
        require(
            _receiver2 != address(0),
            "receiver2 address can not be zero address"
        );
        receiver1 = _receiver1;
        receiver2 = _receiver2;
        governance = _governance;
        riskOnPool = _riskOnPool;
        riskOnPoolRatio = _riskOnPoolRatio;
        startTime = _startTime;
        lastEpochPoint = _startTime;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    // get ETH/USD price from chainlink oracle
    function eth_price() public view returns (uint256) {
        (, int256 answer, , , ) = IChainLink(ethOracle).latestRoundData();
        return answer.abs();
    }

    function eth_price_decimals() public view returns (uint8) {
        return IChainLink(ethOracle).decimals();
    }

    // get wstETH/ETH price from chainlink oracle
    function wsteth_price() public view returns (uint256) {
        (, int256 answer, , , ) = IChainLink(wstethOracle).latestRoundData();
        return answer.abs();
    }

    // get wstETH/USD price from chainlink oracle with 1e18 precision
    function wstETH_price() public view returns (uint256) {
        return wsteth_price() * 1e18 / 10 ** wsteth_price_decimals() * eth_price() / 10 ** eth_price_decimals();
    }

    function wsteth_price_decimals() public view returns (uint8) {
        return IChainLink(wstethOracle).decimals();
    }

    // get USDC/USD price from chainlink oracle
    function usdc_price() public view returns (uint256) {
        (, int256 answer, , , ) = IChainLink(usdcOracle).latestRoundData();
        return answer.abs();
    }

    function usdc_price_decimals() public view returns (uint8) {
        return IChainLink(usdcOracle).decimals();
    }

    // get USDT/USD price from chainlink oracle
    function usdt_price() public view returns (uint256) {
        (, int256 answer, , , ) = IChainLink(usdtOracle).latestRoundData();
        return answer.abs();
    }

    function usdt_price_decimals() public view returns (uint8) {
        return IChainLink(usdtOracle).decimals();
    }

    // required usd collateral in the contract with 1e18 precision
    function getRequiredUsdCollateral() public view returns (uint256) {
        IRiskVault vault = IRiskVault(riskOnPool);

        uint256 usdtAmount = vault.total_supply_wait() +
            vault.total_supply_staked() +
            vault.total_supply_withdraw();
        if (vault.total_supply_reward() >= 0) {
            usdtAmount = usdtAmount + vault.total_supply_reward().abs();
        } else {
            usdtAmount = usdtAmount - vault.total_supply_reward().abs();
        }
        usdtAmount = usdtAmount + vault.amount1() + vault.amount2();
        return (usdtAmount * usdt_price() * 1e12) / 10 ** usdt_price_decimals();
    }

    // get total usd value in the contract with 1e18 precision
    function getUsdValue() public view returns (uint256) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            ,
            ,

        ) = IAavePoolV3(aaveV3).getUserAccountData(riskOnPool);
        uint256 aaveValue = (totalCollateralBase - totalDebtBase) * 1e10;
        // tokenValue: wstETH, WETH, ETH, USDC, USDT
        uint256 tokenValue = (((IERC20(wsteth).balanceOf(riskOnPool) *
            wsteth_price()) / 10 ** wsteth_price_decimals()) * eth_price()) /
            10 ** eth_price_decimals();
        tokenValue =
            tokenValue +
            (IERC20(weth).balanceOf(riskOnPool) * eth_price()) /
            10 ** eth_price_decimals();
        tokenValue =
            tokenValue +
            (riskOnPool.balance * eth_price()) /
            10 ** eth_price_decimals();
        tokenValue =
            tokenValue +
            (IERC20(usdc).balanceOf(riskOnPool) * usdc_price() * 1e12) /
            10 ** usdc_price_decimals();
        tokenValue =
            tokenValue +
            (IERC20(usdcBrdiged).balanceOf(riskOnPool) * usdc_price() * 1e12) /
            10 ** usdc_price_decimals();
        tokenValue =
            tokenValue +
            (IERC20(usdt).balanceOf(riskOnPool) * usdt_price() * 1e12) /
            10 ** usdt_price_decimals();
        uint256 amountValue = (IRiskVault(riskOnPool).amount1() + IRiskVault(riskOnPool).amount2()) * 
            usdt_price() * 1e12 / 10 ** usdt_price_decimals();
        int256 reward = IRiskVault(riskOnPool).total_supply_reward();
        if (reward > 0){
            return aaveValue + tokenValue + amountValue + uint256(reward.abs()) * usdt_price() * 1e12 / 10 ** usdt_price_decimals();
        }else{
            return aaveValue + tokenValue + amountValue - uint256(reward.abs()) * usdt_price() * 1e12 / 10 ** usdt_price_decimals();
        }
    }
    
    
    function open(uint256 _openAmount, uint256 _swapMaxIn, uint256 _repayAmount)external onlyGovernance {
        IRiskVault(riskOnPool).open(_openAmount, _swapMaxIn, _repayAmount);
        emit Open(_openAmount, _swapMaxIn, _repayAmount);
    }
    
    
    function close(uint256 _closeAmount, uint256 _swapMinOut, uint256 _withdrawAmount)external onlyGovernance {
        IRiskVault(riskOnPool).close(_closeAmount, _swapMinOut, _withdrawAmount);
        emit Close(_closeAmount, _swapMinOut, _withdrawAmount);
    }

    function supplyBorrowAave(
        address _supplyToken,
        uint256 _supplyAmount,
        address _borrowToken,
        uint256 _borrowAmount
    ) external onlyGovernance {
        if (_supplyAmount > 0) {
            IRiskVault(riskOnPool).supplyAave(
                _supplyToken,
                _supplyAmount
            );
        }
         if (_borrowAmount > 0) {
            IRiskVault(riskOnPool).borrowAave(
                _borrowToken,
                _borrowAmount
            );
         }
    }

    function supplyAave(
        address _supplyToken,
        uint256 _supplyAmount
    ) external onlyGovernance {
        IRiskVault(riskOnPool).supplyAave(
            _supplyToken,
            _supplyAmount
        );
    }

    function borrowAave(
        address _borrowToken,
        uint256 _borrowAmount
    ) external onlyGovernance {
        IRiskVault(riskOnPool).borrowAave(
            _borrowToken,
            _borrowAmount
        );
    }

    function repayWithdrawAave(
        address _repayToken,
        uint256 _repayAmount,
        address _withdrawToken,
        uint256 _withdrawAmount
    ) external onlyGovernance {
        if (_repayAmount > 0) {
            IRiskVault(riskOnPool).repayAave(_repayToken, _repayAmount);
        }
        if (_withdrawAmount > 0) {
            IRiskVault(riskOnPool).withdrawAave(_withdrawToken, _withdrawAmount);
        }
    }

    function repayAave(
        address _repayToken,
        uint256 _repayAmount
    ) external onlyGovernance {
        IRiskVault(riskOnPool).repayAave(_repayToken, _repayAmount);
    }

    function withdrawAave(
        address _withdrawToken,
        uint256 _withdrawAmount
    ) external onlyGovernance {
        IRiskVault(riskOnPool).withdrawAave(_withdrawToken, _withdrawAmount);
    }

    // send funds(ERC20 tokens) to pool
    function sendPoolFunds(
        address _token,
        uint _amount
    ) external onlyGovernance {
        require(
            _amount <= IERC20(_token).balanceOf(address(this)),
            "insufficient funds"
        );
        IERC20(_token).safeTransfer(riskOnPool, _amount);
    }

    // send funds(ETH) to pool
    function sendPoolFundsETH(uint _amount) external onlyGovernance {
        require(_amount <= address(this).balance, "insufficient funds");
        Address.sendValue(payable(riskOnPool), _amount);
    }

    // withdraw pool funds(ERC20 tokens) to specified address
    function withdrawPoolFunds(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyGovernance {
        if (_to != governance) {
            require(withdrawWhitelistedAddr[_to], "address not in whitelist");
        }
        IRiskVault(riskOnPool).treasuryWithdrawFunds(_token, _amount, _to);
        require(
            (getRequiredUsdCollateral() * riskOnPoolRatio) / 100 <=
                getUsdValue(),
            "low collateral: cannot withdraw pool funds"
        );
    }

    // withdraw pool funds(ETH) to specified address
    function withdrawPoolFundsETH(
        uint _amount,
        address _to
    ) external onlyGovernance {
        if (_to != governance) {
            require(withdrawWhitelistedAddr[_to], "address not in whitelist");
        }
        require(_amount <= riskOnPool.balance, "insufficient funds");
        IRiskVault(riskOnPool).treasuryWithdrawFundsETH(_amount, _to);
        require(
            (getRequiredUsdCollateral() * riskOnPoolRatio) / 100 <=
                getUsdValue(),
            "low collateral: cannot withdraw pool funds"
        );
    }

    function swapPoolExactInput(
        ISwapRouter.ExactInputParams memory params
    )external onlyGovernance {
        if (params.deadline == 0){
            params.deadline = block.timestamp;
        }
        if (params.recipient == address(0)){
            params.recipient = riskOnPool;
        }
        if (params.recipient != riskOnPool && params.recipient != governance) {
            require(withdrawWhitelistedAddr[params.recipient], "address not in whitelist");
        }
        address _tokenIn = getTokenIn(params.path);
        uint256 _amountIn = params.amountIn;
        IRiskVault(riskOnPool).treasuryWithdrawFunds(
            _tokenIn,
            _amountIn,
            address(this)
        );
        ISwapRouter swapRouter = ISwapRouter(uniV3Router);
        IERC20(_tokenIn).safeApprove(uniV3Router, 0);
        IERC20(_tokenIn).safeApprove(uniV3Router, _amountIn);
        swapRouter.exactInput(params);
        require(
            (getRequiredUsdCollateral() * riskOnPoolRatio) / 100 <=
                getUsdValue(),
            "low collateral: cannot withdraw pool funds"
        );
    }

    function getTokenIn(bytes memory path) public pure returns (address tokenIn) {
        assembly {
            tokenIn := mload(add(path, 20))
        }
    }

    function swapPoolTokenToToken(
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _minAmountOut,
        uint24 _fee
    ) public onlyGovernance returns (uint256 amountOut) {
        IRiskVault(riskOnPool).treasuryWithdrawFunds(
            _tokenIn,
            _amountIn,
            address(this)
        );
        ISwapRouter swapRouter = ISwapRouter(uniV3Router);
        IERC20(_tokenIn).safeApprove(uniV3Router, 0);
        IERC20(_tokenIn).safeApprove(uniV3Router, _amountIn);
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _fee,
                recipient: riskOnPool,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: _minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        require(
            (getRequiredUsdCollateral() * riskOnPoolRatio) / 100 <=
                getUsdValue(),
            "low collateral: cannot withdraw pool funds"
        );
    }

    function swapPoolETHToToken(
        uint256 _amountIn,
        address _tokenOut,
        uint256 _minAmountOut,
        uint24 _fee
    ) external payable onlyGovernance {
        IRiskVault(riskOnPool).treasuryWithdrawFundsETH(
            _amountIn,
            address(this)
        );
        ISwapRouter swapRouter = ISwapRouter(uniV3Router);
        swapRouter.exactInputSingle{value: _amountIn}(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: _tokenOut,
                fee: _fee,
                recipient: riskOnPool,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: _minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        require(
            (getRequiredUsdCollateral() * riskOnPoolRatio) / 100 <=
                getUsdValue(),
            "low collateral: cannot withdraw pool funds"
        );
    }

    // allocate rewards
    function allocateReward(int256 amount) external onlyGovernance {
        if (amount > 0) {
            IRiskVault(riskOnPool).setAmounts(
                IRiskVault(riskOnPool).amount1() + uint256(amount / 10),
                IRiskVault(riskOnPool).amount2() + uint256(amount / 10)
            );
            amount = amount * 8 / 10;
        }
        IRiskVault(riskOnPool).allocateReward(amount);
    }

    function claim() external onlyGovernance {
        IRiskVault(riskOnPool).treasuryWithdrawFunds(usdt, IRiskVault(riskOnPool).amount1(), receiver1);
        IRiskVault(riskOnPool).treasuryWithdrawFunds(usdt, IRiskVault(riskOnPool).amount2(), receiver2);
        IRiskVault(riskOnPool).setAmounts(0, 0);
    }

    // deposit funds from gov wallet to treasury
    function deposit(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // deposit ETH from gov wallet to treasury
    function depositETH() external payable onlyGovernance {}

    // withdraw funds(ERC20 tokens) from treasury to the gov wallet
    function withdraw(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    // withdraw funds(ETH) from treasury to the gov wallet
    function withdrawETH(uint256 amount) external nonReentrant onlyGovernance {
        require(amount <= address(this).balance, "insufficient funds");
        Address.sendValue(payable(msg.sender), amount);
    }

    // trigger by the governance wallet at the end of each epoch
    function handleStakeRequest(
        address[] memory _address
    ) external onlyGovernance {
        IRiskVault(riskOnPool).handleStakeRequest(_address);
    }

    // trigger by the governance wallet at the end of each epoch
    function handleWithdrawRequest(
        address[] memory _address
    ) external onlyGovernance {
        IRiskVault(riskOnPool).handleWithdrawRequest(_address);
    }

    function removeWithdrawRequest(
        address[] memory _address
    ) external onlyGovernance {
        IRiskVault(riskOnPool).removeWithdrawRequest(_address);
    }

    function setAaveUserEMode(uint8 categoryId) external onlyGovernance {
        IRiskVault(riskOnPool).setAaveUserEMode(categoryId);
    }

    // trigger by the governance wallet at the end of each epoch
    function updateEpoch() external onlyGovernance {
        require(
            block.timestamp >= nextEpochPoint(),
            "Treasury: not opened yet"
        );
        epoch += 1;
        lastEpochPoint += period;
        emit EpochUpdated(epoch, block.timestamp);
    }

    // update capacity of each pool
    function updateCapacity(uint _riskOnPoolCapacity) external onlyGovernance {
        IRiskVault(riskOnPool).setCapacity(_riskOnPoolCapacity);
    }

    // temporarily halt the system's operations
    function pause() external onlyGovernance {
        IRiskVault(riskOnPool).pause();
    }

    // recover the system's operations
    function unpause() external onlyGovernance {
        IRiskVault(riskOnPool).unpause();
    }

    function addWithdrawWhitelist(address _address) external onlyGovernance {
        require(
            !withdrawWhitelistedAddr[_address],
            "address already in whitelist"
        );
        withdrawWhitelistedAddr[_address] = true;
        withdrawWhitelist.push(_address);
    }

    function removeWithdrawWhitelist(address _address) external onlyGovernance {
        require(withdrawWhitelistedAddr[_address], "address not in whitelist");
        withdrawWhitelistedAddr[_address] = false;
        for (uint i = 0; i < withdrawWhitelist.length; i++) {
            if (withdrawWhitelist[i] == _address) {
                withdrawWhitelist[i] = withdrawWhitelist[
                    withdrawWhitelist.length - 1
                ];
                withdrawWhitelist.pop();
                break;
            }
        }
    }
}

