//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./EnumerableSet.sol";
import "./Strings.sol";


contract NFT is ERC1155("") {
  uint256 public constant NUM_PRIVILEGED_RANKS = 10;
  mapping(uint256 => bool) public isMinted;
  using EnumerableSet for EnumerableSet.AddressSet;
  EnumerableSet.AddressSet private _owners;

  constructor(string memory uri_) {
    _setURI(uri_);
    _owners.add(msg.sender);
  }

  modifier onlyOwner() {
    require(_owners.contains(msg.sender), "only owner can do this action");
    _;
  }

  function setURI(string memory uri_) external onlyOwner {
    _setURI(uri_);
  }

  function _addOwner(address _owner) external onlyOwner {
    _owners.add(_owner);
  }

  function _removeOwner(address _owner) external onlyOwner {
    _owners.remove(_owner);
  }

  function mint(address to, uint256 id) external onlyOwner {
    require(isMinted[id] != true, "already minted");
    isMinted[id] = true;
    _mint(to, id, 1, "");
  }
  	function uri(uint256 _id) public view override returns (string memory) {
		if (_id > NUM_PRIVILEGED_RANKS) {
			_id = NUM_PRIVILEGED_RANKS;
		}
		return string(abi.encodePacked(
			super.uri(_id),
			Strings.uint2str(_id),
			".json"
		));
	}
}

