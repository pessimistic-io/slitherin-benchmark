// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC4626.sol";
import "./ReentrancyGuard.sol";
import "./Registry.sol";

contract Rebalancer is ERC4626, Registry, ReentrancyGuard {
    event Rebalance();
    event FeesChanged(address owner, DataTypes.feeData newFeeData);
    event FeesCharged(address treasury, uint256 amount);
    event RequestWithdraw(address withdrawer, uint256 shares, uint256 id);
    event WithdrawalCompleted(address withdrawer, uint256 amount, uint256 id);
    event SetPoolLimit(uint256 newLimit);

    DataTypes.feeData public FeeData;

    uint256 public totalRequested;
    mapping(address => uint256) public lockedShares;
    DataTypes.withdrawRequest[] public withdrawQueue;
    uint256 private withdrawalRequests;

    uint256 lastBalance;
    uint256 depositsAfterFeeClaim;
    uint256 withdrawalsAfterFeeClaim;

    uint256 public poolLimitSize;
    uint64 public constant MAX_PERFORMANCE_FEE = 0.3 * 1e18;
    uint64 public constant MAX_WITHDRAW_FEE = 0.05 * 1e18;
    uint256 public constant REBALANCE_THRESHOLD = 0.01 * 1e18;
    uint256 public constant WITHDRAW_QUEUE_LIMIT = 10;
    uint256 public constant feeDecimals = 18;

    /**
     * @dev Set the underlying asset contract. Set all starting positions. Set price router.
     */
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address[] memory _positions,
        address[] memory _iTokens,
        address _rebalanceMatrixProvider,
        address _router,
        address[] memory _whitelist,
        uint256 _poolLimitSize
    )
        ERC4626(IERC20(_asset))
        ERC20(_name, _symbol)
        Registry(_positions, _iTokens, _rebalanceMatrixProvider, _router, _whitelist)
    {
        FeeData = DataTypes.feeData({performanceFee: 0.1 * 1e18, withdrawFee: 0.001 * 1e18, treasury: msg.sender});
        poolLimitSize = _poolLimitSize;
    }

    /**
     * @dev calculate the total contract balance converted to underlying asset including not claimed fee
     * @return  uint256 amount of token
     */
    function totalAssetsWithoutFee() private view returns (uint256) {
        uint256 _totalAssets = IERC20(asset()).balanceOf(address(this));
        for (uint i = 0; i < iTokens.length; i++) {
            _totalAssets += router.getTokenValue(asset(), iTokens[i], IERC20(iTokens[i]).balanceOf(address(this)));
        }
        return _totalAssets;
    }

    /**
     * @notice calculate the amount of non claimed performance fee
     * NOTE: Should never revert
     */
    function getAvailableFee() public view returns (uint256) {
        uint256 currentBalance = totalAssetsWithoutFee();
        if (currentBalance + withdrawalsAfterFeeClaim <= lastBalance + depositsAfterFeeClaim) {
            return 0;
        }
        return
            ((currentBalance + withdrawalsAfterFeeClaim - lastBalance - depositsAfterFeeClaim) *
                FeeData.performanceFee) / (10 ** feeDecimals);
    }

    /**
     * @notice calculate the amount of underlying asset covered by all shares
     * @dev not claimed fee should't be included in future shares burning/minting
     * @return uint256 amount of underlying asset
     */
    function totalAssets() public view override returns (uint256) {
        return totalAssetsWithoutFee() - getAvailableFee();
    }

    /**
     * @notice returns the amount of user shares available for transfer/burning
     * @dev doesn't include the amount of shares which will be burned in the next rebalance
     * @param   owner is the owner of shares
     * @return  uint256  amount of available shares
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        return super.maxRedeem(owner) - lockedShares[owner];
    }

    /**
     * @notice  returns the amount of token, which user can transfer or withdraw
     * @dev    doesn't include the amount of token which will be withdrawn in the next rebalance
     * @param   owner  is the owner of the deposit
     * @return  uint256  amount of available tokens
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return _convertToAssets(maxRedeem(owner), Math.Rounding.Down);
    }

    /**
     * @notice  executes rebalance
     * @dev     fullfit all withdrawals
     * @param   distributionMatrix  transactions which contract should execute
     * NOTE: should revert if can't fullfit all requested withdrawals.
     */
    function rebalance(DataTypes.AdaptorCall[] memory distributionMatrix) external nonReentrant onlyRebalanceProvider {
        uint256 balanceBefore = totalAssets();
        _executeTransactions(distributionMatrix);
        uint256 balanceAfter = totalAssets();
        require(
            ((balanceBefore * (1e18 - REBALANCE_THRESHOLD)) / 1e18) <= balanceAfter,
            "Asset balance become too low"
        );
        _fullfitWithdrawals();

        emit Rebalance();
    }

    /**
     * @notice  allows user to request the token withdrawal if the amount of underlying asset is not enougth on the vault
     * @dev     shares shouldn't be burned but user can't use them in any other way
     * @param   shares  amount of shares user will redeem during next rebalance
     */
    function requestWithdraw(uint256 shares) public nonReentrant {
        require(shares <= maxRedeem(msg.sender), "ERC4626: withdraw more than max");
        require(shares > previewWithdraw(IERC20(asset()).balanceOf(address(this))), "Instant withdraw is available");
        require(withdrawQueue.length < WITHDRAW_QUEUE_LIMIT, "Withdraw queue limit exceeded");

        lockedShares[msg.sender] += shares;

        withdrawalRequests++;
        withdrawQueue.push(DataTypes.withdrawRequest(msg.sender, shares, withdrawalRequests));

        totalRequested += shares;

        emit RequestWithdraw(msg.sender, shares, withdrawalRequests);
    }

    /**
     * @notice  the function to set the platform fees.
     * NOTE: fees cannot be above the pre-negotiated limit
     */
    function setFee(DataTypes.feeData memory newFeeData) public onlyOwner {
        require(newFeeData.performanceFee <= MAX_PERFORMANCE_FEE, "Performance fee limit exceeded");
        require(newFeeData.withdrawFee <= MAX_WITHDRAW_FEE, "Withdraw fee limit exceeded");

        claimFee();
        FeeData = newFeeData;

        emit FeesChanged(msg.sender, newFeeData);
    }

    /**
     * @notice  claims all the collected performance fee
     */
    function claimFee() public onlyOwner {
        _payFee(getAvailableFee());

        withdrawalsAfterFeeClaim = 0;
        depositsAfterFeeClaim = 0;
        lastBalance = totalAssetsWithoutFee();
    }

    /**
     * @notice  add a new iToken for the vault. Check if the router supports this token
     */
    function addIToken(address token) public override onlyOwner {
        router.getTokenValue(asset(), token, 0);
        super.addIToken(token);
    }

    /**
     * @notice  shouldn't allow user to transfer his locked shares
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(amount <= maxRedeem(from) || from == address(0), "Transferring more than max available");
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotDepositsPause onlyWhitelisted nonReentrant {
        require(totalAssets() + assets <= poolLimitSize, "Pool limit exceeded");
        depositsAfterFeeClaim += assets;
        super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice  takes withdrawal fee
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        withdrawalsAfterFeeClaim += assets;
        uint256 withdrawFee = (assets * FeeData.withdrawFee) / (10 ** feeDecimals);
        _payFee(withdrawFee);
        super._withdraw(caller, receiver, owner, assets - withdrawFee, shares);
    }

    /**
     * @notice  an internal function to take collected performance fee
     */
    function _payFee(uint256 amount) internal {
        if (amount > 0) {
            IERC20(asset()).transfer(FeeData.treasury, amount);

            emit FeesCharged(FeeData.treasury, amount);
        }
    }

    /**
     * @notice  executes the list of transactions for autocompound or rebalance
     */
    function _executeTransactions(DataTypes.AdaptorCall[] memory _matrix) internal {
        for (uint8 i = 0; i < _matrix.length; ++i) {
            address adaptor = _matrix[i].adaptor;
            require(isAdaptorSetup[adaptor]);
            (bool success, ) = adaptor.call(_matrix[i].callData);
            require(success, "Transaction failed.");
        }
    }

    /**
     * @notice  all users should redeem their shares requested after previous rebalance
     */
    function _fullfitWithdrawals() internal {
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            lockedShares[withdrawQueue[i].receiver] -= withdrawQueue[i].shares;
            uint256 assets = convertToAssets(withdrawQueue[i].shares);
            _withdraw(
                withdrawQueue[i].receiver,
                withdrawQueue[i].receiver,
                withdrawQueue[i].receiver,
                assets,
                withdrawQueue[i].shares
            );
            emit WithdrawalCompleted(withdrawQueue[i].receiver, assets, withdrawQueue[i].id);
        }
        delete withdrawQueue;
        totalRequested = 0;
    }

    function setPoolLimit(uint256 newLimit) public onlyOwner {
        require(newLimit > poolLimitSize, "New limit should be greater");
        poolLimitSize = newLimit;

        emit SetPoolLimit(newLimit);
    }
}

