// SPDX-License-Identifier: None
pragma solidity ^0.8.0;
import "./ERC721Enumerable.sol";
import "./Math.sol";
import "./IArvinDegenNFT.sol";
import "./console.sol";
import "./BoringOwnable.sol";
import "./IERC20.sol";

contract ArvinDegenNFT is ERC721Enumerable, BoringOwnable, IArvinDegenNFT {
    uint256 constant Common = 650; //2%
    uint256 constant Uncommon = 200; //5%
    uint256 constant Rare = 100; //10%
    uint256 constant Legendary = 50; //20%
    string public uri;
    using Strings for uint256;
    IStrictERC20 vin;
    uint256 public mintNeed = 19 ether;
    uint256 increaseAmount = 0.18 ether;
    uint256 public left = 1000;
    uint256[1000] mintLeft;

    constructor(address _vin, string memory _uri) ERC721("Arvin Degen NFT", "ADNFT") {
        uri = _uri;
        vin = IStrictERC20(_vin);
    }

    function mint() public returns (uint256 tokenId) {
        vin.transferFrom(msg.sender, address(0xdead), mintNeed);
        mintNeed += increaseAmount;
        uint256 random = getRandom(getRandom(mintNeed));
        left--;
        tokenId = mintLeft[random] == 0 ? random : mintLeft[random];
        _mint(msg.sender, tokenId);
        mintLeft[random] = mintLeft[left] == 0 ? left : mintLeft[left];
        return tokenId;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        string memory imgUrl = super.tokenURI(tokenId);
        string memory rate = _getRatioByTokenId(tokenId).toString();
        return
            string.concat(
                '{"description":"Arvin Degen NFTs are a collection within the Arvin Finance ecosystem, consisting of a total of 1,000 NFTs categorized into four tiers: legendary, rare, uncommon, and common. These tiers are distributed as follows: 50 legendary, 100 rare, 200 uncommon, and 650 common NFTs. By holding and staking an NFT, users can avail themselves of discounts when using Arvin Finance. The discount percentage varies depending on the NFT tier, with a maximum discount of 20% (i.e., reducing the original interest rate by 20%).","external_url":"https://arvin.finance","image":"',
                imgUrl,
                '.png","attributes":[{"display_type":"boost_percentage","trait_type":"Interest Decrease Ratio","value":',
                rate,
                "}]}"
            );
    }

    function getRandom(uint256 seed) private returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.coinbase, gasleft(), msg.sender, seed))) % left;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return uri;
    }

    function _getRatioByTokenId(uint256 tokenId) public pure returns (uint256 rate) {
        if (tokenId < 650) {
            rate += 2;
        } else if (tokenId < 850) {
            rate += 5;
        } else if (tokenId < 950) {
            rate += 10;
        } else if (tokenId < 1000) {
            rate += 20;
        }
    }

    function getRefundRatio(address user) public view returns (uint256) {
        uint256 balance = balanceOf(user);
        uint256 rate = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint tokenId = tokenOfOwnerByIndex(user, i);
            rate += _getRatioByTokenId(tokenId);

            if (rate >= 20) {
                break;
            }
        }
        return Math.min(rate, 20);
    }
}

