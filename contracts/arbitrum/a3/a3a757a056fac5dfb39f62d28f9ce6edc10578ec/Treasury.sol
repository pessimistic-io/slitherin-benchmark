// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IGLPPool.sol";
import "./Operator.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

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

    address public share;
    address public governance;
    address public riskOffPool;
    address public riskOnPool;

    uint256 public epoch;
    uint256 public startTime;
    uint256 public period = 24 hours;
    uint256 public riskOnPoolRatio;
    uint256 public lastEpochPoint;

    // flags
    bool public initialized = false;

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

    function setPool(address _riskOffPool, address _riskOnPool) external onlyOperator {
        require(_riskOffPool != address(0) && _riskOnPool != address(0), "pool address cannot be zero address");
        riskOffPool = _riskOffPool;
        riskOnPool = _riskOnPool;
    }

    function setRiskOnPoolRatio(uint _riskOnPoolRatio) external onlyGovernance {
        require(_riskOnPoolRatio > 0, "ratio cannot be zero");
        riskOnPoolRatio = _riskOnPoolRatio;
    }

    function setGlpFee(uint _glpInFee, uint _glpOutFee) external onlyGovernance {
        IGLPPool(riskOffPool).setGlpFee(_glpInFee, _glpOutFee);
        IGLPPool(riskOnPool).setGlpFee(_glpInFee, _glpOutFee);
    }

    function setGovernance(address _governance) external {
        require(msg.sender == operator() || msg.sender == governance);
        require(_governance != address(0), "governance address cannot be zero address");
        governance = _governance;
    }

    function initialize(
        address _share,
        address _governance, 
        address _riskOffPool, 
        address _riskOnPool,
        uint256 _riskOnPoolRatio,
        uint256 _startTime
    ) public notInitialized {
        require(_share != address(0), "share address can not be zero address");
        require(_governance != address(0), "governance address can not be zero address");
        require(_riskOffPool != address(0), "riskOffPool address can not be zero address");
        require(_riskOnPool != address(0), "riskOnPool address can not be zero address");
        share = _share;
        governance = _governance;
        riskOffPool = _riskOffPool;
        riskOnPool = _riskOnPool;
        riskOnPoolRatio = _riskOnPoolRatio;
        startTime = _startTime;
        lastEpochPoint = _startTime;
        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function buyGLP(
        address _glpPool, 
        address _token, 
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp
    ) external onlyGovernance {
        IGLPPool(_glpPool).stakeByGov(_token, _amount, _minUsdg, _minGlp);
    }

    function buyGLPWithETH(
        address _glpPool,
        uint256 _amount, 
        uint256 _minUsdg, 
        uint256 _minGlp
    ) external onlyGovernance {
        IGLPPool(_glpPool).stakeETHByGov(_amount, _minUsdg, _minGlp);
    }

    function sellGLP(
        address _glpPool, 
        address _tokenOut, 
        uint256 _glpAmount, 
        uint256 _minOut, 
        address _receiver
    ) external onlyGovernance {
        require(_glpPool == _receiver, "receiver must be equal to glpPool ");
        IGLPPool(_glpPool).withdrawByGov(_tokenOut, _glpAmount, _minOut, _receiver);
    }

    // send funds(ERC20 tokens) to pool
    function sendPoolFunds(address _pool, address _token, uint _amount) external onlyGovernance {
        require(_pool != address(0), "pool address can not be zero address");
        require(_amount <= IERC20(_token).balanceOf(address(this)), "insufficient funds");
        IERC20(_token).safeTransfer(_pool, _amount);
    }

    // send funds(ETH) to pool
    function sendPoolFundsETH(address _pool, uint _amount) external onlyGovernance {
        require(_pool != address(0), "pool address can not be zero address");
        require(_amount <= address(this).balance, "insufficient funds");
        Address.sendValue(payable(_pool), _amount);
    }

    // withdraw pool funds(ERC20 tokens) to specified address
    function withdrawPoolFunds(address _pool, address _token, uint256 _amount, address _to, bool _maximum) external onlyGovernance {
        if (_pool == riskOffPool && _token == share) {
            uint shareAmount = IERC20(share).balanceOf(_pool);
            require(IGLPPool(_pool).getRequiredCollateral() + _amount <= IGLPPool(_pool).getStakedGLPUSDValue(_maximum) + shareAmount, "low collateral: cannot withdraw pool funds");
        }
        if (_pool == riskOnPool && _token == share) {
            uint shareAmount = IERC20(share).balanceOf(_pool);
            require(IGLPPool(_pool).getRequiredCollateral() * riskOnPoolRatio / 100 + _amount <= IGLPPool(_pool).getStakedGLPUSDValue(_maximum) + shareAmount, "low collateral: cannot withdraw pool funds");
        }
        IGLPPool(_pool).treasuryWithdrawFunds(_token, _amount, _to);
    }

    // withdraw pool funds(ETH) to specified address
    function withdrawPoolFundsETH(address _pool, uint _amount, address _to) external onlyGovernance {
        require(_amount <= _pool.balance, "insufficient funds");
        IGLPPool(_pool).treasuryWithdrawFundsETH(_amount, _to);
    }

    // allocate rewards
    function allocateReward(address _pool, int256 _amount) external onlyGovernance {
        IGLPPool(_pool).allocateReward(_amount);
    }

    // deposit funds from gov wallet to treasury
    function deposit(address _token, uint256 amount) external onlyGovernance {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), amount);
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
    function handleStakeRequest(address _pool, address[] memory _address) external onlyGovernance {
        IGLPPool(_pool).handleStakeRequest(_address);
    }

    // trigger by the governance wallet at the end of each epoch
    function handleWithdrawRequest(address _pool, address[] memory _address) external onlyGovernance {
        IGLPPool(_pool).handleWithdrawRequest(_address);
    }
    
    function removeWithdrawRequest(address _pool, address[] memory _address) external onlyGovernance {
        IGLPPool(_pool).removeWithdrawRequest(_address);
    }

    // handle the glp pool's rewards to reinvest
    function handleRewards(
        address _pool,
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external onlyGovernance {
        IGLPPool(_pool).handleRewards(
            _shouldClaimGmx,
            _shouldStakeGmx,
            _shouldClaimEsGmx,
            _shouldStakeEsGmx,
            _shouldStakeMultiplierPoints,
            _shouldClaimWeth,
            _shouldConvertWethToEth);
    }

    // trigger by the governance wallet at the end of each epoch
    function updateEpoch() external onlyGovernance {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");
        epoch += 1;
        lastEpochPoint += period;
        emit EpochUpdated(epoch, block.timestamp);
    }

    // update capacity of each pool
    function updateCapacity(uint _riskOffPoolCapacity, uint _riskOnPoolCapacity) external onlyGovernance {
        IGLPPool(riskOffPool).setCapacity(_riskOffPoolCapacity);
        IGLPPool(riskOnPool).setCapacity(_riskOnPoolCapacity);
    } 

    // temporarily halt the system's operations
    function pause(address _pool) external onlyGovernance {
        IGLPPool(_pool).pause();
    }

    // recover the system's operations
    function unpause(address _pool) external onlyGovernance {
        IGLPPool(_pool).unpause();
    }
}
