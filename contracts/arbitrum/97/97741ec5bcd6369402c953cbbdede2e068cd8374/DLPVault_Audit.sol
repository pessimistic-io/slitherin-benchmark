// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20, IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC4626Upgradeable, IERC20Upgradeable} from "./ERC4626Upgradeable.sol";

import {Kernel, Keycode, Permissions, toKeycode, Policy} from "./Kernel.sol";
import {RolesConsumer, ROLESv1} from "./OlympusRoles.sol";

import {IDLPVault} from "./IDLPVault.sol";
import {ILeverager} from "./ILeverager.sol";
import {IAToken} from "./IAToken.sol";
import {IMultiFeeDistribution, LockedBalance} from "./IMultiFeeDistribution.sol";
import {ILendingPool} from "./ILendingPool.sol";
import {ICreditDelegationToken} from "./ICreditDelegationToken.sol";
import {IBountyManager} from "./IBountyManager.sol";
import {IPool} from "./IPool.sol";
import {IFlashLoanSimpleReceiver} from "./IFlashLoanSimpleReceiver.sol";
import {IVault, IAsset, IWETH} from "./IVault.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

contract DLPVault is
    ERC4626Upgradeable,
    RolesConsumer,
    IFlashLoanSimpleReceiver,
    IDLPVault
{
    using SafeERC20 for IERC20;

    //============================================================================================//
    //                                         CONSTANT                                           //
    //============================================================================================//

    string private constant _NAME = "Radiate DLP Vault";
    string private constant _SYMBOL = "RADT-DLP";

    IERC20 public constant DLP =
        IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);
    IERC20 public constant RDNT =
        IERC20(0x3082CC23568eA640225c2467653dB90e9250AaA0);
    IWETH public constant WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IPool public constant AAVE_LENDING_POOL =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    ILendingPool public constant LENDING_POOL =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);
    IMultiFeeDistribution public constant MFD =
        IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
    ISwapRouter public constant SWAP_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IVault public constant VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 public constant RDNT_WETH_POOL_ID =
        0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd;

    uint256 public constant MAX_QUEUE_PROCESS_LIMIT = 30;
    uint256 public constant MULTIPLIER = 1e6; // 100%

    //============================================================================================//
    //                                          STORAGE                                           //
    //============================================================================================//

    /// @notice kernel
    Kernel public kernel;

    /// @notice treasury wallet
    address public treasury;

    /// @notice cap amount of DLP
    uint256 public vaultCap;

    /// @notice MFD lock index
    uint256 public defaultLockIndex;

    /// @notice DLP from treasury to boost the APY
    uint256 public boostedDLP;

    /// @notice rewards from MFD
    struct RewardInfo {
        address token;
        bool isAToken;
        uint24 poolFee; // UniswapV3 pool fee
        uint256 pending;
    }
    RewardInfo[] public rewards;

    /// @notice fee percent
    struct FeeInfo {
        uint256 depositFee;
        uint256 withdrawFee;
        uint256 compoundFee;
    }
    FeeInfo public fee;

    /// @notice withdrawal queue
    struct WithdrawalQueue {
        uint256 assets;
        address receiver;
        bool isClaimed;
        uint32 createdAt;
    }
    WithdrawalQueue[] public withdrawalQueues;
    uint256 public withdrawalQueueIndex;
    uint256 public queuedDLP;
    uint256 public claimableDLP;

    //============================================================================================//
    //                                           EVENT                                            //
    //============================================================================================//

    event KernelChanged(address kernel);
    event FeeUpdated(
        uint256 depositFee,
        uint256 withdrawFee,
        uint256 compoundFee
    );
    event DefaultLockIndexUpdated(uint256 defaultLockIndex);
    event RewardBaseTokensAdded(address[] rewardBaseTokens);
    event RewardBaseTokensRemoved(address[] rewardBaseTokens);
    event VaultCapUpdated(uint256 vaultCap);
    event CreditDelegationEnabled(
        address indexed token,
        address indexed leverager
    );
    event CreditDelegationDisabled(
        address indexed token,
        address indexed leverager
    );
    event WithdrawQueued(
        uint256 index,
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Claimed(uint256 index, address indexed receiver, uint256 assets);

    //============================================================================================//
    //                                           ERROR                                            //
    //============================================================================================//

    error CALLER_NOT_KERNEL();
    error CALLER_NOT_AAVE();
    error FEE_PERCENT_TOO_HIGH(uint256 fee);
    error INVALID_PARAM();
    error EXCEED_BOOSTED_AMOUNT();
    error EXCEED_VAULT_CAP(uint256 vaultCap);
    error TOO_LOW_DEPOSIT();
    error EXCEED_MAX_WITHDRAW();
    error EXCEED_MAX_REDEEM();
    error NOT_CLAIMABLE();
    error ALREADY_CALIMED();

    //============================================================================================//
    //                                         INITIALIZE                                         //
    //============================================================================================//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(Kernel _kernel) external initializer {
        kernel = _kernel;
        defaultLockIndex = 0;

        DLP.approve(address(MFD), type(uint256).max);

        __ERC20_init(_NAME, _SYMBOL);
        __ERC4626_init(IERC20Upgradeable(address(DLP)));
    }

    receive() external payable {}

    //============================================================================================//
    //                                          MODIFIER                                          //
    //============================================================================================//

    modifier onlyKernel() {
        if (msg.sender != address(kernel)) revert CALLER_NOT_KERNEL();

        _;
    }

    modifier onlyAaveLendingPool() {
        if (msg.sender != address(AAVE_LENDING_POOL)) revert CALLER_NOT_AAVE();

        _;
    }

    modifier onlyAdmin() {
        ROLES.requireRole("admin", msg.sender);

        _;
    }

    modifier onlyLeverager(address initiator) {
        ROLES.requireRole("leverager", initiator);

        _;
    }

    //============================================================================================//
    //                                     DEFAULT OVERRIDES                                      //
    //============================================================================================//

    function changeKernel(Kernel _kernel) external onlyKernel {
        kernel = _kernel;

        emit KernelChanged(address(_kernel));
    }

    function isActive() external view returns (bool) {
        return kernel.isPolicyActive(Policy(address(this)));
    }

    function configureDependencies()
        external
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");
        ROLES = ROLESv1(address(kernel.getModuleForKeycode(dependencies[0])));
        treasury = address(kernel.getModuleForKeycode(dependencies[1]));
    }

    function requestPermissions()
        external
        pure
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](0);
    }

    //============================================================================================//
    //                                         ADMIN                                              //
    //============================================================================================//

    function setFee(
        uint256 _depositFee,
        uint256 _withdrawFee,
        uint256 _compoundFee
    ) external onlyAdmin {
        if (_depositFee >= MULTIPLIER / 2)
            revert FEE_PERCENT_TOO_HIGH(_depositFee);
        if (_withdrawFee >= MULTIPLIER / 2)
            revert FEE_PERCENT_TOO_HIGH(_withdrawFee);
        if (_compoundFee >= MULTIPLIER / 2)
            revert FEE_PERCENT_TOO_HIGH(_compoundFee);

        fee.depositFee = _depositFee;
        fee.withdrawFee = _withdrawFee;
        fee.compoundFee = _compoundFee;

        emit FeeUpdated(_depositFee, _withdrawFee, _compoundFee);
    }

    function setDefaultLockIndex(uint256 _defaultLockIndex) external onlyAdmin {
        defaultLockIndex = _defaultLockIndex;
        MFD.setDefaultRelockTypeIndex(_defaultLockIndex);

        emit DefaultLockIndexUpdated(_defaultLockIndex);
    }

    function addRewardBaseTokens(
        address[] calldata _rewardBaseTokens,
        bool[] calldata _isATokens,
        uint24[] calldata _poolFees
    ) external onlyAdmin {
        uint256 length = _rewardBaseTokens.length;
        if (length != _isATokens.length) revert INVALID_PARAM();
        if (length != _poolFees.length) revert INVALID_PARAM();

        for (uint256 i = 0; i < length; ) {
            rewards.push(
                RewardInfo({
                    token: _rewardBaseTokens[i],
                    isAToken: _isATokens[i],
                    poolFee: _poolFees[i],
                    pending: 0
                })
            );
            unchecked {
                ++i;
            }
        }

        emit RewardBaseTokensAdded(_rewardBaseTokens);
    }

    function removeRewardBaseTokens(
        address[] calldata _rewardBaseTokens
    ) external onlyAdmin {
        uint256 length = _rewardBaseTokens.length;

        for (uint256 i = 0; i < length; ) {
            uint256 count = rewards.length;

            for (uint256 j = 0; j < count; ) {
                if (rewards[j].token == _rewardBaseTokens[i]) {
                    rewards[j] = rewards[count - 1];
                    delete rewards[count - 1];
                    rewards.pop();
                    break;
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        emit RewardBaseTokensRemoved(_rewardBaseTokens);
    }

    function setVaultCap(uint256 _vaultCap) external onlyAdmin {
        vaultCap = _vaultCap;

        emit VaultCapUpdated(_vaultCap);
    }

    function enableCreditDelegation(
        ICreditDelegationToken _token,
        address _leverager
    ) external onlyAdmin {
        _token.approveDelegation(_leverager, type(uint256).max);

        emit CreditDelegationEnabled(address(_token), _leverager);
    }

    function disableCreditDelegation(
        ICreditDelegationToken _token,
        address _leverager
    ) external onlyAdmin {
        _token.approveDelegation(_leverager, 0);

        emit CreditDelegationDisabled(address(_token), _leverager);
    }

    function withdrawTokens(IERC20 _token) external onlyAdmin {
        uint256 amount = _token.balanceOf(address(this));

        if (_token == DLP) {
            _processWithdrawalQueue();
            amount -= claimableDLP;
        }

        if (amount > 0) {
            _token.safeTransfer(msg.sender, amount);
        }
    }

    function boostDLP(uint256 _amount) external onlyAdmin {
        DLP.safeTransferFrom(msg.sender, address(this), _amount);

        boostedDLP += _amount;

        _stakeTokens(_amount);
    }

    function unboostDLP(uint256 _amount) external onlyAdmin {
        if (_amount > boostedDLP) revert EXCEED_BOOSTED_AMOUNT();

        boostedDLP -= _amount;
        queuedDLP += _amount;

        withdrawalQueues.push(
            WithdrawalQueue({
                assets: _amount,
                receiver: msg.sender,
                isClaimed: false,
                createdAt: uint32(block.timestamp)
            })
        );
    }

    function setRelock(bool _status) external onlyAdmin {
        MFD.setRelock(_status);
    }

    function getRewardBaseTokens() external view returns (address[] memory) {
        uint256 length = rewards.length;
        address[] memory rewardBaseTokens = new address[](length);

        for (uint256 i = 0; i < length; ) {
            rewardBaseTokens[i] = rewards[i].token;
            unchecked {
                ++i;
            }
        }

        return rewardBaseTokens;
    }

    //============================================================================================//
    //                                       FEE LOGIC                                            //
    //============================================================================================//

    function _sendCompoundFee(uint256 _index, uint256 _harvested) internal {
        if (fee.compoundFee == 0) return;

        RewardInfo storage reward = rewards[_index];
        uint256 feeAmount = (_harvested * fee.compoundFee) / MULTIPLIER;

        IERC20(reward.token).safeTransfer(treasury, feeAmount);

        reward.pending -= feeAmount;
    }

    function _sendDepositFee(uint256 _assets) internal returns (uint256) {
        if (fee.depositFee == 0) return _assets;

        uint256 feeAssets = (_assets * fee.depositFee) / MULTIPLIER;

        DLP.safeTransferFrom(msg.sender, treasury, feeAssets);

        return _assets - feeAssets;
    }

    function _sendMintFee(uint256 _shares) internal returns (uint256) {
        if (fee.depositFee == 0) return _shares;

        uint256 feeAssets = (super.previewMint(_shares) * fee.depositFee) /
            MULTIPLIER;
        uint256 feeShares = super.previewWithdraw(feeAssets);

        DLP.safeTransferFrom(msg.sender, treasury, feeAssets);

        return _shares - feeShares;
    }

    function _sendWithdrawFee(
        uint256 _assets,
        address _owner
    ) internal returns (uint256) {
        if (fee.withdrawFee == 0) return _assets;

        uint256 feeShares = (super.previewWithdraw(_assets) * fee.withdrawFee) /
            MULTIPLIER;
        uint256 feeAssets = super.previewMint(feeShares);

        if (msg.sender != _owner) {
            super._spendAllowance(_owner, msg.sender, feeShares);
        }
        super._transfer(_owner, treasury, feeShares);

        return _assets - feeAssets;
    }

    function _sendRedeemFee(
        uint256 _shares,
        address _owner
    ) internal returns (uint256) {
        if (fee.withdrawFee == 0) return _shares;

        uint256 feeShares = (_shares * fee.withdrawFee) / MULTIPLIER;

        if (msg.sender != _owner) {
            super._spendAllowance(_owner, msg.sender, feeShares);
        }
        super._transfer(_owner, treasury, feeShares);

        return _shares - feeShares;
    }

    function getFee()
        external
        view
        returns (uint256 depositFee, uint256 withdrawFee, uint256 compoundFee)
    {
        depositFee = fee.depositFee;
        withdrawFee = fee.withdrawFee;
        compoundFee = fee.compoundFee;
    }

    //============================================================================================//
    //                                    LEVERAGER LOGIC                                         //
    //============================================================================================//

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function executeOperation(
        address _asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external
        override
        onlyAaveLendingPool
        onlyLeverager(initiator)
        returns (bool)
    {
        // approve
        if (
            IERC20(_asset).allowance(address(this), address(LENDING_POOL)) == 0
        ) {
            IERC20(_asset).approve(address(LENDING_POOL), type(uint256).max);
        }
        if (
            IERC20(_asset).allowance(
                address(this),
                address(AAVE_LENDING_POOL)
            ) == 0
        ) {
            IERC20(_asset).approve(
                address(AAVE_LENDING_POOL),
                type(uint256).max
            );
        }

        // repay looping
        uint256 interestRateMode = 2; // variable
        LENDING_POOL.repay(_asset, amount, interestRateMode, address(this));

        // repay flashloan
        LENDING_POOL.withdraw(_asset, amount + premium, address(this));

        // withdraw
        (uint256 withdrawAmount, address account) = abi.decode(
            params,
            (uint256, address)
        );
        LENDING_POOL.withdraw(
            _asset,
            _min(
                withdrawAmount - premium,
                IERC20(ILeverager(initiator).getAToken()).balanceOf(
                    address(this)
                )
            ),
            account
        );

        return true;
    }

    function withdrawForLeverager(
        address _account,
        uint256 _amount
    ) external override onlyLeverager(msg.sender) {
        MFD.withdraw(_amount);
        RDNT.safeTransfer(_account, _amount);
    }

    //============================================================================================//
    //                                     REWARDS LOGIC                                          //
    //============================================================================================//

    function compound() public {
        if (totalSupply() == 0) return;

        // reward balance before
        uint256 length = rewards.length;
        uint256[] memory balanceBefore = new uint256[](length);

        for (uint256 i = 0; i < length; ) {
            balanceBefore[i] = IERC20(rewards[i].token).balanceOf(
                address(this)
            );
            unchecked {
                ++i;
            }
        }

        // get reward
        MFD.getAllRewards();

        // reward harvested
        for (uint256 i = 0; i < length; ) {
            RewardInfo storage reward = rewards[i];
            uint256 harvested = IERC20(reward.token).balanceOf(address(this)) -
                balanceBefore[i];

            reward.pending += harvested;
            _sendCompoundFee(i, harvested);
            _swapToWETH(i);

            unchecked {
                ++i;
            }
        }

        // add liquidity
        _joinPool();

        // withdraw expired lock
        MFD.withdrawExpiredLocksForWithOptions(address(this), 0, true);

        // process withdrawal queue
        _processWithdrawalQueue();

        // stake
        _stakeDLP();
    }

    function _swapToWETH(uint256 _index) internal {
        RewardInfo storage reward = rewards[_index];

        // Threshold
        if (
            reward.pending <
            (10 ** (IERC20Metadata(reward.token).decimals() - 2))
        ) return;

        address swapToken;
        uint256 swapAmount;

        // AToken (withdraw underlying token)
        if (reward.isAToken) {
            IERC20(reward.token).approve(address(LENDING_POOL), reward.pending);

            swapToken = IAToken(reward.token).UNDERLYING_ASSET_ADDRESS();
            swapAmount = LENDING_POOL.withdraw(
                swapToken,
                reward.pending,
                address(this)
            );
        }
        // ERC20
        else {
            swapToken = reward.token;
            swapAmount = reward.pending;
        }

        reward.pending = 0;

        // UniswapV3 Swap (REWARD -> WETH)
        if (swapToken == address(WETH)) {
            return;
        }

        IERC20(swapToken).approve(address(SWAP_ROUTER), swapAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: swapToken,
                tokenOut: address(WETH),
                fee: reward.poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: swapAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        SWAP_ROUTER.exactInputSingle(params);
    }

    function _joinPool() internal {
        uint256 _amountWETH = WETH.balanceOf(address(this));
        if (_amountWETH < 0.01 ether) return;

        // Balancer Join Pool (WETH <> RDNT)
        WETH.approve(address(VAULT), _amountWETH);

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(RDNT));
        assets[1] = IAsset(address(WETH));

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = 0;
        maxAmountsIn[1] = _amountWETH;

        IVault.JoinPoolRequest memory request;

        request.assets = assets;
        request.maxAmountsIn = maxAmountsIn;
        request.userData = abi.encode(1, maxAmountsIn, 0);

        VAULT.joinPool(
            RDNT_WETH_POOL_ID,
            address(this),
            address(this),
            request
        );
    }

    function _stakeDLP() internal {
        uint256 balance = DLP.balanceOf(address(this));

        if (balance > queuedDLP) {
            _stakeTokens(balance - queuedDLP);
        }
    }

    function _stakeTokens(uint256 _amount) internal {
        if (_amount < IBountyManager(MFD.bountyManager()).minDLPBalance())
            return;

        MFD.stake(_amount, address(this), defaultLockIndex);
    }

    function _processWithdrawalQueue() internal {
        uint256 balance = DLP.balanceOf(address(this)) - claimableDLP;
        uint256 length = withdrawalQueues.length;

        for (
            uint256 i = 0;
            i < MAX_QUEUE_PROCESS_LIMIT && withdrawalQueueIndex < length;

        ) {
            WithdrawalQueue memory queue = withdrawalQueues[
                withdrawalQueueIndex
            ];

            if (balance < queue.assets) {
                break;
            }

            unchecked {
                balance -= queue.assets;
                claimableDLP += queue.assets;
                ++withdrawalQueueIndex;
                ++i;
            }
        }
    }

    //============================================================================================//
    //                                      ERC4626 OVERRIDES                                     //
    //============================================================================================//

    function deposit(
        uint256 _assets,
        address _receiver
    ) public virtual override returns (uint256) {
        compound();

        _assets = _sendDepositFee(_assets);
        if (totalAssets() + _assets > vaultCap)
            revert EXCEED_VAULT_CAP(totalAssets() + _assets);

        uint256 shares = super.deposit(_assets, _receiver);
        if (shares == 0) revert TOO_LOW_DEPOSIT();

        _stakeDLP();

        return shares;
    }

    function mint(
        uint256 _shares,
        address _receiver
    ) public virtual override returns (uint256) {
        compound();

        _shares = _sendMintFee(_shares);
        if (_shares == 0) revert TOO_LOW_DEPOSIT();

        uint256 assets = super.mint(_shares, _receiver);
        if (totalAssets() > vaultCap) revert EXCEED_VAULT_CAP(totalAssets());

        _stakeDLP();

        return assets;
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public virtual override returns (uint256) {
        compound();

        _assets = _sendWithdrawFee(_assets, _owner);
        if (_assets > maxWithdraw(_owner)) revert EXCEED_MAX_WITHDRAW();

        uint256 shares = super.previewWithdraw(_assets);
        _withdraw(msg.sender, _receiver, _owner, _assets, shares);

        return shares;
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public virtual override returns (uint256) {
        compound();

        _shares = _sendRedeemFee(_shares, _owner);
        if (_shares > maxRedeem(_owner)) revert EXCEED_MAX_REDEEM();

        uint256 assets = super.previewRedeem(_shares);
        _withdraw(msg.sender, _receiver, _owner, assets, _shares);

        return assets;
    }

    function claim(uint256 _index) external {
        if (_index >= withdrawalQueueIndex) revert NOT_CLAIMABLE();

        WithdrawalQueue storage queue = withdrawalQueues[_index];
        if (queue.isClaimed) revert ALREADY_CALIMED();

        queue.isClaimed = true;
        queuedDLP -= queue.assets;
        claimableDLP -= queue.assets;

        DLP.safeTransfer(queue.receiver, queue.assets);

        emit Claimed(_index, queue.receiver, queue.assets);
    }

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    ) internal virtual override {
        if (_caller != _owner) {
            super._spendAllowance(_owner, _caller, _shares);
        }

        super._burn(_owner, _shares);

        queuedDLP += _assets;

        uint256 index = withdrawalQueues.length;
        withdrawalQueues.push(
            WithdrawalQueue({
                assets: _assets,
                receiver: _receiver,
                isClaimed: false,
                createdAt: uint32(block.timestamp)
            })
        );

        emit WithdrawQueued(
            index,
            _caller,
            _receiver,
            _owner,
            _assets,
            _shares
        );
    }

    function totalAssets() public view virtual override returns (uint256) {
        return
            (MFD.totalBalance(address(this)) + DLP.balanceOf(address(this))) -
            (queuedDLP + boostedDLP);
    }

    function withdrawalsOf(
        address _account
    ) external view returns (WithdrawalQueue[] memory queues) {
        uint256 length = withdrawalQueues.length;
        uint256 i;
        uint256 j;

        for (i = 0; i < length; ) {
            WithdrawalQueue memory queue = withdrawalQueues[i];

            if (!queue.isClaimed && queue.receiver == _account) {
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        queues = new WithdrawalQueue[](j);
        j = 0;

        for (i = 0; i < length; ) {
            WithdrawalQueue memory queue = withdrawalQueues[i];

            if (!queue.isClaimed && queue.receiver == _account) {
                queues[j++] = queue;
            }

            unchecked {
                ++i;
            }
        }
    }
}

