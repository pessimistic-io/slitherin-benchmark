// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./Clones.sol";
import "./Ownable.sol";

//local imports
import "./DEAccountManager.sol";
import "./DEBorrowOperations.sol";
import "./CollSurplusPool.sol";
import "./MainPool.sol";
import "./SortedAccounts.sol";
import "./HintHelpers.sol";
import "./MultiAccountGetter.sol";

contract DEShareVaultDeployer is Ownable{

    // implementation addresses to clone and deploy new vaults
    address public accountManager;
    address public borrowOperations;
    address public collSurplusPool;
    address public mainPool;
    address public sortedAccounts;
    address public hintHelpers;
    address public multiAccountGetter;

    address public goveranceFeeAddress; // address where borrowing and redemption fee will be sent

    address public unboundFeesFactory; // unbound fees factory address
    address public undToken; // UND token address

    uint256 public vaultId = 0; // id of the next vault which is going to be deployed

    event NewVaultDeployed (
        address accountManager,
        address borrowOperations,
        address collSurplusPool,
        address mainPool,
        address sortedAccounts,
        address depositToken,
        address hintHelpers,
        address multiAccountGetter
    );

    struct VaultAddresses{
        address accountManager;
        address borrowOperations;
        address collSurplusPool;
        address mainPool;
        address sortedAccounts;
        address depositToken;
        address hintHelpers;
        address multiAccountGetter;
    }

    // to get rid of stack too deep error
    struct LocalVariables {
        uint256 _minimumCollateralRatio;
        address _chainLinkRegistry;
        uint256 _allowedDelay;
    }

    // map vault vaultId with vault addresses struct
    mapping ( uint256 => VaultAddresses ) public vaultAddresses;

    /// @dev Deploys a vaults with given parameters
    /// @param _depositToken Collateral token address
    /// @param _minimumCollateralRatio Minimum collateral ratio for the vault
    /// @param _chainLinkRegistry Chainlink registry address
    /// @param _allowedDelay Allowed delay for price update in chainlink feed
    /// @param _mainPoolContractOwner Owner address of the mainPool contract
    function deployVault(
        address _depositToken,
        uint256 _minimumCollateralRatio,
        address _chainLinkRegistry,
        uint256 _allowedDelay,
        address _mainPoolContractOwner
    ) public onlyOwner {

        VaultAddresses memory vault;

        vault.depositToken = _depositToken;

        vault.accountManager = Clones.clone(accountManager);
        vault.borrowOperations = Clones.clone(borrowOperations);
        vault.collSurplusPool = Clones.clone(collSurplusPool);
        vault.mainPool = Clones.clone(mainPool);
        vault.sortedAccounts = Clones.clone(sortedAccounts);
        vault.hintHelpers = Clones.clone(hintHelpers);
        vault.multiAccountGetter = Clones.clone(multiAccountGetter);

        LocalVariables memory _inputs = LocalVariables(_minimumCollateralRatio, _chainLinkRegistry, _allowedDelay);
        _initAccManager(vault, _inputs);
        _initborrowOps(vault);
        _initCollSurPlusPool(vault);
        _initMainPool(vault, _mainPoolContractOwner);
        _initSortedAccounts(vault);
        _initHintHelpers(vault);
        _initMultiAccountGetter(vault);

        vaultAddresses[vaultId] = vault;
        vaultId++;

        emit NewVaultDeployed(
            vault.accountManager,
            vault.borrowOperations,
            vault.collSurplusPool,
            vault.mainPool,
            vault.sortedAccounts,
            vault.depositToken,
            vault.hintHelpers,
            vault.multiAccountGetter
        );
    }

    function _initAccManager(
        VaultAddresses memory _vault,
        LocalVariables memory _inputs
    ) internal {

        DEAccountManager _accManager = DEAccountManager(_vault.accountManager);

        _accManager.initialize(
            unboundFeesFactory, 
            _vault.borrowOperations, 
            _vault.mainPool, 
            undToken, 
            _vault.sortedAccounts, 
            _vault.collSurplusPool, 
            _vault.depositToken, 
            _inputs._chainLinkRegistry, 
            _inputs._allowedDelay,
            goveranceFeeAddress, 
            _inputs._minimumCollateralRatio
        );
    }

    function _initborrowOps(VaultAddresses memory _vault) internal {
        DEBorrowOperations _borrowOps = DEBorrowOperations(_vault.borrowOperations);

        _borrowOps.initialize(_vault.accountManager);
    }

    function _initCollSurPlusPool(VaultAddresses memory _vault) internal {
        CollSurplusPool _collSurPlusPool = CollSurplusPool(_vault.collSurplusPool);

        _collSurPlusPool.initialize(_vault.accountManager, _vault.borrowOperations);
    }

    function _initMainPool(VaultAddresses memory _vault, address _owner) internal {
        MainPool _mainPool = MainPool(_vault.mainPool); 

        _mainPool.initialize(_vault.accountManager, _vault.borrowOperations, _vault.depositToken, _owner);
    }

    function _initSortedAccounts(VaultAddresses memory _vault) internal {
        SortedAccounts _sortedAccounts = SortedAccounts(_vault.sortedAccounts);

        _sortedAccounts.initialize(_vault.accountManager, _vault.borrowOperations);
    }

    function _initHintHelpers(VaultAddresses memory _vault) internal {
        HintHelpers _hintHelper = HintHelpers(_vault.hintHelpers);

        _hintHelper.initialize(_vault.accountManager, _vault.sortedAccounts);
    }

    function _initMultiAccountGetter(VaultAddresses memory _vault) internal {
        MultiAccountGetter _multiAccountGetter = MultiAccountGetter(_vault.multiAccountGetter);

        _multiAccountGetter.initialize(_vault.accountManager, _vault.sortedAccounts);
    }

    /// @dev Set all required contract address
    /// @param _accountManager DEAccountManager contracts implementation address
    /// @param _borrowOperations DEBorrowOperations contract implementation address
    /// @param _collSurplusPool CollSurplusPool contract implementation address
    /// @param _mainPool MainPool contract implementation address
    /// @param _sortedAccounts SortedAccounts contract implementation address
    /// @param _hintHelpers HintHelpers contract implementation address
    /// @param _multiAccountGetter MultiAccountGetter contract implementation address
    /// @param _unboundFeesFactory Unbound fees factory contracts
    /// @param _undToken UND token contract address
    /// @param _goveranceFeeAddress governance address where all the borrowing & redemption fees will be sent
    function setAddresses(
        address _accountManager,
        address _borrowOperations,
        address _collSurplusPool,
        address _mainPool,
        address _sortedAccounts,
        address _hintHelpers,
        address _multiAccountGetter,
        address _unboundFeesFactory,
        address _undToken,
        address _goveranceFeeAddress
    ) public onlyOwner {
        accountManager = _accountManager;
        borrowOperations = _borrowOperations;
        collSurplusPool = _collSurplusPool;
        mainPool = _mainPool;
        sortedAccounts = _sortedAccounts;
        hintHelpers = _hintHelpers;
        multiAccountGetter = _multiAccountGetter;
        unboundFeesFactory = _unboundFeesFactory;
        undToken = _undToken;
        goveranceFeeAddress = _goveranceFeeAddress;
    }
}
