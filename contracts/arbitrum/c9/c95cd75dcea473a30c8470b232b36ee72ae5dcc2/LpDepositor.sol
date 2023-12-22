// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IRewardPool.sol";
import "./ISolidlyRouter.sol";
import "./ISolidLizardProxy.sol";
import "./IDepositToken.sol";
import "./IChamSLIZ.sol";
import "./IFeeConfig.sol";
import "./Math.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract LpDepositor is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable WETH;
    IERC20 public immutable SLIZ;
    IChamSLIZ public immutable chamSLIZ;
    ISolidLizardProxy public immutable proxy;
    IRewardPool public rewardPool;
    IFeeConfig public coFeeConfig;

    ISolidlyRouter public router;
    ISolidlyRouter.Routes[] public slizToWethRoute;

    address public immutable depositTokenImplementation;
    address public coFeeRecipient;
    address public polWallet;

    uint256 public pendingFeeSLIZ;
    uint256 public lastFeeTransfer;

    uint256 public constant MAX = 10000; // 100%
    uint256 public constant MAX_RATE = 1e18;

    bool public harvestOnDeposit;
    bool public useFixedBoostedFlag = true;
    uint256 public fixedBoostedPercent = 2000; // 20%
    uint256 public feeBoostedPercent = 2000; // 20%
    uint256 public rewardPoolRate = 2000; // 20%

    // pool -> deposit token
    mapping(address => address) public depositTokens;
    // user -> pool -> deposit amount
    mapping(address => mapping(address => uint256)) public userBalances;
    // pool -> total deposit amount
    mapping(address => uint256) public totalBalances;

    // pool -> integrals
    mapping(address => uint256) rewardIntegral;
    // user -> pool -> integrals
    mapping(address => mapping(address => uint256)) rewardIntegralFor;
    // user -> pool -> claimable
    mapping(address => mapping(address => uint256)) unclaimedRewards;

    event Deposit(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 amount
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 amount
    );

    event Claimed(
        address indexed caller,
        address indexed receiver,
        address[] tokens,
        uint256 slizAmount
    );

    event TransferDeposit(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event SetUseFixedBoostedFlag(bool _enabled);
    event SetFixedBoostedPercent(uint256 oldRate, uint256 newRate);
    event SetFeeBoostedPercent(uint256 oldRate, uint256 newRate);
    event SetHarvestOnDeposit(bool isEnabled);
    event SetCoFeeRecipient(address oldFeeRecipient, address newFeeRecipient);
    event SetFeeId(uint256 newFeeId);
    event SetRewardPoolRate(uint256 oldRewardPoolRate, uint256 newRewardPoolRate);
    event SetRewardPool(IRewardPool oldRewardPool, IRewardPool newRewardPool);
    event SetPolWallet(address oldValue, address newValue);
    event SetRouterAndRoute(
        ISolidlyRouter _router,
        ISolidlyRouter.Routes[] _route
    );

    constructor(
        IERC20 _WETH,
        IERC20 _SLIZ,
        ISolidLizardProxy _proxy,
        IChamSLIZ _chamSLIZ,
        IRewardPool _rewardPool,
        IFeeConfig _coFeeConfig,
        address _coFeeRecipient,
        address _depositTokenImplementation,
        address _polWallet,
        ISolidlyRouter _router,
        ISolidlyRouter.Routes[] memory _slizToWethRoute
    ) {
        WETH = _WETH;
        SLIZ = _SLIZ;
        proxy = _proxy;
        chamSLIZ = _chamSLIZ;
        rewardPool = _rewardPool;
        coFeeConfig = _coFeeConfig;
        coFeeRecipient = _coFeeRecipient;
        depositTokenImplementation = _depositTokenImplementation;
        polWallet = _polWallet;
        for (uint i; i < _slizToWethRoute.length; i++) {
            slizToWethRoute.push(_slizToWethRoute[i]);
        }
        router = _router;
        SLIZ.approve(address(chamSLIZ), type(uint256).max);
        SLIZ.approve(address(_router), type(uint256).max);
    }

    function claimable(address _user, address[] calldata _tokens) external view returns (uint256[] memory) {
        uint256[] memory pending = new uint256[](_tokens.length);
        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint256 totalClaimable = proxy.claimableReward(token);
            pending[i] = unclaimedRewards[_user][token];
            uint256 balance = userBalances[_user][token];
            if (balance == 0) continue;

            uint256 integralReward = rewardIntegral[token];
            uint256 total = totalBalances[token];
            if (total > 0) {
                uint256 reward = totalClaimable;
                uint256 fee = reward * fixedBoostedPercent / MAX;
                if (!useFixedBoostedFlag) {
                    uint256 boostedRatio = calculateBoostedRatio(token);
                    fee = (reward * feeBoostedPercent * (boostedRatio - MAX_RATE)) / (MAX * boostedRatio);
                }

                reward = reward - fee;
                integralReward = integralReward + MAX_RATE * reward / total;
            }

            uint256 integralRewardFor = rewardIntegralFor[_user][token];
            if (integralRewardFor < integralReward) {
                pending[i] = pending[i] + balance * (integralReward - integralRewardFor) / MAX_RATE;
            }
        }

        return pending;
    }

    function deposit(address _user, address _token, uint256 _amount) external {
        require(proxy.lpInitialized(_token), "LpDepositor: TOKEN_DEPOSIT_INVALID");
        IERC20(_token).safeTransferFrom(msg.sender, address(proxy), _amount);

        uint256 balance = userBalances[_user][_token];
        uint256 total = totalBalances[_token];
        
        if (harvestOnDeposit) {
            address[] memory _tokens = new address[](1);
            _tokens[0] = _token;
            claim(msg.sender, _tokens);
        }

        proxy.deposit(_token, _amount);
        userBalances[_user][_token] = balance + _amount;
        totalBalances[_token] = total + _amount;

        address depositToken = depositTokens[_token];
        if (depositToken == address(0)) {
            depositToken = _deployDepositToken(_token);
            depositTokens[_token] = depositToken;
        }
        IDepositToken(depositToken).mint(_user, _amount);
        emit Deposit(msg.sender, _user, _token, _amount);
    }

    function withdraw(address _receiver, address _token, uint256 _amount) external {
        uint256 balance = userBalances[msg.sender][_token];
        uint256 total = totalBalances[_token];
        require(balance >= _amount, "LpDepositor: withdraw amount exceeds balance");

        address[] memory _tokens = new address[](1);
        _tokens[0] = _token;
        claim(_receiver, _tokens);
        
        userBalances[msg.sender][_token] = balance - _amount;
        totalBalances[_token] = total - _amount;

        address depositToken = depositTokens[_token];
        IDepositToken(depositToken).burn(msg.sender, _amount);

        proxy.withdraw(_receiver, _token, _amount);
        emit Withdraw(msg.sender, _receiver, _token, _amount);
    }

    /**
        @notice Claim pending SLIZ rewards
        @param _receiver Account to send claimed rewards to
        @param _tokens List of LP tokens to claim for
    */
    function claim(address _receiver, address[] memory _tokens) public {
        uint256 unclaimedReward = 0;
        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint256 before = SLIZ.balanceOf(address(this));
            proxy.getReward(token);
            uint256 reward = SLIZ.balanceOf(address(this)) - before;

            if (reward > 0) {
                _updateIntegrals(msg.sender, token, userBalances[msg.sender][token], totalBalances[token], reward);
                unclaimedReward = unclaimedReward + unclaimedRewards[msg.sender][token];
            }
            delete unclaimedRewards[msg.sender][token];
        }

        if (unclaimedReward > 0) {
            SLIZ.safeTransfer(_receiver, unclaimedReward);
        }

        emit Claimed(msg.sender, _receiver, _tokens, unclaimedReward);
    }

    function transferDeposit(address _token, address _from, address _to, uint256 _amount) external returns (bool) {
        require(msg.sender == depositTokens[_token], "LpDepositor: FORBIDDEN");

        uint256 total = totalBalances[_token];
        uint256 balance = userBalances[_from][_token];
        require(balance >= _amount, "LpDepositor: transfer amount exceeds balance");

        uint256 before = SLIZ.balanceOf(address(this));
        proxy.getReward(_token);
        uint256 reward = SLIZ.balanceOf(address(this)) - before;
        _updateIntegrals(_from, _token, balance, total, reward);
        userBalances[_from][_token] = balance - _amount;

        balance = userBalances[_to][_token];
        _updateIntegrals(_to, _token, balance, total - _amount, 0);
        userBalances[_to][_token] = balance + _amount;
        emit TransferDeposit(_token, _from, _to, _amount);
        return true;
    }

    function pushPendingProtocolFees() public {
        lastFeeTransfer = block.timestamp;
        uint256 slizPendingFee = pendingFeeSLIZ;
        if (slizPendingFee > 0) {
            pendingFeeSLIZ = 0;
            uint256 slizBalance = SLIZ.balanceOf(address(this));
            if (slizPendingFee > slizBalance) slizPendingFee = slizBalance;
            _chargeFees(slizPendingFee);
        }
    }

    function setUseFixedBoostedFlag(bool _isEnable) external onlyOwner {
        useFixedBoostedFlag = _isEnable;
        emit SetUseFixedBoostedFlag(_isEnable);
    }

    function setFixedBoostedPercent(uint256 _rate) external onlyOwner {
        // validation from 0-20%
        require(_rate <= 2000, "LpDepositor: OUT_OF_RANGE");
        emit SetFixedBoostedPercent(fixedBoostedPercent, _rate);
        fixedBoostedPercent = _rate;
    }

    function setFeeBoostedPercent(uint256 _rate) external onlyOwner {
        // validation from 0-50%
        require(_rate <= 5000, "LpDepositor: OUT_OF_RANGE");
        emit SetFeeBoostedPercent(feeBoostedPercent, _rate);
        feeBoostedPercent = _rate;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
        emit SetHarvestOnDeposit(_harvestOnDeposit);
    }

    // Set our router to exchange our rewards, also update new route.
    function setRouterAndRoute(
        ISolidlyRouter _router,
        ISolidlyRouter.Routes[] calldata _route
    ) external onlyOwner {
        uint256 slizToWethRouteLength = slizToWethRoute.length;
        for (uint i; i < slizToWethRouteLength; i++) slizToWethRoute.pop();
        for (uint i; i < _route.length; i++) slizToWethRoute.push(_route[i]);
        router = _router;
        SLIZ.approve(address(_router), type(uint256).max);
        emit SetRouterAndRoute(_router, _route);
    }

    function setFeeId(uint256 feeId) external onlyOwner {
        coFeeConfig.setStratFeeId(feeId);
        emit SetFeeId(feeId);
    }

    function setCoFeeRecipient(address _coFeeRecipient) external onlyOwner {
        emit SetCoFeeRecipient(coFeeRecipient, _coFeeRecipient);
        coFeeRecipient = _coFeeRecipient;
    }

    function setPolWallet(address _polWallet) external onlyOwner {
        emit SetPolWallet(polWallet, _polWallet);
        polWallet = _polWallet;
    }

    function setRewardPool(IRewardPool _rewardPool) external onlyOwner {
        emit SetRewardPool(rewardPool, _rewardPool);
        rewardPool = _rewardPool;
    }

    function setRewardPoolRate(uint256 _rewardPoolRate) external onlyOwner {
        require(_rewardPoolRate <= MAX, "LpDepositor: OUT_OF_RANGE");
        emit SetRewardPoolRate(rewardPoolRate, _rewardPoolRate);
        rewardPoolRate = _rewardPoolRate;
    }

    function calculateBoostedRatio(address _token) public view returns (uint256) {
        uint256 amountDeposited = proxy.totalDeposited(_token);
        uint256 amountBoostedInitial = amountDeposited * 4 / 10;
        uint256 amountBoostedExtra = (proxy.totalLiquidityOfGauge(_token) * proxy.votingBalance() * 6) / (10 * proxy.votingTotal());
        uint256 boostedRatio = Math.min(amountBoostedInitial + amountBoostedExtra, amountDeposited) * MAX_RATE / amountBoostedInitial;
        return boostedRatio;
    }

    function _deployDepositToken(address pool) internal returns (address token) {
        // taken from https://solidity-by-example.org/app/minimal-proxy/
        bytes20 targetBytes = bytes20(depositTokenImplementation);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            token := create(0, clone, 0x37)
        }
        IDepositToken(token).initialize(pool);
        return token;
    }

    function _updateIntegrals(
        address user,
        address pool,
        uint256 balance,
        uint256 total,
        uint256 reward
    ) internal {
        uint256 integralReward = rewardIntegral[pool];
        if (reward > 0) {
            uint256 fee = reward * fixedBoostedPercent / MAX;
            if (!useFixedBoostedFlag) {
                uint256 boostedRatio = calculateBoostedRatio(pool);
                fee = (reward * feeBoostedPercent * (boostedRatio - MAX_RATE)) / (MAX * boostedRatio);
            }
            reward = reward - fee;
            pendingFeeSLIZ = pendingFeeSLIZ + fee;

            integralReward = integralReward + MAX_RATE * reward / total;
            rewardIntegral[pool] = integralReward;
        }
        uint256 integralRewardFor = rewardIntegralFor[user][pool];
        if (integralRewardFor < integralReward) {
            unclaimedRewards[user][pool] = unclaimedRewards[user][pool] + balance * (integralReward - integralRewardFor) / MAX_RATE;
            rewardIntegralFor[user][pool] = integralReward;
        }

        if (lastFeeTransfer + 86400 < block.timestamp) {
            // once a day, transfer pending rewards
            // we only do this on updates to pools without extra incentives because each
            // operation can be gas intensive
            pushPendingProtocolFees();
        }
    }

    function _chargeFees(uint256 rewardAmount) internal {
        // Charge our fees here since we send CeThena to reward pool
        IFeeConfig.FeeCategory memory fees = coFeeConfig.getFees(address(this));
        uint256 feeAmount = (rewardAmount * fees.total) / 1e18;
        if (feeAmount > 0) {
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                feeAmount,
                0,
                slizToWethRoute,
                coFeeRecipient,
                block.timestamp
            );
        }

        chamSLIZ.deposit(rewardAmount - feeAmount);
        uint256 rewardRemainingAmount = chamSLIZ.balanceOf(address(this));
        if (rewardRemainingAmount > 0) {
           if (rewardPoolRate > 0) {
                uint256 rewardPoolAmount = rewardRemainingAmount * rewardPoolRate / MAX;
                chamSLIZ.transfer(address(rewardPool), rewardPoolAmount);
                rewardPool.notifyRewardAmount();
                rewardRemainingAmount = rewardRemainingAmount - rewardPoolAmount;
            }
            chamSLIZ.transfer(polWallet, rewardRemainingAmount);
        }
    }
}

