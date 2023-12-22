// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

contract WFTNFT is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;

    string public baseURI;
    string public baseExtension = "";
    string public notRevealedUri;
    uint256 public cost = 0.0005 ether;
    uint256 public maxSupply = 21000;
    uint256 public FreeSupply = 3000;
    uint256 public MaxperWallet = 100;
    uint256 public MaxperWalletFree = 1;
    bool public paused = false;
    bool public revealed = false;
    IERC20 private _token;
    mapping(address => bool) private _minted;
    mapping(address => bool) private _invited;
    uint256 private _tokenRewardAmount =  1000000000;

    constructor(
        string memory _initBaseURI,
        string memory _notRevealedUri,
        address tokenAddress
    ) ERC721A("WTF Chapter 1", "wtf") {
        setBaseURI(_initBaseURI);
        setNotRevealedURI(_notRevealedUri);
        require(tokenAddress != address(0), "Token address cannot be the zero address");
        _token = IERC20(tokenAddress);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

 function mint(uint256 tokens, address referrer) public payable nonReentrant {
    require(!paused, "oops contract is paused");
    require(tokens <= MaxperWallet, "max mint amount per tx exceeded");
    require(totalSupply() + tokens <= maxSupply, "We Soldout");
    require(_numberMinted(_msgSenderERC721A()) + tokens <= MaxperWallet, "Max NFT Per Wallet exceeded");
    require(msg.value >= cost * tokens, "insufficient funds");
    require(referrer != _msgSenderERC721A(), "Referrer cannot be the same as the buyer");

    _safeMint(_msgSenderERC721A(), tokens);
    uint256 reward = tokens * 1e9 * 10**18; 
    uint256 referrerReward = reward / 2; 
    uint256 buyerReward = reward / 2; 

    bool transferToNftMinterSuccess = _token.transfer(_msgSenderERC721A(), reward);
    require(transferToNftMinterSuccess, "Token transfer to Minter failed");
    bool transferToReferrerSuccess = _token.transfer(referrer, referrerReward);
    require(transferToReferrerSuccess, "Token transfer to referrer failed");

    bool transferToBuyerSuccess = _token.transfer(_msgSenderERC721A(), buyerReward);
    require(transferToBuyerSuccess, "Token transfer to buyer failed");
}



  function freemint(uint256 tokens) public nonReentrant {
    require(!paused, "oops contract is paused");
    require(_numberMinted(_msgSenderERC721A()) + tokens <= MaxperWalletFree, "Max NFT Per Wallet exceeded");
    require(tokens <= MaxperWalletFree, "max mint per Tx exceeded");
    require(totalSupply() + tokens <= FreeSupply, "Free Sold Out");


    _safeMint(_msgSenderERC721A(), tokens);
  }


  function setTokenRewardAmount(uint256 newTokenRewardAmount) public onlyOwner {
    _tokenRewardAmount = newTokenRewardAmount;
}


  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(
      _exists(tokenId),
      "ERC721AMetadata: URI query for nonexistent token"
    );
    
    if(revealed == false) {
        return notRevealedUri;
    }

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
        : "";
  }

    function numberMinted(address owner) public view returns (uint256) {
    return _numberMinted(owner);
  }

      function tokensOfOwner(address owner) public view returns (uint256[] memory) {
        unchecked {
            uint256 tokenIdsIdx;
            address currOwnershipAddr;
            uint256 tokenIdsLength = balanceOf(owner);
            uint256[] memory tokenIds = new uint256[](tokenIdsLength);
            TokenOwnership memory ownership;
            for (uint256 i = _startTokenId(); tokenIdsIdx != tokenIdsLength; ++i) {
                ownership = _ownershipAt(i);
                if (ownership.burned) {
                    continue;
                }
                if (ownership.addr != address(0)) {
                    currOwnershipAddr = ownership.addr;
                }
                if (currOwnershipAddr == owner) {
                    tokenIds[tokenIdsIdx++] = i;
                }
            }
            return tokenIds;
        }
    }

  function reveal(bool _state) public onlyOwner {
      revealed = _state;
  }

  function setMaxPerWallet(uint256 _limit) public onlyOwner {
    MaxperWallet = _limit;
  }

    function setFreeMaxPerWallet(uint256 _limit) public onlyOwner {
    MaxperWalletFree = _limit;
  }

  function setCost(uint256 _newCost) public onlyOwner {
    cost = _newCost;
  }


    function setFreesupply(uint256 _newsupply) public onlyOwner {
    FreeSupply = _newsupply;
  }

  function setBaseURI(string memory _newBaseURI) public onlyOwner {
    baseURI = _newBaseURI;
  }

  function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
    baseExtension = _newBaseExtension;
  }

  function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
    notRevealedUri = _notRevealedURI;
  }

  function pause(bool _state) public onlyOwner {
    paused = _state;
  }
  
  function withdraw() public payable onlyOwner nonReentrant {
      uint256 balance = address(this).balance;
      payable(_msgSenderERC721A()).transfer(balance);
  }
}
