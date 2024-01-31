// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./erc20tax.sol";
import "./Ownable.sol";

contract MEMEWAR is ERC20, Ownable {

    mapping (address => bool) public isBlackListed;

    event DestroyedBlackFunds(address _blackListedUser, uint _balance);

    event AddedBlackList(address _user);

    event RemovedBlackList(address _user);

    

    constructor() ERC20("MEMEWAR", "WAR") {
        _mint(msg.sender, 100000000000000000000000000000);
    }

    function getBlackListStatus(address _maker) external view returns (bool) {
        return isBlackListed[_maker];
    }

    function addBlackList (address _evilUser) public onlyOwner {
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    function removeBlackList (address _clearedUser) public onlyOwner {
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }

    function setTaxWallet(address wallet) external onlyOwner{
        _setTaxWallet(wallet);
    }

    function setTax(uint256 taxPercentage) external onlyOwner{
        _setTax(taxPercentage);
    }

    function excludeFromTax(address excluded) external onlyOwner{
        _setExcluded(excluded, true);
    }

    function includeInTax(address included) external onlyOwner{
        _setExcluded(included, false);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
            require(!isBlackListed[from],"Blocked User");
            super._beforeTokenTransfer(from, to, amount);
    }


}
