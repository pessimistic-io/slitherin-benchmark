// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable.sol";

contract ReadONGenesisNFTVoucher

 is
    Initializable,
    ERC721Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public totalSupply;
    // Default allow transfer
    bool private _transferable;

    mapping(uint256 => Reward) public voucherData;
    struct Reward {
        bool status;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyTransferable() {
        require(_transferable, "ReadON: must transferable");
        _;
    }

    function setClaimed(uint256 tokenId) external onlyRole(ADMIN_ROLE) {
        voucherData[tokenId].status=false;
    }

    /**
     * PRIVILEGED MODULE FUNCTION. Sets a new transferable for all token types.
     */
    function setTransferable(bool transferable) external onlyRole(ADMIN_ROLE) {
        _transferable = transferable;
    }

    function initialize() public initializer {
        _transferable = true;
        __ERC721_init("ReadON Genesis NFT Voucher", "RNV");
        __Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://readon-api.readon.me/v1/nft/arbitrum1/voucher/case/";
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function safeMint(
        address to,
        uint256 tokenId
    ) public onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
        voucherData[tokenId] = Reward(true);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override whenNotPaused onlyTransferable {
        require(
            from == address(0) || to == address(0),
            "ReadON:soul bound nft"
        );
        super._beforeTokenTransfer(from, to, tokenId);
        if (from == address(0)) {
            totalSupply++;
        }
        if (to == address(0)) {
            totalSupply--;
        }
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

