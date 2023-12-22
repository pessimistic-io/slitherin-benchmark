// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./IMasterContract.sol";

contract VibeERC1155 is ERC1155, Ownable, IMasterContract {

    string public _uri;

    function uri(uint256 /*id*/) public view override returns (string memory) {
        return _uri;
    }

    function init(bytes calldata data) public payable override {
        (string memory uri_) = abi.decode(data, (string));
        require(bytes(_uri).length == 0 && bytes(uri_).length != 0);
        _uri = uri_;
        _transferOwnership(msg.sender);
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external onlyOwner {
        _mint(account, id, amount, data);
    }

    function batchMint(address to, uint256 fromId, uint256 toId, uint256 amount, bytes memory data) external onlyOwner {
        for (uint256 id = fromId; id <= toId; id++) {
            _mint(to, id, amount, data);
        }
    }
}

