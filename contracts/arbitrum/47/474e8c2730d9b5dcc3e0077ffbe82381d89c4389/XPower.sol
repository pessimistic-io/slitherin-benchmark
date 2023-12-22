// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./AccessControl.sol";
import "./Ownable.sol";

contract XPOWER is AccessControl, Ownable {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    bytes32 public constant Claimer = keccak256("Claimer");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** XPower of PlanetMan **/
    struct _XPower {
        uint256 level;  /* Lv.1 ~ Lv.13 */
        uint256 POSW;
    }

    mapping (uint256 => _XPower) public XPower; /* tokenId => XPower */

    function getLevel(uint256 _tokenId) external view returns (uint256) {
        return XPower[_tokenId].level;
    }

    function getPOSW(uint256 _tokenId) external view returns (uint256) {
        return XPower[_tokenId].POSW;
    }

    function levelUp(uint256 _tokenId) external onlyRole(Claimer) {
        require(XPower[_tokenId].level < 9, "XPower: You have reached the highest level.");
        XPower[_tokenId].level++;
    }

/** POSW of PlanetMan **/
    function addPOSW_PM (uint256 _tokenId, uint256 _POSW) external onlyRole(Claimer) {
        XPower[_tokenId].POSW += _POSW;
    }

/** Withdraw **/
    function Withdraw(address recipient) public onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }
}
