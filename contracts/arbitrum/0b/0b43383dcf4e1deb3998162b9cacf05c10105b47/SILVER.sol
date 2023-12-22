// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./ERC1155Supply.sol";

contract SILVER is ERC1155, Ownable, ERC1155Supply {
    uint256 public constant TOKEN_ID = 1;

    mapping(address => uint256) private lockAmount;
    mapping(address => bool) public blackListWallet;

    string private _name;
    string private _symbol;

    constructor() ERC1155("https://google.com") {
        _name = "Silver";
        _symbol = "SILVER";
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(
        address account,
        uint256 amount,
        bytes memory data
    ) public onlyOwner {
        _mint(account, TOKEN_ID, amount, data);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) {
        require(!blackListWallet[from], "ERC1155: wallet from is blacklist");
        require(!blackListWallet[to], "ERC1155: wallet to is blacklist");
        if (getLockAmount(msg.sender) > 0) {
            uint256 balance = balanceOf(msg.sender, TOKEN_ID);
            uint256 remains = balance - getLockAmount(msg.sender);
            require(
                remains >= amounts[0],
                "ERC1155: balance not enough to transfer"
            );
        }
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function setBlackListWallet(
        address[] memory wallets,
        bool result
    ) public onlyOwner {
        for (uint i = 0; i < wallets.length; i++) {
            blackListWallet[wallets[i]] = result;
        }
    }

    function getLockAmount(address wallet) public view returns (uint256) {
        return lockAmount[wallet];
    }

    function setLockAmount(address wallet, uint256 amount) public onlyOwner {
        lockAmount[wallet] += amount;
    }
}

