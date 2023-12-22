// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./ERC721Upgradeable.sol";
import "./AddressUpgradeable.sol";

import "./ChainId.sol";
import "./IERC1271.sol";
import "./IERC721PermitUpgradeable.sol";
import "./BlockTimestamp.sol";

/// @title ERC721Upgradeable with permit
/// @notice Nonfungible tokens that support an approve via signature, i.e. permit
abstract contract ERC721PermitUpgradeable is
    Initializable,
    BlockTimestamp,
    ERC721Upgradeable,
    IERC721PermitUpgradeable
{
    /// @dev Gets the current nonce for a token ID and then increments it, returning the original value
    function _getAndIncrementNonce(uint256 tokenId) internal virtual returns (uint256);

    /// @dev The hash of the name used in the permit signature verification
    bytes32 private nameHash;

    /// @dev The hash of the version string used in the permit signature verification
    bytes32 private versionHash;

    /*
     *     bytes4(keccak256('permit(address,uint256,uint256,uint8,bytes32,bytes32)')) == 0x7ac2ff7b
     *     bytes4(keccak256('DOMAIN_SEPARATOR()')) == 0x3644e515
     *     bytes4(keccak256('PERMIT_TYPEHASH()')) == 0x30adf81f
     *
     *
     *     => 0x7ac2ff7b ^ 0x3644e515 ^ 0x30adf81f == 0x7c2be271
     */
    bytes4 private constant _INTERFACE_ID_ERC721_PERMIT = 0x7c2be271;

    function __ERC721Permit_init(
        string memory name_,
        string memory symbol_,
        string memory version_
    ) internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name_, symbol_);
        __ERC721Permit_init_unchained(name_, version_);
    }

    function __ERC721Permit_init_unchained(string memory name_, string memory version_) internal initializer {
        nameHash = keccak256(bytes(name_));
        versionHash = keccak256(bytes(version_));

        // register the supported interfaces via ERC165
        _registerInterface(_INTERFACE_ID_ERC721_PERMIT);
    }

    /// @inheritdoc IERC721PermitUpgradeable
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    nameHash,
                    versionHash,
                    ChainId.get(),
                    address(this)
                )
            );
    }

    /// @inheritdoc IERC721PermitUpgradeable
    /// @dev Value is equal to keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    bytes32 public constant override PERMIT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;

    /// @inheritdoc IERC721PermitUpgradeable
    function permit(
        address spender,
        uint256 tokenId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable override {
        require(_blockTimestamp() <= deadline, 'Permit expired');

        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, _getAndIncrementNonce(tokenId), deadline))
            )
        );
        address owner = ownerOf(tokenId);
        require(spender != owner, 'ERC721Permit: approval to current owner');

        if (AddressUpgradeable.isContract(owner)) {
            require(IERC1271(owner).isValidSignature(digest, abi.encodePacked(r, s, v)) == 0x1626ba7e, 'Unauthorized');
        } else {
            address recoveredAddress = ecrecover(digest, v, r, s);
            require(recoveredAddress != address(0), 'Invalid signature');
            require(recoveredAddress == owner, 'Unauthorized');
        }

        _approve(spender, tokenId);
    }

    uint256[50] private __gap;
}

