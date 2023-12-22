// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ClonesUpgradeable.sol";
import {TreasuryContract} from "./ITreasury.sol";
import {VaultContract} from "./IVault.sol";

contract Factory is Initializable, UUPSUpgradeable {
    using AddressUpgradeable for address;
    address public treasuryContractAddress;
    address public vaultContractImplAddress;
    address public acceptedToken;
    uint64 public tradeFee;
    uint64 public withdrawalFee;
    struct TierData {
        uint256 tvl;
        uint64 reward;
    }
    TierData[] public tierData;
    mapping(string => address) public vaultIdToAddress;

    event CreateVault(
        string id,
        address vaultAddress,
        address[] whitelistAddresses,
        uint256 minimumInvestmentAmount,
        address indexed vaultCreator
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

    modifier isVaultCreator() {
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
     * @notice  Initialize contract and sets the variable value as per the parameters passed.
     * @param   _treasuryContractAddress Treasury contract address.
     * @param   _tradeFee Fee related to copy trade.
     * @param   _withdrawalFee Fee related to withdrawal trade on behalf of user.
     * @param   _acceptedToken Token address in which we will be accepting payment.
     * @param   _tierDataArray Vault creator tier configuration.
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
     * @notice Function to deploy a vault contract, only accessible by VAULT_CREATOR_ROLE.
     * @param _vaultId Unique vault id in string format.
     * @param _whitelistAddresses List of wallet address that are allowed to invest in vault.
     * @param _minimumInvestmentAmount Minimum amount of investment allowed to invest in vault.
     */
    function createVault(
        string memory _vaultId,
        address[] memory _whitelistAddresses,
        uint256 _minimumInvestmentAmount
    ) external isVaultCreator {
        require(
            vaultIdToAddress[_vaultId] == address(0),
            "Vault id already exist"
        );
        address vaultAddress = ClonesUpgradeable.clone(
            vaultContractImplAddress
        );
        VaultContract(vaultAddress).initialize(
            _vaultId,
            _whitelistAddresses,
            _minimumInvestmentAmount,
            address(this)
        );

        vaultIdToAddress[_vaultId] = vaultAddress;
        emit CreateVault(
            _vaultId,
            vaultAddress,
            _whitelistAddresses,
            _minimumInvestmentAmount,
            msg.sender
        );
    }

    /**
     * @notice Function to update the address of the accepted token,only accessible by ADMIN_ROLE.
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
     * @notice Function to update the transaction-related fee configuration,only accessible by ADMIN_ROLE.
     * @param _tradeFee The new trade fee to be applied for copy trade.
     * @param _withdrawalFee The new withdrawal fee to be applied for user withdrawals transaction.
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
     * @notice Function to update treasury address,only accessible by ADMIN_ROLE.
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
     * @notice Function to update vault implementation address,only accessible by ADMIN_ROLE.
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
     * @notice Function to update the tier level data for vault creator,only accessible by ADMIN_ROLE.
     * @param _tierDataArray Array of Tier data.
     */

    function updateTierData(TierData[] memory _tierDataArray) external isAdmin {
        require(
            _tierDataArray.length > 0,
            "Please provide a valid array of Tier data"
        );
        delete tierData;
        tierData.push(_tierDataArray[0]);
        for (uint8 i = 1; i < _tierDataArray.length; i++) {
            require(
                _tierDataArray[i - 1].tvl < _tierDataArray[i].tvl &&
                    _tierDataArray[i - 1].reward < _tierDataArray[i].reward,
                "Please arrange tiers in increasing values"
            );
            tierData.push(_tierDataArray[i]);
        }
        emit UpdatedTierData(tierData);
    }

    /**
     * @notice Function to get vault creator reward by checking vault creator's role and TVL of vault.
     * @param _vaultCreator Address of the vault creator.
     * @param _tvl TVL value of the vault.
     * @return Vault creator reward percentage with basis point.
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
     * @notice Function to fetch tierData length.
     * @return Vault creator tier configuration length.
     */
    function getTierDataLength() external view returns (uint256) {
        return tierData.length;
    }

    /**
     * @dev Function to fetch the vault creater reward based on the closest value.
     * @param _amount TVL value of a vault.
     * @return Closest reward percentage with basis point vault creator will receive.
     */
    function getVaultCreatorRewardBasedOnTVL(
        uint256 _amount
    ) private view returns (uint64) {
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
     * @dev Function to provide functionality for upgrading the contract by adding new implementation contract,
     * only accessible by ADMIN_ROLE.
     * @param   _newImplementation Implementation contract address.
     */
    function _authorizeUpgrade(
        address _newImplementation
    ) internal override isAdmin {}
}

