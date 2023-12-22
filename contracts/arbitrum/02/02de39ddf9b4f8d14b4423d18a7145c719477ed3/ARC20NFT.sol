// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

// import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./ERC20_IERC20.sol";
import "./ERC721.sol";
import "./Counters.sol";

contract ARC20NFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct SaleConfig {
        uint supplyMaximum;
        uint salePrice;
        uint saleBlock;
    }

    struct CustomConfig {
        string contractURI;
        string tokenURI;
    }

    struct GameToken {
        address rewardToken;
        uint preAmount;
    }

    SaleConfig public saleConfig;
    CustomConfig public customConfig;
    GameToken public gameToken;

    mapping(address => bool) public userMinted;

    constructor() ERC721("arc", "arc") {
        saleConfig.salePrice = 0.0069 ether;
        saleConfig.supplyMaximum = 10000;
        saleConfig.saleBlock = 88927585;
        _tokenIds.increment();
    }

    function mint(address ref) external payable {
        uint tokenId = _tokenIds.current();

        address u = msg.sender;
        IERC20 T = IERC20(gameToken.rewardToken);

        require(!userMinted[u], "HAS_MINTED");
        require(block.number > saleConfig.saleBlock, "NOT_START");
        require((tokenId) <= saleConfig.supplyMaximum, "OVERFLOW");
        require(msg.value >= saleConfig.salePrice, "NOT_ENOUGH_ETH");

        userMinted[u] = true;
        _mint(u, tokenId);

        _tokenIds.increment();

        if (ref != address(0)) {
            T.transfer(u, (gameToken.preAmount * 110) / 100);
            T.transfer(ref, (gameToken.preAmount * 10) / 100);
        } else {
            T.transfer(u, gameToken.preAmount);
        }
    }

    function totalSupply() public view returns (uint) {
        return _tokenIds.current() - 1;
    }

    function setSaleConfig(SaleConfig memory config) external onlyOwner {
        saleConfig = config;
    }

    function setCustomConfig(CustomConfig memory config) external onlyOwner {
        customConfig = config;
    }

    function setTokenInfo(GameToken calldata tokenInfo) external onlyOwner {
        gameToken = tokenInfo;
    }

    function withdraw() external payable onlyOwner {
        payable(msg.sender).call{value: address(this).balance}("");
        IERC20 T = IERC20(gameToken.rewardToken);
        T.transfer(msg.sender, T.balanceOf(address(this)));
    }

    function tokenURI(uint tokenId) public view override returns (string memory) {
        tokenId;
        return customConfig.tokenURI;
    }

    function contractURI() public view returns (string memory) {
        return customConfig.contractURI;
    }

    receive() external payable {}
}

