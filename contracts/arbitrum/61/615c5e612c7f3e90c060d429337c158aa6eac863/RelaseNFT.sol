// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;

import "./AccessControl.sol";
import "./ERC721Pausable.sol";
import "./IERC721Receiver.sol";
import "./ERC721.sol";
import "./ISeeder.sol";
import "./ITokenURIBuilder.sol";
import "./RoyaltyStandard.sol";

contract ReleaseNFT is ERC721Pausable, IERC721Receiver, RoyaltyStandard, AccessControl {
    ISeeder public seeder;
    ITokenURIBuilder public builder;

    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant PAUSABLE_ROLE = keccak256("PAUSABLE_ROLE");

    uint256 private _tokenCount = 0;

    struct Meta {
        uint256 seed;
    }

    mapping(uint256 => Meta) public meta;

    constructor(
        string memory name_,
        string memory symbol_,
        ISeeder seeder_,
        ITokenURIBuilder builder_
    ) ERC721(name_, symbol_) {
        // grant admin and mint role to deployer
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINT_ROLE, _msgSender());

        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MINT_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSABLE_ROLE, DEFAULT_ADMIN_ROLE);

        seeder = seeder_;
        builder = builder_;

        // set defult fee receiver as deployer
        _setFeeReceiver(_msgSender());
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, AccessControl, RoyaltyStandard) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function pause() external onlyRole(PAUSABLE_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSABLE_ROLE) {
        _unpause();
    }

    // Only admin cann call
    function changeRoyaltyFeeReceiver(
        address feeReceiver_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeReceiver(feeReceiver_);
    }

    // Only admin cann call
    function changeRoyaltyFeeRate(uint16 feeRate_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeRate(feeRate_);
    }

    // Only granted can call
    function mint(address to, uint256 tokenId) public onlyRole(MINT_ROLE) {
        _mint(to, tokenId);
    }

    function bulkMint(
        address[] memory tos,
        uint256[] memory tokenIds
    ) public onlyRole(MINT_ROLE) {
        require(tos.length > 0, "tos length must be greater than 0");
        require(tos.length < (1 << 8) - 2, "tos length must be less than 254");
        require(tos.length == tokenIds.length, "tos and tokenIds length mismatch");
        for (uint8 i = 0; i < tos.length; i++) {
            _mint(tos[i], tokenIds[i]);
        }
    }

    function burn(uint256 tokenId) public {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _burn(tokenId);
    }

    function bulkTransferFrom(
        address from,
        address[] memory tos,
        uint256[] memory tokenIds
    ) public {
        require(tos.length > 0, "tos length must be greater than 0");
        require(tos.length < (1 << 8) - 2, "tos length must be less than 254");
        require(tos.length == tokenIds.length, "tos and tokenIds length mismatch");

        for (uint8 i = 0; i < tos.length; i++) {
            address to = tos[i];
            uint256 tokenId = tokenIds[i];
            require(
                _isApprovedOrOwner(_msgSender(), tokenId),
                "ERC721: caller is not token owner or approved"
            );
            _transfer(from, to, tokenId);
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (address(builder) != address(0)) {
            require(meta[tokenId].seed != 0, "token not exist");
            return builder.buildTokenURI(meta[tokenId].seed, tokenId);
        }

        return super.tokenURI(tokenId);
    }

    function totalSupply() external view returns (uint256) {
        return _tokenCount;
    }

    // Allow contract receive NFT
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes memory /* data */
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _mint(address to, uint256 tokenId) internal override {
        _tokenCount += 1;
        super._mint(to, tokenId);
        _setMeta(tokenId);
        _setTokenRoyalty(tokenId);
    }

    function _burn(uint256 tokenId) internal override {
        super._burn(tokenId);
    }

    function _setMeta(uint256 tokenId) internal {
        if (address(seeder) != address(0)) {
            meta[tokenId].seed = seeder.generateSeed(tokenId);
        }
    }
}

