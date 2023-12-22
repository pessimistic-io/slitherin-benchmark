// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./ERC4626Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Registry.sol";

contract Rebalancer is ERC4626Upgradeable, Registry, ReentrancyGuardUpgradeable {
    event Rebalance();
    event FeesChanged(address owner, DataTypes.feeData newFeeData);
    event FeesCharged(address treasury, uint256 amount);
    event RequestWithdraw(address withdrawer, uint256 shares, uint256 id);
    event WithdrawRequested(uint256 indexed id, uint256 assets);

    DataTypes.feeData public FeeData;

    uint256 public totalRequested;
    mapping(address => uint256) public lockedShares;
    DataTypes.withdrawRequest[] public withdrawQueue;
    uint256 private withdrawalRequests;

    uint256 private lastBalance;
    uint256 private depositsAfterFeeClaim;
    uint256 private withdrawalsAfterFeeClaim;

    uint64 public constant MAX_PERFORMANCE_FEE = 0.3 * 1e18;
    uint64 public constant MAX_WITHDRAW_FEE = 0.05 * 1e18;
    uint64 public constant REBALANCE_THRESHOLD = 0.01 * 1e18;
    uint32 public constant WITHDRAW_QUEUE_LIMIT = 10;
    uint32 public constant FEE_DECIMALS = 18;

    /**
     * @dev Set the underlying asset contract. Set all starting protocols. Set price router.
     */
    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        address[] memory _protocols,
        DataTypes.ProtocolSelectors[] memory _protocolSelectors,
        address[] memory _iTokens,
        address _rebalanceMatrixProvider,
        address _router,
        uint256 _poolLimit
    )
        initializer external
    {
        __ERC4626_init(IERC20Upgradeable(_asset));
        __ERC20_init(_name, _symbol);
        __Registry_init(_protocols, _protocolSelectors, _iTokens, _rebalanceMatrixProvider, _router, _poolLimit);
        _setFee(0.1 * 1e18, 0.001 * 1e18);
        _setFeeTreasury(msg.sender);
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
                FeeData.performanceFee) / (10 ** FEE_DECIMALS);
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
        return _convertToAssets(maxRedeem(owner), MathUpgradeable.Rounding.Down);
    }

    /**
     * @notice  executes rebalance
     * @dev     fullfit all withdrawals
     * @param   distributionMatrix  transactions which contract should execute
     * NOTE: should revert if can't fullfit all requested withdrawals.
     */
    function rebalance(DataTypes.AdaptorCall[] calldata distributionMatrix) external nonReentrant onlyRebalanceProvider {
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
     * @notice  allows user to request the token withdrawal if the amount of underlying asset is not enough on the vault
     * @dev     shares shouldn't be burned but user can't use them in any other way
     * @param   shares  amount of shares user will redeem during next rebalance
     */
    function requestWithdraw(uint256 shares) external nonReentrant {
        require(shares <= maxRedeem(msg.sender), "ERC4626: withdraw more than max");
        require(shares > 0, "Amount of shares should be greater than 0");
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
    function setFee(uint64 newPerformanceFee, uint64 newWithdrawFee) external onlyOwner {
        _setFee(newPerformanceFee, newWithdrawFee);
    }

    function _setFee(uint64 newPerformanceFee, uint64 newWithdrawFee) private {
        require(newPerformanceFee <= MAX_PERFORMANCE_FEE, "Performance fee limit exceeded");
        require(newWithdrawFee <= MAX_WITHDRAW_FEE, "Withdraw fee limit exceeded");
        claimFee();
        FeeData.performanceFee = newPerformanceFee;
        FeeData.withdrawFee = newWithdrawFee;

        emit FeesChanged(msg.sender, FeeData);
    }

    function setFeeTreasury(address newTreasury) public onlyOwner {
        _setFeeTreasury(newTreasury);
    }

    function _setFeeTreasury(address newTreasury) private {
        FeeData.treasury = newTreasury;

        emit FeesChanged(msg.sender, FeeData);
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
    ) internal virtual override whenNotDepositsPause nonReentrant {
        require(totalAssets() + assets <= poolLimitSize, "Pool limit exceeded");
        require(maxWithdraw(msg.sender) + assets <= userDepositLimit, "User deposit limit exceeded");
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
        uint256 withdrawFee = (assets * FeeData.withdrawFee) / (10 ** FEE_DECIMALS);
        _payFee(withdrawFee);
        assets -= withdrawFee;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _withdrawRequested(address withdrawer, uint256 assets, uint256 shares, uint256 id) internal {
        withdrawalsAfterFeeClaim += assets;
        uint256 withdrawFee = (assets * FeeData.withdrawFee) / (10 ** FEE_DECIMALS);
        _payFee(withdrawFee);

        assets -= withdrawFee;
        _burn(withdrawer, shares);
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), withdrawer, assets);

        emit WithdrawRequested(id, assets);
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

    function _isExecuteLegal(DataTypes.AdaptorCall calldata data) private returns (bool) {
        if (data.adaptor == asset()) {
            (bytes4 selector) = bytes4(data.callData[:4]);
            (address spender,) = abi.decode(data.callData[4:], (address, uint256));
            return selector == IERC20.approve.selector && isProtocol[spender];
        }

        if (isProtocol[data.adaptor]) {
            (bytes4 selector) = bytes4(data.callData[:4]);
            DataTypes.ProtocolSelectors memory adaptorSelectors = protocolSelectors[data.adaptor];
            return selector == adaptorSelectors.deposit || selector == adaptorSelectors.withdraw;
        }

        return false;
    }

    /**
     * @notice  executes the list of transactions for autocompound or rebalance
     */
    function _executeTransactions(DataTypes.AdaptorCall[] calldata _matrix) internal {
        for (uint8 i = 0; i < _matrix.length; ++i) {
            require(_isExecuteLegal(_matrix[i]), "Illegal execute");
            (bool success, ) = _matrix[i].adaptor.call(_matrix[i].callData);
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
            _withdrawRequested(withdrawQueue[i].receiver, assets, withdrawQueue[i].shares, withdrawQueue[i].id);
        }
        delete withdrawQueue;
        totalRequested = 0;
    }

    uint256[50] private __gap;
}

