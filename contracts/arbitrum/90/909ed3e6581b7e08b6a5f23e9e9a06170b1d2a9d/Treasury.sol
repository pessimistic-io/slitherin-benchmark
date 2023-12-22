// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IRiskVault.sol";
import "./Operator.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IAavePoolV3.sol";
import "./IGlpVault.sol";
import "./Abs.sol";
import "./IAavePoolV3.sol";
import "./ISwapRouter.sol";

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

    address public share;
    address public governance;
    address public riskOnPool;

    uint256 public epoch;
    uint256 public startTime;
    uint256 public period = 24 hours;
    uint256 public riskOnPoolRatio;
    uint256 public lastEpochPoint;

    // flags
    bool public initialized = false;
    address public weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public glpVault = address(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    address public aaveV3 = address(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    address public usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address public uniV3Router = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public usdcRiskOnVault = address(0x07Cf4384b5B5Bb90c796b7C23986A4f12898BcAC);
    address[] public withdrawWhitelist;
    mapping (address => bool) public withdrawWhitelistedAddr; 

    event Initialized(address indexed executor, uint256 at);
    event EpochUpdated(uint256 indexed atEpoch, uint256 timestamp);

    modifier onlyGovernance() {
        require(governance == msg.sender, "caller is not the governance");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    event GlpVaultUpdated(uint256 indexed atEpoch, address _glpVault);
    event AaveV3Updated(uint256 indexed atEpoch, address _aaveV3);

    receive() payable external {}
    
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
        require(_riskOnPool != address(0), "pool address cannot be zero address");
        riskOnPool = _riskOnPool;
    }

    function setRiskOnPoolRatio(uint _riskOnPoolRatio) external onlyGovernance {
        require(_riskOnPoolRatio > 0, "ratio cannot be zero");
        riskOnPoolRatio = _riskOnPoolRatio;
    }

    function setGlpFee(uint _glpInFee, uint _glpOutFee) external onlyGovernance {
        IRiskVault(riskOnPool).setGlpFee(_glpInFee, _glpOutFee);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == operator() || msg.sender == governance);
        require(_governance != address(0), "governance address cannot be zero address");
        governance = _governance;
    }

    function setGlpVault(address _glpVault) external onlyOperator {
        require(_glpVault != address(0), "address can not be zero address");
        glpVault = _glpVault;
        emit GlpVaultUpdated(epoch, _glpVault);
    }

    function setAaveV3(address _aaveV3) external onlyOperator {
        require(_aaveV3 != address(0), "address can not be zero address");
        aaveV3 = _aaveV3;
        emit AaveV3Updated(epoch, _aaveV3);
    }

    function initialize(
        address _share,
        address _governance,
        address _riskOnPool,
        uint256 _riskOnPoolRatio,
        uint256 _startTime
    ) public notInitialized {
        require(_share != address(0), "share address can not be zero address");
        require(_governance != address(0), "governance address can not be zero address");
        require(_riskOnPool != address(0), "riskOnPool address can not be zero address");
        share = _share;
        governance = _governance;
        riskOnPool = _riskOnPool;
        riskOnPoolRatio = _riskOnPoolRatio;
        startTime = _startTime;
        lastEpochPoint = _startTime;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function weth_price() public view returns (uint256) {
        return IGlpVault(glpVault).getMinPrice(weth);
    }

    function weth_price_precision() public view  returns (uint256) {
        return IGlpVault(glpVault).PRICE_PRECISION();
    }

    function wsteth_price() public view returns (uint256) {
        return weth_price() * IRiskVault(riskOnPool).share_price() / 10 ** IRiskVault(riskOnPool).share_price_decimals();
    }

    function wsteth_price_precision() public view returns (uint256) {
        return weth_price_precision();
    }

    // required usd collateral in the contract with 1e18 precision
    function getRequiredUsdCollateral() public view returns (uint256) {
        IRiskVault vault = IRiskVault(riskOnPool);
        uint256 wstethValue = (vault.total_supply_wait() + vault.total_supply_staked() + vault.total_supply_withdraw()) * (wsteth_price() * 1e6 / wsteth_price_precision()) / 1e6;
        if (vault.total_supply_reward() >= 0) {
            return wstethValue + vault.total_supply_reward().abs() * weth_price() / weth_price_precision();
        } else {
            return wstethValue - vault.total_supply_reward().abs() * weth_price() / weth_price_precision();
        }
    }

    // get total usd value in the contract with 1e18 precision
    function getUsdValue() public view returns (uint256){
        (uint256 totalCollateralBase,uint256 totalDebtBase,,,,) = IAavePoolV3(aaveV3).getUserAccountData(riskOnPool);
        uint256 aaveValue = (totalCollateralBase - totalDebtBase) * 1e10;
        // tokenValue: wstETH, WETH, ETH, USDC
        uint256 tokenValue = IERC20(share).balanceOf(riskOnPool) * wsteth_price() / wsteth_price_precision();
        tokenValue = tokenValue + IERC20(weth).balanceOf(riskOnPool) * weth_price() / weth_price_precision();
        tokenValue = tokenValue + riskOnPool.balance * weth_price() / weth_price_precision();
        tokenValue = tokenValue + IERC20(usdc).balanceOf(riskOnPool) * 1e12;

        IRiskVault vault = IRiskVault(usdcRiskOnVault);
        uint256 stakedValue = vault.balance_wait(riskOnPool) * 1e12;
        stakedValue = stakedValue + vault.balance_staked(riskOnPool) * 1e12;
        stakedValue = stakedValue + vault.balance_withdraw(riskOnPool) * 1e12;
        int256 _reward = vault.balance_reward(riskOnPool);
        if (_reward >= 0){
            stakedValue = stakedValue + _reward.abs() * 1e12;
        }else{
            stakedValue = stakedValue - _reward.abs() * 1e12;
        }
        return aaveValue + tokenValue + stakedValue;
    }


    function supplyBorrow(uint256 _supplyAmount, uint256 _borrowAmount, uint16 _referralCode) external onlyGovernance {
        IRiskVault(riskOnPool).supplyBorrow(_supplyAmount, _borrowAmount, _referralCode);
    }

    function repayWithdraw(uint256 _repayAmount, uint256 _withdrawAmount) external onlyGovernance {
        IRiskVault(riskOnPool).repayWithdraw(_repayAmount, _withdrawAmount);
    }
    
    function stakeRiskOn(uint256 _amount) external onlyGovernance {
        IRiskVault(riskOnPool).stakeByGov(_amount);
    }

    function withdrawRequestRiskOn(uint256 _amount) external onlyGovernance {
        IRiskVault(riskOnPool).withdrawRequestByGov(_amount);
    }

    function withdrawRiskOn(uint256 _amount) external onlyGovernance {
        IRiskVault(riskOnPool).withdrawByGov(_amount);
    }

    // send funds(ERC20 tokens) to pool
    function sendPoolFunds(address _token, uint _amount) external onlyGovernance {
        require(_amount <= IERC20(_token).balanceOf(address(this)), "insufficient funds");
        IERC20(_token).safeTransfer(riskOnPool, _amount);
    }

    // send funds(ETH) to pool
    function sendPoolFundsETH(uint _amount) external onlyGovernance {
        require(_amount <= address(this).balance, "insufficient funds");
        Address.sendValue(payable(riskOnPool), _amount);
    }


    // withdraw pool funds(ERC20 tokens) to specified address
    function withdrawPoolFunds(address _token, uint256 _amount, address _to) external onlyGovernance {
        if (_to != governance){
            require(withdrawWhitelistedAddr[_to], "address not in whitelist");
        }
        IRiskVault(riskOnPool).treasuryWithdrawFunds(_token, _amount, _to);
        require(getRequiredUsdCollateral() * riskOnPoolRatio / 100 <= getUsdValue(), "low collateral: cannot withdraw pool funds");
    }

    // withdraw pool funds(ETH) to specified address
    function withdrawPoolFundsWETHToETH(uint256 _amount, address _to) external onlyGovernance {
        if (_to != governance){
            require(withdrawWhitelistedAddr[_to], "address not in whitelist");
        }
        IRiskVault(riskOnPool).treasuryWithdrawFundsWETHToETH(_amount, _to);
        require(getRequiredUsdCollateral() * riskOnPoolRatio / 100 <= getUsdValue(), "low collateral: cannot withdraw pool funds");
    }

    // withdraw pool funds(ETH) to specified address
    function withdrawPoolFundsETH(uint _amount, address _to) external onlyGovernance {
        if (_to != governance){
            require(withdrawWhitelistedAddr[_to], "address not in whitelist");
        }
        require(_amount <= riskOnPool.balance, "insufficient funds");
        IRiskVault(riskOnPool).treasuryWithdrawFundsETH(_amount, _to);
        require(getRequiredUsdCollateral() * riskOnPoolRatio / 100 <= getUsdValue(), "low collateral: cannot withdraw pool funds");
    }

    function swapPoolWethToToken(uint256 wethAmount, address _token, uint256 minAmountOut, uint24 _fee) external onlyGovernance {
        IRiskVault(riskOnPool).treasuryWithdrawFunds(weth, wethAmount, address(this));
        ISwapRouter swapRouter = ISwapRouter(uniV3Router);
        IERC20(weth).safeApprove(uniV3Router, 0);
        IERC20(weth).safeApprove(uniV3Router, wethAmount);
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: _token,
                fee: _fee,
                recipient: riskOnPool,
                deadline: block.timestamp,
                amountIn: wethAmount,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        require(getRequiredUsdCollateral() * riskOnPoolRatio / 100 <= getUsdValue(), "low collateral: cannot withdraw pool funds");
    }

    function swapPoolTokenToWeth(address _token, uint256 _tokenAmount, uint256 minWethAmountOut, uint24 _fee) external onlyGovernance {
        IRiskVault(riskOnPool).treasuryWithdrawFunds(_token, _tokenAmount, address(this));
        ISwapRouter swapRouter = ISwapRouter(uniV3Router);
        IERC20(_token).safeApprove(uniV3Router, 0);
        IERC20(_token).safeApprove(uniV3Router, _tokenAmount);
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _token,
                tokenOut: weth,
                fee: _fee,
                recipient: riskOnPool,
                deadline: block.timestamp,
                amountIn: _tokenAmount,
                amountOutMinimum: minWethAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
        require(getRequiredUsdCollateral() * riskOnPoolRatio / 100 <= getUsdValue(), "low collateral: cannot withdraw pool funds");
    }

    // allocate rewards
    function allocateReward(int256 amount) external onlyGovernance {
        IRiskVault(riskOnPool).allocateReward(amount);
    }

    // deposit funds from gov wallet to treasury
    function deposit(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // deposit ETH from gov wallet to treasury
    function depositETH() payable external onlyGovernance {
        
    }

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
    function handleStakeRequest(address[] memory _address) external onlyGovernance {
        IRiskVault(riskOnPool).handleStakeRequest(_address);
    }

    // trigger by the governance wallet at the end of each epoch
    function handleWithdrawRequest(address[] memory _address) external onlyGovernance {
        IRiskVault(riskOnPool).handleWithdrawRequest(_address);
    }
    
    function removeWithdrawRequest(address[] memory _address) external onlyGovernance {
        IRiskVault(riskOnPool).removeWithdrawRequest(_address);
    }

    function setAaveUserEMode(uint8 categoryId) external onlyGovernance {
        IRiskVault(riskOnPool).setAaveUserEMode(categoryId);
    }

    // trigger by the governance wallet at the end of each epoch
    function updateEpoch() external onlyGovernance {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");
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
        require(!withdrawWhitelistedAddr[_address], "address already in whitelist");
        withdrawWhitelistedAddr[_address] = true;
        withdrawWhitelist.push(_address);
    }

    function removeWithdrawWhitelist(address _address) external onlyGovernance {
        require(withdrawWhitelistedAddr[_address], "address not in whitelist");
        withdrawWhitelistedAddr[_address] = false;
        for (uint i = 0; i < withdrawWhitelist.length; i++) {
            if (withdrawWhitelist[i] == _address) {
                withdrawWhitelist[i] = withdrawWhitelist[withdrawWhitelist.length - 1];
                withdrawWhitelist.pop();
                break;
            }
        }
    }
}
