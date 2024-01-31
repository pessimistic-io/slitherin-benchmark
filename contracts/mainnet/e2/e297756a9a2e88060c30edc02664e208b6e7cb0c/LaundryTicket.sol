// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./DefaultOperatorFilterer.sol";

//   _____     _____   _   _    _____ 
//  |  __ \   / ____| | \ | |  / ____|
//  | |  | | | |  __  |  \| | | (___  
//  | |  | | | | |_ | | . ` |  \___ \ 
//  | |__| | | |__| | | |\  |  ____) |
//  |_____/   \_____| |_| \_| |_____/ 
                                                              
contract LaundryTicket is ERC1155, Ownable, DefaultOperatorFilterer {
    using Strings for uint256;
    
    address public DiDContract;
    string public baseURI;
    string public name = "Laundry Ticket";
    string public symbol = "LT";
    bytes32 public merkleRoot;
    bytes32 public goldMerkleRoot;
    bool public mintEnabled = false;
    bool public burnEnabled = false;
    uint256 public maxPerWallet = 1;
    uint256 public maxGoldPerWallet = 1;
    uint256 public maxTickets = 0;
    uint256 public maxGoldTickets = 0;
    uint256 public tickets = 0;
    uint256 public goldTickets = 0;
    uint256 public endTime = 0;
    uint256 public mintWindow = 0;

    mapping(uint256 => bool) public ticketTypes;
    mapping(address => mapping(uint256 => uint256)) private _walletMints;
    mapping(address => mapping(uint256 => uint256)) private _walletGoldMints;

    constructor() ERC1155("") {
        ticketTypes[1] = true;
        ticketTypes[2] = true;
        ticketTypes[3] = true;
        ticketTypes[4] = true;
    }

    function mint(uint256 amount, address to, bytes32[] calldata merkleProof) external {
        require(mintEnabled, "Mint closed for now");
        require(block.timestamp < endTime, "Mint closed for now");
        require(msg.sender == tx.origin, "No contracts");
        require(MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(to))), "Not allowed to mint");
        require(tickets + amount <= maxTickets, "No more available right now");
        require(amount > 0, "Must mint at least one ticket");
        require(_walletMints[to][mintWindow] + amount <= maxPerWallet, "Limit for this wallet reached");

        _walletMints[to][mintWindow] += amount;
        tickets += amount;
        _mint(to, 1, amount, "");
    }

    function mintGold(uint256 amount, address to, bytes32[] calldata merkleProof) external {
        require(mintEnabled, "Mint closed for now");
        require(block.timestamp < endTime, "Mint closed for now");
        require(msg.sender == tx.origin, "No contracts");
        require(MerkleProof.verify(merkleProof, goldMerkleRoot, keccak256(abi.encodePacked(to))), "Not allowed to mint");
        require(goldTickets + amount <= maxGoldTickets, "No more available right now");
        require(amount > 0, "Must mint at least one ticket");
        require(_walletGoldMints[to][mintWindow] + amount <= maxPerWallet, "Limit for this wallet reached");

        _walletGoldMints[to][mintWindow] += amount;
        goldTickets += amount;
        _mint(to, 2, amount, "");
    }

    function toggleMinting() external onlyOwner {
        mintEnabled = !mintEnabled;
    }

    function toggleBurning() external onlyOwner {
        burnEnabled = !burnEnabled;
    }

    function enableMint(uint256 _newMaxTickets, uint256 _newMaxGoldTickets, uint256 _endTime, uint256 _mintWindow) external onlyOwner {
        mintEnabled = true;
        maxTickets = _newMaxTickets;
        maxGoldTickets = _newMaxGoldTickets;
        endTime = _endTime;
        mintWindow = _mintWindow;
    }

    function mintBatch(uint256[] memory ids, uint256[] memory amounts) external onlyOwner {
        _mintBatch(owner(), ids, amounts, "");
    }

    function setDiDContractAddress(address DiDContractAddress) external onlyOwner {
        DiDContract = DiDContractAddress;
    }

    function setMaxPerWallet(uint256 _newMaxPerWallet, uint256 _newMaxGoldPerWallet) external onlyOwner {
        maxPerWallet = _newMaxPerWallet;
        maxGoldPerWallet = _newMaxGoldPerWallet;
    }

    function setMaxSupply(uint256 _newMaxTickets, uint256 _newMaxGoldTickets) external onlyOwner {
        maxTickets = _newMaxTickets;
        maxGoldTickets = _newMaxGoldTickets;
    }

    function setEndTime(uint256 _endTime) external onlyOwner {
        endTime = _endTime;
    }

    function setMintWindow(uint256 _mintWindow) external onlyOwner {
        mintWindow = _mintWindow;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setGoldMerkleRoot(bytes32 _goldMerkleRoot) external onlyOwner {
        goldMerkleRoot = _goldMerkleRoot;
    }

    function updateBaseUri(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function withdraw() public onlyOwner {
        address _address = msg.sender;
        (bool success, ) = _address.call{value: address(this).balance}("");
        require(success, "Failed to withdraw");
    }

    function burnTickets(uint256 typeId, address minter, uint256 amount) external {
        require(burnEnabled, "Burn not open");
        require(msg.sender == DiDContract, "Invalid burner address");
        require(amount > 0, "Must burn at least 1");
        require(ticketTypes[typeId], "Not a valid ticket type" );
        _burn(minter, typeId, amount);
        _mint(minter, typeId + 2, amount, "");
    }

    function uri(uint256 typeId) public view override returns (string memory) {
        require(ticketTypes[typeId], "Not a valid ticket type" );
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, typeId.toString(), ".json")) : baseURI;
    }

    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes memory data)
        public
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }
}
