// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./IERC20.sol";
import {ERC721, IERC721} from "./ERC721.sol";
import {Pausable} from "./Pausable.sol";

import {ISupaConfig, ERC20Pool, ERC20Share, NFTTokenData, ERC20Info, ERC721Info, ContractData, ContractKind} from "./ISupa.sol";
import {IVersionManager} from "./IVersionManager.sol";
import {WalletLib} from "./WalletLib.sol";
import {ERC20PoolLib} from "./ERC20PoolLib.sol";
import {WalletState} from "./WalletState.sol";

import {Errors} from "./Errors.sol";

/// @title Supa State
/// @notice Contract holds the configuration state for Supa
contract SupaState is Pausable {
    using ERC20PoolLib for ERC20Pool;

    IVersionManager public versionManager;
    /// @notice mapping between wallet address and Supa-specific wallet data
    mapping(address => WalletLib.Wallet) public wallets;

    /// @notice mapping between account and their nonce for wallet creation
    mapping(address account => uint256 nonce) public walletNonce;

    /// @notice mapping between wallet address and the proposed new owner
    /// @dev `proposedNewOwner` is address(0) when there is no pending change
    mapping(address => address) public walletProposedNewOwner;

    /// @notice mapping between wallet address and an instance of deployed walletLogic contract.
    /// It means that this specific walletLogic version is setup to operate the wallet.
    // @dev this could be a mapping to a version index instead of the implementation address
    mapping(address => address) public walletLogic;

    /// @notice mapping from
    /// wallet owner address => ERC20 address => wallet spender address => allowed amount of ERC20.
    /// It represent the allowance of `spender` to transfer up to `amount` of `erc20` balance of
    /// owner's creditAccount to some other creditAccount. E.g. 123 => abc => 456 => 1000, means that
    /// wallet 456 can transfer up to 1000 of abc tokens from creditAccount of wallet 123 to some other creditAccount.
    /// Note, that no ERC20 are actually getting transferred - creditAccount is a Supa concept, and
    /// corresponding tokens are owned by Supa
    mapping(address => mapping(address => mapping(address => uint256))) public allowances;

    /// @notice Whether a spender is approved to operate on behalf of an owner
    /// @dev Mapping from wallet owner address => spender address => bool
    mapping(address => mapping(address => bool)) public operatorApprovals;

    mapping(WalletLib.NFTId => NFTTokenData) public tokenDataByNFTId;

    ERC20Info[] public erc20Infos;
    ERC721Info[] public erc721Infos;

    /// @notice mapping of ERC20 or ERC721 address => Supa asset idx and contract kind.
    /// idx is the index of the ERC20 in `erc20Infos` or ERC721 in `erc721Infos`
    /// kind is ContractKind enum, that here can be ERC20 or ERC721
    mapping(address => ContractData) public infoIdx;

    ISupaConfig.Config public config;
    ISupaConfig.TokenStorageConfig public tokenStorageConfig;

    modifier onlyWallet() {
//        if (wallets[msg.sender].owner == address(0) || address(WalletState(msg.sender).supa()) != address(this)) {
            if (wallets[msg.sender].owner == address(0)) {
            revert Errors.OnlyWallet();
        }
        _;
    }

    modifier walletExists(address wallet) {
        if (wallets[wallet].owner == address(0)) {
            revert Errors.WalletNonExistent();
        }
        _;
    }

    function getBalance(
        ERC20Share shares,
        ERC20Info storage erc20Info
    ) internal view returns (int256) {
        ERC20Pool storage pool = ERC20Share.unwrap(shares) > 0
            ? erc20Info.collateral
            : erc20Info.debt;
        return pool.computeERC20(shares);
    }

    function getNFTData(
        WalletLib.NFTId nftId
    ) internal view returns (uint16 erc721Idx, uint256 tokenId) {
        uint256 unwrappedId = WalletLib.NFTId.unwrap(nftId);
        erc721Idx = uint16(unwrappedId);
        tokenId = tokenDataByNFTId[nftId].tokenId | ((unwrappedId >> 240) << 240);
    }

    function getERC20Info(IERC20 erc20) internal view returns (ERC20Info storage, uint16) {
        if (infoIdx[address(erc20)].kind != ContractKind.ERC20) {
            revert Errors.NotRegistered(address(erc20));
        }
        uint16 idx = infoIdx[address(erc20)].idx;
        return (erc20Infos[idx], idx);
    }
}

