// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract FuzzFactory is ERC721Enumerable {
    using Strings for uint256;

    event ClaimFuzzies(address indexed summoner, uint256 amount);
    event ClaimStart(bool _claimStart);
    event RevealStart(bool _revealStart);

    bool claimStart;
    bool revealStart;
    string public baseURI;

    string name_ = "Operation: FuzzFactory";
    string symbol_ = "FUZZIES";

    uint256 public totalCount = 25_250;

    address payable public owner;
    address[4] public ticketContracts;

    // mapping(uint256 => mapping(uint256 => bool)) public claimed;
    mapping(uint => bool) public claimed;

    struct TierLevels {
        uint16 carbon;
        uint16 rhodium;
        uint16 gold;
        uint16 blue;
        string[4] tierLetter;
    }

    struct ClaimTicket {
        string[1] tierLetter;
        uint startMint;
        uint maxMint;
    }

    mapping(address => ClaimTicket) public claimTickets;

    // tier levels are the minting #s each tier starts at
    // each tier is mintable up to where the next tier starts
    // final tier ends at totalCount (set at 25_250);
    // totals per tier: blue = 15,000, gold = 7,500, rhodium = 2,500, carbon = 250
    // tier start mint: carbon = 0, rhodium = 250, gold = 2_750, blue = 10_250

    TierLevels public tierLevels =
        TierLevels(0, 250, 2_750, 10_250, ["C", "R", "G", "B"]);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address[4] memory _ticketContracts, string memory uri) ERC721(name_, symbol_) {
        owner = payable(msg.sender);
        claimStart = false;

        ticketContracts = [
            _ticketContracts[0],
            _ticketContracts[1],
            _ticketContracts[2],
            _ticketContracts[3]
        ];

        claimTickets[_ticketContracts[0]] = ClaimTicket(["C"], 0, 250);
        claimTickets[_ticketContracts[1]] = ClaimTicket(["R"], 250, 2_500);
        claimTickets[_ticketContracts[2]] = ClaimTicket(["G"], 2_750, 7_500);
        claimTickets[_ticketContracts[3]] = ClaimTicket(["B"], 10_250, 15_000);

        baseURI = uri;
    }

    function exists(uint256 tid) public view returns (bool) {
        return _exists(tid);
    }

    function safeMint(address to, uint256 tokenId) public onlyOwner {
        require(totalSupply() < totalCount, "All fuzzies claimed!");
        _safeMint(to, tokenId);
    }

    function totalMinted() public view returns (uint256) {
        return totalMinted();
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _newURI) public onlyOwner {
        baseURI = _newURI;
    }

    function setClaimTicket(
        string calldata tierLetter,
        uint startMint,
        uint maxMint,
        address ticketAddress
    ) public onlyOwner {
        claimTickets[ticketAddress] = ClaimTicket(
            [tierLetter],
            startMint,
            maxMint
        );
    }

    function setClaimStart(bool _claimStart) external onlyOwner {
        claimStart = _claimStart;
        emit ClaimStart(_claimStart);
    }
    
    function setRevealStart(bool _revealStart) external onlyOwner {
        revealStart = _revealStart;
        emit RevealStart(_revealStart);
    }

    /// @param tid => array index of claim-ticket contract
    function claimFuzzies(uint tid) public payable {
        require(claimStart, "Claiming has not started");
        address ticketContract = ticketContracts[tid];

        uint256[] memory ticketsOwned = _remoteInventory(
            msg.sender,
            address(ticketContract)
        );
        ClaimTicket memory ticket = claimTickets[ticketContract];

        uint minted;
        // NOTICE: does not check for id 0; not mintable @ claim ticket contracts
        for (uint256 i = 0; i < ticketsOwned.length; i++) {
            uint localTokenId = ticketsOwned[i] + ticket.startMint - 1;

            if (localTokenId < ticket.maxMint + ticket.startMint)
                if (!claimed[localTokenId])
                    if (!exists(localTokenId)) {
                        claimed[localTokenId] = true;
                        _safeMint(msg.sender, localTokenId);
                        minted++;
                    }
        }

        emit ClaimFuzzies(msg.sender, minted);
    }

    function claimAllFuzzies() external payable {
        for (uint i = 0; i < ticketContracts.length; i++) {
            claimFuzzies(i);
        }
    }

    function checkClaims(
        uint ticketTier,
        address wallet
    ) public view returns (uint256) {
        if (totalSupply() == totalCount) return 0;
        address ticketContract = ticketContracts[ticketTier];
        uint256[] memory ticketsOwned = _remoteInventory(
            wallet,
            address(ticketContract)
        );

        uint availableClaims;
        uint256 remoteTokenId;

        for (uint256 i = 0; i < ticketsOwned.length; i++) {
            remoteTokenId = ticketsOwned[i];
            uint localTokenId = remoteTokenId +
                claimTickets[ticketContract].startMint -
                1;
            if (!claimed[localTokenId]) {
                availableClaims++;
            }
        }

        return availableClaims;
    }

    function checkAllClaims(address wallet) external view returns (uint256) {
        if (totalSupply() == totalCount) return 0;
        uint availableClaims;

        for (uint i = 0; i < ticketContracts.length; i++) {
            availableClaims += checkClaims(i, wallet);
        }

        return availableClaims;
    }

    function tokenURI(
        uint256 _tokenId
    ) public view virtual override returns (string memory) {
        _requireMinted(_tokenId);

        if(!revealStart) return string(abi.encodePacked('preReveal'));

        string memory tier_letter;

        if (_tokenId < tierLevels.rhodium) {
            tier_letter = tierLevels.tierLetter[0];
        } else if (_tokenId < tierLevels.gold) {
            tier_letter = tierLevels.tierLetter[1];
        } else if (_tokenId < tierLevels.blue) {
            tier_letter = tierLevels.tierLetter[2];
        } else {
            tier_letter = tierLevels.tierLetter[3];
        }

        string memory baseURI_ = _baseURI();
        return
            bytes(baseURI_).length > 0
                ? string(
                    abi.encodePacked(baseURI_, _tokenId.toString(), tier_letter)
                )
                : "";
    }

    // this gets the tokenId using the claim ticket's contract address and the tokenId of the claim ticket
    function ticketTieredId(
        uint256 _tokenId,
        address _ticketContract
    ) public view returns (string memory) {
        // _requireMinted(_tokenId);
        require(
            claimTickets[_ticketContract].maxMint > 0,
            "Invalid ticket contract"
        );

        if (_tokenId == 0) return "00";

        string memory tier_letter = claimTickets[_ticketContract].tierLetter[0];
        uint localTokenId = _tokenId +
            claimTickets[_ticketContract].startMint -
            1;

        return string(abi.encodePacked(localTokenId.toString(), tier_letter));
    }

    function walletInventory(
        address _owner
    ) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        uint256[] memory tokensId = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    function _remoteInventory(
        address _owner,
        address _nft
    ) public view returns (uint256[] memory) {
        IERC721Enumerable nft = IERC721Enumerable(_nft);
        uint256 tokenCount = nft.balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = nft.tokenOfOwnerByIndex(_owner, i);
        }

        return tokenIds;
    }

    function withdrawAll() public payable onlyOwner {
        uint256 contract_balance = address(this).balance;
        require(payable(owner).send(contract_balance));
    }

    function rescueTokens(
        address recipient,
        address token,
        uint256 amount
    ) public onlyOwner {
        IERC20(token).transfer(recipient, amount);
    }

    function changeOwner(address payable _newowner) external onlyOwner {
        owner = _newowner;
    }
}

