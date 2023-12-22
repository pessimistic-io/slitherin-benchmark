// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./IERC20.sol";

contract TubylecVIPPass is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using StringsUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;
    mapping(uint256 => uint256) public expiration;

    IERC20 public SHIBDAO;

    function initialize() public initializer {
        __ERC721_init("TUBYLEC.VIP Pass", "VIPPASS");
        __Ownable_init();
    }

    function buyForShibdao(bool long) external {
        uint256 amount = long ? 1_000_000 ether : 100_000 ether;
        bool success = SHIBDAO.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");
        _internalMint(msg.sender, long ? 150 days : 60 days);
    }

    function setShibdao(address _shibdao) external onlyOwner {
        SHIBDAO = IERC20(_shibdao);
    }

    function _internalMint(address to, uint256 newExpiration) internal {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();

        expiration[tokenId] = block.timestamp + newExpiration;

        _safeMint(to, tokenId);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://tubylec.vip/data_nft/";
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
    }

    receive() external payable {}
}

