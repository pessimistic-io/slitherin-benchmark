// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.8.4;

import "./ERC721Enumerable.sol";
import "./ERC721Burnable.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./console.sol";

contract ERC721Token is ERC721Enumerable, Ownable {
    using Strings for uint256;

    address public exchangeContractAddress;
    address public elpTokenAddress;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;
    mapping(address => bool) public whitelisted;
    address public admin;
    uint256 public startTime;
    uint256 public endTime;
    mapping(uint256 => uint256) public classes;

    constructor(
        string memory _name,
        string memory _symbol,
        address _exchangeContractAddress,
        address _elpTokenAddress
    ) ERC721(_name, _symbol) {
        exchangeContractAddress = _exchangeContractAddress;
        elpTokenAddress = _elpTokenAddress;
        setAdmin(0xfE2972473c0Ea680889f6d9106A18b9cAC96a039);
    }

    function setAdmin(address _admin) public onlyOwner {
        admin = _admin;
    }

    function mint(
        address _owner,
        uint256 _mintAmount,
        uint256 _classId
    ) external returns (uint256) {
        // require(msg.sender == elpTokenAddress, "not-valid-sender");
        // require(startTime <= block.timestamp, "start_time <= timestamp");
        // require(
        //     (endTime >= block.timestamp && whitelisted[_owner]) || (endTime < block.timestamp),
        //     "user not whitelisted or not public sale"
        // );
        uint256 supply = totalSupply();

        for (uint256 i = 1; i <= _mintAmount; i++) {
            _owners[supply + i] = _owner;
            classes[supply + i] = _classId;
            _safeMint(_owner, supply + i);
        }
        return supply + 1;
    }

    function _isExchangeContract(address spender) internal view virtual returns (bool) {
        return spender == exchangeContractAddress;
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override(ERC721) returns (bool) {
        return _isExchangeContract(operator) || super.isApprovedForAll(owner, operator);
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(ERC721) {
        require(
            _isExchangeContract(_msgSender()) || _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override(ERC721) returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override(ERC721) returns (address) {
        return address(0);
    }

    function setExchangeContractAddress(address _exchangeContractAddress) public onlyOwner {
        exchangeContractAddress = _exchangeContractAddress;
    }

    function setElpTokenAddress(address _elpTokenAddress) public onlyOwner {
        elpTokenAddress = _elpTokenAddress;
    }

    /**
     * @dev Burns `tokenId`. See {ERC721-_burn}.
     *
     * Requirements:
     *
     * - The caller must own `tokenId` or be an approved operator.
     */
    function burn(uint256[] memory _tokenIds, address _owner) external virtual {
        require(msg.sender == elpTokenAddress, "not-valid-sender");
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 _tokenId = _tokenIds[i];
            address owner = _owners[_tokenId];
            require(_owner == owner, "ERC721Burnable: caller is not owner");
            _burn(_tokenId);
        }
    }

    function whitelistUser(address[] memory _users) public onlyOwner {
        for (uint256 i = 0; i < _users.length; ++i) {
            address user = _users[i];
            whitelisted[user] = true;
        }
    }

    function removeWhitelistUser(address[] memory _users) public onlyOwner {
        for (uint256 i = 0; i < _users.length; ++i) {
            address user = _users[i];
            whitelisted[user] = false;
        }
    }

    function setTime(uint256 _startTime, uint256 _endTime) public onlyOwner {
        startTime = _startTime;
        endTime = _endTime;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://efun-public.s3.ap-southeast-1.amazonaws.com/nft-info/";
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, classes[tokenId].toString())) : "";
    }
}

