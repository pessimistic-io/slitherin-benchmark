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

    mapping(address => uint256) public mintedForShibdao;

    IERC20 public USDC;
    uint256 public usdcPrice;

    function initialize() public initializer {
        __ERC721_init("TUBYLEC.VIP Pass", "VIPPASS");
        __Ownable_init();
    }

    function buyForUSDC() external {
        require(usdcPrice > 0, "USDC price not set");
        bool success = USDC.transferFrom(msg.sender, address(this), usdcPrice);
        require(success, "Transfer failed");
        _internalMint(msg.sender, 30 days);
    }

    function renewForUSDC(uint256 tokenId) external {
        require(usdcPrice > 0, "USDC price not set");
        bool success = USDC.transferFrom(msg.sender, address(this), usdcPrice);
        require(success, "Transfer failed");
        _internalRenew(tokenId);
    }

    function buyForShibdao(bool long) external {
        require(mintedForShibdao[msg.sender] < 1, "Already minted too many");
        uint256 amount = long ? 1_000_000 ether : 100_000 ether;
        bool success = SHIBDAO.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");
        _internalMint(msg.sender, long ? 150 days : 60 days);
        mintedForShibdao[msg.sender]++;
    }

    function setShibdao(address _shibdao) external onlyOwner {
        SHIBDAO = IERC20(_shibdao);
    }

    function setUSDC(address _usdc) external onlyOwner {
        USDC = IERC20(_usdc);
    }

    function setUSDCPrice(uint256 _usdcPrice) external onlyOwner {
        usdcPrice = _usdcPrice;
    }

    function withdrawToken(address _to, address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        bool success = token.transfer(_to, balance);
        require(success, "Transfer failed");
    }

    function _internalMint(address to, uint256 newExpiration) internal {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();

        expiration[tokenId] = block.timestamp + newExpiration;

        _safeMint(to, tokenId);
    }

    function _internalRenew(uint256 tokenId) internal {
        _requireMinted(tokenId);
        if (block.timestamp < expiration[tokenId]) {
            expiration[tokenId] += 30 days;
        } else {
            expiration[tokenId] = block.timestamp + 30 days;
        }
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

