// File: Squires/Rings.sol

import "./ERC1155.sol";
import "./Ownable.sol";

pragma solidity ^0.8.17;

contract SquireRings is ERC1155, Ownable {
  enum ItemType {
    RING,
    POTION,
    TRINKET
  }

  uint256 thisType = uint(ItemType.RING);

  //mappings
  mapping(address => bool) private allowedContracts;

  string public _baseURI =
    "ipfs://QmNaBt67t24B5Zqdpv4g3WEk4K2AGAj5su1K3NjnSahx53/";
  string public _contractURI;

  constructor() ERC1155(_baseURI) {
    allowedContracts[msg.sender] = true;
  }

  function mint(address to, uint typeChoice) external {
    require(allowedContracts[msg.sender]);

    _mint(to, typeChoice, 1, "");
  }

  function mintMany(address to, uint typeChoice, uint amount) external {
    require(allowedContracts[msg.sender]);

    _mint(to, typeChoice, amount, "");
  }

  function burn(address account, uint256 id, uint256 qty) external {
    require(allowedContracts[msg.sender]);
    require(balanceOf(account, id) >= qty, "balance too low");

    _burn(account, id, qty);
  }

  function setBaseURI(string memory newuri) public onlyOwner {
    _baseURI = newuri;
  }

  function setContractURI(string memory newuri) public onlyOwner {
    _contractURI = newuri;
  }

  function uri(uint256 tokenId) public view override returns (string memory) {
    return string(abi.encodePacked(_baseURI, uint2str(tokenId)));
  }

  function contractURI() public view returns (string memory) {
    return _contractURI;
  }

  function uint2str(
    uint256 _i
  ) internal pure returns (string memory _uintAsString) {
    if (_i == 0) {
      return "0";
    }
    uint256 j = _i;
    uint256 len;
    while (j != 0) {
      len++;
      j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint256 k = len;
    while (_i != 0) {
      k = k - 1;
      uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
      bytes1 b1 = bytes1(temp);
      bstr[k] = b1;
      _i /= 10;
    }
    return string(bstr);
  }

  function setAllowedContracts(
    address[] calldata contracts
  ) external onlyOwner {
    for (uint256 i; i < contracts.length; i++) {
      allowedContracts[contracts[i]] = true;
    }
  }

  function checkAllowedContracts(address account) public view returns (bool) {
    return allowedContracts[account];
  }

  //withdraw any funds
  function withdrawToOwner() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }
}

