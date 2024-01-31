// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./EnumerableSetUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IPToken.sol";

abstract contract PTokenStorage is IPToken {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using AddressUpgradeable for address;

    // Constants used in calculation
    uint256 internal constant BASE_PERCENTS = 1e18;

    /// @notice keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice ptoken factory contract address
    address public override factory;

    /// @notice Underlying NFT address
    address public override nftAddress;

    /// @notice nft fraction amount 1 NFT = pieceCount ptoken
    uint256 public override pieceCount;

    bytes32 public override DOMAIN_SEPARATOR;

    /// @notice Nonce for each EIP712 signature <user address, nonce>
    mapping(address => uint) public override nonces;

    // nft id list for random swap
    EnumerableSetUpgradeable.UintSet internal _allRandID;
    
    // All nft id info <NFT ID, NFT Info>
    mapping(uint256 => NftInfo) internal _allInfo;
}
