// SPDX-License-Identifier: MIT
// author : zainamroti
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./IBrokerDefiPriceConsumer.sol";
import "./IBrokerDefiPro.sol";

error WrongCode();

contract BrokerDefiPartner is ERC721, Ownable, ReentrancyGuard {
    uint public TOKEN_ID = 0; // starts from one

    address public BD_PRICE_CONSUMER;

    address private BD_PRO;

    uint public MAX_PER_TRX = 5;

    uint public ALLOCATED_FOR_TEAM = 5000;

    uint public TEAM_COUNT;

    bool public ESCROW_ALLOWED = true;

    uint256 public MAX_SUPPLY = 5000; // max supply of nfts

    bool public saleIsActive = true; // to control public sale

    address payable public treasury;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    // mapping for tokenId to current escrow period if token is in escrow
    mapping(uint256 => uint256) public escrowedAt;

    // mapping for tokenId to total escrow period, doesn't include the escrow period
    mapping(uint256 => uint256) public escrowPeriod;

    // mapping for tokenIds to partner codes
    mapping(uint256 => uint256) public partnerCodes;

    // mapping for partner codes to partner code usage count
    mapping(uint256 => uint256) public partnerCodesCount;

    // mapping for pro codes to pro code usage count
    mapping(uint256 => uint256) public proCodesCount;

    // mapping for partner codes to token ids
    mapping(uint256 => uint256) public codeOwners;

    // additional mapping for partner codes verification for easy one step code check
    mapping(uint256 => bool) public partnerCodesVerification;

    uint public PARTNER_COMMISSION = 20;

    uint public PARTNER_DISCOUNT = 10;

    uint public PRO_COMMISSION = 20;

    uint public PRO_DISCOUNT = 10;

    string public baseTokenURI = "";

    constructor(
        address payable _treasury,
        address priceConsumer
    ) ERC721("BrokerDeFi Partner", "BDPT") {
        treasury = payable(_treasury);
        BD_PRICE_CONSUMER = priceConsumer;
    }

    function setPriceConsumer(address priceConsumer) public onlyOwner {
        BD_PRICE_CONSUMER = priceConsumer;
    }

    function setBDPro(address _brokerDefiPro) public onlyOwner {
        BD_PRO = _brokerDefiPro;
    }

    function setPartnerCommission(uint commission) public onlyOwner {
        PARTNER_COMMISSION = commission;
    }

    function setPartnerDiscount(uint discount) public onlyOwner {
        PARTNER_DISCOUNT = discount;
    }

    function setProCommission(uint commission) public onlyOwner {
        PRO_COMMISSION = commission;
    }

    function setProDiscount(uint discount) public onlyOwner {
        PRO_DISCOUNT = discount;
    }

    function allowEscrow(bool allow) public onlyOwner {
        ESCROW_ALLOWED = allow;
    }

    function changeTreasuryAddress(address payable _newTreasuryAddress) public onlyOwner {
        treasury = _newTreasuryAddress;
    }

    function setTeamAllocation(uint256 _newAllocation) public onlyOwner {
        ALLOCATED_FOR_TEAM = _newAllocation;
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

    function flipSaleState() public onlyOwner {
        saleIsActive = !saleIsActive;
    }

    function setMaxPerTrx(uint maxPerTrx) public onlyOwner {
        MAX_PER_TRX = maxPerTrx;
    }

    // code is actually just a six-8 digit number and it will be public so people can distribute their code to others,
    function setCode(uint tokenId) private {
        uint code = (block.timestamp + tokenId) % 100000000;
        partnerCodes[tokenId] = code;
        partnerCodesVerification[code] = true;
        codeOwners[code] = tokenId;
    }

    function getTotalEscrowPeriod(uint tokenId) public view returns (uint) {
        return (block.timestamp - escrowedAt[tokenId]) + escrowPeriod[tokenId];
    }

    function escrow(uint tokenId) public {
        require(ESCROW_ALLOWED, "escrow not allowed");
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
        return IBrokerDefiPriceConsumer(BD_PRICE_CONSUMER).getPartnerPriceInEth();
    }

    function publicMint(
        address to,
        uint amount,
        uint code,
        bool partnerCode
    ) public payable nonReentrant {
        require(amount > 0 && amount <= MAX_PER_TRX, "Invalid Amount");
        require(
            saleIsActive && treasury != address(0) && BD_PRO != address(0),
            "Config not done yet"
        );
        require((TOKEN_ID + amount) <= MAX_SUPPLY, "Mint exceeds limits");
        uint nftPrice = getTokenPrice();
        require(msg.value >= (nftPrice * amount), "Not enough balance");
        if (code > 0) {
            uint commission;
            uint discount;
            address payable recruiter;
            if (partnerCode) {
                if (!partnerCodesVerification[code]) revert WrongCode();
                partnerCodesCount[code] += 1;
                commission = (msg.value / 100) * PARTNER_COMMISSION;
                discount = (msg.value / 100) * PARTNER_DISCOUNT;
                recruiter = payable(ERC721.ownerOf(codeOwners[code]));
            } else {
                // If it's a PRO code (pro holder recruiting partner)

                if (!IBrokerDefiPro(BD_PRO).proCodesVerification(code)) revert WrongCode();

                proCodesCount[code] += 1;
                commission = (msg.value * PRO_COMMISSION) / 100;
                discount = (msg.value * PRO_DISCOUNT) / 100;
                recruiter = payable(
                    IBrokerDefiPro(BD_PRO).ownerOf(IBrokerDefiPro(BD_PRO).codeOwners(code))
                );
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
            setCode(TOKEN_ID);
        }
    }

    // mass minting function, one for each address, for team
    function massMint(address[] memory addresses) public onlyOwner {
        for (uint index = 0; index < addresses.length; index++) {
            require(
                TEAM_COUNT < ALLOCATED_FOR_TEAM && (TOKEN_ID + 1) <= MAX_SUPPLY,
                "Amount exceeds allocation"
            );
            TOKEN_ID += 1;
            _safeMint(addresses[index], TOKEN_ID);
            TEAM_COUNT += 1;
            setCode(TOKEN_ID);
        }
    }

    /**
        @dev Block transfers while escrowing.
     */

    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(escrowedAt[tokenId] == 0, "BrokerDefi: transfer while escrow not allowed");
        ERC721.transferFrom(from, to, tokenId);
    }

    function safeTransferWhileEscrow(address from, address to, uint256 tokenId) public {
        ERC721.safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        require(escrowedAt[tokenId] == 0, "BrokerDefi: transfer while escrow not allowed");
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override {
        require(escrowedAt[tokenId] == 0, "BrokerDefi: transfer while escrow not allowed");
        require(
            ERC721._isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        ERC721._safeTransfer(from, to, tokenId, _data);
    }

    // additional burn function
    function burn(uint256 tokenId) public {
        require(ERC721._exists(tokenId), "Burning non existent token");
        require(ERC721.ownerOf(tokenId) == msg.sender, "Not your token");
        _burn(tokenId);
    }

    // token ids function for view only, convenience function for frontend to fulfil the gap of erc721 enumerable
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

