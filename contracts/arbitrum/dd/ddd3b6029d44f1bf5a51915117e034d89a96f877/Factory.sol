// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./AddressUpgradeable.sol";
import {TreasuryContract} from "./ITreasury.sol";
import {Vault} from "./Vault.sol";

contract Factory is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;
    address public treasuryContractAddress;
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
        address[] privateWalletAddresses,
        address creator,
        uint256 minimumInvestmentAmount,
        string identifier,
        address vaultAddress
    );

    event UpdatedAcceptedToken(address acceptedToken);

    event UpdatedFee(uint64 tradeFee, uint64 withdrawalFee);

    event UpdatedTierData(TierData[] tierDataArray);

    modifier isAdmin() {
        require(
            TreasuryContract(treasuryContractAddress).isAdmin(msg.sender),
            "Not authorized"
        );
        _;
    }

    modifier vaultCreatorCheck() {
        require(
            TreasuryContract(treasuryContractAddress).isVaultCreator(
                msg.sender
            ) || TreasuryContract(treasuryContractAddress).isAdmin(msg.sender),
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
        uint64 _tradeFee,
        uint64 _withdrawalFee,
        address _acceptedToken,
        TierData[] memory _tierDataArray
    ) public initializer {
        treasuryContractAddress = _treasuryContractAddress;
        tradeFee = _tradeFee;
        withdrawalFee = _withdrawalFee;
        acceptedToken = _acceptedToken;
        for (uint8 i = 0; i < _tierDataArray.length; i++) {
            tierData.push(_tierDataArray[i]);
        }
    }

    /**
     * Function get vault creator fee by checking if vault creator has VAULT_CREATOR_ROLE or ADMIN_ROLE and TVL of vault
     * @param _vaultCreator address of the vault creator
     * @param _tvl TVL value of the vault
     */
    function getVaultCreatorFee(
        address _vaultCreator,
        uint256 _tvl
    ) external view returns (uint64) {
        bool isNonAdmin = TreasuryContract(treasuryContractAddress)
            .isVaultCreator(_vaultCreator) ||
            !TreasuryContract(treasuryContractAddress).isAdmin(_vaultCreator);
        uint64 creatorFee = isNonAdmin ? getVaultCreatorFeeBasedOnTVL(_tvl) : 0;
        return creatorFee;
    }

    /**
     * Function to deploy a vault contract, only accessible by ADMIN_ROLE or VAULT_CREATOR_ROLE
     * @param _privateWalletAddresses list of wallet address that are allowed to invest in vault
     * @param _minimumInvestmentAmount Minimum amount of investment allowed to invest in vault
     */
    function createVault(
        address[] memory _privateWalletAddresses,
        uint256 _minimumInvestmentAmount,
        string memory identifier
    ) external vaultCreatorCheck {
        _vaultIdCounter.increment();
        uint256 vaultId = _vaultIdCounter.current();
        Vault vault = new Vault(
            vaultId,
            _privateWalletAddresses,
            msg.sender,
            _minimumInvestmentAmount,
            address(this)
        );

        vaultIdToAddress[vaultId] = address(vault);
        emit CreateVault(
            vaultId,
            _privateWalletAddresses,
            msg.sender,
            _minimumInvestmentAmount,
            identifier,
            address(vault)
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
                i > 0 && _tierDataArray[i - 1].tvl >= _tierDataArray[i].tvl
                //last tier value is greater than current tiers value
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
    function getVaultCreatorFeeBasedOnTVL(
        uint256 _amount
    ) internal view returns (uint64) {
        require(tierData.length > 0, "No tiers available");

        // uint256 closestDifference = type(uint).max;
        uint64 closestPercentage = tierData[tierData.length - 1].reward;

        for (uint8 i = 0; i < tierData.length - 1; i++) {
            if (_amount >= tierData[i].tvl && _amount < tierData[i + 1].tvl) {
                closestPercentage = tierData[i].reward;
                break;
            }
        }

        return closestPercentage;
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
     * @notice  Provides functionality to upgrade the contract by adding new implementation contract,caller must have Admin role .
     * @param   _newImplementation  .
     */
    function _authorizeUpgrade(
        address _newImplementation
    ) internal override isAdmin {}
}

