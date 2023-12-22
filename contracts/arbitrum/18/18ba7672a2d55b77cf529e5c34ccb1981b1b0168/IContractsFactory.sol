// SPDX-License-Identifier: MIT



pragma solidity >=0.8.0;

interface IContractsFactory {
    error ZeroAddress(string target);
    error InvalidCaller();
    error FeeRateError();
    error ZeroAmount();
    error InvestorAlreadyExists();
    error InvestorNotExists();
    error TraderAlreadyExists();
    error TraderNotExists();
    error FailedWalletDeployment();
    error FailedVaultDeployment();
    error InvalidWallet();
    error InvalidVault();
    error InvalidTrader();
    error InvalidToken();
    error TokenPresent();
    error UsersVaultAlreadyDeployed();

    event FeeRateSet(uint256 newFeeRate);
    event FeeReceiverSet(address newFeeReceiver);
    event InvestorAdded(address indexed investorAddress);
    event InvestorRemoved(address indexed investorAddress);
    event TraderAdded(address indexed traderAddress);
    event TraderRemoved(address indexed traderAddress);
    event GlobalTokenAdded(address tokenAddress);
    event GlobalTokenRemoved(address tokenAddress);
    event AdaptersRegistryAddressSet(address indexed adaptersRegistryAddress);
    event DynamicValuationAddressSet(address indexed dynamicValuationAddress);
    event LensAddressSet(address indexed lensAddress);
    event TraderWalletDeployed(
        address indexed traderWalletAddress,
        address indexed traderAddress,
        address indexed underlyingTokenAddress
    );
    event UsersVaultDeployed(
        address indexed usersVaultAddress,
        address indexed traderWalletAddress
    );
    event OwnershipToWalletChanged(
        address indexed traderWalletAddress,
        address indexed newOwner
    );
    event OwnershipToVaultChanged(
        address indexed usersVaultAddress,
        address indexed newOwner
    );
    event TraderWalletImplementationChanged(address indexed newImplementation);
    event UsersVaultImplementationChanged(address indexed newImplementation);

    function BASE() external view returns (uint256);

    function feeRate() external view returns (uint256);

    function feeReceiver() external view returns (address);

    function dynamicValuationAddress() external view returns (address);

    function adaptersRegistryAddress() external view returns (address);

    function lensAddress() external view returns (address);

    function traderWalletsArray(uint256) external view returns (address);

    function isTraderWallet(address) external view returns (bool);

    function usersVaultsArray(uint256) external view returns (address);

    function isUsersVault(address) external view returns (bool);

    function allowedTraders(address) external view returns (bool);

    function allowedInvestors(address) external view returns (bool);

    function initialize(
        uint256 feeRate,
        address feeReceiver,
        address traderWalletImplementation,
        address usersVaultImplementation
    ) external;

    function addInvestors(address[] calldata investors) external;

    function addInvestor(address investorAddress) external;

    function removeInvestor(address investorAddress) external;

    function addTraders(address[] calldata traders) external;

    function addTrader(address traderAddress) external;

    function removeTrader(address traderAddress) external;

    function setDynamicValuationAddress(
        address dynamicValuationAddress
    ) external;

    function setAdaptersRegistryAddress(
        address adaptersRegistryAddress
    ) external;

    function setLensAddress(address lensAddress) external;

    function setFeeReceiver(address newFeeReceiver) external;

    function setFeeRate(uint256 newFeeRate) external;

    function setUsersVaultImplementation(address newImplementation) external;

    function setTraderWalletImplementation(address newImplementation) external;

    function addGlobalAllowedTokens(address[] calldata) external;

    function removeGlobalToken(address) external;

    function deployTraderWallet(
        address underlyingTokenAddress,
        address traderAddress,
        address owner
    ) external;

    function deployUsersVault(
        address traderWalletAddress,
        address owner,
        string memory sharesName,
        string memory sharesSymbol
    ) external;

    function usersVaultImplementation() external view returns (address);

    function traderWalletImplementation() external view returns (address);

    function numOfTraderWallets() external view returns (uint256);

    function numOfUsersVaults() external view returns (uint256);

    function isAllowedGlobalToken(address token) external returns (bool);

    function allowedGlobalTokensAt(
        uint256 index
    ) external view returns (address);

    function allowedGlobalTokensLength() external view returns (uint256);

    function getAllowedGlobalTokens() external view returns (address[] memory);
}

