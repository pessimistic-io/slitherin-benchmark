// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC4626.sol";
import "./ReentrancyGuard.sol";
import "./Registry.sol";

contract Rebalancer is ERC4626, Registry, ReentrancyGuard {
    event Harvest(address caller, uint256 totalIncome);
    event Rebalance(address caller);
    event FeesChanged(address owner, DataTypes.feeData newFeeData);
    event FeesCharged(address treasury, uint256 amount);
    event RequestWithdraw(address withdrawer, uint256 shares);

    DataTypes.feeData public FeeData;

    uint256 public totalRequested;
    mapping(address => uint256) lockedShares;
    DataTypes.withdrawRequest[] public withdrawQueue;

    uint256 lastBalance;
    uint256 depositsAfterFeeClaim;
    uint256 withdrawalsAfterFeeClaim;

    uint64 public constant MAX_PLATFORM_FEE = 0.3 * 1e18;
    uint64 public constant MAX_WITHDRAW_FEE = 0.05 * 1e18;
    uint256 public constant REBALANCE_THRESHOLD = 0.001 * 1e18;
    uint256 public constant WITHDRAW_QUEUE_LIMIT = 10;
    uint256 public constant feeDecimals = 18;

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _treasury,
        address[] memory _positions,
        address[] memory _iTokens,
        address _rebalanceMatrixProvider,
        address _autocompoundMatrixProvider,
        address _router
    ) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) Registry(_router) {
        FeeData = DataTypes.feeData({platformFee: 0.1 * 1e18, withdrawFee: 0.0001 * 1e18, treasury: _treasury});

        for (uint i = 0; i < _positions.length; i++) {
            addPosition(_positions[i]);
        }

        for (uint i = 0; i < _iTokens.length; i++) {
            addIToken(_iTokens[i]);
        }

        grantRole(REBALANCE_PROVIDER_ROLE, _rebalanceMatrixProvider);
        grantRole(AUTOCOMPOUND_PROVIDER_ROLE, _autocompoundMatrixProvider);
    }

    function _executeTransactions(DataTypes.AdaptorCall[] memory _matrix) internal {
        for (uint8 i = 0; i < _matrix.length; ++i) {
            address adaptor = _matrix[i].adaptor;
            require(isAdaptorSetup[adaptor]);
            (bool success, ) = adaptor.call(_matrix[i].callData);
            require(success, "transaction failed");
        }
    }

    function totalAssetsWithoutFee() private view returns (uint256) {
        uint256 _totalAssets = IERC20(asset()).balanceOf(address(this));
        for (uint i = 0; i < iTokens.length; i++) {
            _totalAssets += router.getTokenValue(asset(), iTokens[i], IERC20(iTokens[i]).balanceOf(address(this)));
        }
        return _totalAssets;
    }

    function getAvailableFee() public view returns (uint256) {
        return
            ((totalAssetsWithoutFee() + withdrawalsAfterFeeClaim - lastBalance - depositsAfterFeeClaim) *
                FeeData.platformFee) / (10 ** feeDecimals);
    }

    function totalAssets() public view override returns (uint256) {
        return totalAssetsWithoutFee() - getAvailableFee();
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return super.maxWithdraw(owner) - lockedShares[owner];
    }

    function harvest(DataTypes.AdaptorCall[] memory autocompoundMatrix) external nonReentrant {
        uint256 balanceBefore = totalAssets();
        _executeTransactions(autocompoundMatrix);
        uint256 balanceAfter = totalAssets();
        require(balanceBefore < balanceAfter, "Balance after should be greater");

        emit Harvest(msg.sender, balanceAfter - balanceBefore);
    }

    function rebalance(DataTypes.AdaptorCall[] memory distributionMatrix) external nonReentrant {
        uint256 balanceBefore = totalAssets();
        _executeTransactions(distributionMatrix);
        uint256 balanceAfter = totalAssets();
        require(
            ((balanceBefore * (1e18 - REBALANCE_THRESHOLD)) / 1e18) <= balanceAfter,
            "Asset balance become too low."
        );
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
        }
        delete withdrawQueue;

        emit Rebalance(msg.sender);
    }

    function requestWithdraw(uint256 shares) public nonReentrant {
        require(shares <= maxWithdraw(msg.sender), "ERC4626: withdraw more than max");
        require(shares > previewWithdraw(IERC20(asset()).balanceOf(address(this))), "Instant withdraw is available");
        require(withdrawQueue.length < WITHDRAW_QUEUE_LIMIT, "Withdraw queue limit exceeded.");

        lockedShares[msg.sender] += shares;

        withdrawQueue.push(DataTypes.withdrawRequest(msg.sender, shares));

        totalRequested += shares;

        emit RequestWithdraw(msg.sender, shares);
    }

    function setFee(DataTypes.feeData memory newFeeData) public onlyOwner {
        require(newFeeData.platformFee <= MAX_PLATFORM_FEE, "Platform fee limit exceeded.");
        require(newFeeData.withdrawFee <= MAX_WITHDRAW_FEE, "Withdraw fee limit exceeded.");

        claimFee();
        FeeData = newFeeData;

        emit FeesChanged(msg.sender, newFeeData);
    }

    function claimFee() public onlyOwner {
        _payFee(getAvailableFee());

        withdrawalsAfterFeeClaim = 0;
        depositsAfterFeeClaim = 0;
        lastBalance = totalAssetsWithoutFee();
    }

    function addIToken(address token) public override onlyOwner {
        router.getTokenValue(asset(), token, 0);
        super.addIToken(token);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        depositsAfterFeeClaim += assets;
        super._deposit(caller, receiver, assets, shares);
    }

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

    function _payFee(uint256 amount) internal {
        if (amount > 0) {
            IERC20(asset()).transfer(FeeData.treasury, amount);

            emit FeesCharged(FeeData.treasury, amount);
        }
    }
}

