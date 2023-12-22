// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./Strings.sol";
import "./Ownable.sol";
import "./IERC2981.sol";
import "./ECDSA.sol";
import "./ERC721Enumerable.sol";

import "./ITroveStreetPunksMetadata.sol";

contract TroveStreetPunks is Ownable, ERC721Enumerable, IERC2981 {
    
    using Strings for uint256;
    using ECDSA for bytes32;

    string public constant IMAGE_PROVENANCE_HASH = "8be79a66ee42d5047855316c2e7ebefe47eb8c2f5795eff0453719a7febbf60e";

    address public constant SIGNER_ADDRESS = 0xf77f5B4921547f34B37dC7675E978F0cac1A8211;

    uint256 public constant SALE_START = 1655485200;
    uint256 public constant WHITELIST_END = 1655658000;

    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MAX_PER_TRANSACTION = 10;

    uint256 public royaltyAmount;
    address public royaltyAddress;

    address public metadataAddress;

    string private baseTokenURI;
    string private wholeContractURI;

    uint256 private whitelistReserved;
    uint256 private teamReserved = 500;

    mapping(address => bool) private blacklist;
    mapping(uint256 => uint256) private whitelistPrice;
    mapping(uint256 => uint256) private whitelistQuantity;
    mapping(uint256 => mapping(address => uint256)) private whitelistMinted;

    uint256 private availableTokens = MAX_SUPPLY;
    mapping(uint256 => uint256) private availableIds;
    
    constructor() ERC721("TroveStreetPunks", "TSP") {}

    function claim(uint256 _amount, uint256 _role, bytes memory _signature) external payable {
        _baseRequirements(_amount);

        require(isWhitelistLive(), "Whitelist ended");
        require(_role > 0 && _role < 6, "Unknown role");

        address sender = _msgSender();
        uint256 minted = whitelistMinted[_role][sender];

        if (minted == 0) {
            require(_verify(abi.encodePacked(sender, _role), _signature), "Invalid signature");   
        }

        uint256 maxQuantity = whitelistQuantity[_role];
        require(minted + _amount <= maxQuantity, "Exceeds role limit");

        uint256 price = whitelistPrice[_role];
        require(msg.value >= price * _amount, "Payment too low");

        require(_amount + totalSupply() <= _whitelistSupply(), "Exceeds limit");
        require(!blacklist[sender], "Blacklisted");

        whitelistReserved -= _amount;
        whitelistMinted[_role][sender] += _amount;

        _mintRandom(sender, _amount);
    }

    function mint(uint256 _amount) external payable {
        _baseRequirements(_amount);

        require(_amount <= MAX_PER_TRANSACTION, "Invalid amount");
        require(msg.value >= whitelistPrice[0] * _amount,  "Payment too low");
        require(_amount + totalSupply() <= _mintSupply(), "Exceeds limit");

        whitelistMinted[0][_msgSender()] += _amount;

        _mintRandom(_msgSender(), _amount);
    }

    function mintTeam(address _address, uint256 _amount) external onlyOwner {
        require(_amount > 0 && _amount <= teamReserved);

        teamReserved -= _amount;

        _mintRandom(_address, _amount);
    }

    function withdraw(address _address) external onlyOwner {
        payable(_address).transfer(address(this).balance);
    }

    function setBlacklist(address _address, bool _blacklist) external onlyOwner {
        blacklist[_address] = _blacklist;
    }

    function setMintPrice(uint256 _role, uint256 _price) external onlyOwner {
        whitelistPrice[_role] = _price;
    }

    function setMintQuantity(uint256 _role, uint256 _quantity) external onlyOwner {
        whitelistQuantity[_role] = _quantity;
    }

    function setRoyaltyAmount(uint256 _amount) external onlyOwner {
        royaltyAmount = _amount;
    }

    function setRoyaltyAddress(address _address) external onlyOwner {
        royaltyAddress = _address;
    }

    function setMetadataAddress(address _address) external onlyOwner {
        metadataAddress = _address;
    }

    function setBaseTokenURI(string memory _string) external onlyOwner {
        baseTokenURI = _string;
    }

    function setContractURI(string memory _string) external onlyOwner {
        wholeContractURI = _string;
    }

    function addWhitelistReserved(uint256 _amount) external onlyOwner {
        whitelistReserved += _amount;
    }

    function contractURI() external view returns (string memory) {
        return wholeContractURI;
    }

    function royaltyInfo(uint256, uint256 _salePrice) external view override returns (address, uint256) {
		return (royaltyAddress, (_salePrice * royaltyAmount) / 10000);
	}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId));

        if (metadataAddress != address(0)) {

            string memory metadata = ITroveStreetPunksMetadata(metadataAddress).metadataOf(tokenId);

            if (bytes(metadata).length > 0) {
                return metadata;
            }
            
        }

        return bytes(baseTokenURI).length > 0 ? string(abi.encodePacked(baseTokenURI, tokenId.toString())) : "";
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function isSaleLive() public view returns (bool) {
        return SALE_START <= block.timestamp;
    }

    function isWhitelistLive() public view returns (bool) {
        return WHITELIST_END > block.timestamp;
    }

    function isBlacklisted(address _address) public view returns (bool) {
        return blacklist[_address];
    }

    function mintInfo(address _address) public view returns (uint256[] memory) {
        uint256[] memory mints = new uint256[](6);

        for (uint256 i = 0; i < 6; i ++) {
            mints[i] = whitelistMinted[i][_address];
        }

        return mints;
    }

    function walletOfOwner(address _address) public view returns (uint256[] memory) {
        uint256 count = balanceOf(_address);
        uint256[] memory ids = new uint256[](count);

        for (uint256 i = 0; i < count; i ++) {
            ids[i] = tokenOfOwnerByIndex(_address, i);
        }

        return ids;
    }

    function _mintRandom(address _to, uint256 _amount) internal {
        for (uint256 i; i < _amount; ++ i) { 
            uint256 tokenId = _getRandomIndex(_to);
            _mint(_to, tokenId);
            -- availableTokens;
        }
    }

    function _getRandomIndex(address _to) internal returns (uint256) {

        uint256 randomNum = uint256(
            keccak256(
                abi.encode(
                    _to,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    block.difficulty,
                    blockhash(block.number - 1),
                    address(this),
                    availableTokens
                )
            )
        );

        uint256 randomIndex = randomNum % availableTokens;
        uint256 valAtIndex = availableIds[randomIndex];
        uint256 result;

        if (valAtIndex == 0) {
            result = randomIndex;
        } else {
            result = valAtIndex;
        }

        uint256 lastIndex = availableTokens - 1;

        if (randomIndex != lastIndex) {

            uint256 lastValInArray = availableIds[lastIndex];

            if (lastValInArray == 0) {
                availableIds[randomIndex] = lastIndex;
            } else {
                availableIds[randomIndex] = lastValInArray;
                delete availableIds[lastIndex];
            }

        }
        
        return result;
    }

    function _baseRequirements(uint256 _amount) internal view {
        require(isSaleLive(), "Sale not live");
        require(_msgSender() == tx.origin, "Contracts cannot mint");
        require(_amount > 0, "Invalid amount");
    }

    function _whitelistSupply() internal view returns (uint256) {
        return MAX_SUPPLY - teamReserved;
    }

    function _mintSupply() internal view returns (uint256) {
        if (isWhitelistLive()) {
            return _whitelistSupply() - whitelistReserved;
        }

        return _whitelistSupply();
    }

    function _verify(bytes memory data, bytes memory signature) internal pure returns (bool) {
        return keccak256(data)
            .toEthSignedMessageHash()
            .recover(signature) == SIGNER_ADDRESS;
    }

}
