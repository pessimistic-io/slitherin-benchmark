// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721, IERC721, IERC165} from "./ERC721.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {Address} from "./Address.sol";

import {SupaState} from "./SupaState.sol";
import {WalletProxy} from "./WalletProxy.sol";

import {ISupaConfig, ERC20Pool, ERC20Share, ERC20Info, ERC721Info, ContractData, ContractKind} from "./ISupa.sol";
import {IVersionManager} from "./IVersionManager.sol";
import {IERC20ValueOracle} from "./IERC20ValueOracle.sol";
import {INFTValueOracle} from "./INFTValueOracle.sol";

import {ImmutableGovernance} from "./ImmutableGovernance.sol";
import {WalletLib} from "./WalletLib.sol";
import {ERC20PoolLib} from "./ERC20PoolLib.sol";

import {Errors} from "./Errors.sol";

/// @title Supa Config
contract SupaConfig is SupaState, ImmutableGovernance, ISupaConfig {
    using WalletLib for WalletLib.Wallet;
    using ERC20PoolLib for ERC20Pool;
    using SafeERC20 for IERC20;
    using Address for address;

    constructor(address _owner) ImmutableGovernance(_owner) {}

    /// @inheritdoc ISupaConfig
    function upgradeWalletImplementation(
        string calldata version
    ) external override onlyWallet whenNotPaused {
        (
            ,
            IVersionManager.Status status,
            IVersionManager.BugLevel bugLevel,
            address implementation,

        ) = versionManager.getVersionDetails(version);
        if (implementation == address(0) || !implementation.isContract()) {
            revert Errors.InvalidImplementation();
        }
        if (status == IVersionManager.Status.DEPRECATED) {
            revert Errors.DeprecatedVersion();
        }
        if (bugLevel != IVersionManager.BugLevel.NONE) {
            revert Errors.BugLevelTooHigh();
        }
        walletLogic[msg.sender] = implementation;
        emit ISupaConfig.WalletImplementationUpgraded(msg.sender, version, implementation);
    }

    /// @inheritdoc ISupaConfig
    function proposeTransferWalletOwnership(
        address newOwner
    ) external override onlyWallet whenNotPaused {
        walletProposedNewOwner[msg.sender] = newOwner;
        emit ISupaConfig.WalletOwnershipTransferProposed(msg.sender, newOwner);
    }

    /// @inheritdoc ISupaConfig
    function executeTransferWalletOwnership(address wallet) external override whenNotPaused {
        if (msg.sender != walletProposedNewOwner[wallet]) {
            revert Errors.InvalidNewOwner(walletProposedNewOwner[wallet], msg.sender);
        }
        wallets[wallet].owner = msg.sender;
        delete walletProposedNewOwner[wallet];
        emit ISupaConfig.WalletOwnershipTransferred(wallet, msg.sender);
    }

    /// @inheritdoc ISupaConfig
    function pause() external override onlyGovernance {
        _pause();
    }

    /// @inheritdoc ISupaConfig
    function unpause() external override onlyGovernance {
        _unpause();
    }

    /// @inheritdoc ISupaConfig
    function addERC20Info(
        address erc20Contract,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address valueOracle,
        uint256 baseRate,
        uint256 slope1,
        uint256 slope2,
        uint256 targetUtilization
    ) external override onlyGovernance returns (uint16) {
        uint16 erc20Idx = uint16(erc20Infos.length);
        erc20Infos.push(
            ERC20Info(
                erc20Contract,
                IERC20ValueOracle(valueOracle),
                ERC20Pool(0, 0),
                ERC20Pool(0, 0),
                baseRate,
                slope1,
                slope2,
                targetUtilization,
                block.timestamp
            )
        );
        infoIdx[erc20Contract] = ContractData(erc20Idx, ContractKind.ERC20);
        emit ISupaConfig.ERC20Added(
            erc20Idx,
            erc20Contract,
            name,
            symbol,
            decimals,
            valueOracle,
            baseRate,
            slope1,
            slope2,
            targetUtilization
        );
        return erc20Idx;
    }

    /// @inheritdoc ISupaConfig
    function addERC721Info(
        address erc721Contract,
        address valueOracleAddress
    ) external override onlyGovernance {
        if (!IERC165(erc721Contract).supportsInterface(type(IERC721).interfaceId)) {
            revert Errors.NotNFT();
        }
        INFTValueOracle valueOracle = INFTValueOracle(valueOracleAddress);
        uint256 erc721Idx = erc721Infos.length;
        erc721Infos.push(ERC721Info(erc721Contract, valueOracle));
        infoIdx[erc721Contract] = ContractData(uint16(erc721Idx), ContractKind.ERC721);
        emit ISupaConfig.ERC721Added(erc721Idx, erc721Contract, valueOracleAddress);
    }

    /// @inheritdoc ISupaConfig
    function setConfig(Config calldata _config) external override onlyGovernance {
        config = _config;
        emit ISupaConfig.ConfigSet(_config);
    }

    /// @inheritdoc ISupaConfig
    function setTokenStorageConfig(
        TokenStorageConfig calldata _tokenStorageConfig
    ) external override onlyGovernance {
        tokenStorageConfig = _tokenStorageConfig;
        emit ISupaConfig.TokenStorageConfigSet(_tokenStorageConfig);
    }

    /// @inheritdoc ISupaConfig
    function setVersionManager(address _versionManager) external override onlyGovernance {
        versionManager = IVersionManager(_versionManager);
        emit ISupaConfig.VersionManagerSet(_versionManager);
    }

    /// @inheritdoc ISupaConfig
    function setERC20Data(
        address erc20,
        address valueOracle,
        uint256 baseRate,
        uint256 slope1,
        uint256 slope2,
        uint256 targetUtilization
    ) external override onlyGovernance {
        uint16 erc20Idx = infoIdx[erc20].idx;
        if (infoIdx[erc20].kind != ContractKind.ERC20) {
            revert Errors.NotERC20();
        }
        erc20Infos[erc20Idx].valueOracle = IERC20ValueOracle(valueOracle);
        erc20Infos[erc20Idx].baseRate = baseRate;
        erc20Infos[erc20Idx].slope1 = slope1;
        erc20Infos[erc20Idx].slope2 = slope2;
        erc20Infos[erc20Idx].targetUtilization = targetUtilization;
        emit ISupaConfig.ERC20DataSet(
            erc20,
            erc20Idx,
            valueOracle,
            baseRate,
            slope1,
            slope2,
            targetUtilization
        );
    }

    /// @inheritdoc ISupaConfig
    function createWallet() external override whenNotPaused returns (address wallet) {
        wallet = address(new WalletProxy{salt: keccak256(abi.encode(msg.sender, walletNonce[msg.sender]++))}(address(this)));
        wallets[wallet].owner = msg.sender;

        // add a version parameter if users should pick a specific version
        (, , , address implementation, ) = versionManager.getRecommendedVersion();
        walletLogic[wallet] = implementation;
        emit ISupaConfig.WalletCreated(wallet, msg.sender);
    }

    /// @inheritdoc ISupaConfig
    function getCreditAccountERC20(
        address walletAddr,
        IERC20 erc20
    ) external view override returns (int256) {
        WalletLib.Wallet storage wallet = wallets[walletAddr];
        (ERC20Info storage erc20Info, uint16 erc20Idx) = getERC20Info(erc20);
        ERC20Share erc20Share = wallet.erc20Share[erc20Idx];
        return getBalance(erc20Share, erc20Info);
    }

    /// @inheritdoc ISupaConfig
    function getCreditAccountERC721(
        address wallet
    ) external view override returns (NFTData[] memory) {
        NFTData[] memory nftData = new NFTData[](wallets[wallet].nfts.length);
        for (uint i = 0; i < nftData.length; i++) {
            (uint16 erc721Idx, uint256 tokenId) = getNFTData(wallets[wallet].nfts[i]);
            nftData[i] = NFTData(erc721Infos[erc721Idx].erc721Contract, tokenId);
        }
        return nftData;
    }

    /// @inheritdoc ISupaConfig
    function getCreditAccountERC721Counter(address wallet) external view returns (uint256) {
        return wallets[wallet].nfts.length;
    }
}

