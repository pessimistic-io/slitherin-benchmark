//SPDX-License-Identifier:MIT
import "./ERC721.sol";
import "./IERC20.sol";
pragma solidity ^0.8.7;

contract WildCard is ERC721 {
  IERC20 public constant BUSD =
    IERC20(0xFEa7a6a0B346362BF88A9e4A88416B77a57D6c2A); // 0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee
  //0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56

  IERC20 public constant DAI =
    IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1); //0xEC5dCb5Dbf4B114C9d0F65BcCAb49EC54F6A0867
  //0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3

  IERC20 public constant USDT =
    IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9); //0x337610d27c682E347C9cD60BD4b3b107C9d34dDd
  //0x55d398326f99059fF775485246999027B3197955

  IERC20 public constant USDC =
    IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8); //0x64544969ed7EBf5f083679233325356EbE738930

  // 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d

  uint256 public price = 33 ether;
  address public treasury = 0x81E0cCB4cB547b9551835Be01340508138695999;
  address public owner;

  constructor() ERC721("Lodge Wildcard", "LWC") {
    s_tokenCounter = 0;
    owner = msg.sender;
  }

  string public constant TOKEN_URI = "WILDCARD";
  uint256 private s_tokenCounter;

  function bulkMintNFT(
    uint256 _quantity,
    IERC20 token
  ) public returns (uint256) {
    require(
      token == BUSD || token == DAI || token == USDT || token == USDC,
      "Token Not Accepted"
    );
    require(_quantity > 0, "Invalid quantity");
    require(
      IERC20(token).balanceOf(msg.sender) >= _quantity * price,
      "Not enough tokens"
    );
    require(
      IERC20(token).allowance(msg.sender, address(this)) >= _quantity * price,
      "Allowance Required"
    );
    IERC20(token).transferFrom(msg.sender, treasury, _quantity * price);
    for (uint256 i = 0; i < _quantity; i++) {
      _safeMint(msg.sender, s_tokenCounter);
      s_tokenCounter = s_tokenCounter + 1;
    }
    return s_tokenCounter;
  }

  function ownerMint(
    uint256 _quantity,
    address destination
  ) public returns (uint256) {
    require(msg.sender == owner);
    for (uint256 i = 0; i < _quantity; i++) {
      _safeMint(destination, s_tokenCounter);
      s_tokenCounter = s_tokenCounter + 1;
    }
    return s_tokenCounter;
  }

  function tokenURI(
    uint256 /*tokenId*/
  ) public view override returns (string memory) {
    return TOKEN_URI;
  }

  function getTokenCounter() public view returns (uint256) {
    return s_tokenCounter;
  }
}

