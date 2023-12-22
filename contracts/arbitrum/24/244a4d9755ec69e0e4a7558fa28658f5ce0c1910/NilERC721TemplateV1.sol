// SPDX-License-Identifier: MIT
/**
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(     (@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(   @@@@@@@@@@@@@@@@@@@@(            @@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@         @@@@@@@@@@@@@@@             @@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @@@@@@@@@@@(            @@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@      @@@@@@@@@@@@             @@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@(            @@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@     @@@@@@@     @@@@@@@             @@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@(         @@(         @@(            @@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@          @@          @@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@     @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@ @@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(     @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @           @           @@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@(            @@@         @@@         @@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@             @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@(            @@@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@             @@@@@@@@@@@       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@(            @@@@@@@@@@@@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@             @@@@@@@@@@@@@@@         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@(            @@@@@@@@@@@@@@@@@@@@@   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@(     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 */
pragma solidity 0.8.11;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./interfaces_IERC165Upgradeable.sol";
import "./IERC2981Upgradeable.sol";
import "./Initializable.sol";
import "./draft-EIP712Upgradeable.sol";
import "./INilERC721V1.sol";
import "./NilRoles.sol";
import "./NilRolesUpgradeable.sol";

contract NilERC721TemplateV1 is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    INilERC721V1,
    NilRolesUpgradeable,
    EIP712Upgradeable,
    IERC2981Upgradeable
{
    uint8 public constant MAX_MULTI_MINT_AMOUNT = 32;
    uint16 public constant MAX_ROYALTIES_AMOUNT = 1500;
    uint16 public constant ROYALTIES_BASIS_POINTS = 10000;

    bool public remainingSupplyRemoved;
    uint256 public currentTokenId;
    uint256 public currentNTokenId;
    uint256 public protocolFeesInBPS;

    NftParameters public nftParameters;
    ContractAddresses public contractAddresses;

    mapping(uint256 => bytes32) public seeds;
    mapping(uint256 => bool) public usedN;
    mapping(bytes => bool) public usedVouchers;
    mapping(uint256 => string) public metadata;

    //Add variables for upgrades after this comment.

    event Minted(address receiver, uint256 tokenId, bytes32 seed, address nftContract);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        string calldata name,
        string calldata symbol,
        NftParameters calldata nftParameters_,
        address owner_,
        uint256 protocolFeesInBPS_,
        INilERC721V1.ContractAddresses calldata contractAddresses_
    ) public initializer {
        __ERC721_init(name, symbol);
        __EIP712_init(name, "1.0.0");
        __ERC721Enumerable_init();
        __ReentrancyGuard_init();
        __NilRoles_init(owner_, contractAddresses_.dao, contractAddresses_.operator, contractAddresses_.signer);
        contractAddresses = contractAddresses_;
        require(
            nftParameters_.saleOpenTime > block.timestamp + 24 hours &&
                nftParameters_.saleOpenTime < block.timestamp + 14 days,
            "NIL:SALE_WINDOW_NOT_ALLOWED"
        );
        nftParameters = nftParameters_;
        nftParameters.maxMintAllowance = nftParameters.maxMintAllowance < MAX_MULTI_MINT_AMOUNT
            ? nftParameters.maxMintAllowance
            : MAX_MULTI_MINT_AMOUNT;
        require(nftParameters.nAllowance <= nftParameters.maxTotalSupply, "NIL:N_ALLOWANCE_EXCEEDS_TOTAL_SUPPLY");
        _owner = owner_;
        protocolFeesInBPS = protocolFeesInBPS_;
        require(nftParameters.royaltiesAmount <= MAX_ROYALTIES_AMOUNT, "NIL:ROYALTIES_EXCEEDING_MAX");
    }

    modifier nonContractCaller() {
        require(msg.sender == tx.origin, "NIL:CONTRACT_CALLER");
        _;
    }

    function publicSaleOpen() public view returns (bool) {
        return
            block.timestamp >= (nftParameters.saleOpenTime + 1 hours)
                ? true
                : (nftParameters.nAllowance == 0 && block.timestamp >= nftParameters.saleOpenTime)
                ? true
                : false;
    }

    function nSaleOpen() public view returns (bool) {
        return
            (!publicSaleOpen() && nftParameters.nAllowance > 0 && block.timestamp >= (nftParameters.saleOpenTime))
                ? true
                : false;
    }

    function mintETH(bytes calldata data) external payable virtual nonReentrant nonContractCaller {
        require(publicSaleOpen(), "NIL:PUBLIC_SALE_NOT_OPEN");
        require(!nftParameters.isNilSale, "NIL:ONLY_POSSIBLE_TO_PAY_WITH_ETH");
        (uint256 amount, uint256 expiry, uint256 random, bytes memory signature) = abi.decode(
            data,
            (uint256, uint256, uint256, bytes)
        );
        require(block.timestamp <= expiry, "NIL:VOUCHER_EXPIRED");
        require(!usedVouchers[signature], "NIL:VOUCHER_ALREADY_USED");
        require(_verify(_hash(msg.sender, amount, expiry, random), signature), "NIL:INVALID_SIGNATURE");
        require(amount <= nftParameters.maxMintAllowance, "NIL:MINT_ABOVE_MAX_MINT_ALLOWANCE");
        require(
            balanceOf(msg.sender) + amount <= nftParameters.maxMintablePerAddress,
            "NIL:ADDRESS_MAX_ALLOCATION_REACHED"
        );
        require(totalMintsAvailable() >= amount, "NIL:MAX_ALLOCATION_REACHED");
        require(amount * nftParameters.priceInWei == msg.value, "NIL:INVALID_PRICE");
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, currentTokenId);
            seeds[currentTokenId] = keccak256(
                abi.encodePacked(currentTokenId, block.number, blockhash(block.number - 1), msg.sender, random)
            );
            emit Minted(msg.sender, currentTokenId, seeds[currentTokenId], address(this));
            currentTokenId++;
        }
        usedVouchers[signature] = true;
    }

    function totalMintsAvailable() public view returns (uint256) {
        if (remainingSupplyRemoved) {
            return 0;
        }
        uint256 totalAvailable = nftParameters.maxTotalSupply - currentTokenId;
        if (nftParameters.isBurnEnabled) {
            if (block.timestamp > nftParameters.saleOpenTime + 24 hours) {
                // Double candle burning starts and decreases max. mintable supply with 1 token per minute.
                uint256 doubleBurn = (block.timestamp - (nftParameters.saleOpenTime + 24 hours)) / 1 minutes;
                totalAvailable = totalAvailable > doubleBurn ? totalAvailable - doubleBurn : 0;
            }
        }
        return totalAvailable;
    }

    function totalNMintsAvailable() public view returns (uint256) {
        if (remainingSupplyRemoved) {
            return 0;
        }
        uint256 totalNAvailable = nftParameters.nAllowance - currentNTokenId;
        return totalMintsAvailable() < totalNAvailable ? totalMintsAvailable() : totalNAvailable;
    }

    function burnRemainingSupply(bool setting) public onlyOwner {
        remainingSupplyRemoved = setting;
    }

    // Hack for OpenSea collection editing
    function owner() external view returns (address) {
        return _owner;
    }

    // Hack for OpenSea collection editing
    function transferOwner(address newOwner) public onlyOwner {
        grantRole(OWNER_ROLE, newOwner);
        revokeRole(OWNER_ROLE, _owner);
        _owner = newOwner;
    }

    function setRoyalties(address payout, uint256 amount) public onlyOwner {
        require(amount <= MAX_ROYALTIES_AMOUNT, "NIL:ROYALTIES_EXCEEDING_MAX");
        nftParameters.royaltiesPayout = payout;
        nftParameters.royaltiesAmount = amount;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256 royaltyAmount) {
        royaltyAmount = (salePrice * nftParameters.royaltiesAmount) / ROYALTIES_BASIS_POINTS;
        return (nftParameters.royaltiesPayout, royaltyAmount);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "NIL: URI query for nonexistent token");
        if(bytes(metadata[tokenId]).length == 0) {
            return nftParameters.metadataURI;
        }
        return metadata[tokenId];
    }

    function setContractURI(string calldata contractURI) public onlyOperator {
        nftParameters.contractURI = contractURI;
    }

    function setMetadataURI(string calldata metadataURI) public onlyOperator {
        nftParameters.metadataURI = metadataURI;
    }

    function setTokenURIs(uint256[] calldata tokenIDs, string[] calldata tokenURIs) public virtual onlyOperator {
        require(tokenIDs.length == tokenURIs.length, "NIL:TOKENID_AND_TOKENURI_ARRAY_NOT_EQUAL");
        require(tokenIDs.length <= 50, "NIL:TOKENID_LENTGH_EXCEEDS_MAX");
        for(uint8 i = 0; i < tokenIDs.length; i++) {
            metadata[tokenIDs[i]] = tokenURIs[i];
        }
    }

    function setBundleURI(string calldata bundleURI) public virtual onlyOperator {
        nftParameters.bundleURI = bundleURI;
    }

    function withdrawProceeds() public {
        if (!nftParameters.isNilSale) {
            uint256 contractBalance = address(this).balance;
            payable(_owner).transfer((contractBalance * (1000 - protocolFeesInBPS)) / 1000);
            //sent 3.5% to DAO
            payable(contractAddresses.dao).transfer((contractBalance * protocolFeesInBPS) / 1000);
        }
    }

    function nUsed(uint256 nid) external view override returns (bool) {
        return usedN[nid];
    }

    function canMint(address account) public view virtual override returns (bool) {
        uint256 balance = balanceOf(account);
        if (publicSaleOpen() && totalMintsAvailable() > 0 && balance < nftParameters.maxMintablePerAddress) {
            return true;
        }
        return false;
    }

    function vouchersActive() external view returns (bool) {
        return nSaleOpen() || publicSaleOpen();
    }

    function _hash(
        address minter,
        uint256 amount,
        uint256 expiry,
        uint256 random
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("Voucher(uint256 amount,address minter,uint256 expiry,uint256 random)"),
                        amount,
                        minter,
                        expiry,
                        random
                    )
                )
            );
    }

    function _verify(bytes32 digest, bytes memory signature) internal view returns (bool) {
        return hasRole(SIGNER_ROLE, ECDSAUpgradeable.recover(digest, signature));
    }

    function toHex16(bytes16 data) internal pure returns (bytes32 result) {
        result =
            (bytes32(data) & 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000) |
            ((bytes32(data) & 0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >> 64);
        result =
            (result & 0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000) |
            ((result & 0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >> 32);
        result =
            (result & 0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000) |
            ((result & 0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >> 16);
        result =
            (result & 0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000) |
            ((result & 0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >> 8);
        result =
            ((result & 0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >> 4) |
            ((result & 0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >> 8);
        result = bytes32(
            0x3030303030303030303030303030303030303030303030303030303030303030 +
                uint256(result) +
                (((uint256(result) + 0x0606060606060606060606060606060606060606060606060606060606060606) >> 4) &
                    0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) *
                7
        );
    }

    function getSeed(uint256 tokenId) public view returns (string memory) {
        return string(abi.encodePacked(toHex16(bytes16(seeds[tokenId])), toHex16(bytes16(seeds[tokenId] << 128))));
    }

    function mintParameters() external view returns (INilERC721V1.MintParams memory) {
        return
            INilERC721V1.MintParams({
                isNilSale: nftParameters.isNilSale,
                maxMintAllowance: nftParameters.maxMintAllowance,
                nAllowance: nftParameters.nAllowance,
                maxMintablePerAddress: nftParameters.maxMintablePerAddress,
                maxTotalSupply: nftParameters.maxTotalSupply,
                totalMintsAvailable: totalMintsAvailable(),
                totalNMintsAvailable: totalNMintsAvailable(),
                totalSupply: totalSupply(),
                saleOpenTime: nftParameters.saleOpenTime,
                priceInWei: nftParameters.priceInWei,
                protocolFeesInBPS: protocolFeesInBPS,
                metadataURI: nftParameters.metadataURI,
                bundleURI: nftParameters.bundleURI,
                contractURI: nftParameters.contractURI
            });
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

