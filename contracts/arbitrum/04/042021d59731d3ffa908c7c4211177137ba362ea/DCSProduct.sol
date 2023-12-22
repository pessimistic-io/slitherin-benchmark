// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IERC20 } from "./ERC20_IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Math } from "./Math.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { ICegaState } from "./ICegaState.sol";
import { Deposit, OptionBarrier, VaultStatus, Withdrawal } from "./Structs.sol";
import { DCSVault } from "./DCSVault.sol";
import { DCSCalculations } from "./DCSCalculations.sol";

contract DCSProduct is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event DCSProductCreated(
        address indexed cegaState,
        address indexed baseAssetAddress,
        address indexed alternativeAssetAddress,
        string name,
        uint256 feeBps,
        uint256 maxDepositAmountLimit,
        uint256 minDepositAmount,
        uint256 minWithdrawalAmount,
        address dcsCalculationsAddress
    );

    event MinDepositAmountUpdated(uint256 minDepositAmount);
    event MinWithdrawalAmountUpdated(uint256 minWithdrawalAmount);
    event IsDepositQueueOpenUpdated(bool isDepositQueueOpen);
    event MaxDepositAmountLimitUpdated(uint256 maxDepositAmountLimit);

    event VaultCreated(address indexed vaultAddress, string _tokenSymbol, string _tokenName, uint256 _vaultStart);
    event VaultRemoved(address indexed vaultAddress);

    event DepositQueued(address indexed receiver, uint256 amount);
    event DepositProcessed(address indexed vaultAddress, address indexed receiver, uint256 amount);

    event WithdrawalQueued(address indexed vaultAddress, address indexed receiver, uint256 amountShares);

    event VaultStatusUpdated(address indexed vaultAddress, VaultStatus vaultStatus);

    ICegaState public cegaState;

    address public immutable baseAssetAddress; // will usually be usdc
    address public immutable alternativeAssetAddress; // asset returned if final spot falls below strike
    string public name;
    uint256 public feeBps; // basis points
    bool public isDepositQueueOpen;
    uint256 public maxDepositAmountLimit;
    uint256 public minDepositAmount;
    uint256 public minWithdrawalAmount;

    uint256 public sumVaultUnderlyingAmounts;
    uint256 public queuedDepositsTotalAmount;
    uint256 public queuedDepositsCount;

    address[] public vaultAddresses;

    Deposit[] public depositQueue;

    address public dcsCalculationsAddress;

    /**
     * @notice Creates a new DCSProduct
     * @param _cegaState is the address of the CegaState contract
     * @param _baseAssetAddress is the address of the base currency
     * @param _alternativeAssetAddress is the adress of the alternative currency
     * @param _name is the name of the product
     * @param _maxDepositAmountLimit is the deposit limit for the product
     * @param _minDepositAmount is the minimum units of underlying for a user to deposit
     * @param _minWithdrawalAmount is the minimum units of vault shares for a user to withdraw
     */
    constructor(
        address _cegaState,
        address _baseAssetAddress,
        address _alternativeAssetAddress,
        string memory _name,
        uint256 _feeBps,
        uint256 _maxDepositAmountLimit,
        uint256 _minDepositAmount,
        uint256 _minWithdrawalAmount,
        address _dcsCalculationsAddress // if we need to upgrade/swap out calculations logic
    ) {
        require(_feeBps < 1e4, "400:IB");
        require(_minDepositAmount > 0, "400:IU");
        require(_minWithdrawalAmount > 0, "400:IU");
        require(_baseAssetAddress != address(0), "400:AD");
        require(_alternativeAssetAddress != address(0), "400:AD");

        cegaState = ICegaState(_cegaState);
        baseAssetAddress = _baseAssetAddress;
        alternativeAssetAddress = _alternativeAssetAddress;
        name = _name;
        feeBps = _feeBps;
        maxDepositAmountLimit = _maxDepositAmountLimit;
        isDepositQueueOpen = false;

        minDepositAmount = _minDepositAmount;
        minWithdrawalAmount = _minWithdrawalAmount;

        dcsCalculationsAddress = _dcsCalculationsAddress;
    }

    /**
     * @notice Asserts whether the sender has the DEFAULT_ADMIN_ROLE
     */
    modifier onlyDefaultAdmin() {
        require(cegaState.isDefaultAdmin(msg.sender), "403:DA");
        _;
    }

    /**
     * @notice Asserts whether the sender has the TRADER_ADMIN_ROLE
     */
    modifier onlyTraderAdmin() {
        require(cegaState.isTraderAdmin(msg.sender), "403:TA");
        _;
    }

    /**
     * @notice Asserts whether the sender has the OPERATOR_ADMIN_ROLE
     */
    modifier onlyOperatorAdmin() {
        require(cegaState.isOperatorAdmin(msg.sender), "403:OA");
        _;
    }

    /**
     * @notice Asserts that the vault has been initialized & is a Cega Vault
     */
    modifier onlyValidVault(address vaultAddress) {
        DCSVault vault = DCSVault(vaultAddress);
        // require(vault.vaultStart != 0, "400:VA");
        _;
    }

    /**
     * @notice Returns array of vault addresses associated with the product
     */
    function getVaultAddresses() public view returns (address[] memory) {
        return vaultAddresses;
    }

    /**
     * @notice Returns sum of base assets in all vaults
     */
    function getSumVaultBaseAssets() public view returns (uint256) {
        uint256 sumVaultBaseAssets = 0;
        for (uint i = 0; i < vaultAddresses.length; i++) {
            DCSVault vault = DCSVault(vaultAddresses[i]);
            uint256 vaultBaseAssets = vault.totalBaseAssets();
            sumVaultBaseAssets += vaultBaseAssets;
        }
        return sumVaultBaseAssets;
    }

    /**
     * @notice Returns sum of alternative assets in all vaults
     */
    function getSumVaultAlternativeAssets() public view returns (uint256) {
        uint256 sumVaultAlternativeAssets = 0;
        for (uint i = 0; i < vaultAddresses.length; i++) {
            DCSVault vault = DCSVault(vaultAddresses[i]);
            uint256 vaultAlternativeAssets = vault.totalAlternativeAssets();
            sumVaultAlternativeAssets += vaultAlternativeAssets;
        }
        return sumVaultAlternativeAssets;
    }

    function getFeeBps() public view returns (uint256) {
        return feeBps;
    }

    /**
     * @notice Sets a new address for DCSCalculations for future upgradability. Can only be modified by defaultadmin
     */
    function setDCSCalculationsAddress(address _newDCSCalculationsAddress) public onlyDefaultAdmin {
        dcsCalculationsAddress = _newDCSCalculationsAddress;
    }

    /**
     * @notice Sets the management fee for the product
     * @param _feeBps is the management fee in bps (100% = 10000)
     */
    function setFeeBps(uint256 _feeBps) public onlyOperatorAdmin {
        require(_feeBps < 1e4, "400:IB");
        feeBps = _feeBps;
    }

    /**
     * @notice Sets the min deposit amount for the product
     * @param _minDepositAmount is the minimum units of underlying for a user to deposit
     */
    function setMinDepositAmount(uint256 _minDepositAmount) public onlyOperatorAdmin {
        require(_minDepositAmount > 0, "400:IU");
        minDepositAmount = _minDepositAmount;
        emit MinDepositAmountUpdated(_minDepositAmount);
    }

    /**
     * @notice Sets the min withdrawal amount for the product
     * @param _minWithdrawalAmount is the minimum units of vault shares for a user to withdraw
     */
    function setMinWithdrawalAmount(uint256 _minWithdrawalAmount) public onlyOperatorAdmin {
        require(_minWithdrawalAmount > 0, "400:IU");
        minWithdrawalAmount = _minWithdrawalAmount;
        emit MinWithdrawalAmountUpdated(_minWithdrawalAmount);
    }

    /**
     * @notice Toggles whether the product is open or closed for deposits
     * @param _isDepositQueueOpen is a boolean for whether the deposit queue is accepting deposits
     */
    function setIsDepositQueueOpen(bool _isDepositQueueOpen) public onlyOperatorAdmin {
        isDepositQueueOpen = _isDepositQueueOpen;
        emit IsDepositQueueOpenUpdated(_isDepositQueueOpen);
    }

    /**
     * @notice Sets the maximum deposit limit for the product
     * @param _maxDepositAmountLimit is the deposit limit for the product
     */
    function setMaxDepositAmountLimit(uint256 _maxDepositAmountLimit) public onlyTraderAdmin {
        require(queuedDepositsTotalAmount + sumVaultUnderlyingAmounts <= _maxDepositAmountLimit, "400:TooSmall");
        maxDepositAmountLimit = _maxDepositAmountLimit;
        emit MaxDepositAmountLimitUpdated(_maxDepositAmountLimit);
    }

    /**
     * @notice Creates a new vault for the product & maps the new vault address to the vaultMetadata
     * @param _tokenName is the name of the token for the vault
     * @param _tokenSymbol is the symbol for the vault's token
     * @param _vaultStart is the timestamp of the vault's start
     */
    function createVault(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _vaultStart,
        address _cegaState
    ) public onlyTraderAdmin returns (address vaultAddress) {
        require(_vaultStart != 0, "400:VS");
        DCSVault vault = new DCSVault(_cegaState, baseAssetAddress, alternativeAssetAddress, _tokenName, _tokenSymbol);
        address newVaultAddress = address(vault);
        vaultAddresses.push(newVaultAddress);

        emit VaultCreated(newVaultAddress, _tokenSymbol, _tokenName, _vaultStart);
        return newVaultAddress;
    }

    /**
     * @notice defaultAdmin has the ability to remove a Vault
     * @param i is the index of the vault in the vaultAddresses array
     */
    function removeVault(uint256 i) public onlyDefaultAdmin {
        address vaultAddress = vaultAddresses[i];
        vaultAddresses[i] = vaultAddresses[vaultAddresses.length - 1];
        vaultAddresses.pop();

        emit VaultRemoved(vaultAddress);
    }

    /**
     * Transfers assets from the user to the product
     * @param amount is the amount of assets being deposited
     */
    function addToDepositQueue(uint256 amount) public nonReentrant {
        require(isDepositQueueOpen, "500:NotOpen");
        require(amount >= minDepositAmount, "400:DA");

        queuedDepositsCount += 1;
        queuedDepositsTotalAmount += amount;
        require((queuedDepositsTotalAmount + getSumVaultBaseAssets()) <= maxDepositAmountLimit, "500:TooBig");

        IERC20(baseAssetAddress).safeTransferFrom(msg.sender, address(this), amount);
        depositQueue.push(Deposit({ amount: amount, receiver: msg.sender }));
        emit DepositQueued(msg.sender, amount);
    }

    /**
     * Processes the product's deposit queue into a specific vault
     * @param vaultAddress is the address of the vault
     * @param maxProcessCount is the number of elements in the deposit queue to be processed
     */

    function processDepositQueue(
        address vaultAddress,
        uint256 maxProcessCount
    ) public nonReentrant onlyTraderAdmin onlyValidVault(vaultAddress) {
        DCSVault vault = DCSVault(vaultAddress);
        // require(vault.vaultStatus == VaultStatus.DepositsOpen, "500:WS");
        // require(!(vault.totalBaseAssets == 0 && vault.totalSupply() > 0), "500:Z");

        uint256 processCount = Math.min(queuedDepositsCount, maxProcessCount);
        Deposit storage deposit;

        while (processCount > 0) {
            deposit = depositQueue[queuedDepositsCount - 1];

            queuedDepositsTotalAmount -= deposit.amount;
            vault.deposit(deposit.amount, deposit.receiver);
            IERC20(baseAssetAddress).safeTransferFrom(address(this), vaultAddress, deposit.amount);

            depositQueue.pop();
            queuedDepositsCount -= 1;
            processCount -= 1;

            emit DepositProcessed(vaultAddress, deposit.receiver, deposit.amount);
        }

        if (queuedDepositsCount == 0) {
            // vault.vaultStatus = VaultStatus.NotTraded;
            emit VaultStatusUpdated(vaultAddress, VaultStatus.NotTraded);
        }
    }
}

