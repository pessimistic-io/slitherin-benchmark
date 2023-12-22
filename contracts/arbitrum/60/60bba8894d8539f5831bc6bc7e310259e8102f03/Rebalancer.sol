// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC4626.sol";
import "./ReentrancyGuard.sol";
import "./Registry.sol";

contract Rebalancer is ERC4626, Registry, ReentrancyGuard {
    event DistributionMatrixUpdated(
        address provider,
        DataTypes.AdaptorCall[] _newMatrix
    );
    event AutocompoundMatrixUpdated(
        address provider,
        DataTypes.AdaptorCall[] _newMatrix
    );
    event Harvest(address caller, uint256 totalIncome);
    event Rebalance(address caller);
    event FeesChanged(address owner, DataTypes.feeData newFeeData);
    event FeesCharged(address treasury, uint256 amount);
    event RequestWithdraw(address withdrawer, uint256 amount);

    DataTypes.feeData public FeeData;
    DataTypes.AdaptorCall[] public distributionMatrix;
    DataTypes.AdaptorCall[] public autocompoundMatrix;

    bool public distributionMatrixExecuted;
    bool public autocompoundMatrixExecuted;

    address public poolToken;
    DataTypes.withdrawRequest[] public withdrawQueue;
    uint256 public totalRequested;

    uint256 lastBalance;
    uint256 depositsAfterFeeClaim;
    uint256 withdrawalsAfterFeeClaim;

    uint64 public constant MAX_PLATFORM_FEE = 0.3 * 1e18;
    uint64 public constant MAX_WITHDRAW_FEE = 0.05 * 1e18;
    uint256 public constant WITHDRAW_QUEUE_LIMIT = 10;
    uint256 public constant feeDecimals = 18;

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _treasury,
        address[] memory _positions,
        address[] memory _iBTokens,
        address rebalanceMatrixProvider,
        address autocompoundMatrixProvider
    ) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) {
        poolToken = _asset;

        FeeData = DataTypes.feeData({
            platformFee: 0.05 * 1e18,
            withdrawFee: 0.0001 * 1e18,
            treasury: _treasury
        });

        for (uint i = 0; i < _positions.length; i++) {
            addPosition(_positions[i]);
        }

        for (uint i = 0; i < _iBTokens.length; i++) {
            addIBToken(_iBTokens[i]);
        }
        grantRole(REBALANCE_PROVIDER_ROLE, rebalanceMatrixProvider);
        grantRole(AUTOCOMPOUND_PROVIDER_ROLE, autocompoundMatrixProvider);
    }

    function setDistributionMatrix(
        DataTypes.AdaptorCall[] memory _newMatrix
    ) public onlyRebalanceProvider {
        delete distributionMatrix;
        distributionMatrixExecuted = false;

        for (uint8 i = 0; i < _newMatrix.length; ++i) {
            require(
                isAdaptorSetup[_newMatrix[i].adaptor],
                "Adaptor is not whitelisted"
            );
            distributionMatrix.push(_newMatrix[i]);
        }

        emit DistributionMatrixUpdated(msg.sender, _newMatrix);
    }

    function setAutocompoundMatrix(
        DataTypes.AdaptorCall[] memory _newMatrix
    ) public onlyAutocompoundProvider {
        delete autocompoundMatrix;
        autocompoundMatrixExecuted = false;

        for (uint8 i = 0; i < _newMatrix.length; ++i) {
            require(
                isAdaptorSetup[_newMatrix[i].adaptor],
                "Adaptor is not whitelisted"
            );
            autocompoundMatrix.push(_newMatrix[i]);
        }

        emit AutocompoundMatrixUpdated(msg.sender, _newMatrix);
    }

    function harvest() external nonReentrant {
        require(!autocompoundMatrixExecuted, "Matrix already executed");
        uint256 balanceBefore = totalAssets();
        _executeTransactions(autocompoundMatrix);
        uint256 balanceAfter = totalAssets();
        require(
            balanceBefore < balanceAfter,
            "Balance after should be greater"
        );
        autocompoundMatrixExecuted = true;

        emit Harvest(msg.sender, balanceAfter - balanceBefore);
    }

    function rebalance() external nonReentrant {
        require(!distributionMatrixExecuted, "Matrix already executed");
        _executeTransactions(distributionMatrix);
        distributionMatrixExecuted = true;

        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            uint256 fee = (withdrawQueue[i].amount * FeeData.withdrawFee) /
                (10 ** feeDecimals);
            _payFee(fee);
            IERC20(poolToken).transfer(
                withdrawQueue[i].receiver,
                withdrawQueue[i].amount - fee
            );
        }
        delete withdrawQueue;
        totalRequested = 0;
        emit Rebalance(msg.sender);
    }

    function _executeTransactions(
        DataTypes.AdaptorCall[] memory _matrix
    ) internal {
        for (uint8 i = 0; i < _matrix.length; ++i) {
            address adaptor = _matrix[i].adaptor;
            (bool success, ) = adaptor.call(_matrix[i].callData);
            require(success, "transaction failed");
        }
    }

    function totalAssetsWithoutFee() private view returns (uint256) {
        uint256 _totalAssets = IERC20(asset()).balanceOf(address(this));
        for (uint i = 0; i < iBTokens.length; i++) {
            _totalAssets += IERC20(iBTokens[i]).balanceOf(address(this));
        }
        _totalAssets -= totalRequested;

        return _totalAssets;
    }

    function totalAssets() public view override returns (uint256) {
        return totalAssetsWithoutFee() - getAvailableFee();
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
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
        uint256 withdrawFee = (assets * FeeData.withdrawFee) /
            (10 ** feeDecimals);
        _payFee(withdrawFee);
        super._withdraw(caller, receiver, owner, assets - withdrawFee, shares);
    }

    function requestWithdraw(uint256 assets) public {
        require(
            assets <= maxWithdraw(msg.sender),
            "ERC4626: withdraw more than max"
        );
        require(
            assets > IERC20(poolToken).balanceOf(address(this)),
            "Instant withdraw is available"
        );
        require(
            withdrawQueue.length < WITHDRAW_QUEUE_LIMIT,
            "Withdraw queue limit exceeded."
        );

        withdrawalsAfterFeeClaim += assets;

        uint256 shares = previewWithdraw(assets);

        _burn(msg.sender, shares);
        totalRequested += assets;
        withdrawQueue.push(DataTypes.withdrawRequest(msg.sender, assets));

        emit RequestWithdraw(msg.sender, assets);
    }

    function setFee(DataTypes.feeData memory newFeeData) public onlyOwner {
        require(
            newFeeData.platformFee <= MAX_PLATFORM_FEE,
            "Platform fee limit exceeded."
        );
        require(
            newFeeData.withdrawFee <= MAX_WITHDRAW_FEE,
            "Withdraw fee limit exceeded."
        );
        FeeData = newFeeData;

        emit FeesChanged(msg.sender, newFeeData);
    }

    function getAvailableFee() public view returns (uint256) {
        return
            ((totalAssetsWithoutFee() +
                withdrawalsAfterFeeClaim -
                lastBalance -
                depositsAfterFeeClaim) * FeeData.platformFee) /
            (10 ** feeDecimals);
    }

    function claimFee() public onlyOwner {
        _payFee(getAvailableFee());
        withdrawalsAfterFeeClaim = 0;
        depositsAfterFeeClaim = 0;
        lastBalance = totalAssetsWithoutFee();
    }

    function _payFee(uint256 amount) internal {
        if (amount > 0) {
            IERC20(poolToken).transfer(FeeData.treasury, amount);

            emit FeesCharged(FeeData.treasury, amount);
        }
    }
}

