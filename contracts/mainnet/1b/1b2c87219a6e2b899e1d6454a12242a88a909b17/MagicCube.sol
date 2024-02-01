// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./MagicCubeX.sol";
import "./Ownable.sol";
import "./ERC721A.sol";

contract MagicCube is Ownable, ERC721A {

    using Strings for uint256;

    address public MagicCubeXAddress;

    uint256 public constant TOTAL_MAX_QTY = 8888;
    uint256 public constant MAX_PER_TX = 4;
    uint256 public constant MAX_PER_FREE = 4;
    uint256 public constant MAX_PER_WALLET = 12;
    uint256 public constant MAX_FREE = 2222;

    uint256 public startMint = 1677078000;
    uint256 public endMintAndStartMerge = 1677337200;
    uint256 public endMerge = 1677423600;
    
    string private _tokenURI;
    uint256 public rewardTimes = 0;
    uint256 public baseReward = 0;
    mapping(address => uint256) public address2Free;

    constructor(
        string memory tokenURI_
    ) ERC721A("Magic Cube", "Magic Cube") {
        _tokenURI = tokenURI_;
    }

    function getPrice() public view returns (uint256) {
        uint256 minted = totalSupply();
        uint256 cost = 0;
        if (minted < 2222) {
            cost = 0;
        } else if (minted < 4444) {
            cost = 0.002 ether;
        } else if (minted < 6666) {
            cost = 0.004 ether;
        } else {
            cost = 0.006 ether;
        }

        return cost;
    }

    function getTotalCost(uint256 quantity) public view returns (uint256) {
        uint256 cost = getPrice();
        require(quantity <= MAX_PER_TX, "Max per tx");
        uint256 totalCost;
        if (cost == 0) {
            uint256 blank = (totalSupply() / 2222 + 1) * 2222 - totalSupply();
            uint256 amount = address2Free[msg.sender];
            if (blank < amount) {
                amount = blank;
            }
            totalCost = amount * (cost + 0.002 ether);
        } else {
            uint256 blank = (totalSupply() / 2222 + 1) * 2222 - totalSupply();
            if (blank >= quantity) {
                totalCost = quantity * cost;
            } else {
                totalCost = blank * cost + (quantity - blank) * (cost + 0.002 ether);
            }
        }

        return totalCost;
    }

    function publicMint(uint256 quantity) external payable {
        require(block.timestamp >= startMint, "Please wait!");
        require(block.timestamp <= endMintAndStartMerge, "End mint!");
        require(totalSupply() + quantity <= TOTAL_MAX_QTY, "No more");
        require(quantity <= MAX_PER_TX, "Max per tx");
        require(
            balanceOf(msg.sender) + quantity <= MAX_PER_WALLET,
            "Max per wallet"
        );
        uint256 totalCost = getTotalCost(quantity);
        
        require(msg.value >= totalCost, "Please send the exact amount.");
        _safeMint(msg.sender, quantity);

        baseReward = baseReward + (totalCost / 2 / 200);
        address2Free[msg.sender] = address2Free[msg.sender] + quantity;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _indexURI(tokenId))) : "";
    }

    function setTokenURI(string memory tokenURI_) external onlyOwner {
        _tokenURI = tokenURI_;
    }

    function setMagicCubeX(address magicCubeX_) external onlyOwner {
        MagicCubeXAddress = magicCubeX_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _tokenURI;
    }

    function _indexURI(uint256 tokenId) internal view virtual returns (string memory) {
        uint256 index = tokenId % 4 + 1;
        if (index % 111 == 0) {
            index = index * 10;
        }
        return index.toString();
    }

    function rewardTotal() public view returns (uint256) {
        return address(this).balance / 2;
    }

    function reward(uint256[4] memory tokenIds) public view returns (uint256) {
        if (rewardTimes > 200) {
            return 0;
        }
        uint256 totalReward = baseReward;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if ((tokenIds[i] + 1) % 111 == 0) {
                totalReward = totalReward + baseReward / 2;
            }
        }
        return totalReward;
    }

    function merge(uint256[4] memory tokenIds) external {
        require(block.timestamp >= endMintAndStartMerge, "Please wait!");
        require(block.timestamp <= endMerge, "End merge!");
        require(
            (tokenIds[0] % 4 + 1) * (tokenIds[1] % 4 + 1) * (tokenIds[2] % 4 + 1) * (tokenIds[3] % 4 + 1) == 24, 
            "Piece repeat!"
        );
        uint256 totalReward = reward(tokenIds);
        for (uint i = 0; i < tokenIds.length; i++) {
            address owner = ownerOf(tokenIds[i]);
            require(msg.sender == owner, "Error: Not ERC721 owner");
            _burn(tokenIds[i]);
        }

        MagicCubeX(MagicCubeXAddress).holderMint(msg.sender);

        (bool success, ) = payable(msg.sender).call{
            value: totalReward
        }("");
        require(success, "Transfer failed.");
    }

    function withdraw() external onlyOwner {
        require(block.timestamp > endMerge, "Merging!");
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "Transfer failed.");
    }
}

