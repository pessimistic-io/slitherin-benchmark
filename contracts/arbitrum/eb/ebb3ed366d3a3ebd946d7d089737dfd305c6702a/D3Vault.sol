// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./D3VaultFunding.sol";
import "./D3VaultLiquidation.sol";

contract D3Vault is D3VaultFunding, D3VaultLiquidation {
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    // ---------- Setting ----------

    function addD3PoolByFactory(address pool) external onlyFactory {
        require(allPoolAddrMap[pool] == false, Errors.POOL_ALREADY_ADDED);
        allPoolAddrMap[pool] = true;
        address creator = ID3MM(pool)._CREATOR_();
        creatorPoolMap[creator].push(pool);
        emit AddPool(pool);
    }

    function addD3Pool(address pool) external onlyOwner {
        require(allPoolAddrMap[pool] == false, Errors.POOL_ALREADY_ADDED);
        allPoolAddrMap[pool] = true;
        address creator = ID3MM(pool)._CREATOR_();
        creatorPoolMap[creator].push(pool);
        emit AddPool(pool);
    }

    // ================= Remove Pool Steps ===================

    /// @notice When removing a pool
    /// @notice if the pool has enough assets to repay all borrows, we can just repay:
    /// @notice removeD3Pool() -> pendingRemovePoolRepayAll() -> finishPoolRemove()
    /// @notice if not, should go through liquidation process by DODO:
    /// @notice removeD3Pool() -> liquidateByDODO() -> finishPoolRemove()
    function removeD3Pool(address pool) external onlyOwner {
        require(allPoolAddrMap[pool] == true, Errors.POOL_NOT_ADDED);
        ID3MM(pool).startLiquidation();

        allPoolAddrMap[pool] = false;
        _PENDING_REMOVE_POOL_ = pool;
        address creator = ID3MM(pool)._CREATOR_();
        address[] memory poolList = creatorPoolMap[creator];
        for (uint256 i = 0; i < poolList.length; i++) {
            if (poolList[i] == pool) {
                poolList[i] == poolList[poolList.length - 1];
                creatorPoolMap[creator] = poolList;
                creatorPoolMap[creator].pop();
                emit RemovePool(pool);
                break;
            }
        }
    }

    function pendingRemovePoolRepayAll(address token) external onlyOwner {
        _poolRepayAll(_PENDING_REMOVE_POOL_, token);
        ID3MM(_PENDING_REMOVE_POOL_).updateReserveByVault(token);
    }

    function finishPoolRemove() external onlyOwner {
        ID3MM(_PENDING_REMOVE_POOL_).finishLiquidation();
        _PENDING_REMOVE_POOL_ = address(0);
        emit RemovePool(_PENDING_REMOVE_POOL_);
    }

    // ====================================================

    function setCloneFactory(address cloneFactory) external onlyOwner {
        _CLONE_FACTORY_ = cloneFactory;
    }

    function setNewD3Factory(address newFactory) external onlyOwner {
        _D3_FACTORY_ = newFactory;
    }

    function setNewD3UserQuota(address newQuota) external onlyOwner {
        _USER_QUOTA_ = newQuota;
    }

    function setNewD3PoolQuota(address newQuota) external onlyOwner {
        _POOL_QUOTA_ = newQuota;
    }

    function setNewOracle(address newOracle) external onlyOwner {
        _ORACLE_ = newOracle;
    }

    function setNewRateManager(address newRateManager) external onlyOwner {
        _RATE_MANAGER_ = newRateManager;
    }

    function setMaintainer(address maintainer) external onlyOwner {
        _MAINTAINER_ = maintainer;
    }

    function setIM(uint256 newIM) external onlyOwner {
        IM = newIM;
    }

    function setMM(uint256 newMM) external onlyOwner {
        MM = newMM;
    }

    function setDiscount(uint256 discount) external onlyOwner {
        DISCOUNT = discount;
    }

    function setDTokenTemplate(address dTokenTemplate) external onlyOwner {
        _D3TOKEN_LOGIC_ = dTokenTemplate;
    }

    function addRouter(address router) external onlyOwner {
        allowedRouter[router] = true;
    }

    function removeRouter(address router) external onlyOwner {
        allowedRouter[router] = false;
    }

    function addLiquidator(address liquidator) external onlyOwner {
        allowedLiquidator[liquidator] = true;
    }

    function removeLiquidator(address liquidator) external onlyOwner {
        allowedLiquidator[liquidator] = false;
    }

    function addNewToken(
        address token,
        uint256 maxDeposit,
        uint256 maxCollateral,
        uint256 collateralWeight,
        uint256 debtWeight,
        uint256 reserveFactor
    ) external onlyOwner {
        require(!tokens[token], Errors.TOKEN_ALREADY_EXIST);
        require(collateralWeight < 1e18 && debtWeight > 1e18, Errors.WRONG_WEIGHT);
        require(reserveFactor < 1e18, Errors.WRONG_RESERVE_FACTOR);
        tokens[token] = true;
        tokenList.push(token);
        address dToken = createDToken(token);
        AssetInfo storage info = assetInfo[token];
        info.dToken = dToken;
        info.reserveFactor = reserveFactor;
        info.borrowIndex = 1e18;
        info.accrualTime = block.timestamp;
        info.maxDepositAmount = maxDeposit;
        info.maxCollateralAmount = maxCollateral;
        info.collateralWeight = collateralWeight;
        info.debtWeight = debtWeight;
    }

    function createDToken(address token) public returns (address) {
        address d3Token = ICloneFactory(_CLONE_FACTORY_).clone(_D3TOKEN_LOGIC_);
        IDToken(d3Token).init(token, address(this));
        return d3Token;
    }

    function setToken(
        address token,
        uint256 maxDeposit,
        uint256 maxCollateral,
        uint256 collateralWeight,
        uint256 debtWeight,
        uint256 reserveFactor
    ) external onlyOwner {
        require(tokens[token], Errors.TOKEN_NOT_EXIST);
        require(collateralWeight < 1e18 && debtWeight > 1e18, Errors.WRONG_WEIGHT);
        require(reserveFactor < 1e18, Errors.WRONG_RESERVE_FACTOR);
        AssetInfo storage info = assetInfo[token];
        info.maxDepositAmount = maxDeposit;
        info.maxCollateralAmount = maxCollateral;
        info.collateralWeight = collateralWeight;
        info.debtWeight = debtWeight;
        info.reserveFactor = reserveFactor;
    }

    function withdrawReserves(address token, uint256 amount) external nonReentrant allowedToken(token) onlyOwner {
        accrueInterest(token);
        AssetInfo storage info = assetInfo[token];
        uint256 totalReserves = info.totalReserves;
        uint256 withdrawnReserves = info.withdrawnReserves;
        require(amount <= totalReserves - withdrawnReserves, Errors.WITHDRAW_AMOUNT_EXCEED);
        info.withdrawnReserves = info.withdrawnReserves + amount;
        IERC20(token).safeTransfer(_MAINTAINER_, amount);
    }

    // ---------- View ----------

    function getAssetInfo(address token)
        external
        view
        returns (
            address dToken,
            uint256 totalBorrows,
            uint256 totalReserves,
            uint256 reserveFactor,
            uint256 borrowIndex,
            uint256 accrualTime,
            uint256 maxDepositAmount,
            uint256 collateralWeight,
            uint256 debtWeight,
            uint256 withdrawnReserves,
            uint256 balance
        )
    {
        AssetInfo storage info = assetInfo[token];
        balance = info.balance;
        dToken = info.dToken;
        totalBorrows = info.totalBorrows;
        totalReserves = info.totalReserves;
        reserveFactor = info.reserveFactor;
        borrowIndex = info.borrowIndex;
        accrualTime = info.accrualTime;
        maxDepositAmount = info.maxDepositAmount;
        collateralWeight = info.collateralWeight;
        debtWeight = info.debtWeight;
        withdrawnReserves = info.withdrawnReserves;
    }

    function getIMMM() external view returns (uint256, uint256) {
        return (IM, MM);
    }

    function getTokenList() external view returns (address[] memory) {
        return tokenList;
    }
}

