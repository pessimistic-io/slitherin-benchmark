// SPDX-License-Identifier: GPL-3.0

/// This contract is the main contract for customer transactions.
pragma solidity >=0.8.0;

import "./IERC20.sol";
import "./IVault.sol";

import "./Address.sol";
import "./TransferHelper.sol";

import {IRetireOption} from "./IRetireOption.sol";
import {IApplyBuyIntent} from "./IApplyBuyIntent.sol";
import {IExecution} from "./IExecution.sol";
import {IJudgementCondition} from "./IJudgementCondition.sol";

import "./ISwap.sol";
import {Auxiliary} from "./Auxiliary.sol";
import {DataTypes} from "./DataTypes.sol";

import {IProductPool} from "./IProductPool.sol";
import {ICustomerPool} from "./ICustomerPool.sol";

import {Initializable} from "./Initializable.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ICDXNFT} from "./ICDXNFT.sol";
import {ConfigurationParam} from "./ConfigurationParam.sol";

contract CDX is Ownable, Initializable, ReentrancyGuard {
    address public ownerAddress;
    IRetireOption public retireOption;
    ICustomerPool public customerPool;
    IJudgementCondition public judgmentCondition;
    ISwap public swap;
    IExecution public execution;
    IProductPool public productPool;
    IApplyBuyIntent public applyBuyIntent;
    IVault public vault;
    ICDXNFT public CDXNFT;
    bool public notFreezeStatus;
    address public guardianAddress;
    bool public locked;
    uint256 public applyBuyFee;
    uint256 public rewardFee;
    address public stableC;

    /// @dev Initialise important addresses for the contract.
    function initialize() external initializer {
        _transferOwnership(_msgSender());
        _initNonReentrant();
        ownerAddress = msg.sender;
        notFreezeStatus = true;
        applyBuyFee = 1000;
        rewardFee = 100000;
        stableC = ConfigurationParam.USDT;
        guardianAddress = ConfigurationParam.GUARDIAN;
    }

    function updateApplyBuyFee(uint256 _applyBuyFee) external onlyOwner {
        require(_applyBuyFee > 0, "applyBuyFee is zero");
        applyBuyFee = _applyBuyFee;
    }

    function updateRewardFee(uint256 _rewardFee) external onlyOwner {
        require(_rewardFee > 0, "rewardFee is zero");
        rewardFee = _rewardFee;
    }

    /// @dev Update StableC addresses for the contract.
    function updateStableC(address _stableC) external onlyOwner {
        require(
            _stableC == ConfigurationParam.USDC || _stableC == ConfigurationParam.USDT,
            "BasePositionManager: the parameter is error address"
        );
        stableC = _stableC;
    }

    /// @dev Update CDXNFT contract addresses for the contract.
    function updateCDXNFTAddress(address _NFTAddress) external onlyOwner {
        require(Address.isContract(_NFTAddress), "BasePositionManager: the parameter is not the contract address");
        CDXNFT = ICDXNFT(_NFTAddress);
    }

    /// @dev Update Vault addresses for the contract.
    function updateVaultAddress(address _vaultAddress) external onlyOwner {
        require(Address.isContract(_vaultAddress), "BasePositionManager: the parameter is not the contract address");
        vault = IVault(_vaultAddress);
    }

    /**
     * notice Call vault to get the reward amount.
     * @param _pid Product id.
     * @param _customerId Customer id.
     * @param _customerReward Reward.
     */
    function updateCustomerReward(
        uint256 _pid,
        uint256 _customerId,
        uint256 _customerReward
    ) external nonReentrant synchronized onlyOwner {
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        require(_customerReward > 0, "BasePositionManager: must be greater than zero");
        DataTypes.PurchaseProduct memory purchaseProduct = customerPool.getSpecifiedProduct(_pid, _customerId);
        require(purchaseProduct.amount > 0, "CustomerPoolManager: purchase record not found");
        vault.transferToCDX(
            stableC,
            _customerReward,
            _customerId,
            _pid,
            purchaseProduct.amount,
            purchaseProduct.releaseHeight
        );
        bool result = customerPool.updateCustomerReward(_pid, _customerId, _customerReward);
        require(result, "CustomerPoolManager: update failed");
    }

    /**
     * notice Customers purchase products.
     * @param _pid Product id.
     * @param amount Purchase quota.
     */
    function _c_applyBuyIntent(uint256 amount, uint256 _pid) external nonReentrant synchronized returns (bool) {
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        uint256 manageFee = (amount * applyBuyFee) / ConfigurationParam.FEE_DECIMAL;
        uint256 buyAmount = amount - manageFee;
        (uint256 cryptoQuantity, address ercToken) = applyBuyIntent.dealApplyBuyCryptoQuantity(
            buyAmount,
            _pid,
            productPool,
            stableC
        );
        uint256 customerId = CDXNFT.mintCDX(msg.sender);
        bool success = customerPool.addCustomerByProduct(
            _pid,
            customerId,
            msg.sender,
            buyAmount,
            ercToken,
            0,
            cryptoQuantity
        );
        require(success, "CustomerPoolManager: applyBuyIntent failed");
        bool updateSoldTotalAmount = productPool.updateSoldTotalAmount(_pid, buyAmount);
        require(updateSoldTotalAmount, "ProductManager: updateSoldTotalAmount failed");
        TransferHelper.safeTransferFrom(ercToken, msg.sender, address(this), amount);
        TransferHelper.safeTransfer(ercToken, guardianAddress, manageFee);
        DataTypes.TransferHelperInfo[] memory transferHelperInfo = new DataTypes.TransferHelperInfo[](2);
        transferHelperInfo[0] = DataTypes.TransferHelperInfo(
            msg.sender,
            address(this),
            amount,
            ercToken,
            DataTypes.TransferHelperStatus.TOTHIS
        );
        transferHelperInfo[1] = DataTypes.TransferHelperInfo(
            address(this),
            guardianAddress,
            manageFee,
            ercToken,
            DataTypes.TransferHelperStatus.TOMANAGE
        );
        emit ApplyBuyIntent(_pid, msg.sender, amount, ercToken, customerId, transferHelperInfo);
        return success;
    }

    fallback() external payable {
        emit Log(msg.sender, msg.value);
    }

    receive() external payable {
        emit Log(msg.sender, msg.value);
    }

    /// @dev Update Judgment contract addresses for the contract.
    function updateJudgmentAddress(address _judgmentAddress) external onlyOwner {
        require(Address.isContract(_judgmentAddress), "BasePositionManager: the parameter is not the contract address");
        judgmentCondition = IJudgementCondition(_judgmentAddress);
    }

    /// @dev Update Swap contract addresses for the contract.
    function updateSwapExactAddress(address _swapAddress) external onlyOwner {
        require(Address.isContract(_swapAddress), "BasePositionManager: the parameter is not the contract address");
        swap = ISwap(_swapAddress);
    }

    /// @dev Update ApplyBuyIntent contract addresses for the contract.
    function updateApplyBuyIntentAddress(address _applyBuyIntent) external onlyOwner {
        require(Address.isContract(_applyBuyIntent), "BasePositionManager: the parameter is not the contract address");
        applyBuyIntent = IApplyBuyIntent(_applyBuyIntent);
    }

    /// @dev Update RetireOption contract addresses for the contract.
    function updateRetireOptionAddress(address _retireOptionAddress) external onlyOwner {
        require(
            Address.isContract(_retireOptionAddress),
            "BasePositionManager: the parameter is not the contract address"
        );
        retireOption = IRetireOption(_retireOptionAddress);
    }

    /// @dev Update Execution contract addresses for the contract.
    function updateExecutionAddress(address _executionAddress) external onlyOwner {
        require(
            Address.isContract(_executionAddress),
            "BasePositionManager: the parameter is not the contract address"
        );
        execution = IExecution(_executionAddress);
    }

    /// @dev Update ProductPool contract addresses for the contract.
    function updateProductPoolAddress(address _productPoolAddress) external onlyOwner {
        require(
            Address.isContract(_productPoolAddress),
            "BasePositionManager: the parameter is not the contract address"
        );
        productPool = IProductPool(_productPoolAddress);
    }

    /// @dev Update CustomerPool contract addresses for the contract.
    function updateCustomerPoolAddress(address _customerPoolAddress) external onlyOwner {
        require(
            Address.isContract(_customerPoolAddress),
            "BasePositionManager: the parameter is not the contract address"
        );
        customerPool = ICustomerPool(_customerPoolAddress);
    }

    /**
     * notice Retire of specified products.
     * @param _s_pid Product id.
     */
    function _s_retireOneProduct(uint256 _s_pid) external onlyOwner synchronized nonReentrant returns (bool) {
        DataTypes.ProgressStatus result = judgmentCondition.judgementConditionAmount(address(productPool), _s_pid);
        uint256 amount;
        DataTypes.TransferHelperInfo memory transferHelperInfo;
        if (DataTypes.ProgressStatus.UNREACHED == result) {
            Auxiliary.updateProductStatus(productPool, _s_pid, result);
        } else {
            Auxiliary.updateProductStatus(productPool, _s_pid, result);
            (, amount) = Auxiliary.swapExchange(productPool, retireOption, swap, applyBuyIntent, _s_pid, stableC);
            if (amount > 0) {
                TransferHelper.safeTransfer(stableC, address(vault), amount);
                transferHelperInfo = DataTypes.TransferHelperInfo(
                    address(this),
                    address(vault),
                    amount,
                    stableC,
                    DataTypes.TransferHelperStatus.TOVALUT
                );
            }
        }
        emit RetireOneProduct(_s_pid, msg.sender, result, transferHelperInfo);
        return true;
    }

    /**
     * notice Specify purchase record exercise.
     * @param _s_pid Product id.
     * @param _customerId Customer id.
     */
    function _c_executeOneCustomer(
        uint256 _s_pid,
        uint256 _customerId
    ) external synchronized nonReentrant returns (bool) {
        require(notFreezeStatus, "BasePositionManager: this operation cannot be performed.");
        DataTypes.ProductInfo memory product = productPool.getProductInfoByPid(_s_pid);
        require(
            DataTypes.ProgressStatus.UNDELIVERED != product.resultByCondition,
            "ProductManager: undelivered product"
        );
        (DataTypes.CustomerByCrypto memory principal, DataTypes.CustomerByCrypto memory rewards) = execution
            .executeWithRewards(address(productPool), _customerId, msg.sender, _s_pid, customerPool, stableC);
        uint256 rewardFeeValue = (rewards.amount * rewardFee) / ConfigurationParam.FEE_DECIMAL;
        Auxiliary.delCustomerFromProductList(_s_pid, _customerId, customerPool);
        TransferHelper.safeTransfer(rewards.cryptoAddress, guardianAddress, rewardFeeValue);
        TransferHelper.safeTransfer(principal.cryptoAddress, principal.customerAddress, principal.amount);
        TransferHelper.safeTransfer(rewards.cryptoAddress, rewards.customerAddress, rewards.amount - rewardFeeValue);
        DataTypes.TransferHelperInfo[] memory transferHelperInfo = new DataTypes.TransferHelperInfo[](3);
        transferHelperInfo[0] = DataTypes.TransferHelperInfo(
            address(this),
            guardianAddress,
            rewardFeeValue,
            rewards.cryptoAddress,
            DataTypes.TransferHelperStatus.TOMANAGE
        );
        transferHelperInfo[1] = DataTypes.TransferHelperInfo(
            address(this),
            principal.customerAddress,
            principal.amount,
            principal.cryptoAddress,
            DataTypes.TransferHelperStatus.TOCUSTOMERP
        );
        transferHelperInfo[2] = DataTypes.TransferHelperInfo(
            address(this),
            rewards.customerAddress,
            rewards.amount - rewardFeeValue,
            rewards.cryptoAddress,
            DataTypes.TransferHelperStatus.TOCUSTOMERR
        );
        emit ExecuteOneCustomer(_s_pid, _customerId, msg.sender, transferHelperInfo);
        return true;
    }

    function withdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyGuardian nonReentrant returns (bool) {
        require(recipient != address(0), "BasePositionManager: the recipient address cannot be empty");
        require(token != address(0), "TokenManager: the token address cannot be empty");
        uint256 balance = getBalanceOf(token);
        require(balance > 0, "BasePositionManager: insufficient balance");
        require(balance >= amount, "TransferManager: excess balance");
        TransferHelper.safeTransfer(token, recipient, amount);
        emit Withdraw(address(this), recipient, token, amount);
        return true;
    }

    function allowanceFrom(address ercToken, address from) public view returns (uint256) {
        IERC20 tokenErc20 = IERC20(ercToken);
        uint256 amount = tokenErc20.allowance(from, address(this));
        return amount;
    }

    /// @dev Gets the token balance specified in the contract.
    function getBalanceOf(address token) public view returns (uint256) {
        IERC20 tokenInToken = IERC20(token);
        return tokenInToken.balanceOf(address(this));
    }

    modifier onlyGuardian() {
        require(guardianAddress == msg.sender, "Ownable: caller is not the Guardian");
        _;
    }

    modifier synchronized() {
        require(!locked, "BasePositionManager: Please wait");
        locked = true;
        _;
        locked = false;
    }

    event ApplyBuyIntent(
        uint256 _pid,
        address sender,
        uint256 amount,
        address ercToken,
        uint256 customerId,
        DataTypes.TransferHelperInfo[] transferHelperInfoList
    );
    event RetireOneProduct(
        uint256 productId,
        address msgSend,
        DataTypes.ProgressStatus status,
        DataTypes.TransferHelperInfo transferHelperInfo
    );
    event ExecuteOneCustomer(
        uint256 productAddr,
        uint256 releaseHeight,
        address msgSend,
        DataTypes.TransferHelperInfo[] transferHelperInfoList
    );
    event Withdraw(address from, address to, address cryptoAddress, uint256 amount);
    event Log(address from, uint256 value);
}

