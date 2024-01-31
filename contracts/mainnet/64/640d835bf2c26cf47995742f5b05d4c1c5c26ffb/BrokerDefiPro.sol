// SPDX-License-Identifier: MIT
// author : zainamroti
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./IBrokerDefiPriceConsumer.sol";
import "./IBrokerDefiPartner.sol";

contract BrokerDefiPro is ERC721, Ownable, ReentrancyGuard {
    address public BD_PRICE_CONSUMER;

    uint public TOKEN_ID = 0; // starts from one, also the total supply of pro nfts

    bool public saleIsActive = true; // to control public sale

    address payable public treasury;

    bool public ESCROW_ALLOWED = true;

    address public BD_PARTNER;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    // mapping for tokenId to escrow period
    mapping(uint256 => uint256) public escrowedAt;

    // mapping for tokenId to total escrow period, doesn't include the escrow period
    mapping(uint256 => uint256) public escrowPeriod;

    // mapping for tokenIds to pro codes
    mapping(uint256 => uint256) public proCodes;

    // additional mapping for pro codes verification
    mapping(uint256 => bool) public proCodesVerification;

    // mapping for pro codes to token ids
    mapping(uint256 => uint256) public codeOwners;

    uint public PARTNER_COMMISSION = 10;
    uint public PARTNER_DISCOUNT = 10;
    uint public PRO_COMMISSION = 10;
    uint public PRO_DISCOUNT = 10;

    // mapping for partner codes to partner code usage count
    mapping(uint256 => uint256) public partnerCodesCount;

    // mapping for pro codes to partner code usage count
    mapping(uint256 => uint256) public proCodesCount;

    // Token URI
    string public baseTokenURI = "";

    constructor(
        address payable _treasury,
        address brokerDefiPartner,
        address priceConsumer
    ) ERC721("BrokerDeFi PRO", "BDPR") {
        treasury = _treasury;
        BD_PARTNER = brokerDefiPartner;
        BD_PRICE_CONSUMER = priceConsumer;
    }

    function setPriceConsumer(address priceConsumer) public onlyOwner {
        BD_PRICE_CONSUMER = priceConsumer;
    }

    function setPartnerCommission(uint commission) public onlyOwner {
        PARTNER_COMMISSION = commission;
    }

    function setProCommission(uint commission) public onlyOwner {
        PRO_COMMISSION = commission;
    }

    function setPartnerDiscount(uint discount) public onlyOwner {
        PARTNER_DISCOUNT = discount;
    }

    function setProDiscount(uint discount) public onlyOwner {
        PRO_DISCOUNT = discount;
    }

    function changeTreasuryAddress(address payable _newTreasuryAddress) public onlyOwner {
        treasury = _newTreasuryAddress;
    }

    function setPartnerAddress(address _partner) public onlyOwner {
        BD_PARTNER = _partner;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseTokenURI = _newBaseURI;
    }

    // function to set a particular token uri manually if something incorrect in one of the metadata files
    function setTokenURI(uint tokenID, string memory uri) public onlyOwner {
        _tokenURIs[tokenID] = uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            return _tokenURIs[tokenId];
        }
        return string(abi.encodePacked(baseTokenURI, Strings.toString(tokenId)));
    }

    /*
     * for public sale
     */
    function flipSaleState() public onlyOwner {
        saleIsActive = !saleIsActive;
    }

    function setCode(uint tokenId) private {
        uint code = (block.timestamp + tokenId) % 100000000;
        proCodes[tokenId] = code;
        proCodesVerification[code] = true;
        codeOwners[code] = tokenId;
    }

    function getTotalEscrowPeriod(uint tokenId) public view returns (uint) {
        return (block.timestamp - escrowedAt[tokenId]) + escrowPeriod[tokenId];
    }

    function escrow(uint tokenId) public {
        require(ERC721._exists(tokenId), "escrowing non existent token");
        require(ERC721.ownerOf(tokenId) == msg.sender, "Not your token");
        require(escrowedAt[tokenId] == 0, "Already in escrow");
        escrowedAt[tokenId] = block.timestamp;
    }

    function unEscrow(uint tokenId) public {
        require(escrowedAt[tokenId] != 0, "Not in escrow yet");
        require(ERC721._exists(tokenId), "UnEscrowing non existent token");
        require(ERC721.ownerOf(tokenId) == msg.sender, "Not your token");
        escrowPeriod[tokenId] += (block.timestamp - escrowedAt[tokenId]);
        escrowedAt[tokenId] = 0;
    }

    function getTokenPrice() public view returns (uint price) {
        return IBrokerDefiPriceConsumer(BD_PRICE_CONSUMER).getProPriceInEth();
    }

    // mint function for public sale with partner code
    function publicMint(
        address to,
        uint amount,
        uint code,
        bool proCode
    ) public payable nonReentrant {
        require(saleIsActive && treasury != address(0), "Config not done yet");
        uint nftPrice = getTokenPrice();
        require(msg.value >= (nftPrice * amount), "Not enough balance");
        if (code > 0) {
            uint commission;
            uint discount;
            address payable recruiter;
            if (proCode) {
                require(proCodesVerification[code], "Wrong code");
                proCodesCount[code] += 1;
                commission = (msg.value * PRO_COMMISSION) / 100;
                discount = (msg.value * PRO_DISCOUNT) / 100;
                recruiter = payable(ERC721.ownerOf(codeOwners[code]));
            } else {
                // If it's a PARTNER code (partner holder recruiting pro)
                require(
                    IBrokerDefiPartner(BD_PARTNER).partnerCodesVerification(code),
                    "Wrong code"
                );
                partnerCodesCount[code] += 1;
                commission = (msg.value * PARTNER_COMMISSION) / 100;
                discount = (msg.value * PARTNER_DISCOUNT) / 100;
                uint tokenId = IBrokerDefiPartner(BD_PARTNER).codeOwners(code);
                recruiter = payable(IBrokerDefiPartner(BD_PARTNER).ownerOf(tokenId));
            }
            recruiter.transfer(commission);
            treasury.transfer(msg.value - (commission + discount));
            address payable buyer = payable(msg.sender);
            buyer.transfer(discount); // transferring discount back to buyer
        } else {
            treasury.transfer(msg.value);
        }
        for (uint index = 0; index < amount; index++) {
            TOKEN_ID += 1;
            _safeMint(to, TOKEN_ID);
            escrowedAt[TOKEN_ID] = block.timestamp;
            setCode(TOKEN_ID);
        }
    }

    // mass minting function for owner, one for each address
    function massMint(address[] memory addresses) public onlyOwner {
        for (uint index = 0; index < addresses.length; index++) {
            TOKEN_ID += 1;
            _safeMint(addresses[index], TOKEN_ID);
            escrowedAt[TOKEN_ID] = block.timestamp;
            setCode(TOKEN_ID);
        }
    }

    /**
        @dev Pro nfts transfer is not allowed, they will remain in the wallet forever.
     */

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address /*from */,
        address /* to */,
        uint256 /*tokenId */
    ) public pure override {
        revert("Transfer of BrokerDefiPro tokens is not allowed");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address /*from */,
        address /* to */,
        uint256 /*tokenId */
    ) public virtual override {
        revert("Transfer of BrokerDefiPro tokens is not allowed");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address /*from */,
        address /* to */,
        uint256 /*tokenId */,
        bytes memory /* _data */
    ) public pure override {
        revert("Transfer of BrokerDefiPro tokens is not allowed");
    }

    // additional burn function
    function burn(uint256 tokenId) public {
        require(ERC721._exists(tokenId), "burning non existent token");
        require(ERC721.ownerOf(tokenId) == msg.sender, "Not your token");
        _burn(tokenId);
    }

    // token ids function for view only, convenience function for frontend
    function ownerTokens() public view returns (uint[] memory) {
        uint[] memory tokenIds = new uint[](ERC721.balanceOf(msg.sender));
        uint tokenIdsIndex = 0;
        for (uint index = 1; index <= TOKEN_ID; index++) {
            if (ERC721.ownerOf(index) == msg.sender) {
                tokenIds[tokenIdsIndex] = index;
                tokenIdsIndex++;
            }
        }
        return tokenIds;
    }
}

