// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ISharplabs.sol";
import "./AaveLogic.sol";

import "./ContractGuard.sol";
import "./ReentrancyGuard.sol";

import "./Operator.sol";
import "./Blacklistable.sol";
import "./Pausable.sol";

import "./ITreasury.sol";
import "./IAavePoolV3.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3Pool.sol";

import "./Abs.sol";
import "./SafeCast.sol";

import "./ShareWrapper.sol";

// import "hardhat/console.sol";

contract St5Vault is
    ShareWrapper,
    ContractGuard,
    ReentrancyGuard,
    Operator,
    Blacklistable,
    Pausable
{
    using SafeERC20 for IERC20;
    using Address for address;
    using Abs for int256;
    using SafeCast for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        int256 rewardEarned;
        uint256 lastSnapshotIndex;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        int256 rewardReceived;
        int256 rewardPerShare;
        uint256 time;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }

    struct WithdrawInfo {
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }
    
    struct SwapCallbackData {
        bool open;
        uint256 swapMinOut;
        uint256 swapMaxIn;
        uint256 amount;
    }

    /* ========== STATE VARIABLES ========== */

    // reward
    uint256 public totalWithdrawRequest;
    address public token;
    address public treasury;

    uint256 public gasthreshold;
    uint256 public minimumRequest;
    uint256 public minHealthFactor;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => StakeInfo) public stakeRequest;
    mapping(address => WithdrawInfo) public withdrawRequest;

    uint256 public withdrawLockupEpochs;
    uint256 public userExitEpochs;

    uint256 public inFee;
    uint256 public outFee;
    uint256 public capacity;

    // flags
    bool public initialized;

    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public wsteth = 0x5979D7b546E38E414F7E9822514be443A4800529;
    address public usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint16 public referralCode = 0;

    uint256 public uintMax = type(uint256).max;
    uint256 public amount1 = 0;
    uint256 public amount2 = 0;

    uint24 ETH_USDT_fee = 500;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    address wstethPool = 0x35218a1cbaC5Bbc3E57fd9Bd38219D37571b3537;//wstETH-WETH;
    ISwapRouter swapRouter = ISwapRouter(uniV3Router);
    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event WithdrawRequest(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);
    event StakedByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event StakedETHByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event WithdrawRequestedByGov(
        uint256 indexed atEpoch,
        uint256 amount,
        uint256 time
    );
    event WithdrawnByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event RewardPaid(address indexed user, int256 reward);
    event RewardAdded(
        uint256 time,
        uint256 indexed atEpoch,
        uint256 period,
        uint256 totalStakedAmount,
        int256 reward
    );
    event Exit(address indexed user, uint256 amount);
    event StakeRequestIgnored(address indexed ignored, uint256 atEpoch);
    event WithdrawRequestIgnored(address indexed ignored, uint256 atEpoch);
    event HandledStakeRequest(uint256 indexed atEpoch, address[] _address);
    event HandledWithdrawRequest(uint256 indexed atEpoch, address[] _address);
    event HandledReward(uint256 indexed atEpoch, uint256 time);
    event CapacityUpdated(uint256 indexed atEpoch, uint256 _capacity);
    event FeeUpdated(uint256 indexed atEpoch, uint256 _inFee, uint256 _outFee);
    event WithdrawLockupEpochsUpdated(
        uint256 indexed atEpoch,
        uint256 _withdrawLockupEpochs
    );
    event UserExitEpochsUpdated(
        uint256 indexed atEpoch,
        uint256 _userExitEpochs
    );
    event ProtocolFeeUpdated(uint256 indexed atEpoch, uint256 _fee);
    event ProtocolFeeToUpdated(uint256 indexed atEpoch, address _feeTo);
    event AaveV3Updated(uint256 indexed atEpoch, address _aaveV3);
    event TreasuryUpdated(uint256 indexed atEpoch, address _treasury);
    event GasthresholdUpdated(uint256 indexed atEpoch, uint256 _gasthreshold);
    event MinimumRequestUpdated(
        uint256 indexed atEpoch,
        uint256 _minimumRequest
    );
    event MinHealthFactorUpdated(
        uint256 indexed atEpoch,
        uint256 _minHealthFactor
    );

    /* ========== Modifiers =============== */

    modifier onlyTreasury() {
        require(treasury == msg.sender, "caller is not the treasury");
        _;
    }

    modifier memberExists() {
        require(balance_staked(msg.sender) > 0, "The member does not exist");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    receive() external payable {}

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _token,
        uint256 _protocolFee,
        address _protocolFeeTo,
        uint256 _inFee,
        uint256 _outFee,
        uint256 _gasthreshold,
        uint256 _minimumRequset,
        address _treasury
    ) public notInitialized {
        require(_token != address(0), "address can not be zero address");
        require(
            _protocolFeeTo != address(0),
            "address can not be zero address"
        );
        require(
            _treasury != address(0),
            "address can not be zero address"
        );
        token = _token;
        protocolFee = _protocolFee;
        protocolFeeTo = _protocolFeeTo;
        inFee = _inFee;
        outFee = _outFee;
        gasthreshold = _gasthreshold;
        minimumRequest = _minimumRequset;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({
            time: block.number,
            rewardReceived: 0,
            rewardPerShare: 0
        });
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 2; // Lock for 2 epochs (48h) before release withdraw
        userExitEpochs = 4;
        capacity = 10e18;
        minHealthFactor = (110 * 1e18) / 1e2;
        initialized = true;

        emit Initialized(msg.sender, block.number);
    }

    /* ========== CONFIG ========== */

    function pause() external onlyTreasury {
        super._pause();
    }

    function unpause() external onlyTreasury {
        super._unpause();
    }

    function setLockUp(uint256 _withdrawLockupEpochs) external onlyOperator {
        withdrawLockupEpochs = _withdrawLockupEpochs;
        emit WithdrawLockupEpochsUpdated(epoch(), _withdrawLockupEpochs);
    }

    function setExitEpochs(uint256 _userExitEpochs) external onlyOperator {
        require(
            _userExitEpochs > 0,
            "userExitEpochs must be greater than zero"
        );
        userExitEpochs = _userExitEpochs;
        emit UserExitEpochsUpdated(epoch(), _userExitEpochs);
    }

    function setProtocolFee(uint256 _fee) external onlyOperator {
        require(_fee <= 500, "protocolFee: out of range");
        protocolFee = _fee;
        emit ProtocolFeeUpdated(epoch(), _fee);
    }

    function setProtocolFeeTo(address _feeTo) external onlyOperator {
        require(_feeTo != address(0), "address can not be zero address");
        protocolFeeTo = _feeTo;
        emit ProtocolFeeToUpdated(epoch(), _feeTo);
    }

    function setCapacity(uint256 _capacity) external onlyTreasury {
        capacity = _capacity;
        emit CapacityUpdated(epoch(), _capacity);
    }

    function setFee(uint256 _inFee, uint256 _outFee) external onlyTreasury {
        require(_inFee <= 500, "inFee: out of range");
        require(_outFee <= 500, "outFee: out of range");
        inFee = _inFee;
        outFee = _outFee;
        emit FeeUpdated(epoch(), _inFee, _outFee);
    }

    function setAaveV3(address _aaveV3) external onlyOperator {
        require(_aaveV3 != address(0), "address can not be zero address");
        aaveV3 = _aaveV3;
        emit AaveV3Updated(epoch(), _aaveV3);
    }

    function setTreasury(address _treasury) external onlyOperator {
        require(_treasury != address(0), "address can not be zero address");
        treasury = _treasury;
        emit TreasuryUpdated(epoch(), _treasury);
    }

    function setGasThreshold(uint256 _gasthreshold) external onlyOperator {
        gasthreshold = _gasthreshold;
        emit GasthresholdUpdated(epoch(), _gasthreshold);
    }

    function setMinimumRequest(uint256 _minimumRequest) external onlyOperator {
        minimumRequest = _minimumRequest;
        emit MinimumRequestUpdated(epoch(), _minimumRequest);
    }

    function setMinHealthFactor(
        uint256 _minHealthFactor
    ) external onlyOperator {
        require(
            minHealthFactor >= (110 * 1e18) / 1e2,
            "minHealthFactor must be greater than 110%"
        );
        minHealthFactor = _minHealthFactor;
        emit MinHealthFactorUpdated(epoch(), _minHealthFactor);
    }

    function setReferralCode(uint16 _referralCode) external onlyTreasury {
        referralCode = _referralCode;
    }

    function setETH_USDT_fee(uint24 _ETH_USDT_fee) external onlyOperator {
        ETH_USDT_fee = _ETH_USDT_fee;
    }

    function setWstethPool(address _wstethPool) external onlyOperator {
        wstethPool = _wstethPool;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length - 1;
    }

    function getLatestSnapshot()
        internal
        view
        returns (BoardroomSnapshot memory)
    {
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(
        address member
    ) public view returns (uint256) {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(
        address member
    ) internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[getLastSnapshotIndexOf(member)];
    }

    function canWithdraw(address member) external view returns (bool) {
        return
            members[member].epochTimerStart + withdrawLockupEpochs <= epoch();
    }

    function epoch() public view returns (uint256) {
        return ITreasury(treasury).epoch();
    }

    function nextEpochPoint() public view returns (uint256) {
        return ITreasury(treasury).nextEpochPoint();
    }

    function wsteth_price() public view returns (uint256) {
        return ITreasury(treasury).wstETH_price();
    }

    // =========== Member getters

    function rewardPerShare() public view returns (int256) {
        return getLatestSnapshot().rewardPerShare;
    }

    // calculate earned reward of specified user
    function earned(address member) public view returns (int256) {
        int256 latestRPS = getLatestSnapshot().rewardPerShare;
        int256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return
            (balance_staked(member).toInt256() * (latestRPS - storedRPS)) /
            1e18 +
            members[member].rewardEarned;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(
        uint256 _amount
    )
        public
        payable
        override
        onlyOneBlock
        notBlacklisted(msg.sender)
        whenNotPaused
    {
        require(_amount >= minimumRequest, "stake amount too low");
        require(
            _totalSupply.staked + _totalSupply.wait + _amount <= capacity,
            "stake no capacity"
        );
        require(msg.value >= gasthreshold, "need more gas to handle request");
        if (protocolFee > 0) {
            uint tax = (_amount * protocolFee) / 10000;
            _amount = _amount - tax;
            IERC20(share).safeTransferFrom(msg.sender, protocolFeeTo, tax);
        }
        if (inFee > 0) {
            uint _inFee = (_amount * inFee) / 10000;
            _amount = _amount - _inFee;
            IERC20(share).safeTransferFrom(msg.sender, address(this), _inFee);
        }
        super.stake(_amount);
        stakeRequest[msg.sender].amount += _amount;
        stakeRequest[msg.sender].requestTimestamp = block.timestamp;
        stakeRequest[msg.sender].requestEpoch = epoch();
        ISharplabs(token).mint(msg.sender, _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw_request(
        uint256 _amount
    ) external payable memberExists notBlacklisted(msg.sender) whenNotPaused {
        require(_amount != 0, "withdraw request cannot be equal to 0");
        require(
            _amount + withdrawRequest[msg.sender].amount <=
                _balances[msg.sender].staked,
            "withdraw amount exceeds the staked balance"
        );
        require(
            members[msg.sender].epochTimerStart + withdrawLockupEpochs <=
                epoch(),
            "still in withdraw lockup"
        );
        require(msg.value >= gasthreshold, "need more gas to handle request");
        withdrawRequest[msg.sender].amount += _amount;
        withdrawRequest[msg.sender].requestTimestamp = block.timestamp;
        withdrawRequest[msg.sender].requestEpoch = epoch();
        totalWithdrawRequest += _amount;
        emit WithdrawRequest(msg.sender, _amount);
    }

    function withdraw(
        uint256 amount
    ) public override onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        require(amount != 0, "cannot withdraw 0");
        super.withdraw(amount);
        try ISharplabs(token).burn(msg.sender, amount) {} catch {}
        emit Withdrawn(msg.sender, amount);
    }

    function redeem()
        external
        onlyOneBlock
        notBlacklisted(msg.sender)
        whenNotPaused
    {
        uint256 _epoch = epoch();
        require(
            _epoch == stakeRequest[msg.sender].requestEpoch,
            "can not redeem"
        );
        uint amount = balance_wait(msg.sender);
        _balances[msg.sender].wait -= amount;
        _totalSupply.wait -= amount;
        IERC20(share).safeTransfer(msg.sender, amount);
        try ISharplabs(token).burn(msg.sender, amount) {} catch {}
        delete stakeRequest[msg.sender];
        emit Redeemed(msg.sender, amount);
    }

    function handleStakeRequest(
        address[] memory _address
    ) external onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = stakeRequest[user].amount;
            if (stakeRequest[user].requestEpoch == _epoch) {
                // check latest epoch
                emit StakeRequestIgnored(user, _epoch);
                continue;
            }
            if (stakeRequest[user].requestTimestamp == 0) {
                continue;
            }
            updateReward(user);
            _balances[user].wait -= amount;
            _balances[user].staked += amount;
            _totalSupply.wait -= amount;
            _totalSupply.staked += amount;
            members[user].epochTimerStart = _epoch - 1; // reset timer
            delete stakeRequest[user];
        }
        emit HandledStakeRequest(_epoch, _address);
    }

    function handleWithdrawRequest(
        address[] memory _address
    ) external onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            uint amountReceived = amount; // user real received amount
            if (withdrawRequest[user].requestEpoch == _epoch) {
                // check latest epoch
                emit WithdrawRequestIgnored(user, _epoch);
                continue;
            }
            if (withdrawRequest[user].requestTimestamp == 0) {
                continue;
            }
            claimReward(user);
            if (outFee > 0) {
                uint _outFee = (amount * outFee) / 10000;
                try ISharplabs(token).burn(user, _outFee) {} catch {}
                amountReceived = amount - _outFee;
            }
            _balances[user].staked -= amount;
            _balances[user].withdrawable += amountReceived;
            _totalSupply.staked -= amount;
            _totalSupply.withdrawable += amountReceived;
            totalWithdrawRequest -= amount;
            members[user].epochTimerStart = _epoch - 1; // reset timer
            delete withdrawRequest[user];
        }
        emit HandledWithdrawRequest(_epoch, _address);
    }

    function removeWithdrawRequest(
        address[] memory _address
    ) external onlyTreasury {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            totalWithdrawRequest -= amount;
            delete withdrawRequest[user];
        }
    }

    function updateReward(address member) internal {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
    }

    function claimReward(address member) internal returns (int) {
        updateReward(member);
        int256 reward = members[member].rewardEarned;
        members[member].rewardEarned = 0;
        _balances[member].reward += reward;
        emit RewardPaid(member, reward);
        return reward;
    }

    function setAmounts(uint256 _amount1, uint256 _amount2) external onlyTreasury {
        amount1 = _amount1;
        amount2 = _amount2;
    }

    function allocateReward(int256 amount) external onlyOneBlock onlyTreasury {
        require(total_supply_staked() > 0, "totalSupply is 0");

        // Create & add new snapshot
        int256 prevRPS = getLatestSnapshot().rewardPerShare;
        int256 nextRPS = prevRPS +
            (amount * 1e18) /
            total_supply_staked().toInt256();

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardroomHistory.push(newSnapshot);

        _totalSupply.reward += amount;
        emit RewardAdded(
            block.number,
            epoch(),
            ITreasury(treasury).period(),
            total_supply_staked(),
            amount
        );
    }

    // 0: Disable E-Mode, 1: stable coin, 2: eth correlated
    function setAaveUserEMode(uint8 categoryId) external onlyTreasury {
        AaveLogic.setUserEMode(aaveV3, minHealthFactor, categoryId);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) public {
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        if (data.open){
            // wstETH-WETH pool: zeroForOne = false
            AaveLogic.supply(aaveV3, wsteth, uint256(-amount0Delta), referralCode);
            if (data.swapMaxIn > data.amount){
                IAavePoolV3(aaveV3).borrow(usdt,data.swapMaxIn - data.amount,2,referralCode,address(this));
            }
            
            IERC20(usdt).safeApprove(uniV3Router, 0);
            IERC20(usdt).safeApprove(uniV3Router, data.swapMaxIn);
            uint256 amountIn = swapRouter.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: usdt,
                    tokenOut: weth,
                    fee: ETH_USDT_fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: uint256(amount1Delta),
                    amountInMaximum: data.swapMaxIn,
                    sqrtPriceLimitX96: 0
                })
            );
            uint256 reapyAmount;
            if (data.swapMaxIn > data.amount){
                reapyAmount = data.swapMaxIn - amountIn;
            }else{
                reapyAmount = data.amount - amountIn;
            }
            if (IERC20(IAavePoolV3(aaveV3).getReserveData(usdt).variableDebtTokenAddress).balanceOf(address(this)) > 0){
                AaveLogic.repay(aaveV3, usdt, reapyAmount);
            }
            IERC20(weth).safeTransfer(wstethPool, uint256(amount1Delta));
        }else{
            // wstETH-WETH pool: zeroForOne = true
            IERC20(weth).safeApprove(uniV3Router, 0);
            IERC20(weth).safeApprove(uniV3Router, uint256(-amount1Delta));
            uint256 amountOut = swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: weth,
                    tokenOut: usdt,
                    fee: ETH_USDT_fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: uint256(-amount1Delta),
                    amountOutMinimum: data.swapMinOut,
                    sqrtPriceLimitX96: 0
                })
            );
            // data.amount: withdrawAmount
            if (amountOut > data.amount){
                if (amountOut - data.amount > 1e6){
                    AaveLogic.repay(aaveV3, usdt, amountOut - data.amount);
                }
            }else{
                AaveLogic.borrow(aaveV3, minHealthFactor, usdt, data.amount - amountOut, referralCode);
            }
            IAavePoolV3(aaveV3).withdraw(AaveLogic.withdrawArgs(AaveLogic.getAssetId(aaveV3, wsteth), uint256(amount0Delta)));
            IERC20(wsteth).safeTransfer(wstethPool, uint256(amount0Delta));
        }
    }

    function open(uint256 _openAmount, uint256 _swapMaxIn, uint256 _repayAmount)external onlyTreasury {
        IUniswapV3Pool(wstethPool).swap(
            address(this),
            false,
            -_openAmount.toInt256(),
            MAX_SQRT_RATIO - 1,
            abi.encode(
                SwapCallbackData({
                    open: true,
                    swapMinOut: 0,
                    swapMaxIn: _swapMaxIn,
                    amount: _repayAmount
                })
            )
        );
        (, , , , , uint256 healthFactor) = IAavePoolV3(aaveV3).getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
    }

    function close(uint256 _closeAmount, uint256 _swapMinOut, uint256 _withdrawAmount)external onlyTreasury {
        IUniswapV3Pool(wstethPool).swap(
            address(this),
            true,
            _closeAmount.toInt256(),
            MIN_SQRT_RATIO + 1,
            abi.encode(
                SwapCallbackData({
                    open: false,
                    swapMinOut: _swapMinOut,
                    swapMaxIn: 0,
                    amount: _withdrawAmount
                })
            )
        );

        (, , , , , uint256 healthFactor) = IAavePoolV3(aaveV3).getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
    }

    function supplyAave(
        address _supplyToken,
        uint256 _supplyAmount
    ) public onlyTreasury {
        AaveLogic.supply(aaveV3, _supplyToken, _supplyAmount, referralCode);
    }

    function borrowAave(
        address _borrowToken,
        uint256 _borrowAmount
    ) public onlyTreasury {
        AaveLogic.borrow(aaveV3, minHealthFactor, _borrowToken, _borrowAmount, referralCode);
    }

    function repayAave(address _repayToken, uint256 _repayAmount) public onlyTreasury  {
        AaveLogic.repay(aaveV3, _repayToken, _repayAmount);
    }

    function withdrawAave(
        address _withdrawToken,
        uint256 _withdrawAmount
    ) public onlyTreasury {
        AaveLogic.withdraw(aaveV3, minHealthFactor, _withdrawToken, _withdrawAmount);
    }

    function treasuryWithdrawFunds(
        address _token,
        uint256 amount,
        address to
    ) external onlyTreasury {
        require(to != address(0), "address can not be zero address");
        IERC20(_token).safeTransfer(to, amount);
    }

    function treasuryWithdrawFundsETH(
        uint256 amount,
        address to
    ) external nonReentrant onlyTreasury {
        require(to != address(0), "address can not be zero address");
        Address.sendValue(payable(to), amount);
    }
}
