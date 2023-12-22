// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ClonesUpgradeable.sol";
import {TreasuryContract} from "./ITreasury.sol";
import {VaultContract} from "./IVault.sol";

contract Factory is Initializable, UUPSUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;
    address public treasuryContractAddress;
    address public vaultContractImplAddress;
    address public acceptedToken;
    uint64 public tradeFee;
    uint64 public withdrawalFee;
    struct TierData {
        uint tvl;
        uint64 reward;
    }
    CountersUpgradeable.Counter private _vaultIdCounter;
    TierData[] public tierData;
    mapping(uint256 => address) public vaultIdToAddress;

    event CreateVault(
        uint256 indexed id,
        address vaultAddress,
        address[] privateWalletAddresses,
        uint256 minimumInvestmentAmount,
        address vaultCreator
    );

    event UpdatedAcceptedToken(address acceptedToken);

    event UpdatedFee(uint64 tradeFee, uint64 withdrawalFee);

    event UpdatedTierData(TierData[] tierDataArray);

    event UpdatedTreasuryAddress(address treasuryContractAddress);

    event UpdatedVaultImplAddress(address vaultContractImplAddress);

    modifier isAdmin() {
        require(
            TreasuryContract(treasuryContractAddress).isAdmin(msg.sender),
            "Not authorized"
        );
        _;
    }

    modifier isPlatformWallet() {
        require(
            TreasuryContract(treasuryContractAddress).isPlatformWallet(
                msg.sender
            ),
            "Not authorized"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice  Initialize contract,provides _superAdmin wallet address DEFAULT_ADMIN and ADMIN role and sets role ADMIN as a role admin for ENTREPRENEUR role  .
     * @param   _treasuryContractAddress  .
     * @param   _tradeFee .
     * @param   _withdrawalFee .
     * @param   _acceptedToken .
     * @param   _tierDataArray .
     */
    function initialize(
        address _treasuryContractAddress,
        address _vaultContractImplAddress,
        uint64 _tradeFee,
        uint64 _withdrawalFee,
        address _acceptedToken,
        TierData[] memory _tierDataArray
    ) public initializer {
        treasuryContractAddress = _treasuryContractAddress;
        vaultContractImplAddress = _vaultContractImplAddress;
        tradeFee = _tradeFee;
        withdrawalFee = _withdrawalFee;
        acceptedToken = _acceptedToken;
        for (uint8 i = 0; i < _tierDataArray.length; i++) {
            tierData.push(_tierDataArray[i]);
        }
    }

    /**
     * Function to get vault creator reward by checking vault creator's role and TVL of vault
     * @param _vaultCreator address of the vault creator
     * @param _tvl TVL value of the vault
     */
    function getVaultCreatorReward(
        address _vaultCreator,
        uint256 _tvl
    ) external view returns (uint64) {
        bool hasAdminRole = TreasuryContract(treasuryContractAddress).isAdmin(
            _vaultCreator
        );
        uint64 creatorReward = hasAdminRole
            ? 0
            : getVaultCreatorRewardBasedOnTVL(_tvl);
        return creatorReward;
    }

    /**
     * Function to deploy a vault contract, only accessible by PLATFORM_ROLE
     * @param _vaultCreator wallet address of user requested for vault deployment
     * @param _privateWalletAddresses list of wallet address that are allowed to invest in vault
     * @param _minimumInvestmentAmount Minimum amount of investment allowed to invest in vault
     */
    function createVault(
        address _vaultCreator,
        address[] memory _privateWalletAddresses,
        uint256 _minimumInvestmentAmount
    ) external isPlatformWallet {
        _vaultIdCounter.increment();
        uint256 vaultId = _vaultIdCounter.current();
        address vaultAddress = ClonesUpgradeable.clone(
            vaultContractImplAddress
        );
        VaultContract(vaultAddress).initialize(
            vaultId,
            _privateWalletAddresses,
            _vaultCreator,
            _minimumInvestmentAmount,
            address(this)
        );

        vaultIdToAddress[vaultId] = vaultAddress;
        emit CreateVault(
            vaultId,
            vaultAddress,
            _privateWalletAddresses,
            _minimumInvestmentAmount,
            _vaultCreator
        );
    }

    /**
     * Function to update the address of the accepted token.
     * @param _acceptedToken The new address of the accepted token.
     */
    function updateAcceptedTokens(address _acceptedToken) external isAdmin {
        require(
            _acceptedToken.isContract(),
            "Please provide valid token address"
        );
        acceptedToken = _acceptedToken;
        emit UpdatedAcceptedToken(acceptedToken);
    }

    /**
     * Function to fetch tierData length.
     */
    function getTierDataLength() external view returns (uint256) {
        return tierData.length;
    }

    /**
     * @notice Update the transaction-related fee configuration.
     * @param _tradeFee The new trade fee to be applied for transactions.
     * @param _withdrawalFee The new withdrawal fee to be applied for user withdrawals.
     */
    function updateTransactionFee(
        uint64 _tradeFee,
        uint64 _withdrawalFee
    ) external isAdmin {
        tradeFee = _tradeFee;
        withdrawalFee = _withdrawalFee;
        emit UpdatedFee(tradeFee, withdrawalFee);
    }

    /**
     * @notice Update treasury address.
     * @param _treasuryContractAddress The new treasury address.
     */
    function updateTreasuryAddress(
        address _treasuryContractAddress
    ) external isAdmin {
        require(
            _treasuryContractAddress.isContract(),
            "Please provide valid contract address"
        );
        treasuryContractAddress = _treasuryContractAddress;
        emit UpdatedTreasuryAddress(treasuryContractAddress);
    }

    /**
     * @notice Update vault Implementation address.
     * @param _vaultContractImplAddress The new implementation contract address for vault.
     */
    function updateVaultContractImplAddress(
        address _vaultContractImplAddress
    ) external isAdmin {
        require(
            _vaultContractImplAddress.isContract(),
            "Please provide valid contract address"
        );
        vaultContractImplAddress = _vaultContractImplAddress;
        emit UpdatedVaultImplAddress(vaultContractImplAddress);
    }

    /**
     * Function to update the tier level data for vault creator.
     * deletes the previous tier data and sets it with the new one
     * @param _tierDataArray Array of Tier data
     */
    function updateTierData(TierData[] memory _tierDataArray) external isAdmin {
        require(
            _tierDataArray.length > 0,
            "Please provide valid array of Tier data"
        );
        delete tierData;
        bool isSorted = true;
        for (uint8 i = 0; i < _tierDataArray.length; i++) {
            if (
                i > 0 &&
                _tierDataArray[i - 1].tvl >= _tierDataArray[i].tvl &&
                _tierDataArray[i - 1].reward >= _tierDataArray[i].reward
                //last tier value should be greater than current tiers value
            ) {
                isSorted = false;
                break;
            }
            tierData.push(_tierDataArray[i]);
        }
        require(isSorted, "Factory: tiers should have increasing values");
        emit UpdatedTierData(tierData);
    }

    /**
     * Function to fetch the vault creater reward based on the closest value.
     * @param _amount TVL value of a vault
     */
    function getVaultCreatorRewardBasedOnTVL(
        uint256 _amount
    ) internal view returns (uint64) {
        require(tierData.length > 0, "No tiers available");
        uint64 closestPercentage;
        if (_amount < tierData[0].tvl) {
            return closestPercentage;
        }
        if (_amount >= tierData[tierData.length - 1].tvl) {
            return closestPercentage = tierData[tierData.length - 1].reward;
        }
        for (uint8 i = 0; i <= tierData.length - 2; i++) {
            if (_amount >= tierData[i].tvl && _amount < tierData[i + 1].tvl) {
                closestPercentage = tierData[i].reward;
                break;
            }
        }

        return closestPercentage;
    }

    /**
     * @notice  Provides functionality to upgrade the contract by adding new implementation contract,caller must have Admin role .
     * @param   _newImplementation  .
     */
    function _authorizeUpgrade(
        address _newImplementation
    ) internal override isAdmin {}
}

