// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ERC20.sol";

contract AdvertiseToken is ERC20, Ownable {
    bool public isOwnerOnlyMode;

    string internal _content;

    mapping(address => bool) internal _whitelist;

    constructor(string memory content_) ERC20("", "") Ownable() {
        _content = content_;
    }

    function name() public view virtual override returns (string memory) {
        return _content;
    }

    function symbol() public view virtual override returns (string memory) {
        return _content;
    }

    function mint(address account, uint256 amount) external onlyOwner {
        super._mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner {
        super._burn(account, amount);
    }

    function setContent(string memory newContent) external onlyOwner {
        _content = newContent;
    }

    function switchOwnerOnlyMode() external onlyOwner {
        isOwnerOnlyMode = !isOwnerOnlyMode;
    }

    function setWhitelist(address account, bool allowed) external onlyOwner {
        _whitelist[account] = allowed;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(
            !isOwnerOnlyMode ||
                (_whitelist[from] || _whitelist[to] || msg.sender == owner()),
            "InOwnerOnlyMode"
        );
        super._beforeTokenTransfer(from, to, amount);
    }
}

